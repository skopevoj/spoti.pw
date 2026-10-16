// SGHeadGestureDetector.h says what this tells apart and how.
#include "SGHeadGestureDetector.h"
#include <math.h>
#include <string.h>

static const double kPi = 3.14159265358979;
// Stillness: below this on both axes, and for how long before a gesture may start.
static const double kStillRate = 0.45, kStillBefore = 0.35;
// A swing starts above `on` and ends below `off` or when the head turns back.
static const double kNodOn = 1.1, kShakeOn = 1.4;
// The least it must turn, the longest it may take, and how far it must outrun the other axis.
static const double kNodTravel = 0.09, kShakeTravel = 0.14, kSwingLongest = 0.6, kDominance = 1.3;
// The most between one swing and the next, and how long the head rests before the gesture counts.
static const double kBetweenSwings = 0.3, kRestAfter = 0.25;
static const int kLeastSwings = 3, kMostSwings = 7;
// A gap in the readings this long starts over.
static const double kGap = 0.25;

static double wrap(double radians) {
    while (radians > kPi) radians -= 2 * kPi;
    while (radians < -kPi) radians += 2 * kPi;
    return radians;
}

static void clearAxis(SGHeadGestureAxis *axis) { memset(axis, 0, sizeof *axis); }

void SGHeadGestureReset(SGHeadGestureDetector *d) {
    float nod = d->nodScale, shake = d->shakeScale;
    memset(d, 0, sizeof *d);
    d->nodScale = nod;
    d->shakeScale = shake;
}

float SGHeadGestureNodSpeed(void) { return (float)kNodOn; }
float SGHeadGestureShakeSpeed(void) { return (float)kShakeOn; }

static double scaleOf(float scale) { return scale > 0.2f && scale < 5 ? scale : 1; }

// The swing that just ended joins the sequence, or ends it if it does not fit.
static void endSwing(SGHeadGestureAxis *axis, double time, double travel) {
    bool fits = axis->swingTravel >= travel && time - axis->swingStart <= kSwingLongest &&
        axis->swingPeak >= kDominance * axis->swingOtherPeak && (axis->swings == 0 || axis->swingSign != axis->lastSign);
    if (fits) {
        axis->swings++;
        axis->lastSign = axis->swingSign;
        axis->lastSwingEnd = time;
    } else {
        axis->swings = -1;   // spoilt: nothing counts until the head has been still again
    }
    axis->swingSign = 0;
}

// One axis's step; answers YES when its gesture has just ended.
static bool step(SGHeadGestureAxis *axis, double time, double dt, double rate, double other, double on, double travel,
                 bool wasStill) {
    int sign = rate > 0 ? 1 : -1;
    double speed = fabs(rate);
    if (axis->swingSign != 0 && (speed < on * 0.5 || sign != axis->swingSign)) endSwing(axis, time, travel);
    if (axis->swingSign == 0 && speed >= on) {
        bool joins = axis->swings > 0 && time - axis->lastSwingEnd <= kBetweenSwings;
        if (axis->swings == 0 && wasStill) joins = true;
        if (joins) {
            axis->swingSign = sign;
            axis->swingStart = time;
            axis->swingTravel = 0;
            axis->swingPeak = 0;
            axis->swingOtherPeak = 0;
        } else if (axis->swings > 0) {
            axis->swings = -1;
        }
    }
    if (axis->swingSign != 0) {
        axis->swingTravel += speed * dt;
        if (speed > axis->swingPeak) axis->swingPeak = speed;
        if (fabs(other) > axis->swingOtherPeak) axis->swingOtherPeak = fabs(other);
    }
    if (axis->swings > 0 && axis->swingSign == 0 && time - axis->lastSwingEnd >= kRestAfter) {
        bool gesture = axis->swings >= kLeastSwings && axis->swings <= kMostSwings;
        axis->swings = -1;
        return gesture;
    }
    return false;
}

SGHeadGesture SGHeadGestureFeed(SGHeadGestureDetector *d, double time, double pitch, double yaw) {
    if (!isfinite(time) || !isfinite(pitch) || !isfinite(yaw)) return SGHeadGestureNone;
    double dt = time - d->lastTime;
    if (!d->started || dt <= 0 || dt > kGap) {
        SGHeadGestureReset(d);
        d->started = true;
        d->lastTime = time; d->pitch = pitch; d->yaw = yaw;
        d->movingAt = time;   // stillness is counted from the first reading after a gap
        return SGHeadGestureNone;
    }
    double pitchRate = wrap(pitch - d->pitch) / dt, yawRate = wrap(yaw - d->yaw) / dt;
    d->pitchRate += (pitchRate - d->pitchRate) * 0.5;
    d->yawRate += (yawRate - d->yawRate) * 0.5;
    d->lastTime = time; d->pitch = pitch; d->yaw = yaw;

    bool wasStill = time - d->movingAt >= kStillBefore;
    bool still = fabs(d->pitchRate) < kStillRate && fabs(d->yawRate) < kStillRate;
    if (!still) d->movingAt = time;
    // A spoilt sequence waits for stillness before anything counts again.
    if (still && wasStill) {
        if (d->nod.swings < 0) clearAxis(&d->nod);
        if (d->shake.swings < 0) clearAxis(&d->shake);
    }
    double nodScale = scaleOf(d->nodScale), shakeScale = scaleOf(d->shakeScale);
    bool nod = step(&d->nod, time, dt, d->pitchRate, d->yawRate, kNodOn * nodScale, kNodTravel * nodScale, wasStill && d->nod.swings == 0);
    bool shake = step(&d->shake, time, dt, d->yawRate, d->pitchRate, kShakeOn * shakeScale, kShakeTravel * shakeScale, wasStill && d->shake.swings == 0);
    if (nod && !shake) return SGHeadGestureNod;
    if (shake && !nod) return SGHeadGestureShake;
    return SGHeadGestureNone;
}
