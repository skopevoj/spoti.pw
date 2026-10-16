// Spatial voice follows Sing on and off (SGSpatialVoice.h).
#import "Core/SGCore.h"
#import "SGSingController.h"
#import "SGSpatialVoice.h"

%ctor {
    if (!SGSingSupported()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:SGSingDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) { SGSpatialVoiceApply(); }];
        SGSpatialVoiceApply();
    });
}
