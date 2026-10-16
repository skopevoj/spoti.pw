// Landscape lyrics (Mod Settings > Lyrics, in the redesign): turning the phone on its side while the
// player's or the lyrics page's lyrics are on screen brings up a screen of their own, the lyrics across
// the long side at a larger size, the track's name in a corner; turning it back takes it away. Spotify
// runs in portrait only, so the screen is a window of the mod's own over Spotify's, its content turned a
// quarter round to the way the phone is held, the status bar hidden. Portrait Orientation Lock keeps the
// phone from saying it turned, and then nothing happens, as in any app.
#import <UIKit/UIKit.h>

#define SGRKeyLandscapeLyrics @"spotifyglass.redesign.landscapeLyrics"   // on until switched off

@class SGModRow;
SGModRow *SGRLandscapeLyricsRow(void);
