// Read-only look-ahead for the verified Spotify decoder. No private calls or PCM reads.
#pragma once
#import <AudioToolbox/AudioToolbox.h>
#include <stdbool.h>

void SGAudioSourceQueueInitialize(void); // off-render, before registering source callbacks
bool SGAudioSourceQueueSupported(AURenderCallbackStruct callback);
typedef struct {
    UInt32 frames;
    UInt32 boundary; // first frame after a verified, traversable end marker; UINT32_MAX otherwise
} SGAudioSourcePrefix;
// A continuous stream may cross one end marker only when the native reader can continue
// without stopping. Commands, a second marker, or an unstable snapshot still fence the prefix.
SGAudioSourcePrefix SGAudioSourceQueuePrefix(AURenderCallbackStruct callback, UInt32 maximumFrames, bool continuous);
// Sole source consumer only. Zero means no verified spare audio, including an event boundary.
// Inspect only the prefix needed for this pull; never walk the entire decoder queue needlessly.
UInt32 SGAudioSourceQueueFrames(AURenderCallbackStruct callback, UInt32 maximumFrames);
