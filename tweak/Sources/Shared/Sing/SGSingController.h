// Sing's player lifecycle and worker ownership. Main thread except the clock and invalidation APIs.
#import <Foundation/Foundation.h>
#include "SGSingLevel.h"
@class SPTPlayerState;
extern NSString *const SGSingDidChangeNotification;
typedef NS_ENUM(NSUInteger, SGSingState) {
    SGSingUnavailable, SGSingIdle, SGSingPreparing, SGSingActive, SGSingDraining, SGSingFailed,
    SGSingReady, // the local model is loaded; playback has not supplied audio yet
    SGSingRecovering // aligned original audio while a temporarily late worker catches up
};
// Sing is on: the model is loaded and the song's vocals are turned down, or will be as soon as it
// plays (Ready), or are about to be again (Recovering).
static inline BOOL SGSingStateIsOn(SGSingState state) {
    return state == SGSingActive || state == SGSingReady || state == SGSingRecovering;
}
BOOL SGSingSupported(void); // iOS 27, the first the separator runs on
// Sing's switch (the redesign's Mod Settings > Karaoke), at launch and whenever it is turned. Off, Sing does no
// work and is unavailable; on, it is available once its voice model is on this iPhone (SGSingModel.h).
void SGSingConfigure(BOOL enabled);
SGSingState SGSingCurrentState(void);
// Sing is switched on and has its model: the lyrics show its microphone. SGSingDidChangeNotification says
// when this changes.
BOOL SGSingAvailable(void);
NSString *SGSingExplanation(void);
BOOL SGSingCanRetry(void); // current playback/thermal restrictions and previous generation retired
BOOL SGSingEnabled(void); // user's intent, retained across playback changes
float SGSingVocalLevel(void);
float SGSingReducedLevel(void); // the last level below 100 %, which turning Sing on goes back to
void SGSingSetVocalLevel(float level);
// Vocals only: the instrumental is taken out and the vocals play at full, whatever the level. Sing's switch
// still decides whether it runs; this changes what it plays. Safe before Sing is configured.
BOOL SGSingVocalsOnly(void);
void SGSingSetVocalsOnly(BOOL vocalsOnly);
void SGSingSetEnabled(BOOL enabled);
// Before/after an explicit seek or skip. The first invalidates render output immediately.
void SGSingPlaybackWillChange(void);
void SGSingPlaybackDidChange(void);
void SGSingPlaybackDidSeek(double seconds);
uint64_t SGSingTrackIdentifier(id uri);
BOOL SGSingPosition(SPTPlayerState *state, double *position);
double SGSingSourcePosition(SPTPlayerState *state); // the unmodified player getter, defined by hooks
