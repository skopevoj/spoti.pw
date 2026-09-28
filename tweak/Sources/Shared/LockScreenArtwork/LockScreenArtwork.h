// The playing track's Canvas as the system's animated now playing artwork: from iOS 26 the lock
// screen plays a looping clip behind the controls the way Apple Music plays an animated cover. It
// draws nothing on Spotify's own screens, so it answers under either look.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@class SGCanvas, SGModRow, SPTPlayerTrack;

#define SGKeyLockScreenArtwork @"spotifyglass.lockscreen.animatedartwork"
#define SGKeyLockScreenArtworkSources @"spotifyglass.lockscreen.artworksources"

// Where a clip can come from: the track's Canvas, or the album's animated cover on Apple Music.
extern NSString *const SGArtworkSourceSpotify;
extern NSString *const SGArtworkSourceApple;
// The sources stored under `key` in the user's order, the ones switched off left out; Spotify, then
// Apple Music until set. The lock screen's order is SGKeyLockScreenArtworkSources.
NSArray<NSString *> *SGArtworkOrderFor(NSString *key);
void SGArtworkSetOrderFor(NSString *key, NSArray<NSString *> *order);
// One source's clip for `track`, on the main queue, or nil and why: Spotify's from `fromMetadata` or else
// its canvas service with the account's own token, Apple Music's by the artist and album name, the
// 3:4 cover first when `tall` (LockScreenArtwork.x).
void SGArtworkAsk(NSString *source, SPTPlayerTrack *track, SGCanvas *fromMetadata, BOOL tall,
                  void (^done)(SGCanvas *canvas, NSString *note));

// Whether this iOS has MPMediaItemAnimatedArtwork at all.
BOOL SGAnimatedArtworkAvailable(void);
// Every now playing key this iOS takes a clip under, and the one of them the Canvas goes under with
// the shape it wants there through `aspect`; nil where there is none.
NSArray<NSString *> *SGAnimatedArtworkKeys(void);
NSString *SGAnimatedArtworkKey(CGFloat *aspect);
// `artwork` under `key` in a copy of `info`, everything else left as it stands. The lock screen
// lyrics rewrite the dictionary on a timer, so the key is put back on every one that passes.
NSDictionary *SGArtworkInInfo(NSDictionary *info, id artwork, NSString *key);
// The rows for the Lock screen widget page; below iOS 26 one row reads out what is missing instead.
NSArray<SGModRow *> *SGAnimatedArtworkRows(void);
// A Sources row for the order under `key`, opening the page it is dragged in with `note` under the list.
SGModRow *SGArtworkSourcesRow(NSString *key, NSString *note);
