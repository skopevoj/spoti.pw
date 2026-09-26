// Worker callbacks run off the render thread. context remains owned by the caller until Finished.
#pragma once
#include <stdint.h>
enum { SGStemLoading = 1, SGStemReady, SGStemFinished, SGStemFailed };
// Read returns a stereo frame count (at most 1024), zero while idle/paused, or -1 when cancelled.
// metadata is generation, track, source frame, format. No PCM is written outside this process.
typedef int32_t (*SGStemRead)(void *context, float *pcm, uint64_t *metadata);
// Write returns 1 when accepted, 0 when the generation has ended, -1 on a transport failure.
typedef int32_t (*SGStemWrite)(void *context, const float *pcm, uint32_t frames,
                              uint64_t generation, uint64_t track, uint64_t sourceFrame, uint32_t format);
typedef void (*SGStemStatus)(void *context, int32_t status);
// Returns an owned cancellation handle, or NULL when this OS has no supported runtime. Cancel
// releases that handle exactly once. Finished is called once even when cancellation interrupts load.
void *SGStemWorkerStart(void *context, const char *modelPath, const char *hashesPath, uint32_t hopFrames,
                       SGStemRead read, SGStemWrite write, SGStemStatus status);
void SGStemWorkerCancel(void *handle, int32_t unload);

int32_t SGStemArchitectureMatches(const char *architecture);

void SGStemWorkerPurge(void);
