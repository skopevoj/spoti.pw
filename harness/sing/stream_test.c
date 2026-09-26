// Production streaming regression with controlled source availability and inference deadlines.
#include "Shared/Sing/SGSingStream.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { window = 88200, hop = 66150, rate = 44100 };
static float input[2048], output[8192], vocals[hop*2];
static uint64_t pulled, audible, workerFrames, nextWindow;
static uint32_t seed = 41, budget;
static bool sourceFails;
static unsigned sourceCalls;
static float sampleAt(uint64_t frame) { return .31f*sinf((float)(frame % rate)*.031f); }
static int32_t source(void *context, uint32_t count, float *pcm) {
    assert(context == &pulled && count <= budget);
    sourceCalls++;
    if (sourceFails) return -42;
    budget -= count;
    for (unsigned n=0;n<count;n++) {
        pcm[n*2] = sampleAt(pulled+n); pcm[n*2+1] = -.7f*pcm[n*2];
    }
    pulled += count;
    return 0;
}
static unsigned scenario(bool ahead, bool stall, bool cancelEarly, float level, unsigned inferenceMilliseconds) {
    pulled = audible = workerFrames = nextWindow = 0;
    SGSingStream *stream = SGSingStreamCreate((SGAudioStamp){1,2,0,3,0},window,hop,level);
    assert(stream);
    uint64_t clock=0, due=0, activatedAt=0, recoveredAt=0;
    unsigned jobs=0;
    bool active=false, recovering=false, restored=false, cancelled=false;
    float factor=1 - .4f*(1-level*level);
    const unsigned totalSeconds = inferenceMilliseconds >= 1000 ? 140 : 50;
    const unsigned cancelSeconds = cancelEarly ? 1 : totalSeconds - 10;
    for (unsigned tick=0; clock < rate*totalSeconds; tick++) {
        seed=seed*1664525u+1013904223u;
        uint32_t frames=128u << ((seed>>16)%5);
        uint32_t available=ahead && tick%37<30 ? rate : 0;
        SGAudioStamp packet;
        while (SGSingStreamReadInput(stream,&packet,input)) {
            assert(packet.sourceFrame == workerFrames);
            for (unsigned n=0;n<packet.frames;n++) assert(input[n*2] == sampleAt(workerFrames+n));
            workerFrames += packet.frames;
        }
        if (!due && workerFrames >= nextWindow+window && !cancelled)
            due=clock+(stall && jobs==6 ? rate*4 : rate*inferenceMilliseconds/1000);
        if (due && clock>=due && !cancelled) {
            for (unsigned n=0;n<hop;n++) {
                vocals[n*2]=.4f*sampleAt(nextWindow+n); vocals[n*2+1]=-.7f*vocals[n*2];
            }
            assert(SGSingStreamWriteVocals(stream,(SGAudioStamp){1,2,nextWindow,3,hop},vocals));
            nextWindow+=hop; jobs++; due=0;
        }
        if (!cancelled && clock >= (rate*cancelSeconds)) {
            SGSingStreamBypass(stream); cancelled=true;
        }
        uint64_t queued=SGSingStreamQueued(stream);
        budget=available>5292 ? available-5292 : 0;
        uint32_t minimum=queued < frames ? frames-(uint32_t)queued : 0;
        if (budget<minimum) budget=minimum;
        // Draining has no source reads until its last retained prefix is emitted.
        if (cancelled) budget=minimum;
        assert(!SGSingStreamRender(stream,frames,output,source,&pulled,available));
        SGSingTimelineState state=SGSingStreamState(stream);
        if (state==SGSingTimelineActive) {
            if (!active) activatedAt=clock;
            active=true;
            if (recovering) { restored=true; if (!recoveredAt) recoveredAt=clock; }
        }
        if (state==SGSingTimelineRecovering) recovering=true;
        for (unsigned n=0;n<frames;n++) {
            float dry=sampleAt(audible+n), result=output[n*2];
            assert(isfinite(result) && fabsf(output[n*2+1]+.7f*result)<1e-6);
            if (!active || level==1 || (cancelled && clock > (rate*(cancelSeconds+1))))
                assert(result==dry);
            else if (fabsf(dry)>1e-6) assert(result/dry>=factor-1e-5 && result/dry<=1+1e-5);
        }
        audible+=frames; clock+=frames;
        assert(SGSingStreamPresented(stream)==audible);
        assert(SGSingStreamQueued(stream)<=window*2+hop+2048);
        assert(SGSingStreamStopReason(stream)==(cancelled ? SGSingStopRequested : SGSingStopNone));
        if (!cancelled && clock>rate*30 && ahead) {
            assert(state==SGSingTimelineActive);
            for (unsigned n=0;n<frames;n++) assert(fabsf(output[n*2]-factor*sampleAt(audible-frames+n))<1e-6);
        }
        if (tick%53==52 && !cancelled) {
            uint64_t before=pulled, presented=SGSingStreamPresented(stream);
            SGSingStreamPause(stream,true);
            assert(!SGSingStreamRender(stream,frames,output,source,&pulled,available));
            for (unsigned n=0;n<frames*2;n++) assert(output[n]==0);
            assert(pulled==before && SGSingStreamPresented(stream)==presented);
            SGSingStreamPause(stream,false);
        }
    }
    assert(SGSingStreamState(stream)==SGSingTimelineIdle && !SGSingStreamQueued(stream) && pulled==audible);
    fprintf(stderr,"scenario %d %d %d active=%d activatedAt=%.3f recovering=%d restored=%d jobs=%u\n",ahead,stall,cancelEarly,active,(double)activatedAt/rate,recovering,restored,jobs);
    if (ahead && !cancelEarly) assert(active && activatedAt<rate*35 && (!stall || (recovering && restored)));
    else assert(!active);
    SGSingStreamDestroy(stream);
    printf("ahead=%d stall=%d early-cancel=%d level=%.2f first reduced=%.3fs recovered=%.3fs: every original sample preserved\n",
           ahead,stall,cancelEarly,level,(double)activatedAt/rate,(double)recoveredAt/rate);
    return jobs;
}
static void failures(void) {
    pulled = audible = 0;
    SGSingStream *stream = SGSingStreamCreate((SGAudioStamp){1,2,0,3,0},window,hop,.2f);
    // A worker that never consumes input cannot exhaust unbounded memory or mute playback.
    for (unsigned tick = 0; tick < 1025; tick++) {
        budget = UINT32_MAX;
        assert(!SGSingStreamRender(stream,64,output,source,&pulled,rate));
        for (unsigned n=0;n<64;n++) assert(output[n*2] == sampleAt(audible+n));
        audible += 64;
    }
    assert(SGSingStreamStopReason(stream) == SGSingStopCapacity);
    while (SGSingStreamState(stream) != SGSingTimelineIdle) {
        budget = UINT32_MAX;
        assert(!SGSingStreamRender(stream,997,output,source,&pulled,rate));
        for (unsigned n=0;n<997;n++) assert(output[n*2] == sampleAt(audible+n));
        audible += 997;
    }
    assert(pulled == audible && !SGSingStreamQueued(stream));
    unsigned before = sourceCalls; sourceFails = true;
    assert(SGSingStreamRender(stream,64,output,source,&pulled,rate) == -42);
    assert(sourceCalls == before + 1); // a failed source is never retried in one render
    SGSingStreamDestroy(stream);
    stream = SGSingStreamCreate((SGAudioStamp){2,9,0,3,0},window,hop,.2f);
    before = sourceCalls;
    assert(SGSingStreamRender(stream,64,output,source,&pulled,rate) == -42);
    assert(sourceCalls == before + 1 && SGSingStreamStopReason(stream) == SGSingStopSourceError);
    assert(SGSingStreamSourceError(stream) == -42);
    SGSingStreamDestroy(stream); sourceFails = false;
}
static void coldPrefix(void) {
    pulled = 0;
    SGSingStream *s = SGSingStreamCreate((SGAudioStamp){3,9,0,1,0},window,hop,.7f);
    for (unsigned tick = 0; tick < 800; tick++) {
        budget = UINT32_MAX;
        assert(!SGSingStreamRender(s,441,output,source,&pulled,rate));
        for (unsigned n = 0; n < 441; n++) assert(output[n*2] == sampleAt(tick*441+n));
    }
    budget = UINT32_MAX;
    assert(!SGSingStreamRender(s,17,output,source,&pulled,rate));
    SGAudioStamp packet;
    assert(SGSingStreamReadLiveInput(s,&packet,input));
    assert(packet.sourceFrame == 800*441+17);
    for (unsigned n = 0; n < packet.frames; n++) assert(input[n*2] == sampleAt(packet.sourceFrame+n));
    uint64_t expected = packet.sourceFrame + packet.frames;
    budget = UINT32_MAX;
    assert(!SGSingStreamRender(s,4096,output,source,&pulled,rate));
    assert(SGSingStreamReadLiveInput(s,&packet,input));
    assert(packet.sourceFrame == expected); // only the initial expired prefix may be skipped
    assert(SGSingStreamStopReason(s) == SGSingStopNone);
    SGSingStreamDestroy(s);
    // Even a very slow cold model load cannot fill the worker queue or interrupt playback.
    pulled = 0;
    s = SGSingStreamCreate((SGAudioStamp){4,9,0,1,0},window,hop,.7f);
    SGSingStreamSetModelReady(s,false);
    for (unsigned tick = 0; tick < 3000; tick++) {
        budget = UINT32_MAX;
        assert(!SGSingStreamRender(s,441,output,source,&pulled,rate));
        for (unsigned n = 0; n < 441; n++) assert(output[n*2] == sampleAt(tick*441+n));
        assert(SGSingStreamStopReason(s) == SGSingStopNone);
        assert(!SGSingStreamReadInput(s,&packet,input));
    }
    SGSingStreamSetModelReady(s,true);
    budget = UINT32_MAX;
    assert(!SGSingStreamRender(s,441,output,source,&pulled,rate));
    assert(SGSingStreamReadLiveInput(s,&packet,input));
    assert(packet.sourceFrame == 3001 * 441 && packet.frames > 0);
    for (unsigned n = 0; n < packet.frames; n++) assert(input[n*2] == sampleAt(packet.sourceFrame+n));
    SGSingStreamDestroy(s);
}
int main(void) {
    coldPrefix();
    failures();
    assert(scenario(true,false,false,1,800)>20);
    assert(scenario(true,false,false,.7f,800)>20);
    assert(scenario(true,true,false,.2f,800)>20);
    scenario(false,false,false,.7f,800);
    scenario(true,false,false,.7f,1300);
    scenario(true,false,true,.7f,800);
    puts("Continuous preparation, source order, recovery, shortages, pause and cancellation passed.");
}
