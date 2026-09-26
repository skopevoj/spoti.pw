#import "Core/SGCore.h"
#import "SGRSingControl.h"
#import "Shared/Sing/SGSingController.h"

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGFlag(SGRKeySing, NO)) return;
    dispatch_async(dispatch_get_main_queue(), ^{ SGSingConfigure(YES); });
}
