#import <Orion/Orion.h>
#import <Foundation/Foundation.h>

static void StudifyOverlayLog(NSString *message) {
    NSString *logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"studify_overlay_debug.log"];
    NSString *timestamp = [[NSDate date] description];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];

    if ([[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

__attribute__((constructor)) static void init() {
    @try {
        NSLog(@"[StudifyOverlay] Initializing overlay tweak...");
        orion_init();
        NSLog(@"[StudifyOverlay] Overlay initialized successfully");
    }
    @catch (NSException *exception) {
        NSString *message = [NSString stringWithFormat:@"ERROR: overlay init failed: %@, reason: %@", exception, [exception reason]];
        NSLog(@"[StudifyOverlay] %@", message);
        StudifyOverlayLog(message);
    }
}
