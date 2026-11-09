// Keeps the areas the redesign stripped transparent when Spotify repaints them, and learns which view
// is the now playing bar's card from the album-colour paint.
#import "Core/SGCore.h"
#import "SGRRepaint.h"
#import "SGRTokens.h"

__weak UIView *sgr_nowPlayingRoot = nil;
__weak UIView *sgr_nowPlayingCard = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (color && (sgr_nowPlayingRoot || sgr_lyricsPageRoot || sgr_playlistRoot || sgr_albumRoot || sgr_artistRoot)) {
        UIView *view = (UIView *)self.delegate;
        if ([view isKindOfClass:UIView.class] && view.layer == self && !SGKeepsColor(view)) {
            if (SGIsInside(view, sgr_nowPlayingRoot)) {
                if (SGLooksLikeCard(view, color) && sgr_nowPlayingCard != view) {
                    sgr_nowPlayingCard = view;
                    UIView *bar = sgr_nowPlayingRoot;
                    dispatch_async(dispatch_get_main_queue(), ^{ [bar.superview setNeedsLayout]; });
                }
                color = NULL;
            } else if (SGIsInside(view, sgr_lyricsPageRoot)) {
                color = NULL;
            } else if (SGRIsBaseSurface(color) && (SGIsInside(view, sgr_playlistRoot) || SGIsInside(view, sgr_albumRoot) || SGIsInside(view, sgr_artistRoot))) {
                color = NULL;
            }
        }
    }
    %orig(color);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
