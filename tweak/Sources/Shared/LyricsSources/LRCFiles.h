#import <Foundation/Foundation.h>
#import "LyricsSources.h"

NSArray<NSString *> *SGLRCFiles(void);
NSString *SGLRCImport(NSURL *url, NSError **error);
BOOL SGLRCDelete(NSString *name);
void SGLRCAssignToTrack(NSString *name, NSString *trackID);
extern SGLyricsAsk SGImportedLRCAsk;
UIViewController *SGLRCFilesPage(void);
