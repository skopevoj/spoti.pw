// SGSpatialVoice.h says what this is.
#import "Core/SGCore.h"
#import "Shared/HeadMotion/SGHeadMotion.h"
#import "SGSingController.h"
#import "SGSingDSP.h"
#import "SGSpatialVoice.h"
#include <math.h>

// How long "in front" takes to settle on where the head rests, with Follow the iPhone on.
static const double kFollowSeconds = 8;

static id sg_token;
// The head queue's own: where in front is, and when the last reading came.
static double sg_reference;
static double sg_lastTime;
static BOOL sg_started;

static double wrap(double radians) {
    while (radians > M_PI) radians -= 2 * M_PI;
    while (radians < -M_PI) radians += 2 * M_PI;
    return radians;
}

static void follow(CMDeviceMotion *motion) {
    double yaw = motion.attitude.yaw;
    if (!sg_started) {
        sg_reference = yaw;
        sg_started = YES;
    } else if (SGFlag(SGKeySpatialVoiceFollow, YES)) {
        double elapsed = sg_lastTime > 0 ? motion.timestamp - sg_lastTime : 0;
        if (elapsed > 0 && elapsed < 1) sg_reference = wrap(sg_reference + wrap(yaw - sg_reference) * (elapsed / kFollowSeconds));
    }
    sg_lastTime = motion.timestamp;
    // Core Motion's yaw grows as the head turns left, which leaves the voice to its right.
    SGSingSpatialSetAzimuth((float)wrap(yaw - sg_reference));
}

void SGSpatialVoiceApply(void) {
    BOOL wanted = SGFlag(SGKeySpatialVoice, NO) && SGHeadMotionSupported() && SGSingStateIsOn(SGSingCurrentState());
    SGSingSpatialSetEnabled(SGFlag(SGKeySpatialVoice, NO));
    if (wanted && !sg_token) {
        sg_started = NO;
        sg_lastTime = 0;
        SGSingSpatialSetAzimuth(0);
        sg_token = SGHeadMotionAddObserver(^(CMDeviceMotion *motion) { follow(motion); });
        SGLog(@"spatial voice: following the head");
    } else if (!wanted && sg_token) {
        SGHeadMotionRemoveObserver(sg_token);
        sg_token = nil;
        SGSingSpatialSetAzimuth(0);
        SGLog(@"spatial voice: stopped");
    }
}
