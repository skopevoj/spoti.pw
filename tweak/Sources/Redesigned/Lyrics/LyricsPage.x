// The redesign's full screen lyrics page, on glass over the redesigned player, which shows through it:
// the lyrics card under the player reads as having grown to the screen. A copy of
// Native/Lyrics/LyricsPage.x without its switch.
//
// Page (trees/lyrics.txt): a page of its own, presented over the player by a
// _UIOverFullscreenPresentationController, which is why the card's glass stops at the card's edge.
// Tome_PageTemplateImpl paints the template view #121212 and FullscreenView paints itself the
// album colour on top, both opaque; clearing them lets the player's blurred artwork through.
//
// The album colour is the stubborn one: it arrives per track, after the page has laid out, and it
// comes back through a path SGRRepaint.x never sees, so a sweep at layout time loses the race.
// FullscreenView is asked not to keep it at all instead. The pane goes inside FullscreenView, in
// front of whatever that view still fills itself with, rather than behind the whole page.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRRepaint.h"

static char kPageGlassKey;

// Up to the presentation: the template views in between paint themselves opaque once, at setup.
// Only the chain is cleared, not the subtree -- nothing else on the page is painted.
static UIView *clearAncestors(UIView *view) {
    UIView *top = view;
    for (UIView *v = view; v && ![v isKindOfClass:UIWindow.class]
            && ![NSStringFromClass(v.class) hasPrefix:@"UITransition"]; v = v.superview) {
        v.layer.backgroundColor = NULL;
        top = v;
    }
    return top;
}

%hook _TtC32Lyrics_FullscreenElementPageImpl14FullscreenView
// A colour kept here is re-applied whenever UIKit feels like it, so it is refused outright.
- (void)setBackgroundColor:(UIColor *)color {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"lyrics page paints itself %@ through UIView", color); });
    %orig(nil);
}

- (void)layoutSubviews {
    %orig;
    UIView *page = (UIView *)self;
    if (page.bounds.size.height < 200) return;

    page.layer.backgroundColor = NULL;
    sgr_lyricsPageRoot = clearAncestors(page);

    UIVisualEffectView *glass = SGGlassFor(page, &kPageGlassKey);
    // Dark whatever the system is set to: the page is presented outside the navigation stacks Spotify
    // makes dark, and would be light glass under white lyrics on a phone in light mode.
    if (glass.overrideUserInterfaceStyle != SGRedesignAppearanceStyle()) glass.overrideUserInterfaceStyle = SGRedesignAppearanceStyle();
    glass.frame = page.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // Full bleed, so the shape is spelled out: a fresh pane does not promise square corners.
    SGShapeGlass(glass, 0, NO);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC32Lyrics_FullscreenElementPageImpl14FullscreenView"]);
}
