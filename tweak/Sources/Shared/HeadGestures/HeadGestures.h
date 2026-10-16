// AirPods gestures (Mod Settings > AirPods gestures), under either look: with head tracking AirPods in,
// nodding twice or shaking the head runs a player command of the user's picking, so a song can be
// skipped or paused with both hands full. The head is read through Shared/HeadMotion and told apart
// from nodding along by SGHeadGestureDetector (plain C, harness/headgestures/). The commands are the
// ones the mini player sends (SPTPlayer.h). The switch and the choices apply at once.
//
//     HeadGestures.m          follows the head while the switch is on, runs the command
//     HeadGesturesSettings.m  its page
//     HeadGestures.x          starts it at launch
#import <UIKit/UIKit.h>

#define SGKeyHeadGestures @"spotifyglass.headGestures"            // off until switched on
#define SGKeyHeadGestureNod @"spotifyglass.headGestures.nod"      // an SGHeadGestureAction, Like unset
#define SGKeyHeadGestureShake @"spotifyglass.headGestures.shake"  // an SGHeadGestureAction, Next track unset
// How hard this listener nods and shakes against the defaults, in percent, learned on the page; 100 unset.
#define SGKeyHeadGestureNodScale @"spotifyglass.headGestures.nodScale"
#define SGKeyHeadGestureShakeScale @"spotifyglass.headGestures.shakeScale"

typedef NS_ENUM(NSInteger, SGHeadGestureAction) {
    SGHeadGestureActionNothing = 0,
    SGHeadGestureActionPlayPause,
    SGHeadGestureActionNext,
    SGHeadGestureActionPrevious,
    SGHeadGestureActionRestart,
    SGHeadGestureActionLike,   // saved to Liked Songs (Shared/Player/SGLibrary.h)
};

// Follows the head for `seconds` and answers with the fastest nod and shake swings seen, radians a second;
// nil and nil when no head tracking came in. Main thread, the answer too.
void SGHeadGesturesMeasure(NSTimeInterval seconds, void (^done)(NSNumber *nodSpeed, NSNumber *shakeSpeed));

// Reads the switch and starts or stops following the head. Main thread.
void SGHeadGesturesApply(void);
UIViewController *SGHeadGesturesSettingsPage(void);
// Beside the row on Mod Settings' main page: Off, or On.
NSString *SGHeadGesturesSummary(void);
