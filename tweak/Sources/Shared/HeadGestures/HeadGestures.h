// Head gestures (Mod Settings > Player > Head gestures), under either look: a double nod and a shake of the head,
// read out of AirPods' motion sensors, doing what a double tap on the player's cover can do (Gestures.h has the
// list: play or pause, next, previous, seek, shuffle, repeat).
//
//     SGHeadDetector.m        nod and shake out of pitch and yaw, and the learning of a person's own swing: plain C
//     HeadGestures.x          CMHeadphoneMotionManager fed to the detector while a song plays, the action it fires
//     HeadGesturesSettings.m  the Head gestures page
//
// The sensors are listened to only while the switch is on and a song is playing (or paused for under a minute, so a
// nod can still resume it), and only while AirPods that report their motion are in: the system asks the person
// once, with the NSMotionUsageDescription plist/ puts in Spotify's Info.plist. It applies at once, without a restart.
// Threading: the settings and the actions are main thread; the detector runs on the manager's own serial queue.
#import <UIKit/UIKit.h>
#import "Shared/Gestures/Gestures.h"

#define SGKeyHeadGestures @"spotifyglass.headgestures"                  // off until switched on
// What each gesture does, an SGGestureAction stored as its index into SGGestureActionNames().
#define SGKeyHeadNodAction @"spotifyglass.headgestures.nod"
#define SGKeyHeadShakeAction @"spotifyglass.headgestures.shake"
// How far the head has to tip (nod) or turn (shake) from where it rests, in degrees; learned or set by hand.
#define SGKeyHeadNodDegrees @"spotifyglass.headgestures.nod.degrees"
#define SGKeyHeadShakeDegrees @"spotifyglass.headgestures.shake.degrees"

enum {
    SGHeadDegreesMin = 5, SGHeadDegreesMax = 34,   // the detector's own range, 4.6 to 34 degrees
    SGHeadNodDegreesDefault = 14, SGHeadShakeDegreesDefault = 20,
};

// Reads the switch and the settings again and starts or stops listening. Call after any of them changed.
void SGHeadGesturesApply(void);
// What the feature is doing, for the settings page: Off, Waiting for a song, Waiting for AirPods, Listening, or
// that motion access was refused.
NSString *SGHeadGesturesStatus(void);
// Asks for `axis` (0 a nod, 1 a shake) to be performed for `seconds`, then stores the person's own threshold. `done`
// is told on the main thread whether enough swings were seen and the threshold in degrees. One run at a time.
void SGHeadGesturesCalibrate(NSInteger axis, NSTimeInterval seconds, void (^done)(BOOL found, NSInteger degrees));

UIViewController *SGHeadGesturesSettingsPage(void);
