#pragma once
#include "SGSingStream.h"

typedef struct SGSingAudio SGSingAudio;
// One source generation. Off-render creation, attachment, detachment and destruction. The worker
// retains Stream until it finishes; detach first, then await its completion before Destroy.
SGSingAudio *SGSingAudioCreate(SGAudioStamp origin, uint32_t windowFrames, uint32_t hopFrames, float level);
SGSingStream *SGSingAudioStream(SGSingAudio *audio);
bool SGSingAudioAttach(SGSingAudio *audio);
void SGSingAudioDetach(SGSingAudio *audio);
void SGSingAudioDestroy(SGSingAudio *audio);

// Invalidates in-flight output before a seek/track/route change. Atomic, safe from player callbacks.
void SGSingAudioInvalidate(void);
void SGSingAudioSetClock(SGSingAudio *audio, double sourcePosition, uint64_t track);
// Main-thread queue intent; no network request or private PCM read. Prepare at most one next
// song from the source's verified continuous prefix, preserving a single inference stream.
void SGSingAudioExpectTrack(SGSingAudio *audio, uint64_t track);
bool SGSingAudioContinueTrack(SGSingAudio *audio, uint64_t track);
bool SGSingAudioAwaitingTrack(SGSingAudio *audio, uint64_t track);
// Total downstream delay in source seconds, updated off-render when the route/rate changes.
void SGSingAudioSetLatency(SGSingAudio *audio, double seconds);
bool SGSingAudioClock(uint64_t track, double *position);
