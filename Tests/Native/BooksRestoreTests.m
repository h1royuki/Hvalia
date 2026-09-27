// Compile the shipping implementation against an in-memory AFC filesystem.
// No device discovery/session functions are called by this test executable.
#define main HvaliaUnusedDeviceMain
#define AFCFileInfoOpen TestFileInfoOpen
#define AFCKeyValueRead TestKeyValueRead
#define AFCKeyValueClose TestKeyValueClose
#define AFCFileRefOpen TestFileRefOpen
#define AFCFileRefRead TestFileRefRead
#define AFCFileRefWrite TestFileRefWrite
#define AFCFileRefClose TestFileRefClose
#define AFCDirectoryOpen TestDirectoryOpen
#define AFCDirectoryRead TestDirectoryRead
#define AFCDirectoryClose TestDirectoryClose
#define AFCDirectoryCreate TestDirectoryCreate
#define AFCRemovePath TestRemovePath
#include "../../Native/device_helper.m"
#undef main

@interface FakeHandle: NSObject
@property NSArray *entries;
@property NSUInteger index;
@property NSString *path;
@end
@implementation FakeHandle
@end
static NSMutableDictionary<NSString *, NSMutableDictionary *> *tree;
static NSMutableArray<NSString *> *removed;
static NSString *deniedPath;
static int failures=0, cases=0;
static void Check(BOOL value, NSString *label) { if (!value) { failures++; fprintf(stderr,"FAIL: %s\n",label.UTF8String); } }
static void Dir(NSString *path) { tree[path]=[@{@"kind":@"S_IFDIR"} mutableCopy]; }
static void File(NSString *path, NSString *contents) { tree[path]=[@{@"kind":@"S_IFREG",@"data":[contents dataUsingEncoding:NSUTF8StringEncoding]} mutableCopy]; }
static void *Retain(id value) { return (void *)CFBridgingRetain(value); }
static NSArray *Names(NSString *path) {
    NSMutableArray *a=NSMutableArray.array;
    for (NSString *key in tree) if ([[key stringByDeletingLastPathComponent] isEqual:path]) [a addObject:key.lastPathComponent];
    return [a sortedArrayUsingSelector:@selector(compare:)];
}
int TestFileInfoOpen(AFCConnectionRef afc,const char *path,AFCKeyValueRef *out) {
    NSString *p=@(path); if ([p isEqual:deniedPath]) return 10;
    NSDictionary *row=tree[p]; if (!row) return 8;
    FakeHandle *h=FakeHandle.new;
    h.entries=@[@[@"st_ifmt",row[@"kind"]],@[@"st_size",[NSString stringWithFormat:@"%lu",(unsigned long)[row[@"data"] length]]]];
    *out=Retain(h); return 0;
}
int TestKeyValueRead(AFCKeyValueRef ref,char **key,char **value) {
    FakeHandle *h=(__bridge FakeHandle *)ref;
    if (h.index>=h.entries.count) { *key=NULL;*value=NULL;return 0; }
    NSArray *row=h.entries[h.index++];*key=(char *)[row[0] UTF8String];*value=(char *)[row[1] UTF8String];return 0;
}
int TestKeyValueClose(AFCKeyValueRef ref) { CFRelease(ref);return 0; }
int TestFileRefOpen(AFCConnectionRef afc,const char *path,unsigned long long mode,AFCFileRef *out) {
    NSString *p=@(path); if ([p isEqual:deniedPath]) return 10;
    if (mode==3) {
        if (![tree[p.stringByDeletingLastPathComponent][@"kind"] isEqual:@"S_IFDIR"]) return 8;
        if (tree[p] && ![tree[p][@"kind"] isEqual:@"S_IFREG"]) return 10;
        File(p,@"");
    }
    if (![tree[p][@"kind"] isEqual:@"S_IFREG"]) return 8;
    FakeHandle *h=FakeHandle.new;h.path=p;*out=Retain(h);return 0;
}
int TestFileRefRead(AFCConnectionRef afc,AFCFileRef ref,void *bytes,long *length) {
    FakeHandle *h=(__bridge FakeHandle *)ref;NSData *data=tree[h.path][@"data"];
    NSUInteger n=MIN((NSUInteger)*length,data.length-h.index);
    if (n) memcpy(bytes,(const uint8_t *)data.bytes+h.index,n);
    *length=(long)n;h.index+=n;return 0;
}
int TestFileRefWrite(AFCConnectionRef afc,AFCFileRef ref,const void *bytes,long length) {
    FakeHandle *h=(__bridge FakeHandle *)ref;NSMutableData *data=[tree[h.path][@"data"] mutableCopy];
    [data appendBytes:bytes length:(NSUInteger)length];tree[h.path][@"data"]=data;return 0;
}
int TestFileRefClose(AFCConnectionRef afc,AFCFileRef ref) { CFRelease(ref);return 0; }
int TestDirectoryOpen(AFCConnectionRef afc,const char *path,AFCDirectoryRef *out) {
    NSString *p=@(path);if (![tree[p][@"kind"] isEqual:@"S_IFDIR"]) return 8;
    FakeHandle *h=FakeHandle.new;h.entries=Names(p);*out=Retain(h);return 0;
}
int TestDirectoryRead(AFCConnectionRef afc,AFCDirectoryRef ref,char **entry) {
    FakeHandle *h=(__bridge FakeHandle *)ref;*entry=h.index<h.entries.count ? (char *)[h.entries[h.index++] UTF8String] : NULL;return 0;
}
int TestDirectoryClose(AFCConnectionRef afc,AFCDirectoryRef ref) { CFRelease(ref);return 0; }
int TestDirectoryCreate(AFCConnectionRef afc,const char *path) {
    NSString *p=@(path),*parent=p.stringByDeletingLastPathComponent;
    if (tree[p] || (parent.length && ![tree[parent][@"kind"] isEqual:@"S_IFDIR"])) return 10;
    Dir(p);return 0;
}
int TestRemovePath(AFCConnectionRef afc,const char *path) {
    NSString *p=@(path);if (!tree[p]) return 8;
    if (Names(p).count) return 10;
    [removed addObject:p];[tree removeObjectForKey:p];return 0;
}
static NSString *Snapshot(int layout) {
    tree=NSMutableDictionary.dictionary;removed=NSMutableArray.array;deniedPath=nil;
    if (layout>0) { Dir(@"Books");File(@"Books/reader.epub",@"original book bytes"); }
    if (layout>1) { Dir(@"Books/Sync");Dir(@"Books/Sync/Database");File(@"Books/Sync/Database/OutstandingAssets_4.sqlite",@"original database"); }
    if (layout==3) File(@"Books/Sync/.bookSync.lock",@"");
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"Hvalia-native-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    Check([SnapshotBooksState(NULL,root)[@"ok"] boolValue],@"tracked snapshot");
    Check([FullSnapshot(NULL,root)[@"ok"] boolValue],@"full snapshot");return root;
}
static void Synced(void) {
    if (!tree[@"Books"]) Dir(@"Books");if (!tree[@"Books/Sync"]) Dir(@"Books/Sync");
    if (!tree[@"Books/Sync/Database"]) Dir(@"Books/Sync/Database");
    File(@"Books/Sync/Books.plist",@"generated sync manifest");File(@"Books/Sync/.bookSync.lock",@"");
    File(@"Books/Sync/Database/OutstandingAssets_4.sqlite",@"modified database");
}
static void Done(NSString *root) { [NSFileManager.defaultManager removeItemAtPath:root error:nil];cases++; }
int main(void) { @autoreleasepool {
    for (int layout=0;layout<3;layout++) {
        NSString *root=Snapshot(layout);Synced();
        Check(![FullVerify(NULL,root)[@"ok"] boolValue],@"preflight remains strict");
        NSDictionary *result=FullRestore(NULL,root);
        Check([result[@"ok"] boolValue],[@"restore with new lock layout " stringByAppendingFormat:@"%d",layout]);
        Check(tree[@"Books/Sync/.bookSync.lock"]!=nil,@"lock retained");
        Check(![removed containsObject:@"Books/Sync/.bookSync.lock"],@"lock never unlinked");
        if (layout>0) Check([tree[@"Books/reader.epub"][@"data"] isEqual:[@"original book bytes" dataUsingEncoding:NSUTF8StringEncoding]],@"book bytes preserved");
        if (layout>1) Check([tree[@"Books/Sync/Database/OutstandingAssets_4.sqlite"][@"data"] isEqual:[@"original database" dataUsingEncoding:NSUTF8StringEncoding]],@"database restored");
        Check([FullRestore(NULL,root)[@"ok"] boolValue],@"idempotent restore");Done(root);
    }
    NSString *root=Snapshot(2);Synced();File(@"Books/new-user-file.epub",@"new content");
    Check(![FullRestore(NULL,root)[@"ok"] boolValue],@"unknown new file rejected");Check(tree[@"Books/new-user-file.epub"]!=nil,@"unknown file retained");Done(root);
    root=Snapshot(0);Synced();File(@"Books/Sync/.bookSync.lock",@"unexpected content");
    Check(![FullRestore(NULL,root)[@"ok"] boolValue],@"nonempty lock rejected");Check(tree[@"Books/Sync/.bookSync.lock"]!=nil,@"nonempty lock preserved");Done(root);
    root=Snapshot(2);Synced();tree[@"Books/Sync/.bookSync.lock"]=[@{@"kind":@"S_IFLNK"} mutableCopy];
    Check(![FullRestore(NULL,root)[@"ok"] boolValue],@"symlink lock rejected");Done(root);
    root=Snapshot(2);Synced();deniedPath=@"Books/Sync/Database/OutstandingAssets_4.sqlite";
    Check(![FullRestore(NULL,root)[@"ok"] boolValue],@"access errors rejected");Done(root);
    root=Snapshot(2);File(@"Books/reader.epub",@"changed book");
    Check(![FullVerify(NULL,root)[@"ok"] boolValue],@"changed original bytes rejected");
    Check([FullRestore(NULL,root)[@"ok"] boolValue],@"changed original bytes restored");Done(root);
    root=Snapshot(3);Synced();[tree removeObjectForKey:@"Books/Sync/.bookSync.lock"];
    Check([FullRestore(NULL,root)[@"ok"] boolValue],@"service may remove an existing empty lock");
    Check(tree[@"Books/Sync/.bookSync.lock"]==nil,@"runtime lock not recreated");Done(root);
    root=Snapshot(3);Synced();File(@"Books/Sync/.bookSync.lock",@"new unexpected lock data");
    Check(![FullRestore(NULL,root)[@"ok"] boolValue],@"changed existing lock rejected");
    Check([tree[@"Books/Sync/.bookSync.lock"][@"data"] length]>0,@"runtime lock not truncated");Done(root);
    printf("%d native Books scenarios, %d failures; no device access\n",cases,failures);return failures ? 1 : 0;
} }
