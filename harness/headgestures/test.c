// Tests SGHeadDetector.m on synthetic head movement, at the rate AirPods report (25 Hz). Plain C, no iPhone. From the
// repo root:  cc -x c -std=gnu11 -O1 -Wall -o /tmp/headgestures harness/headgestures/test.c
//             tweak/Sources/Shared/HeadGestures/SGHeadDetector.m -lm && /tmp/headgestures
#include "../../tweak/Sources/Shared/HeadGestures/SGHeadDetector.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define RATE 25.0
static int failures;

#define CHECK(condition, ...) do { if (!(condition)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

// Radians for degrees.
static double rad(double degrees) { return degrees * M_PI / 180.0; }

typedef struct { double time; int nods, shakes; } Run;

static void feed(SGHeadDetector *d, Run *run, double pitch, double yaw) {
    SGHeadEvent event = SGHeadDetectorFeed(d, run->time, pitch, yaw);
    if (event == SGHeadEventNod) run->nods++;
    if (event == SGHeadEventShake) run->shakes++;
    run->time += 1.0 / RATE;
}

// Seconds of a head at rest, a little noisy.
static void rest(SGHeadDetector *d, Run *run, double seconds, double pitch, double yaw) {
    for (int i = 0; i < seconds * RATE; i++) {
        double noise = rad(0.4) * sin(i * 1.7);
        feed(d, run, pitch + noise, yaw - noise);
    }
}

// `cycles` swings on one axis of `amplitude` degrees (a shake: both ways), each `period` seconds long, the other axis still.
static void swing(SGHeadDetector *d, Run *run, int axis, int cycles, double amplitude, double period, double pitch0, double yaw0) {
    int steps = (int)(cycles * period * RATE);
    for (int i = 0; i < steps; i++) {
        double angle = rad(amplitude) * sin(2 * M_PI * i / (period * RATE));
        feed(d, run, pitch0 + (axis == 0 ? angle : 0), yaw0 + (axis == 1 ? angle : 0));
    }
}

// `cycles` nods of `amplitude` degrees: a real nod tips the head down and brings it back once, so the swing is one
// sided, each `period` seconds long, the yaw still.
static void nod(SGHeadDetector *d, Run *run, int cycles, double amplitude, double period, double pitch0, double yaw0) {
    int steps = (int)(cycles * period * RATE);
    for (int i = 0; i < steps; i++) {
        double angle = -rad(amplitude) * 0.5 * (1 - cos(2 * M_PI * i / (period * RATE)));
        feed(d, run, pitch0 + angle, yaw0);
    }
}

int main(void) {
    SGHeadDetector d;

    // A double nod at 18 degrees is one nod, and no shake.
    SGHeadDetectorInit(&d, rad(14), rad(20));
    Run run = {0, 0, 0};
    rest(&d, &run, 3, 0.1, 0.3);
    nod(&d, &run, 2, 18, 0.6, 0.1, 0.3);
    rest(&d, &run, 1, 0.1, 0.3);
    CHECK(run.nods == 1 && run.shakes == 0, "double nod gave %d nods, %d shakes", run.nods, run.shakes);

    // One nod alone is nothing.
    SGHeadDetectorInit(&d, rad(14), rad(20));
    run = (Run){0, 0, 0};
    rest(&d, &run, 3, 0, 0);
    nod(&d, &run, 1, 18, 0.6, 0, 0);
    rest(&d, &run, 3, 0, 0);
    CHECK(run.nods == 0 && run.shakes == 0, "a single nod gave %d nods, %d shakes", run.nods, run.shakes);

    // A shake of three turns at 25 degrees is one shake.
    SGHeadDetectorInit(&d, rad(14), rad(20));
    run = (Run){0, 0, 0};
    rest(&d, &run, 3, 0, 0);
    swing(&d, &run, 1, 3, 25, 0.5, 0, 0);
    rest(&d, &run, 1, 0, 0);
    CHECK(run.shakes == 1 && run.nods == 0, "shake gave %d shakes, %d nods", run.shakes, run.nods);

    // Turning to look at something and holding it, then turning back, is not a shake.
    SGHeadDetectorInit(&d, rad(14), rad(20));
    run = (Run){0, 0, 0};
    rest(&d, &run, 3, 0, 0);
    rest(&d, &run, 4, 0, rad(60));
    rest(&d, &run, 4, 0, 0);
    CHECK(run.shakes == 0 && run.nods == 0, "a look round gave %d shakes, %d nods", run.shakes, run.nods);

    // Nodding along to a song at 6 degrees, under the nod size, is not a nod.
    SGHeadDetectorInit(&d, rad(14), rad(20));
    run = (Run){0, 0, 0};
    rest(&d, &run, 3, 0, 0);
    nod(&d, &run, 10, 6, 0.5, 0, 0);
    CHECK(run.nods == 0, "a small nod along counted %d nods", run.nods);

    // The same nod after the size is brought down to 4 degrees' worth does count.
    SGHeadDetectorInit(&d, rad(5), rad(20));
    run = (Run){0, 0, 0};
    rest(&d, &run, 3, 0, 0);
    nod(&d, &run, 3, 6, 0.5, 0, 0);
    CHECK(run.nods >= 1, "a small nod at a small size gave %d nods", run.nods);

    // Where the head rests does not matter: the same nod with the head tipped back 25 degrees.
    SGHeadDetectorInit(&d, rad(14), rad(20));
    run = (Run){0, 0, 0};
    rest(&d, &run, 3, rad(-25), rad(150));
    nod(&d, &run, 2, 18, 0.6, rad(-25), rad(150));
    CHECK(run.nods == 1, "a nod from a tipped head gave %d nods", run.nods);

    // A shake with yaw going round the half turn (-180 / 180) still counts.
    SGHeadDetectorInit(&d, rad(14), rad(20));
    run = (Run){0, 0, 0};
    rest(&d, &run, 3, 0, rad(178));
    for (int i = 0; i < 3 * 0.5 * RATE; i++) {
        double yaw = rad(178) + rad(25) * sin(2 * M_PI * i / (0.5 * RATE));
        if (yaw > M_PI) yaw -= 2 * M_PI;
        feed(&d, &run, 0, yaw);
    }
    CHECK(run.shakes == 1, "a shake across the half turn gave %d shakes", run.shakes);

    // One gesture is one action: two nods inside the two-second rest count once.
    SGHeadDetectorInit(&d, rad(14), rad(20));
    run = (Run){0, 0, 0};
    rest(&d, &run, 3, 0, 0);
    nod(&d, &run, 2, 18, 0.5, 0, 0);
    nod(&d, &run, 2, 18, 0.5, 0, 0);
    CHECK(run.nods == 1, "two nods in a row inside the rest gave %d", run.nods);

    // A nod that also turns the head sideways about as much (a diagonal wobble) is neither.
    SGHeadDetectorInit(&d, rad(14), rad(20));
    run = (Run){0, 0, 0};
    rest(&d, &run, 3, 0, 0);
    for (int i = 0; i < 2 * 0.6 * RATE; i++) {
        double angle = rad(18) * sin(2 * M_PI * i / (0.6 * RATE));
        feed(&d, &run, angle, angle);
    }
    CHECK(run.nods == 0 && run.shakes == 0, "a diagonal wobble gave %d nods, %d shakes", run.nods, run.shakes);

    // A gap in the samples starts it over: a half nod before the gap and one after are not two.
    SGHeadDetectorInit(&d, rad(14), rad(20));
    run = (Run){0, 0, 0};
    rest(&d, &run, 3, 0, 0);
    nod(&d, &run, 1, 18, 0.6, 0, 0);
    run.time += 2;
    rest(&d, &run, 3, 0, 0);
    nod(&d, &run, 1, 18, 0.6, 0, 0);
    CHECK(run.nods == 0, "nods split by a gap gave %d", run.nods);

    // Out-of-range thresholds are brought in; nothing not finite does harm.
    SGHeadDetectorInit(&d, 0.0, 10.0);
    CHECK(d.nodThreshold >= 0.08 && d.shakeThreshold <= 0.6, "thresholds %.3f %.3f not clamped", d.nodThreshold, d.shakeThreshold);
    CHECK(SGHeadDetectorFeed(&d, NAN, 0, 0) == SGHeadEventNone, "a NaN time was an event");
    CHECK(SGHeadDetectorFeed(&d, 1, INFINITY, 0) == SGHeadEventNone, "an infinite pitch was an event");

    // Learning: nods of 20 degrees give a threshold near 0.55 of the swing, shakes are measured apart.
    SGHeadCalibrator c;
    SGHeadCalibratorBegin(&c);
    SGHeadCalibratorSetAxis(&c, 0);
    run = (Run){0, 0, 0};
    SGHeadDetector sink;
    SGHeadDetectorInit(&sink, rad(14), rad(20));
    for (int i = 0; i < 6 * RATE; i++) {
        double pitch = rad(20) * sin(2 * M_PI * i / (0.7 * RATE));
        SGHeadCalibratorFeed(&c, run.time, pitch, rad(1) * sin(i * 0.3));
        run.time += 1.0 / RATE;
    }
    double threshold = 0;
    CHECK(SGHeadCalibratorResult(&c, 0, &threshold), "learning a nod found no swings");
    CHECK(fabs(threshold - 0.55 * rad(20)) < rad(4), "learned nod threshold %.1f degrees, wanted about %.1f", threshold * 180 / M_PI, 0.55 * 20);
    CHECK(!SGHeadCalibratorResult(&c, 1, &threshold), "learning a shake found swings while only nods were made");

    SGHeadCalibratorBegin(&c);
    SGHeadCalibratorSetAxis(&c, 0);
    CHECK(!SGHeadCalibratorResult(&c, 0, &threshold), "a still head learned a threshold");

    printf(failures ? "%d FAILED\n" : "all passed\n", failures);
    return failures ? 1 : 0;
}
