// Keeps the areas the redesign stripped transparent when Spotify repaints them, and learns which view
// is the now playing bar's card from the album-colour paint.
#import "Core/SGCore.h"
#import "SGRRepaint.h"

__weak UIView *sgr_nowPlayingRoot = nil;
__weak UIView *sgr_nowPlayingCard = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;

static char kPaintedCardKey;

BOOL SGRPaintedAsCard(UIView *view) {
    return objc_getAssociatedObject(view, &kPaintedCardKey) != nil;
}

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (color && (sgr_nowPlayingRoot || sgr_lyricsPageRoot || sgr_playlistRoot || sgr_albumRoot || sgr_artistRoot)) {
        UIView *view = (UIView *)self.delegate;
        if ([view isKindOfClass:UIView.class] && view.layer == self && !SGKeepsColor(view)) {
            if (SGIsInside(view, sgr_nowPlayingRoot)) {
                // Spotify paints more than the track's card in the bar (a Jam's "Jam by ..." strip), so a
                // painted view is only remembered here; NowPlayingBar.x picks the card among them. One
                // already picked is not taken over by a later paint, or the glass jumped to that strip.
                if (SGLooksLikeCard(view, color)) {
                    objc_setAssociatedObject(view, &kPaintedCardKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    if (sgr_nowPlayingCard != view && !SGIsInside(sgr_nowPlayingCard, sgr_nowPlayingRoot)) {
                        sgr_nowPlayingCard = view;
                        UIView *bar = sgr_nowPlayingRoot;
                        dispatch_async(dispatch_get_main_queue(), ^{ [bar.superview setNeedsLayout]; });
                    }
                }
                color = NULL;
            } else if (SGIsInside(view, sgr_lyricsPageRoot)) {
                color = NULL;
            } else if (SGIsBaseSurface(color) && (SGIsInside(view, sgr_playlistRoot) || SGIsInside(view, sgr_albumRoot) || SGIsInside(view, sgr_artistRoot))) {
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
