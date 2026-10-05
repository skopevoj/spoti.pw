#include "SGHeadDetector.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

static const double kMinimumThreshold = 0.08, kMaximumThreshold = 0.6;
static const double kBaselineSeconds = 2.0;    // the resting attitude follows the head with this time constant
static const double kPeakHalfLife = 0.8;       // how long the far end of a swing is remembered
static const double kQuietAxis = 0.7;          // the other axis must have moved less than this much of the gesture's own
static const double kLargestGap = 0.5;         // a longer silence in the samples starts the detector over

static double clampThreshold(double value) {
    return isfinite(value) ? fmax(kMinimumThreshold, fmin(kMaximumThreshold, value)) : 0.2;
}
// An angle difference taken the short way round, for yaw, which jumps at the half turn.
static double wrap(double angle) {
    while (angle > M_PI) angle -= 2 * M_PI;
    while (angle < -M_PI) angle += 2 * M_PI;
    return angle;
}
static int signOf(double value) { return value < 0 ? -1 : 1; }

void SGHeadDetectorInit(SGHeadDetector *d, double nodThreshold, double shakeThreshold) {
    memset(d, 0, sizeof *d);
    d->nodThreshold = clampThreshold(nodThreshold);
    d->shakeThreshold = clampThreshold(shakeThreshold);
    SGHeadDetectorReset(d);
}

void SGHeadDetectorReset(SGHeadDetector *d) {
    d->primed = false;
    d->count[0] = d->count[1] = 0;
    d->recentPeak[0] = d->recentPeak[1] = 0;
    d->armed[0] = d->armed[1] = true;
    d->lastSign[0] = d->lastSign[1] = 0;
}

SGHeadEvent SGHeadDetectorFeed(SGHeadDetector *d, double time, double pitch, double yaw) {
    if (!isfinite(time) || !isfinite(pitch) || !isfinite(yaw)) return SGHeadEventNone;
    double angle[2] = {pitch, yaw};
    if (!d->primed || time <= d->lastTime || time - d->lastTime > kLargestGap) {
        SGHeadDetectorReset(d);
        d->baseline[0] = pitch;
        d->baseline[1] = yaw;
        d->lastTime = time;
        d->primed = true;
        return SGHeadEventNone;
    }
    double dt = time - d->lastTime;
    d->lastTime = time;
    double follow = 1 - exp(-dt / kBaselineSeconds), fade = pow(0.5, dt / kPeakHalfLife);
    double threshold[2] = {d->nodThreshold, d->shakeThreshold};
    double window[2] = {SGHeadNodWindow, SGHeadShakeWindow};
    int needed[2] = {SGHeadNodExcursions, SGHeadShakeExcursions};
    double offset[2];
    for (int axis = 0; axis < 2; axis++) {
        offset[axis] = wrap(angle[axis] - d->baseline[axis]);
        d->baseline[axis] = wrap(d->baseline[axis] + wrap(angle[axis] - d->baseline[axis]) * follow);
        d->recentPeak[axis] = fmax(fabs(offset[axis]), d->recentPeak[axis] * fade);
    }
    if (time < d->cooldownUntil) return SGHeadEventNone;

    for (int axis = 0; axis < 2; axis++) {
        double away = fabs(offset[axis]);
        int sign = signOf(offset[axis]);
        if (away < threshold[axis] * 0.5) d->armed[axis] = true;
        // Past the threshold, having come back (or having gone round to the other side): one more excursion.
        if (away > threshold[axis] && (d->armed[axis] || sign != d->lastSign[axis])) {
            d->armed[axis] = false;
            d->lastSign[axis] = sign;
            // Only the ones still inside the window count.
            int kept = 0;
            for (int i = 0; i < d->count[axis]; i++) {
                if (time - d->times[axis][i] <= window[axis]) d->times[axis][kept++] = d->times[axis][i];
            }
            d->count[axis] = kept;
            if (d->count[axis] < SGHeadShakeExcursions + 1) d->times[axis][d->count[axis]++] = time;
            if (d->count[axis] >= needed[axis]) {
                int other = 1 - axis;
                bool quiet = d->recentPeak[other] < kQuietAxis * d->recentPeak[axis];
                d->count[0] = d->count[1] = 0;
                if (!quiet) continue;
                d->cooldownUntil = time + SGHeadCooldown;
                d->recentPeak[0] = d->recentPeak[1] = 0;
                d->armed[0] = d->armed[1] = false;
                return axis == 0 ? SGHeadEventNod : SGHeadEventShake;
            }
        }
    }
    return SGHeadEventNone;
}

#pragma mark - learning the swing of a person

void SGHeadCalibratorBegin(SGHeadCalibrator *c) {
    memset(c, 0, sizeof *c);
    c->axis = -1;
}

void SGHeadCalibratorSetAxis(SGHeadCalibrator *c, int axis) {
    c->axis = axis == 0 || axis == 1 ? axis : -1;
    c->extreme[0] = c->extreme[1] = 0;
}

static void record(SGHeadCalibrator *c, int axis) {
    if (c->axis == axis && c->count[axis] < SGHeadCalibrationPeaks && c->extreme[axis] > kMinimumThreshold) {
        c->peaks[axis][c->count[axis]++] = c->extreme[axis];
    }
    c->extreme[axis] = 0;
}

void SGHeadCalibratorFeed(SGHeadCalibrator *c, double time, double pitch, double yaw) {
    if (!isfinite(time) || !isfinite(pitch) || !isfinite(yaw)) return;
    double angle[2] = {pitch, yaw};
    if (!c->primed || time <= c->lastTime || time - c->lastTime > kLargestGap) {
        c->baseline[0] = pitch;
        c->baseline[1] = yaw;
        c->lastTime = time;
        c->primed = true;
        return;
    }
    double dt = time - c->lastTime, follow = 1 - exp(-dt / kBaselineSeconds);
    c->lastTime = time;
    for (int axis = 0; axis < 2; axis++) {
        double offset = wrap(angle[axis] - c->baseline[axis]);
        c->baseline[axis] = wrap(c->baseline[axis] + offset * follow);
        int sign = signOf(offset);
        // A swing ends when the head comes back to rest or goes round to the other side.
        if (c->extreme[axis] > 0 && (fabs(offset) < kMinimumThreshold * 0.5 || sign != c->lastSign[axis])) record(c, axis);
        if (fabs(offset) > c->extreme[axis]) c->extreme[axis] = fabs(offset);
        c->lastSign[axis] = sign;
    }
}

static int compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

bool SGHeadCalibratorResult(const SGHeadCalibrator *c, int axis, double *threshold) {
    if ((axis != 0 && axis != 1) || c->count[axis] < 3) return false;
    double sorted[SGHeadCalibrationPeaks];
    int n = c->count[axis];
    memcpy(sorted, c->peaks[axis], (size_t)n * sizeof(double));
    qsort(sorted, (size_t)n, sizeof(double), compare);
    double median = n % 2 ? sorted[n / 2] : 0.5 * (sorted[n / 2 - 1] + sorted[n / 2]);
    if (threshold) *threshold = clampThreshold(0.55 * median);
    return true;
}
