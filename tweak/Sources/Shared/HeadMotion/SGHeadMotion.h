// AirPods head tracking, one CMHeadphoneMotionManager for the whole app: Spatial voice (Shared/Sing) and
// AirPods gestures (Shared/HeadGestures) each ask for it while they need it, and it runs only while one
// does. Headphones without head tracking, or none at all, simply send nothing.
//
// The first start asks for Motion & Fitness access, worded by NSMotionUsageDescription, which
// scripts/merge-local-network-plist.py adds to the IPA when Spotify has none of its own.
//
// Threading: observers are called on a serial queue of the module's own, never the main thread.
#import <Foundation/Foundation.h>
#import <CoreMotion/CoreMotion.h>

typedef void (^SGHeadMotionHandler)(CMDeviceMotion *motion);

// Starts the updates if they are not running; the token is what stops them again.
id SGHeadMotionAddObserver(SGHeadMotionHandler handler);
void SGHeadMotionRemoveObserver(id token);
// The iPhone can do head tracking at all (iOS 14 and up); says nothing about what is connected.
BOOL SGHeadMotionSupported(void);
// Head tracking headphones are connected and sending, as far as the manager has said.
BOOL SGHeadMotionConnected(void);
