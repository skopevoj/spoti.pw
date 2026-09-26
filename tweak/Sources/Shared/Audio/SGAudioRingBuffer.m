#include "SGAudioRingBuffer.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct SGAudioRingBuffer {
    _Atomic uint64_t head, tail;
    uint32_t capacity, frames, channels;
    size_t stride;
    unsigned char *storage;
};

SGAudioRingBuffer *SGAudioRingCreate(uint32_t packets, uint32_t frames, uint32_t channels) {
    if (!packets || packets > 1024 || !frames || frames > 352800 || !channels || channels > 4) return NULL;
    size_t stride = sizeof(SGAudioStamp) + (size_t)frames * channels * sizeof(float);
    // Every packet header stays aligned even for odd numbers of float samples.
    stride = (stride + _Alignof(SGAudioStamp) - 1) & ~((size_t)_Alignof(SGAudioStamp) - 1);
    if (stride > SIZE_MAX / packets || stride * packets > 64 * 1024 * 1024) return NULL;
    SGAudioRingBuffer *r = calloc(1, sizeof *r);
    if (!r) return NULL;
    atomic_init(&r->head, 0); atomic_init(&r->tail, 0);
    if (!atomic_is_lock_free(&r->head) || !atomic_is_lock_free(&r->tail)) { free(r); return NULL; }
    r->storage = calloc(packets, stride);
    if (!r->storage) { free(r); return NULL; }
    r->capacity = packets; r->frames = frames; r->channels = channels; r->stride = stride;
    return r;
}
void SGAudioRingDestroy(SGAudioRingBuffer *r) {
    if (r) { free(r->storage); free(r); }
}
bool SGAudioRingWrite(SGAudioRingBuffer *r, SGAudioStamp stamp, const float *pcm) {
    if (!r || !pcm || !stamp.frames || stamp.frames > r->frames) return false;
    uint64_t head = atomic_load_explicit(&r->head, memory_order_relaxed);
    uint64_t tail = atomic_load_explicit(&r->tail, memory_order_acquire);
    if (head - tail >= r->capacity) return false;
    unsigned char *packet = r->storage + (head % r->capacity) * r->stride;
    memcpy(packet, &stamp, sizeof stamp);
    memcpy(packet + sizeof stamp, pcm, (size_t)stamp.frames * r->channels * sizeof(float));
    atomic_store_explicit(&r->head, head + 1, memory_order_release);
    return true;
}
bool SGAudioRingRead(SGAudioRingBuffer *r, SGAudioStamp *stamp, float *pcm) {
    if (!r || !stamp || !pcm) return false;
    uint64_t tail = atomic_load_explicit(&r->tail, memory_order_relaxed);
    uint64_t head = atomic_load_explicit(&r->head, memory_order_acquire);
    if (tail == head) return false;
    unsigned char *packet = r->storage + (tail % r->capacity) * r->stride;
    memcpy(stamp, packet, sizeof *stamp);
    memcpy(pcm, packet + sizeof *stamp, (size_t)stamp->frames * r->channels * sizeof(float));
    atomic_store_explicit(&r->tail, tail + 1, memory_order_release);
    return true;
}
uint32_t SGAudioRingCount(const SGAudioRingBuffer *r) {
    if (!r) return 0;
    // A third-party diagnostic reader may observe different epochs. Clamp its advisory snapshot.
    uint64_t tail = atomic_load_explicit(&r->tail, memory_order_acquire);
    uint64_t head = atomic_load_explicit(&r->head, memory_order_acquire);
    uint64_t count = head - tail;
    return count > r->capacity ? r->capacity : (uint32_t)count;
}
bool SGAudioStampMatches(SGAudioStamp stamp, uint64_t generation, uint64_t track, uint32_t format) {
    return stamp.generation == generation && stamp.track == track && stamp.format == format;
}
