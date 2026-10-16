// Listening stats record from launch while switched on, and write down the listen going on whenever
// Spotify leaves the screen or is about to be quit (ListeningStats.h).
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "ListeningStats.h"

void SGListeningStatsFlush(void);

%ctor {
    if (SGOff("stats")) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGListeningStatsApply();
        for (NSNotificationName name in @[UIApplicationDidEnterBackgroundNotification, UIApplicationWillTerminateNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                        usingBlock:^(NSNotification *note) { SGListeningStatsFlush(); }];
        }
    });
}
