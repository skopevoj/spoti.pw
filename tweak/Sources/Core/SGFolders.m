// SGFolders.h says what this is.
#import "SGFolders.h"
#import "SGLog.h"

NSString *SGDocumentsFolder(void) {
    static NSString *folder;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        folder = [documents stringByAppendingPathComponent:@"rokis.pw"];
        NSString *earlier = [documents stringByAppendingPathComponent:@"spoti.pw"];
        NSFileManager *files = NSFileManager.defaultManager;
        if ([files fileExistsAtPath:earlier] && ![files fileExistsAtPath:folder]) {
            NSError *error = nil;
            BOOL moved = [files moveItemAtPath:earlier toPath:folder error:&error];
            SGLog(@"folders: Documents/spoti.pw %@", moved ? @"moved to Documents/rokis.pw" : error.localizedDescription);
        }
    });
    return folder;
}
