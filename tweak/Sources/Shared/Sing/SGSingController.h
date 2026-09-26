// Sing's player lifecycle and worker ownership. Main thread except the clock and invalidation APIs.
#import <Foundation/Foundation.h>
#include "SGSingLevel.h"
@class SPTPlayerState;
#define SGKeySingKillSwitch @"spotifyglass.sing.killSwitch"
extern NSString *const SGSingDidChangeNotification;
typedef NS_ENUM(NSUInteger, SGSingState) {
    SGSingUnavailable, SGSingIdle, SGSingPreparing, SGSingActive, SGSingDraining, SGSingFailed,
    SGSingReady, // the local model is loaded; playback has not supplied audio yet
    SGSingRecovering // aligned original audio while a temporarily late worker catches up
};
void SGSingConfigure(BOOL enabled);
BOOL SGSingConfigured(void);
SGSingState SGSingCurrentState(void);
NSString *SGSingExplanation(void);
BOOL SGSingCanRetry(void); // current playback/thermal restrictions and previous generation retired
BOOL SGSingEnabled(void); // user's intent, retained across playback changes
float SGSingVocalLevel(void);
float SGSingReducedLevel(void);
void SGSingSetVocalLevel(float level);
void SGSingSetEnabled(BOOL enabled);
// Before/after an explicit seek or skip. The first invalidates render output immediately.
void SGSingPlaybackWillChange(void);
void SGSingPlaybackDidChange(void);
void SGSingPlaybackDidSeek(double seconds);
uint64_t SGSingTrackIdentifier(id uri);
BOOL SGSingPosition(SPTPlayerState *state, double *position);
double SGSingSourcePosition(SPTPlayerState *state); // the unmodified player getter, defined by hooks
