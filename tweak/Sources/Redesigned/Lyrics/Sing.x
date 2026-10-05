#import "Core/SGCore.h"
#import "Sing.h"
#import "Shared/Sing/SGSingController.h"

// Only the running look is told: a redesign switched on in Appearance but not yet restarted into takes the
// switch as it finds it at its launch.
void SGRSingApplySwitch(void) {
    if (!SGRedesignedUI()) return;
    SGSingConfigure(SGFlag(SGRKeySing, NO));
}

void SGRSingApplyVocalsOnly(void) {
    if (!SGRedesignedUI()) return;
    SGSingSetVocalsOnly(SGFlag(SGRKeySingVocalsOnly, NO));
}

%ctor {
    if (!SGRedesignedUI()) return;
    dispatch_async(dispatch_get_main_queue(), ^{ SGRSingApplySwitch(); SGRSingApplyVocalsOnly(); });
}
