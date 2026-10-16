// The one shape of audio Sing works in, for the render side, the controller and their tests. The Swift
// worker has the model's side of it (SGStemShape in SGStemSeparator.swift) and checks the model it loads
// against the window it is given.
#pragma once

enum {
    SGSingSampleRate = 44100,                          // Spotify's decoded source, stereo float
    SGSingWindowFrames = 88200,                        // two seconds, one run of the model
    SGSingHopFrames = SGSingWindowFrames * 3 / 4,      // 66150: a window every 1.5 s, half a second overlapping
    // 120 ms: what is left in Spotify's own queue when reading ahead, and the reserve of ready vocals the
    // mix keeps so that its ramp back to the original (SGSingMixerBypass) always has vocals to ramp over.
    SGSingReserveFrames = SGSingSampleRate * 120 / 1000,
    SGSingTimelineFrames = SGSingSampleRate * 8,       // eight seconds of original kept for the worker
};
