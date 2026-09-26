// Single owner of Spotify's mixer connection and RemoteIO notify. Registrations are fixed slots,
// independent of constructor/rebinding order. All render functions are bounded C callbacks.
#pragma once
#import <AudioToolbox/AudioToolbox.h>
#import "SGAudioSourceQueue.h"
#include <stdbool.h>

typedef enum {
    SGAudioStageSing,
    SGAudioStageSpeedPitch,
    SGAudioStageEffects,
    SGAudioStageHaptics,
    SGAudioStageCount
} SGAudioStage;

typedef struct {
    // Non-render thread: start or format change, before output is started.
    void (*prepare)(AudioUnit output);
    // Render thread: output-domain processors run once, in the order above.
    AURenderCallback output;
} SGAudioProcessor;

// Register immutable, process-lifetime storage, during startup only. No dynamic callbacks/blocks.
bool SGAudioPipelineRegister(SGAudioStage stage, const SGAudioProcessor *processor);
bool SGAudioPipelineAvailable(void);
bool SGAudioPipelineTapped(void);
UInt32 SGAudioPipelineMaximumFrames(void);
// Input to speed/pitch: the mixer in unique sample-time chunks, then source-domain processing.
OSStatus SGAudioPipelinePull(UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time);
// Sing's source-domain processor runs before a speed/pitch unit consumes these frames. Its raw
// source callback calls PullOriginal, never Pull (which would recurse into the processor).
typedef OSStatus (*SGAudioSourceProcessor)(void *context, UInt32 frames, AudioBufferList *data,
                                          const AudioTimeStamp *time);
OSStatus SGAudioPipelinePullOriginal(UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time);
// Render endpoint only: verified decoded prefix, capped at maximumFrames, before a source event.
// Zero keeps normal pulls and lets retained original audio drain. Never an extra source consumer.
UInt32 SGAudioPipelineSourceAheadFrames(UInt32 maximumFrames);
SGAudioSourcePrefix SGAudioPipelineSourcePrefix(UInt32 maximumFrames, bool continuous);
bool SGAudioPipelineSourceCanReadAhead(void); // off-render; exact supported source callback
// Off-render only. Waits for an active callback to leave before replacing the context. After this
// returns, the old context is no longer used by the pipeline (its worker may still own it).
bool SGAudioPipelineSetSourceProcessor(SGAudioSourceProcessor processor, void *context);
bool SGAudioPipelineClearSourceProcessor(void *context); // only if this context is still installed
bool SGAudioPipelineSourceFormat(AudioStreamBasicDescription *format); // off-render snapshot
bool SGAudioPipelineSourceProcessorAttached(void *context); // lock-free control/diagnostic read
// A pull processor either handles the buffer (including an error) or leaves source unconsumed.
typedef bool (*SGAudioPullProcessor)(UInt32 frames, AudioBufferList *data, OSStatus *status);
void SGAudioPipelineSetPullProcessor(SGAudioPullProcessor processor);
