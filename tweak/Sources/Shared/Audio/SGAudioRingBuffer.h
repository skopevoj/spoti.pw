// Preallocated single-producer/single-consumer PCM packets. Creation/destruction require both
// endpoints to be stopped. Never reset indices across threads; invalidate by generation instead.
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint64_t generation, track, sourceFrame;
    uint32_t format, frames;
} SGAudioStamp;
typedef struct SGAudioRingBuffer SGAudioRingBuffer;
SGAudioRingBuffer *SGAudioRingCreate(uint32_t packets, uint32_t maxFrames, uint32_t channels);
void SGAudioRingDestroy(SGAudioRingBuffer *ring);
// Interleaved float PCM; a full queue rejects a whole packet, never overwrites the consumer.
bool SGAudioRingWrite(SGAudioRingBuffer *ring, SGAudioStamp stamp, const float *pcm);
// Pops at most one packet; destination has maxFrames * channels capacity. Consumer only.
bool SGAudioRingRead(SGAudioRingBuffer *ring, SGAudioStamp *stamp, float *pcm);
uint32_t SGAudioRingCount(const SGAudioRingBuffer *ring);
bool SGAudioStampMatches(SGAudioStamp stamp, uint64_t generation, uint64_t track, uint32_t format);
