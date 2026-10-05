// Nod and shake, read out of a head's attitude: plain C, no Foundation, so harness/headgestures tests it on a Mac or
// Linux with synthetic movements. Fed pitch and yaw in radians at whatever rate the headphones report (AirPods:
// about 25 Hz), on one thread at a time.
//
// The attitude is made relative to a slow average of itself, so where the head rests does not matter, only the
// swing around it. A swing is an "excursion": the head going further than the threshold from that average and
// coming back (or going the other way). A nod is two excursions of pitch within a short time, a shake three of yaw,
// and the other axis must have stayed quiet, so turning to look at something and then at something else is not a
// shake and a nod along to a song at a small amplitude is not a nod. After one gesture the detector is deaf for a
// moment, so one nod is one action.
#pragma once
#include <stdbool.h>

typedef enum { SGHeadEventNone, SGHeadEventNod, SGHeadEventShake } SGHeadEvent;

// How many excursions make each gesture, and in how long; and the rest after one.
enum { SGHeadNodExcursions = 2, SGHeadShakeExcursions = 3 };
#define SGHeadNodWindow 1.4
#define SGHeadShakeWindow 1.8
#define SGHeadCooldown 2.0

typedef struct {
    double nodThreshold, shakeThreshold;   // radians away from the resting attitude
    double baseline[2];                    // the slow average of pitch, yaw
    double lastTime, cooldownUntil;
    double recentPeak[2];                  // the furthest the head went on each axis lately, fading
    double times[2][SGHeadShakeExcursions + 1];
    int count[2], lastSign[2];
    bool primed, armed[2];
} SGHeadDetector;

// Both thresholds in radians; what is out of range is brought into 0.08 ... 0.6 (4.6 to 34 degrees).
void SGHeadDetectorInit(SGHeadDetector *detector, double nodThreshold, double shakeThreshold);
// Forgets the resting attitude and any gesture under way: for a gap in the samples or headphones that came back.
void SGHeadDetectorReset(SGHeadDetector *detector);
// `time` in seconds, any origin, increasing. The event is returned once, the moment the gesture completes.
SGHeadEvent SGHeadDetectorFeed(SGHeadDetector *detector, double time, double pitch, double yaw);

// The threshold of a person's own movement, found by asking them to nod and then shake: the swings of each
// axis are measured while its phase runs.
enum { SGHeadCalibrationPeaks = 48 };
typedef struct {
    double baseline[2], lastTime;
    double extreme[2];                     // the furthest point of the swing in progress
    int axis;                              // which axis is being measured: 0 pitch, 1 yaw, -1 none
    double peaks[2][SGHeadCalibrationPeaks];
    int count[2], lastSign[2];
    bool primed;
} SGHeadCalibrator;

void SGHeadCalibratorBegin(SGHeadCalibrator *calibrator);
void SGHeadCalibratorSetAxis(SGHeadCalibrator *calibrator, int axis);
void SGHeadCalibratorFeed(SGHeadCalibrator *calibrator, double time, double pitch, double yaw);
// The threshold for `axis` (0 nod, 1 shake), a little over half the typical swing, once at least three
// swings were seen; false with nothing written when there were fewer.
bool SGHeadCalibratorResult(const SGHeadCalibrator *calibrator, int axis, double *threshold);
