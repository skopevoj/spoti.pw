// Spatial voice: while Sing is on and head tracking AirPods are in, the song's voice stays in front of
// the listener as they turn their head, the way a singer in the room would; the instrumental stays where
// the mix put it. The pan itself is SGSingDSP's, on the render thread; this follows the head
// (Shared/HeadMotion) and hands it the angle. Its switch is on Mod Settings > Karaoke and applies at once.
#import <Foundation/Foundation.h>

#define SGKeySpatialVoice @"spotifyglass.sing.spatial"                // off until switched on
// Follow the iPhone: what counts as in front slowly settles where the head rests, so turning the whole
// body (or lying down) brings the voice along after a few seconds. On until switched off.
#define SGKeySpatialVoiceFollow @"spotifyglass.sing.spatial.follow"

// Reads the switches and starts or stops following the head as Sing goes on and off. Main thread.
void SGSpatialVoiceApply(void);
