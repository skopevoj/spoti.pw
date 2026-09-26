// UI fixture only. The audio/controller integration is exercised separately in the real app.
#import <UIKit/UIKit.h>
#import "Shared/Sing/SGSingController.h"
NSString *const SGSingDidChangeNotification = @"spotifyglass.singChanged";
static SGSingState state = SGSingIdle;
static float level = SGSingMinimumVocalLevel, reduced = SGSingMinimumVocalLevel;
static NSUInteger generation;
BOOL SGSingConfigured(void) { return [NSUserDefaults.standardUserDefaults boolForKey:@"sing-ui"]; }
SGSingState SGSingCurrentState(void) { return state; }
NSString *SGSingExplanation(void) { return @"Test model unavailable"; }
BOOL SGSingCanRetry(void) { return ![NSUserDefaults.standardUserDefaults boolForKey:@"sing-blocked"]; }
float SGSingVocalLevel(void) { return level; }
float SGSingReducedLevel(void) { return reduced; }
static void changed(void) { [NSNotificationCenter.defaultCenter postNotificationName:SGSingDidChangeNotification object:nil]; }
void SGSingSetVocalLevel(float value) { level = SGSingClampLevel(value); if (level < 1) reduced = level; changed(); }
void SGSingSetEnabled(BOOL enabled) {
    if (enabled && !SGSingCanRetry()) { state = SGSingFailed; changed(); return; }
    NSUInteger ticket = ++generation;
    state = enabled ? SGSingPreparing : SGSingDraining; changed();
    double delay = [NSUserDefaults.standardUserDefaults boolForKey:@"sing-slow"] ? 6 : 0.5;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (ticket != generation) return;
        state = enabled ? ([NSUserDefaults.standardUserDefaults boolForKey:@"sing-paused"] ? SGSingReady : SGSingActive) : SGSingIdle; changed();
        if (enabled && [NSUserDefaults.standardUserDefaults boolForKey:@"sing-recovery"]) {
            state = SGSingRecovering; changed();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (ticket != generation) return;
                state = SGSingActive; changed();
            });
        }
    });
}
