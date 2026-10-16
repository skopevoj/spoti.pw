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
    // Four fifths up is the original mix, the top vocals alone.
    assert(SGSingLevelFromPosition(0) == .2f && SGSingLevelFromPosition(1) == SGSingVocalsOnlyLevel);
    assert(fabsf(SGSingLevelFromPosition(SGSingOriginalPosition) - 1) < 1e-6f);
    assert(fabsf(SGSingLevelFromPosition(.4f) - .6f) < 1e-6f);
    assert(SGSingPositionFromLevel(.2f) == 0 && fabsf(SGSingPositionFromLevel(1) - SGSingOriginalPosition) < 1e-6f);
    assert(fabsf(SGSingPositionFromLevel(SGSingVocalsOnlyLevel) - 1) < 1e-6f);
    for (float p = 0; p <= 1; p += 0.05f) assert(fabsf(SGSingPositionFromLevel(SGSingLevelFromPosition(p)) - p) < 1e-5f);
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
    // Vocals only: the instrumental fades out and the vocals stay whole, and a bypass still lands on the original.
    SGSingMixerInit(&m, 44100, 1);
    SGSingMixerSetLevel(&m, SGSingVocalsOnlyLevel);
    for (unsigned i = 0; i < 1323; i++) SGSingMixerProcess(&m, original, vocal, out, 1);
    assert(fabsf(out[0] - vocal[0]) < 1e-6f && fabsf(out[1] - vocal[1]) < 1e-6f);
    SGSingMixerSetLevel(&m, 1.5f);
    for (unsigned i = 0; i < 1323; i++) SGSingMixerProcess(&m, original, vocal, out, 1);
    assert(fabsf(out[0] - (0.25f * (original[0] - vocal[0]) + vocal[0])) < 1e-5f);
    SGSingMixerBypass(&m);
    for (unsigned i = 0; i < 5292; i++) SGSingMixerProcess(&m, original, vocal, out, 1);
    assert(out[0] == original[0] && out[1] == original[1]);
    assert(SGSingClampLevel(5) == SGSingVocalsOnlyLevel);
}
// Spatial voice: straight ahead it changes nothing, turned it moves the voice and only the voice, and a
// bypass still lands exactly on the original.
static void spatial(void) {
    SGSingMixer plain, placed;
    float original[] = {0.4f, 0.2f}, vocal[] = {0.3f, 0.1f}, a[2], b[2];
    SGSingSpatialSetEnabled(false);
    SGSingMixerInit(&plain, 44100, 1); SGSingMixerSetLevel(&plain, 0.6f);
    SGSingSpatialSetEnabled(true); SGSingSpatialSetAzimuth(0);
    SGSingMixerInit(&placed, 44100, 1); SGSingMixerSetLevel(&placed, 0.6f);
    assert(placed.spatialTarget == 1 && plain.spatialTarget == 0);
    for (unsigned i = 0; i < 4410; i++) {
        SGSingMixerProcess(&plain, original, vocal, a, 1);
        SGSingMixerProcess(&placed, original, vocal, b, 1);
    }
    assert(fabsf(a[0] - b[0]) < 1e-5f && fabsf(a[1] - b[1]) < 1e-5f);

    // A centred voice, the head turned so it should be heard on the right.
    float centred[] = {0.3f, 0.3f}, silent[] = {0.3f, 0.3f};
    SGSingSpatialSetAzimuth(1.2f);
    for (unsigned i = 0; i < 44100; i++) SGSingMixerProcess(&placed, silent, centred, b, 1);
    assert(b[1] > b[0] + 0.05f);
    SGSingSpatialSetAzimuth(-1.2f);
    for (unsigned i = 0; i < 44100; i++) SGSingMixerProcess(&placed, silent, centred, b, 1);
    assert(b[0] > b[1] + 0.05f);
    // The instrumental is never moved: no vocals, no change.
    float none[] = {0, 0};
    SGSingMixerProcess(&placed, original, none, b, 1);
    for (unsigned i = 0; i < 64; i++) SGSingMixerProcess(&placed, original, none, b, 1);
    assert(fabsf(b[0] - original[0]) < 1e-6f && fabsf(b[1] - original[1]) < 1e-6f);

    SGSingMixerBypass(&placed);
    for (unsigned i = 0; i < 5292; i++) SGSingMixerProcess(&placed, original, vocal, b, 1);
    assert(placed.spatial == 0 && b[0] == original[0] && b[1] == original[1]);
    SGSingSpatialSetAzimuth(NAN);
    assert(SGSingSpatialAzimuth() == 0);
    SGSingSpatialSetEnabled(false);
}
int main(void) {
    rings(); mixing(); spatial();
    puts("sing: wraparound, full/empty, 100000 concurrent packets, ramps, limiter and spatial voice passed");
}
