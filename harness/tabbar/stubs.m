// What the harness does not compile: the accent hook (SGRAccent.x), the repaint hook (SGRRepaint.x), the
// Mod Settings and Spotify URI dispatcher. The real navbar composition runs.
#import <UIKit/UIKit.h>
#import "Shared/Navigation/Links.h"

UIColor *SGRAccentColor(void) { return nil; }
__weak UIView *sgr_nowPlayingRoot = nil;
__weak UIView *sgr_nowPlayingCard = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;

BOOL SGOpenSpotifyURI(NSURL *uri) { return YES; }
id SGLinkDispatcher(void) { return nil; }
SGLinkRoute SGSpotifyURIRoute(NSURL *uri, NSString **via) { return SGLinkRouteOpens; }
NSURL *SGSpotifyURIFromText(NSString *text) { return [NSURL URLWithString:text]; }
void SGOpenModSettings(UIView *source) {}
