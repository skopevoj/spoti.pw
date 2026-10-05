#include "Shared/Sing/SGSingTimeline.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

enum { block = 441, capacity = 44100 * 4 };
static float dry[block * 2], vocal[block * 2], output[block * 2];
static SGAudioStamp stamp(uint64_t at) { return (SGAudioStamp){7, 12, at, 1, block}; }
static float signal(uint64_t sample) { return .25f + .125f * sinf((float)(sample % 44100) * .013f); }
static void fill(uint64_t at) {
    for (unsigned i = 0; i < block; i++) {
        dry[i*2] = signal(at+i); dry[i*2+1] = -dry[i*2];
        vocal[i*2] = dry[i*2] * .4f; vocal[i*2+1] = -vocal[i*2];
    }
}
static void verify(uint64_t at, uint32_t count, float gain) {
    for (unsigned i = 0; i < count; i++) {
        assert(fabsf(output[i*2] - signal(at+i)*gain) < 1e-6);
        assert(fabsf(output[i*2] + output[i*2+1]) < 1e-6);
    }
}
static void recoverWithoutChattering(bool sustained) {
    SGSingTimeline *t = SGSingTimelineCreate(44100 * 8, 88200);
    SGSingTimelineBegin(t, stamp(0), .2f);
    uint64_t captured = 0, processed = 0, consumed = 0;
    for (; captured < 44100 * 6; captured += block) {
        fill(captured); assert(SGSingTimelineCapture(t, stamp(captured), dry));
    }
    for (; processed < 44100 * 3; processed += block) {
        fill(processed); assert(SGSingTimelineVocals(t, stamp(processed), vocal));
    }
    // Every callback emits the next original frame, including recovery and a final drain.
    #define ADVANCE() do { \
        if (SGSingTimelineWritable(t) >= block) { \
            fill(captured); assert(SGSingTimelineCapture(t, stamp(captured), dry)); captured += block; \
        } \
        assert(SGSingTimelineRead(t, output, block) == block); \
        for (unsigned n = 0; n < block; n++) { \
            float ratio = output[n*2] / signal(consumed+n); \
            assert(ratio >= .616f - 1e-5 && ratio <= 1 + 1e-5); \
            assert(fabsf(output[n*2] + output[n*2+1]) < 1e-6); \
        } \
        consumed += block; \
    } while (0)
    while (SGSingTimelineGetState(t) != SGSingTimelineRecovering) ADVANCE();
    uint64_t firstRecovery = consumed;
    for (; processed < consumed + 44100; processed += block) {
        fill(processed); assert(SGSingTimelineVocals(t, stamp(processed), vocal));
    }
    ADVANCE();
    // One late hop used to re-enable reduction with only a second of coverage. Another
    // slow inference would bring the original vocals back almost immediately.
    assert(SGSingTimelineGetState(t) == SGSingTimelineRecovering);
    for (; processed < consumed + 88200; processed += block) {
        fill(processed); assert(SGSingTimelineVocals(t, stamp(processed), vocal));
    }
    ADVANCE();
    assert(SGSingTimelineGetState(t) == SGSingTimelineActive);
    if (sustained) {
        uint64_t healthyUntil = consumed + SGSingRecoveryLimitFrames + block * 2;
        while (consumed < healthyUntil) {
            for (; processed < captured; processed += block) {
                fill(processed); assert(SGSingTimelineVocals(t, stamp(processed), vocal));
            }
            ADVANCE();
            assert(SGSingTimelineGetState(t) == SGSingTimelineActive);
        }
    }
    while (SGSingTimelineGetState(t) != SGSingTimelineRecovering) ADVANCE();
    if (sustained) {
        // A genuinely healthy interval earns a new budget for a later, unrelated stall.
        firstRecovery = consumed;
        ADVANCE();
        assert(SGSingTimelineGetState(t) == SGSingTimelineRecovering);
    }
    // A brief recovery is not a healthy run and must not reset the outage deadline.
    while (consumed < firstRecovery + SGSingRecoveryLimitFrames + block) ADVANCE();
    assert(SGSingTimelineGetState(t) == SGSingTimelineDraining);
    SGSingTimelineDestroy(t);
    #undef ADVANCE
}
int main(void) {
    SGSingTimeline *cold = SGSingTimelineCreate(block * 40, block * 2);
    SGSingTimelineBegin(cold, stamp(0), .7f);
    for (unsigned n = 0; n < 32; n++) { fill(n*block); assert(SGSingTimelineCapture(cold,stamp(n*block),dry)); }
    for (unsigned n = 0; n < 4; n++) {
        assert(SGSingTimelineRead(cold, output, block) == block); verify(n*block,block,1);
    }
    fill(5*block); assert(!SGSingTimelineVocals(cold,stamp(5*block),vocal)); // future gap
    fill(4*block); assert(SGSingTimelineVocals(cold,stamp(4*block),vocal)); // expired initial prefix
    fill(6*block); assert(!SGSingTimelineVocals(cold,stamp(6*block),vocal)); // a later gap is still rejected
    fill(5*block); assert(SGSingTimelineVocals(cold,stamp(5*block),vocal));
    for (unsigned n = 6; n < 20; n++) { fill(n*block); assert(SGSingTimelineVocals(cold,stamp(n*block),vocal)); }
    assert(SGSingTimelineRead(cold,output,block) == block && SGSingTimelineGetState(cold) == SGSingTimelineActive);
    SGSingTimelineDestroy(cold);
    recoverWithoutChattering(false);
    recoverWithoutChattering(true);
    assert(!SGSingTimelineCreate(0, 1));
    SGSingTimeline *t = SGSingTimelineCreate(capacity, block*2);
    assert(t);
    SGSingTimelineBegin(t, stamp(0), 0);
    uint64_t captured = 0, consumed = 0;
    // Capture ahead while original audio remains continuous from the first callback.
    for (unsigned i = 0; i < 200; i++) {
        for (unsigned extra = 0; extra < 2; extra++) {
            fill(captured);
            assert(SGSingTimelineCapture(t, stamp(captured), dry));
            captured += block;
        }
        assert(SGSingTimelineRead(t, output, block) == block);
        verify(consumed, block, 1);
        consumed += block;
        assert(SGSingTimelineConsumed(t) == consumed);
    }
    for (uint64_t at = 0; at < captured; at += block) {
        fill(at); assert(SGSingTimelineVocals(t, stamp(at), vocal));
    }
    // Cross the circular buffer repeatedly while preserving exact source order.
    for (unsigned i = 0; i < 1000; i++) {
        fill(captured);
        assert(SGSingTimelineCapture(t, stamp(captured), dry));
        assert(SGSingTimelineVocals(t, stamp(captured), vocal));
        captured += block;
        assert(SGSingTimelineRead(t, output, block) == block);
        if (i >= 3) verify(consumed, block, .616f); // initial 30 ms fade into reduced vocals
        consumed += block;
    }
    assert(SGSingTimelineGetState(t) == SGSingTimelineActive);
    SGSingTimelineBypass(t);
    assert(!SGSingTimelineWritable(t));
    assert(!SGSingTimelineCapture(t, stamp(captured), dry));
    assert(!SGSingTimelineVocals(t, stamp(captured), vocal));
    unsigned fadeBlocks = 0;
    while (SGSingTimelineQueued(t)) {
        uint32_t count = SGSingTimelineRead(t, output, block);
        assert(count == block);
        if (fadeBlocks++ >= 12) verify(consumed, count, 1);
        consumed += count;
    }
    assert(consumed == captured && SGSingTimelineGetState(t) == SGSingTimelineIdle);
    assert(SGSingTimelineConsumed(t) == captured);
    // No captured frame was skipped or replayed; the next direct pull begins at captured.
    SGSingTimelineBegin(t, (SGAudioStamp){8, 99, 1234, 2, block}, 0);
    assert(!SGSingTimelineVocals(t, stamp(0), vocal));
    assert(!SGSingTimelineCapture(t, stamp(1234), dry));
    assert(!SGSingTimelineCapture(t, (SGAudioStamp){8, 99, 1235, 2, block}, dry));
    assert(SGSingTimelineCapture(t, (SGAudioStamp){8, 99, 1234, 2, block}, dry));
    SGSingTimelineBypass(t); // cancelled before a model result: all buffered original still drains
    assert(SGSingTimelineRead(t, output, block) == block);
    for (unsigned i = 0; i < block*2; i++) assert(output[i] == dry[i]);
    assert(SGSingTimelineGetState(t) == SGSingTimelineIdle);
    // Permanent worker outage first keeps dry playback aligned, then expires its recovery budget
    // and releases the delay. The source keeps supplying audio until the terminal drain.
    SGSingTimelineBegin(t, stamp(0), 0);
    for (uint64_t at = 0; at < 44100; at += block) {
        fill(at); assert(SGSingTimelineCapture(t, stamp(at), dry));
        if (at < 8820) assert(SGSingTimelineVocals(t, stamp(at), vocal));
    }
    consumed = 0;
    captured = 44100;
    while (SGSingTimelineGetState(t) != SGSingTimelineIdle) {
        if (SGSingTimelineWritable(t)) {
            fill(captured); assert(SGSingTimelineCapture(t, stamp(captured), dry)); captured += block;
        }
        uint32_t count = SGSingTimelineRead(t, output, block);
        assert(count == block);
        if (consumed >= 8820 + 5292) verify(consumed, count, 1);
        for (unsigned i = 0; i < block*2; i++) assert(isfinite(output[i]) && fabsf(output[i]) <= 1);
        consumed += count;
    }
    assert(consumed == captured && consumed > SGSingRecoveryLimitFrames && SGSingTimelineGetState(t) == SGSingTimelineIdle);
    SGSingTimelineDestroy(t);
    puts("sing timeline: buffering, wraparound, exact source order, dry drain, stale results and worker outage passed");
}
