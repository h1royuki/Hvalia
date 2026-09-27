// Hvalia additions. Only Books snapshots and generated Media objects are exposed.
static NSDictionary *StrictInfo(AFCConnectionRef afc, NSString *path, int *status) {
    AFCKeyValueRef ref = NULL;
    *status = AFCFileInfoOpen(afc, path.fileSystemRepresentation, &ref);
    if (*status || !ref) return nil;
    NSMutableDictionary *result = NSMutableDictionary.dictionary;
    char *key = NULL, *value = NULL;
    while (AFCKeyValueRead(ref, &key, &value) == 0 && key && value) {
        result[@(key)] = @(value); key = NULL; value = NULL;
    }
    AFCKeyValueClose(ref); return result;
}
static NSArray *Children(AFCConnectionRef afc, NSString *path) {
    AFCDirectoryRef ref = NULL;
    if (AFCDirectoryOpen(afc, path.fileSystemRepresentation, &ref) || !ref) return nil;
    NSMutableArray *result = NSMutableArray.array;
    BOOL ended = NO, valid = YES;
    for (int i = 0; i < 10000; i++) {
        char *entry = NULL;
        if (AFCDirectoryRead(afc, ref, &entry)) { valid = NO; break; }
        if (!entry) { ended = YES; break; }
        NSString *name = @(entry);
        if ([name isEqual:@"."] || [name isEqual:@".."]) continue;
        if ([name containsString:@"/"] || !name.length) { valid = NO; break; }
        [result addObject:name];
    }
    AFCDirectoryClose(afc, ref);
    return valid && ended ? [result sortedArrayUsingSelector:@selector(compare:)] : nil;
}
static BOOL BooksPath(NSString *path) {
    return ([path isEqual:@"Books"] || [path hasPrefix:@"Books/"]) && IsSafeRelativePath(path);
}
static BOOL GatherBooks(AFCConnectionRef afc, NSString *path, NSMutableArray *rows, NSString *root, NSUInteger depth, unsigned long long *bytes) {
    if (depth > 20 || rows.count > 10000 || !BooksPath(path)) return NO;
    int status = 0; NSDictionary *info = StrictInfo(afc, path, &status);
    if (status == 8 && [path isEqual:@"Books"]) return YES;
    if (!info) return NO;
    NSString *kind = info[@"st_ifmt"];
    NSMutableDictionary *row = [@{@"path":path, @"kind":kind ?: @"unknown"} mutableCopy];
    if ([kind isEqual:@"S_IFREG"]) {
        NSData *data = AFCReadFileWithLimit(afc, path, 128*1024*1024);
        if (!data) return NO;
        *bytes += data.length; if (*bytes > 256*1024*1024) return NO;
        NSString *local = [NSString stringWithFormat:@"full-%lu.bin", (unsigned long)rows.count];
        if (root && ![data writeToFile:[root stringByAppendingPathComponent:local] options:NSDataWritingWithoutOverwriting error:nil]) return NO;
        row[@"local"] = local; row[@"size"] = @(data.length);
    } else if (![kind isEqual:@"S_IFDIR"]) return NO;
    [rows addObject:row];
    if ([kind isEqual:@"S_IFDIR"]) {
        NSArray *children = Children(afc,path); if (!children) return NO;
        for (NSString *name in children) if (!GatherBooks(afc,[path stringByAppendingPathComponent:name],rows,root,depth+1,bytes)) return NO;
    }
    return YES;
}
static NSDictionary *FullSnapshot(AFCConnectionRef afc, NSString *root) {
    NSMutableArray *rows = NSMutableArray.array; unsigned long long bytes = 0;
    NSString *file = [root stringByAppendingPathComponent:@"full-manifest.plist"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:file] || !GatherBooks(afc,@"Books",rows,root,0,&bytes)) return @{@"ok":@NO};
    NSDictionary *tracked=LoadBooksSnapshot(root);
    if (!tracked) return @{@"ok":@NO};
    NSMutableDictionary *byPath=NSMutableDictionary.dictionary;
    for (NSDictionary *row in rows) byPath[row[@"path"]]=row;
    for (NSString *path in tracked[@"files"]) {
        NSDictionary *entry=tracked[@"files"][path], *full=byPath[path];
        if ([entry[@"exists"] boolValue] != (full != nil)) return @{@"ok":@NO};
        if (full) {
            NSData *a=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:entry[@"localName"]]];
            NSData *b=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:full[@"local"]]];
            if (![a isEqual:b]) return @{@"ok":@NO};
        }
    }
    for (NSString *path in tracked[@"directories"]) if ([tracked[@"directories"][path] boolValue] != (byPath[path] != nil)) return @{@"ok":@NO};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"version":@1,@"rows":rows} format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    BOOL ok = data && [data writeToFile:file options:NSDataWritingWithoutOverwriting error:nil];
    return @{@"ok":@(ok),@"filesAndDirectories":@(rows.count),@"bytes":@(bytes)};
}
static NSArray *FullRows(NSString *root) {
    NSData *data = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"full-manifest.plist"]];
    NSDictionary *m = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil] : nil;
    NSArray *rows = [m isKindOfClass:NSDictionary.class] ? m[@"rows"] : nil;
    if (![m[@"version"] isEqual:@1] || ![rows isKindOfClass:NSArray.class]) return nil;
    NSMutableSet *paths = NSMutableSet.set;
    for (NSDictionary *row in rows) {
        if (![row isKindOfClass:NSDictionary.class] || ![row[@"path"] isKindOfClass:NSString.class] || !BooksPath(row[@"path"]) || [paths containsObject:row[@"path"]]) return nil;
        [paths addObject:row[@"path"]];
        if ([row[@"kind"] isEqual:@"S_IFREG"]) {
            NSString *local = row[@"local"];
            if (![local isKindOfClass:NSString.class] || [local containsString:@"/"] || ![local hasPrefix:@"full-"] || ![local hasSuffix:@".bin"]) return nil;
            NSData *blob = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:local]];
            if (!blob || blob.length != [row[@"size"] unsignedLongLongValue]) return nil;
        } else if (![row[@"kind"] isEqual:@"S_IFDIR"]) return nil;
    }
    return rows;
}
static NSDictionary *FullVerifyWithServiceArtifacts(AFCConnectionRef afc, NSString *root, BOOL allowServiceLock) {
    NSArray *rows = FullRows(root); if (!rows) return @{@"ok":@NO};
    NSMutableArray *now = NSMutableArray.array; unsigned long long bytes = 0;
    if (!GatherBooks(afc,@"Books",now,nil,0,&bytes)) return @{@"ok":@NO};
    NSSet *beforePaths = [NSSet setWithArray:[rows valueForKey:@"path"]];
    NSMutableSet *extra = [NSMutableSet setWithArray:[now valueForKey:@"path"]];
    [extra minusSet:beforePaths];
    NSMutableSet *missing = [beforePaths mutableCopy];
    [missing minusSet:[NSSet setWithArray:[now valueForKey:@"path"]]];
    NSMutableArray *preservedServiceArtifacts = NSMutableArray.array;
    NSMutableArray *absentServiceArtifacts = NSMutableArray.array;
    if (allowServiceLock && [missing containsObject:@"Books/Sync/.bookSync.lock"]) {
        for (NSDictionary *row in rows) if ([row[@"path"] isEqual:@"Books/Sync/.bookSync.lock"] && [row[@"kind"] isEqual:@"S_IFREG"] && [row[@"size"] unsignedLongLongValue]==0) {
            [missing removeObject:row[@"path"]]; [absentServiceArtifacts addObject:row[@"path"]];
        }
    }
    // atc creates this zero-byte lock during sync. Never unlink an active service lock.
    if (allowServiceLock && [extra containsObject:@"Books/Sync/.bookSync.lock"]) {
        for (NSDictionary *row in now) {
            if ([row[@"path"] isEqual:@"Books/Sync/.bookSync.lock"] && [row[@"kind"] isEqual:@"S_IFREG"] && [row[@"size"] unsignedLongLongValue] == 0) {
                [extra removeObject:row[@"path"]]; [preservedServiceArtifacts addObject:row[@"path"]];
            }
        }
    }
    if (preservedServiceArtifacts.count) {
        for (NSString *ancestor in @[@"Books", @"Books/Sync"]) {
            for (NSDictionary *row in now) if ([row[@"path"] isEqual:ancestor] && [row[@"kind"] isEqual:@"S_IFDIR"]) [extra removeObject:ancestor];
        }
    }
    if (extra.count || missing.count) return @{@"ok":@NO,@"reason":@"books_tree_changed",@"extraPaths":extra.allObjects,@"missingPaths":missing.allObjects};
    for (NSDictionary *row in rows) {
        int status = 0; NSDictionary *info = StrictInfo(afc,row[@"path"],&status);
        if (allowServiceLock && status==8 && [row[@"path"] isEqual:@"Books/Sync/.bookSync.lock"] && [row[@"kind"] isEqual:@"S_IFREG"] && [row[@"size"] unsignedLongLongValue]==0) continue;
        if (!info || ![info[@"st_ifmt"] isEqual:row[@"kind"]]) return @{@"ok":@NO,@"reason":@"books_type_changed",@"path":row[@"path"],@"afcError":@(status)};
        if ([row[@"kind"] isEqual:@"S_IFREG"]) {
            NSData *before = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:row[@"local"]]];
            if (![before isEqual:AFCReadFileWithLimit(afc,row[@"path"],128*1024*1024)]) return @{@"ok":@NO,@"reason":@"books_bytes_changed",@"path":row[@"path"]};
        }
    }
    return @{@"ok":@YES,@"preservedServiceArtifacts":preservedServiceArtifacts,@"absentServiceArtifacts":absentServiceArtifacts};
}
static NSDictionary *FullVerify(AFCConnectionRef afc, NSString *root) {
    return FullVerifyWithServiceArtifacts(afc, root, NO);
}
static BOOL ServiceLockOnlyDirectory(AFCConnectionRef afc, NSString *path) {
    if (![path isEqual:@"Books"] && ![path isEqual:@"Books/Sync"]) return NO;
    NSArray *children = Children(afc,path);
    if ([path isEqual:@"Books"]) return [children isEqual:@[@"Sync"]] && ServiceLockOnlyDirectory(afc,@"Books/Sync");
    if (![children isEqual:@[@".bookSync.lock"]]) return NO;
    int status=0; NSDictionary *info=StrictInfo(afc,@"Books/Sync/.bookSync.lock",&status);
    return status==0 && [info[@"st_ifmt"] isEqual:@"S_IFREG"] && [info[@"st_size"] longLongValue]==0;
}
static BOOL SafeParents(AFCConnectionRef afc, NSString *path) {
    NSString *parent=[path stringByDeletingLastPathComponent];
    if (!parent.length) return YES;
    int status=0; NSDictionary *info=StrictInfo(afc,parent,&status);
    if (status==0) return [info[@"st_ifmt"] isEqual:@"S_IFDIR"] && SafeParents(afc,parent);
    return status==8 && SafeParents(afc,parent) && AFCDirectoryCreate(afc,parent.fileSystemRepresentation)==0;
}
static NSDictionary *FullRestore(AFCConnectionRef afc, NSString *root) {
    NSArray *rows=FullRows(root); NSDictionary *tracked=LoadBooksSnapshot(root);
    if (!rows || !tracked) return @{@"ok":@NO,@"reason":@"invalid_snapshot"};
    // Restore known sync files first, but defer directory removal until complete originals are restored.
    // An active empty .bookSync.lock and its necessary parents must survive cleanup.
    for (NSString *path in tracked[@"files"]) {
        NSDictionary *row=tracked[@"files"][path];
        int status=0; NSDictionary *info=StrictInfo(afc,path,&status);
        if ((status && status!=8) || (info && ![info[@"st_ifmt"] isEqual:@"S_IFREG"]))
            return @{@"ok":@NO,@"reason":@"tracked_type_or_access_error",@"path":path,@"afcError":@(status)};
        if ([row[@"exists"] boolValue]) {
            NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:row[@"localName"]]];
            if (!data || !SafeParents(afc,path) || (![data isEqual:AFCReadFileWithLimit(afc,path,128*1024*1024)] && !AFCWriteFile(afc,path,data)))
                return @{@"ok":@NO,@"reason":@"tracked_write_failed",@"path":path};
        } else if (info && AFCRemovePath(afc,path.fileSystemRepresentation)!=0)
            return @{@"ok":@NO,@"reason":@"tracked_remove_failed",@"path":path};
    }
    for (NSDictionary *row in rows) {
        NSString *path=row[@"path"]; int status=0; NSDictionary *info=StrictInfo(afc,path,&status);
        if ((status && status!=8) || (info && ![info[@"st_ifmt"] isEqual:row[@"kind"]]))
            return @{@"ok":@NO,@"reason":@"books_type_or_access_error",@"path":path,@"afcError":@(status)};
        if ([path isEqual:@"Books/Sync/.bookSync.lock"] && [row[@"kind"] isEqual:@"S_IFREG"] && [row[@"size"] unsignedLongLongValue]==0) {
            if (info && [info[@"st_size"] longLongValue]!=0) return @{@"ok":@NO,@"reason":@"service_lock_changed",@"path":path};
            continue; // Do not create, truncate or remove a runtime service lock.
        }
        if ([row[@"kind"] isEqual:@"S_IFDIR"]) {
            if (!SafeParents(afc,path) || (!info && AFCDirectoryCreate(afc,path.fileSystemRepresentation)!=0)) return @{@"ok":@NO,@"reason":@"directory_restore_failed",@"path":path};
        } else {
            NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:row[@"local"]]];
            if (!SafeParents(afc,path) || (![data isEqual:AFCReadFileWithLimit(afc,path,128*1024*1024)] && !AFCWriteFile(afc,path,data)))
                return @{@"ok":@NO,@"reason":@"books_write_failed",@"path":path};
        }
    }
    for (NSString *path in @[@"Books/Sync/Database",@"Books/Sync",@"Books"]) {
        if ([tracked[@"directories"][path] boolValue]) continue;
        int status=0; NSDictionary *info=StrictInfo(afc,path,&status);
        if (status==8) continue;
        if (status || ![info[@"st_ifmt"] isEqual:@"S_IFDIR"]) return @{@"ok":@NO,@"reason":@"directory_type_or_access_error",@"path":path,@"afcError":@(status)};
        if (ServiceLockOnlyDirectory(afc,path)) continue;
        NSArray *children=Children(afc,path);
        if (!children || children.count || AFCRemovePath(afc,path.fileSystemRepresentation)!=0)
            return @{@"ok":@NO,@"reason":@"unexpected_directory_contents",@"path":path};
    }
    return FullVerifyWithServiceArtifacts(afc,root,YES);
}
static NSDictionary *ReadOwned(AFCConnectionRef afc, NSString *path, NSString *output) {
    BOOL allowed = GeneratedToken(path,AIRLIFT_RECOVERED_PREFIX) != nil;
    if (!allowed) return @{@"ok":@NO};
    int status = 0; NSDictionary *info = StrictInfo(afc,path,&status);
    if (!info || ![info[@"st_ifmt"] isEqual:@"S_IFREG"]) return @{@"ok":@NO,@"afcError":@(status)};
    NSData *data = AFCReadFileWithLimit(afc,path,1024*1024);
    BOOL ok = data && [data writeToFile:output options:NSDataWritingWithoutOverwriting error:nil];
    return @{@"ok":@(ok),@"bytes":@(data.length),@"afcError":@0};
}
static NSDictionary *CleanupOwned(AFCConnectionRef afc, NSString *source, NSString *link, NSString *recovered) {
    if (!GeneratedNamesMatch(source,link,recovered)) return @{@"ok":@NO};
    int status = 0; NSDictionary *info = StrictInfo(afc,link,&status);
    if (status != 0 && status != 8) return @{@"ok":@NO,@"afcError":@(status)};
    if (info) {
        if (![info[@"st_ifmt"] isEqual:@"S_IFLNK"] || ![info[@"LinkTarget"] isEqual:@"../../../var/mobile/Library/CountryBundles/Overlay"]) return @{@"ok":@NO};
        if (AFCRemovePath(afc,link.fileSystemRepresentation)) return @{@"ok":@NO};
    }
    info = StrictInfo(afc,source,&status);
    if (status != 0 && status != 8) return @{@"ok":@NO,@"afcError":@(status)};
    if (info && (![info[@"st_ifmt"] isEqual:@"S_IFDIR"] || !RemoveGeneratedTree(afc,source,0))) return @{@"ok":@NO};
    // Never remove a recovered original, or access link/leaf during cleanup.
    return @{@"ok":@YES,@"originalRetained":@YES};
}
