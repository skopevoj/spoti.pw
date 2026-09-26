#include "Shared/Audio/SGAudioRingBuffer.h"
#include "Shared/Sing/SGSingDSP.h"
#include <assert.h>
#include <math.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>

static SGAudioRingBuffer *shared;
static void *produce(void *unused) {
    (void)unused;
    for (uint64_t n = 0; n < 100000; n++) {
        float pcm[2] = {(float)n, -(float)n};
        SGAudioStamp stamp = {.generation = n / 1000, .track = 42, .sourceFrame = n, .format = 1, .frames = 1};
        while (!SGAudioRingWrite(shared, stamp, pcm)) sched_yield();
    }
    return NULL;
}
static void rings(void) {
    assert(!SGAudioRingCreate(0, 1, 2));
    assert(!SGAudioRingCreate(1024, 352800, 4)); // hard memory ceiling
    SGAudioRingBuffer *r = SGAudioRingCreate(3, 3, 1); // odd stride and non-power-of-two capacity
    assert(r);
    float pcm[3] = {0.1f, 0.2f, 0.3f}, out[3];
    SGAudioStamp stamp = {.generation = 4, .track = 7, .sourceFrame = 9, .format = 2, .frames = 3}, got;
    for (unsigned n = 0; n < 100; n++) {
        assert(!SGAudioRingRead(r, &got, out));
        for (unsigned i = 0; i < 3; i++) assert(SGAudioRingWrite(r, stamp, pcm));
        assert(!SGAudioRingWrite(r, stamp, pcm));
        assert(SGAudioRingCount(r) == 3);
        for (unsigned i = 0; i < 3; i++) {
            assert(SGAudioRingRead(r, &got, out));
            assert(got.frames == 3 && got.sourceFrame == 9 && out[2] == pcm[2]);
            assert(SGAudioStampMatches(got, 4, 7, 2));
            assert(!SGAudioStampMatches(got, 5, 7, 2));
            assert(!SGAudioStampMatches(got, 4, 8, 2));
            assert(!SGAudioStampMatches(got, 4, 7, 3));
        }
    }
    stamp.frames = 4;
    assert(!SGAudioRingWrite(r, stamp, pcm));
    SGAudioRingDestroy(r);

    shared = SGAudioRingCreate(7, 1, 2);
    assert(shared);
    pthread_t thread; assert(!pthread_create(&thread, NULL, produce, NULL));
    for (uint64_t n = 0; n < 100000; n++) {
        while (!SGAudioRingRead(shared, &got, out)) sched_yield();
        assert(got.sourceFrame == n && got.generation == n / 1000);
        assert(out[0] == (float)n && out[1] == -(float)n);
    }
    assert(!pthread_join(thread, NULL));
    assert(SGAudioRingCount(shared) == 0);
    SGAudioRingDestroy(shared);
}
static void mixing(void) {
    SGSingMixer m;
    float original[] = {0.7f, -0.3f}, vocal[] = {0.5f, -0.5f}, out[2];
    SGSingMixerInit(&m, 44100, 0);
    SGSingMixerProcess(&m, original, vocal, out, 1);
    assert(fabsf(out[0] - 0.22f) < 1e-6f && fabsf(out[1] - 0.18f) < 1e-6f);
    assert(fabsf(m.gain - .04f) < 1e-6f); // minimum 20%, including non-UI requests
    SGSingMixerSetLevel(&m, -10); assert(fabsf(m.targetGain - .04f) < 1e-6f);
    assert(SGSingLevelFromPosition(0) == .2f && SGSingLevelFromPosition(1) == 1);
    assert(fabsf(SGSingLevelFromPosition(.5f) - .6f) < 1e-6f);
    assert(SGSingPositionFromLevel(.2f) == 0 && SGSingPositionFromLevel(1) == 1);
    assert(SGSingClampLevel(NAN) == 1);
    SGSingMixerSetLevel(&m, 1);
    float last = out[0];
    for (unsigned i = 0; i < 1323; i++) {
        SGSingMixerProcess(&m, original, vocal, out, 1);
        assert(out[0] >= last && out[0] - last < 0.001f);
        last = out[0];
    }
    assert(m.remaining == 0 && out[0] == original[0] && out[1] == original[1]);
    SGSingMixerInit(&m, 48000, 0.5f);
    assert(m.gain == 0.25f);
    SGSingMixerBypass(&m);
    assert(m.remaining == 5760);
    for (unsigned i = 0; i < 5760; i++) SGSingMixerProcess(&m, original, vocal, out, 1);
    assert(out[0] == original[0]);
    SGSingMixerInit(&m, 44100, 0);
    float loud[] = {3, -3};
    SGSingMixerProcess(&m, loud, vocal, out, 1);
    assert(out[0] == 1 && out[1] == -1);
    float invalid[] = {NAN, INFINITY};
    SGSingMixerProcess(&m, invalid, invalid, out, 1);
    assert(out[0] == 0 && out[1] == 0);
    SGSingMixerSetLevel(&m, NAN);
    assert(m.targetGain == 1);
}
static void timeline(void) {
    assert(SGSingAudiblePosition(10, 88200, 44100) == 8);
    assert(SGSingAudiblePosition(1, 88200, 44100) == 0);
    assert(SGSingAudiblePosition(10, 0, 44100) == 10);
    assert(SGSingAudiblePosition(10, 4, 0) == 10);
    SGSingGeneration s = {.enabled = true};
    SGSingInvalidate(&s, 42, 1);
    uint64_t old = s.generation;
    assert(SGSingAccepts(&s, old, 42, 1));
    s.paused = true; // an in-flight block may finish while paused; no new source is requested
    assert(SGSingAccepts(&s, old, 42, 1));
    SGSingInvalidate(&s, 42, 1); // seek, same track
    assert(!SGSingAccepts(&s, old, 42, 1));
    SGSingInvalidate(&s, 43, 2); // next track or route/format
    assert(!SGSingAccepts(&s, s.generation, 42, 1));
    s.enabled = false;
    assert(!SGSingAccepts(&s, s.generation, 43, 2));
}
int main(void) {
    rings(); mixing(); timeline();
    puts("sing: wraparound, full/empty, 100000 concurrent packets, generations, ramps, limiter and clock passed");
}
