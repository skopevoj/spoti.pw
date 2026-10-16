// The line being sung in place of the artist in the system's now playing: lock screen, Dynamic Island,
// Control Center, CarPlay. There is a Live Activity for it too (Shared/LiveActivity). The
// lines and the clock come from Karaoke.
#import <Foundation/Foundation.h>

#define SGKeyLockScreenLyrics @"spotifyglass.lockScreenLyrics"
// Where the line shows: in place of the artist (unset), as the artwork, the line and the next one drawn over
// the cover blurred, or both.
#define SGKeyLockScreenLyricsPlace @"spotifyglass.lockScreenLyrics.place"

typedef NS_ENUM(NSInteger, SGLockScreenLyricsPlace) {
    SGLockScreenLyricsArtist = 0,
    SGLockScreenLyricsArtwork,
    SGLockScreenLyricsBoth,
};
