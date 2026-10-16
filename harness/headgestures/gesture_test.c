// AirPods gestures' detector against made-up head movements at the rate AirPods report (25 Hz):
// deliberate nods and shakes count once, nodding along to a song, looking down at the phone and a
// head turned diagonally never do.
//   cc -std=c11 -I tweak/Sources harness/headgestures/gesture_test.c tweak/Sources/Shared/HeadGestures/SGHeadGestureDetector.m -lm
#include "Shared/HeadGestures/SGHeadGestureDetector.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static double kRate = 25;
static const double kPi = 3.14159265358979;

typedef struct { double pitch, yaw; } Pose;
typedef Pose (*Motion)(double t);

static int counts[3];
static double clock_;

static void run(SGHeadGestureDetector *d, Motion motion, double seconds) {
    double start = clock_;
    for (int n = 0; n < (int)(seconds * kRate); n++) {
        clock_ += 1 / kRate;
        Pose pose = motion(clock_ - start);
        counts[SGHeadGestureFeed(d, clock_, pose.pitch, pose.yaw)]++;
    }
}
static void clear(void) { counts[0] = counts[1] = counts[2] = 0; }

static Pose still(double t) { (void)t; return (Pose){0.05, 0.3}; }
// Down, up, down, up and back to rest: one and a half nods' worth of swings at 2.5 Hz, 12 degrees.
static Pose nod(double t) {
    double p = t < 0.8 ? -0.21 * sin(2 * kPi * 2.5 * t) : 0;
    return (Pose){0.05 + p, 0.3};
}
// Left, right, left, back: a shake at 2 Hz, 17 degrees.
static Pose shake(double t) {
    double y = t < 0.75 ? 0.3 * sin(2 * kPi * 2 * t) : 0;
    return (Pose){0.05, 0.3 + y};
}
// Nodding along to a 120 bpm song for twenty seconds, never resting.
static Pose groove(double t) { return (Pose){0.05 - 0.18 * sin(2 * kPi * 2 * t), 0.3 + 0.03 * sin(2 * kPi * 0.3 * t)}; }
// Looking down at the phone over a second, and staying there.
static Pose lookDown(double t) { return (Pose){0.05 - 0.7 * fmin(1, t), 0.3}; }
// A quick diagonal circle: both axes at once.
static Pose diagonal(double t) {
    double a = t < 0.8 ? 0.25 * sin(2 * kPi * 2.5 * t) : 0;
    return (Pose){0.05 + a, 0.3 + a * 1.1};
}
// Yaw across the -pi/pi seam while shaking.
static Pose seamShake(double t) {
    double y = t < 0.75 ? 0.3 * sin(2 * kPi * 2 * t) : 0;
    double yaw = 3.1 + y;
    if (yaw > kPi) yaw -= 2 * kPi;
    return (Pose){0.05, yaw};
}

static Pose stillAtSeam(double t) { (void)t; return (Pose){0.05, 3.1}; }

static void suite(void) {
    SGHeadGestureDetector d;
    SGHeadGestureReset(&d);

    run(&d, still, 1); clear();
    run(&d, nod, 1); run(&d, still, 1);
    assert(counts[SGHeadGestureNod] == 1 && counts[SGHeadGestureShake] == 0);

    clear();
    run(&d, shake, 1); run(&d, still, 1);
    assert(counts[SGHeadGestureShake] == 1 && counts[SGHeadGestureNod] == 0);

    clear();
    run(&d, groove, 20); run(&d, still, 1);
    assert(counts[SGHeadGestureNod] == 0 && counts[SGHeadGestureShake] == 0);

    clear();
    run(&d, lookDown, 2); run(&d, still, 1);
    assert(counts[SGHeadGestureNod] == 0 && counts[SGHeadGestureShake] == 0);

    clear();
    run(&d, diagonal, 1); run(&d, still, 1);
    assert(counts[SGHeadGestureNod] == 0 && counts[SGHeadGestureShake] == 0);

    // A nod straight out of the groove, without a rest before it, does not count; after a rest it does.
    clear();
    run(&d, groove, 3); run(&d, nod, 1); run(&d, still, 1);
    assert(counts[SGHeadGestureNod] == 0);
    run(&d, nod, 1); run(&d, still, 1);
    assert(counts[SGHeadGestureNod] == 1);

    clear();
    run(&d, stillAtSeam, 1); run(&d, seamShake, 1); run(&d, stillAtSeam, 1);
    assert(counts[SGHeadGestureShake] == 1);

    // A gap in the readings starts over without a false gesture, and readings that are not numbers are ignored.
    clear();
    clock_ += 5;
    run(&d, still, 1); run(&d, nod, 1); run(&d, still, 1);
    assert(counts[SGHeadGestureNod] == 1);
    assert(SGHeadGestureFeed(&d, NAN, 0, 0) == SGHeadGestureNone);

}

// A small nod, half the size of the default one: missed at the default scale, caught once learned.
static Pose smallNod(double t) {
    double p = t < 0.8 ? -0.09 * sin(2 * kPi * 2.5 * t) : 0;
    return (Pose){0.05 + p, 0.3};
}

static void learned(void) {
    SGHeadGestureDetector d = {0};
    SGHeadGestureReset(&d);
    clear();
    run(&d, still, 1); run(&d, smallNod, 1); run(&d, still, 1);
    assert(counts[SGHeadGestureNod] == 0);
    d.nodScale = 0.45f;
    SGHeadGestureReset(&d);
    assert(d.nodScale == 0.45f);
    clear();
    run(&d, still, 1); run(&d, smallNod, 1); run(&d, still, 1);
    assert(counts[SGHeadGestureNod] == 1);
    // A listener who nods softly still does not trip it nodding along.
    clear();
    run(&d, groove, 10); run(&d, still, 1);
    assert(counts[SGHeadGestureNod] == 0);
}

int main(void) {
    // AirPods report at about 25 Hz; the detector should not care if that changes.
    double rates[] = {25, 50, 100};
    for (unsigned i = 0; i < 3; i++) { kRate = rates[i]; suite(); learned(); }
    puts("head gestures: nod, shake, groove, look down, diagonal, seam and gaps passed at 25, 50 and 100 Hz");
    return 0;
}
