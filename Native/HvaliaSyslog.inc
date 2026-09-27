// Native read-only syslog_relay client. Uses Apple's system framework, no bundled third-party executable.
extern long AMDServiceConnectionReceive(AMDServiceConnectionRef connection, void *bytes, long length);
static int StreamLogs(DeviceSession *session, NSString *filter) {
    if (!session->sessionStarted || !([filter isEqual:@"atc"] || [filter isEqual:@"CommCenter"])) return 2;
    AMDServiceConnectionRef service = NULL;
    if (AMDeviceSecureStartService(session->device, CFSTR("com.apple.syslog_relay"), NULL, &service) || !service) return 3;
    struct timeval timeout = {.tv_sec=3,.tv_usec=0};
    setsockopt(AMDServiceConnectionGetSocket(service),SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    const char *ready="HVALIA_LOG_READY\n"; write(STDOUT_FILENO,ready,strlen(ready));
    NSMutableData *pending=NSMutableData.data;
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:600];
    NSUInteger written=0;
    pid_t parent = getppid();
    while (getppid() == parent && end.timeIntervalSinceNow > 0 && written < 32*1024*1024) {
        char buffer[4096]; long count=AMDServiceConnectionReceive(service,buffer,sizeof(buffer));
        if (count <= 0) break;
        for (long i=0;i<count;i++) {
            if (buffer[i] == '\n' || buffer[i] == '\0') {
                if (pending.length) {
                    NSString *line=[[NSString alloc] initWithData:pending encoding:NSUTF8StringEncoding];
                    if ([line containsString:filter]) { write(STDOUT_FILENO,pending.bytes,pending.length); write(STDOUT_FILENO,"\n",1); written+=pending.length+1; }
                    [pending setLength:0];
                }
            } else {
                [pending appendBytes:&buffer[i] length:1];
                if (pending.length > 1024*1024) { AMDServiceConnectionInvalidate(service); return 4; }
            }
        }
    }
    AMDServiceConnectionInvalidate(service); return 0;
}
