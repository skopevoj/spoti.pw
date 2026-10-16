// A nod or a shake of the head, told apart from nodding along to the music: plain C, fed the head's
// attitude from AirPods head tracking (Shared/HeadMotion) and tested on the Mac or Linux against
// harness/headgestures/.
//
// A gesture is a quick back and forth of at least three swings on one axis (down, up, down for a nod;
// left, right, left for a shake), each turning at least a few degrees fast, the other axis staying
// mostly still, begun after a moment of stillness and followed by one. Nodding along to a song never
// rests between nods, so it is never taken for a gesture, and neither is looking down at the phone,
// which is too slow.
#pragma once
#include <stdbool.h>

typedef enum { SGHeadGestureNone = 0, SGHeadGestureNod, SGHeadGestureShake } SGHeadGesture;

typedef struct {
    int swingSign;                 // the direction of the swing going on, 0 between swings
    double swingStart, swingTravel, swingPeak, swingOtherPeak;
    int swings, lastSign;          // valid swings in the sequence so far, and the last one's direction
    double lastSwingEnd;
} SGHeadGestureAxis;

typedef struct {
    // How hard this listener nods and shakes against the defaults, learned (HeadGesturesSettings.m): the
    // speeds and turns a swing needs are scaled by these. 0 is taken as 1.
    float nodScale, shakeScale;
    bool started;
    double lastTime, pitch, yaw;   // the previous reading
    double pitchRate, yawRate;     // smoothed, radians a second
    double movingAt;               // when the head last moved more than stillness allows
    SGHeadGestureAxis nod, shake;
} SGHeadGestureDetector;

// Keeps the scales.
void SGHeadGestureReset(SGHeadGestureDetector *detector);
// The default speed a nod's and a shake's swing starts at, radians a second, for learning a listener's own.
float SGHeadGestureNodSpeed(void);
float SGHeadGestureShakeSpeed(void);
// One reading: its time in seconds and the head's pitch and yaw in radians (Core Motion's attitude).
// Answers the gesture that has just ended, if one has.
SGHeadGesture SGHeadGestureFeed(SGHeadGestureDetector *detector, double time, double pitch, double yaw);
