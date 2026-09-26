// The redesign's now playing bar: the album-coloured card becomes a glass card with round artwork and the
// progress line under the text. Spotify's own labels, buttons and gestures stay in place.
//
// The full screen player morphs the bar's own card and artwork into the cover art. The bar was
// written to hand itself back to Spotify for that animation, from NowPlaying_ViewPageImpl's
// Show/CloseFullscreenAnimatedTransitioning, but Spotify 9.1.78 never runs the player through those,
// so the handback never happened and is gone; if the morph ever reads as a cut, the place to start is
// Shared/Player/PlayerEvents.h, which does fire. What does move with the player is a stand-in of the
// bar, which BarTransition.x keeps glass behind.
//
// Tree (trees/home.txt): NowPlayingBarContainerViewController.view 402x56 > NowPlayingBarViewController.view
//   at {8,0} 386x56 > UIView 386x56 (the painted card) > artwork 40x40 r=4, title stack,
//   progress line 370x2 at the bottom. The glass pane goes on the container's view.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "NowPlayingBar.h"

static const CGFloat kCardRadius = 24;
static char kGlassKey;
static __weak UIVisualEffectView *sg_cardGlass;
static __weak UIView *sg_cardArtwork;

CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius) {
    UIVisualEffectView *glass = sg_cardGlass;
    if (!glass.superview || !glass.window || !host) return CGRectNull;
    if (radius) *radius = MIN(kCardRadius, glass.bounds.size.height / 2);
    return [host convertRect:glass.bounds fromView:glass];
}

CGRect SGRNowPlayingArtworkFrameIn(UIView *host) {
    UIView *artwork = sg_cardArtwork;
    if (!artwork.window || !host) return CGRectNull;
    return [host convertRect:artwork.bounds fromView:artwork];
}

// Spotify hangs attachments on the bar's card: in a Jam, the "Jam by ..." hat, a SwiftUI
// _UIHostingView of Jam_AttachmentsImpl.JamHatElement as wide as the card and 44 high (FLEX, Jam
// running). It is not the card, and the painted view around both took the glass up onto the hat. Only
// the hats are matched: a container of the attachments module may hold the card itself.
static BOOL isAttachment(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"AttachmentsImpl"] && [name containsString:@"Hat"];
}

static BOOL insideAttachment(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) if (isAttachment(v)) return YES;
    return NO;
}

static BOOL holdsAttachment(UIView *view) {
    __block BOOL found = NO;
    SGForEachView(view, ^(UIView *v) {
        if (!found) found = isAttachment(v);
    });
    return found;
}

// The track's card holds its title and artist (Connect's InformationContainer, trees/test6.txt) or, in a
// bar without one, the artwork.
static BOOL holdsTrack(UIView *view, BOOL named) {
    if (insideAttachment(view, nil)) return NO;
    __block BOOL found = NO;
    SGForEachView(view, ^(UIView *v) {
        if (found || insideAttachment(v, view)) return;
        if (named) {
            found = [NSStringFromClass(v.class) containsString:@"InformationContainer"];
            return;
        }
        CGSize size = v.bounds.size;
        found = ![v isKindOfClass:UIControl.class] && size.width >= 36 && size.width <= 48 && fabs(size.width - size.height) < 1;
    });
    return found;
}

// The largest painted view holding the track, one without an attachment in it before one with.
static UIView *detectColoredCard(UIView *bar, BOOL named) {
    __block UIView *best = nil, *bestWithAttachment = nil;
    __block CGFloat bestArea = 0, bestWithAttachmentArea = 0;
    SGForEachView(bar, ^(UIView *v) {
        if ([v isKindOfClass:UIVisualEffectView.class] || SGKeepsColor(v)) return;
        if (!SGLooksLikeCard(v, v.layer.backgroundColor) && !SGRPaintedAsCard(v)) return;
        if (!holdsTrack(v, named)) return;
        CGFloat area = v.bounds.size.width * v.bounds.size.height;
        if (holdsAttachment(v)) {
            if (area > bestWithAttachmentArea) { bestWithAttachmentArea = area; bestWithAttachment = v; }
        } else if (area > bestArea) {
            bestArea = area;
            best = v;
        }
    });
    return best ?: bestWithAttachment;
}

// The card's frame with the attachments on it cut off, the hat above it or anything hung below.
static CGRect withoutAttachments(CGRect frame, UIView *target) {
    __block CGRect cut = frame;
    SGForEachView(target, ^(UIView *v) {
        if (!isAttachment(v) || insideAttachment(v.superview, target) || v.hidden || v.alpha == 0) return;
        CGRect attachment = SGFrameIn(v, target);
        if (!CGRectIntersectsRect(cut, attachment)) return;
        if (CGRectGetMidY(attachment) < CGRectGetMidY(cut)) {
            CGFloat top = CGRectGetMaxY(attachment);
            cut.size.height = CGRectGetMaxY(cut) - top;
            cut.origin.y = top;
        } else {
            cut.size.height = CGRectGetMinY(attachment) - CGRectGetMinY(cut);
        }
    });
    return cut;
}

// Fallback when nothing is painted: the box around artwork, text and the small buttons.
static CGRect contentBounds(UIView *bar, UIView *target) {
    __block CGRect box = CGRectNull;
    SGForEachView(bar, ^(UIView *v) {
        if (v.hidden || v.alpha == 0 || insideAttachment(v, bar)) return;
        CGFloat width = v.bounds.size.width;
        BOOL content = ([v isKindOfClass:UIImageView.class] && width >= 20 && width <= 120)
            || [v isKindOfClass:UILabel.class]
            || ([v isKindOfClass:UIControl.class] && width <= 100);
        if (content) box = CGRectUnion(box, SGFrameIn(v, target));
    });
    return CGRectIsNull(box) ? box : CGRectInset(box, -10, -8);
}

static void roundView(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
}

static void restyleCardContent(UIView *card) {
    SGForEachView(card, ^(UIView *v) {
        CGSize size = v.bounds.size;
        BOOL square = size.width >= 36 && size.width <= 48 && fabs(size.width - size.height) < 1;
        if (!square || v.layer.cornerRadius <= 0 || insideAttachment(v, card)) return;
        if (v.layer.cornerRadius >= size.width / 2) {
            if (!sg_cardArtwork) sg_cardArtwork = v;
            return;
        }
        UIView *outer = v;
        for (UIView *u = v; u && u != card && CGSizeEqualToSize(u.bounds.size, size); u = u.superview) {
            roundView(u, size.width / 2);
            u.clipsToBounds = YES;
            outer = u;
        }
        sg_cardArtwork = outer;
    });
    SGForEachView(card, ^(UIView *v) {
        CGRect f = v.frame;
        if (f.size.height > 3 || f.size.width < 200 || v.superview.bounds.size.height < 40 || insideAttachment(v, card)) return;
        CGRect target = CGRectMake(52, card.bounds.size.height - 6, 226, 2);
        if (CGRectEqualToRect(f, target)) return;
        v.frame = target;
        [v setNeedsLayout];
        [v layoutIfNeeded];
    });
}

static BOOL shownIn(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) if (v.hidden || v.alpha == 0) return NO;
    return YES;
}

// A hat and the card share one glass card, the hat its header row: two panes stacked with a gap read
// as two bars, and the hat's pane was measured off the SwiftUI view mid-animation, 12 above where the
// hat settles (trees/jam-now.txt: pane at y -12, hat at 0). The edge on the hat's side comes from the
// bar instead, which Spotify grows by the hat's 44 (386x100 in a Jam, card at y 44) and whose changes
// lay the container out again.
static CGRect withHat(CGRect cardFrame, UIView *bar, UIView *host) {
    __block UIView *hat = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (!hat && isAttachment(v) && v.bounds.size.height >= 20 && shownIn(v, bar)) hat = v;
    });
    if (!hat) return cardFrame;
    CGRect barFrame = SGFrameIn(bar, host), hatFrame = SGFrameIn(hat, host);
    CGRect frame = cardFrame;
    if (CGRectGetMidY(hatFrame) < CGRectGetMidY(cardFrame)) {
        CGFloat top = MAX(CGRectGetMinY(barFrame), CGRectGetMinY(hatFrame));
        if (top >= CGRectGetMinY(cardFrame)) return cardFrame;
        frame.size.height = CGRectGetMaxY(cardFrame) - top;
        frame.origin.y = top;
    } else {
        CGFloat bottom = MIN(CGRectGetMaxY(barFrame), CGRectGetMaxY(hatFrame));
        if (bottom <= CGRectGetMaxY(cardFrame)) return cardFrame;
        frame.size.height = bottom - CGRectGetMinY(cardFrame);
    }

    static NSUInteger logged;
    if (logged++ < 2) {
        SGLog(@"now playing hat %@ at %@ joins the card %@ as %@", hat.class, NSStringFromCGRect(hatFrame),
              NSStringFromCGRect(cardFrame), NSStringFromCGRect(frame));
    }
    return frame;
}

static void styleNowPlayingBar(UIViewController *container) {
    UIViewController *barVC = container.childViewControllers.firstObject;
    UIView *bar = barVC.viewIfLoaded ?: container.view;
    sgr_nowPlayingRoot = bar;

    BOOL named = SGHasClass(bar, @"InformationContainer");
    UIView *card = sgr_nowPlayingCard;
    if (!card || !SGIsInside(card, bar) || !holdsTrack(card, named) || holdsAttachment(card)) {
        UIView *passed = card;
        card = sgr_nowPlayingCard = detectColoredCard(bar, named);
        static NSUInteger logged;
        if (passed && passed != card && SGIsInside(passed, bar) && logged++ < 4) {
            SGLog(@"now playing card: passed over %@ %@ for %@ %@", passed.class, NSStringFromCGRect(SGFrameIn(passed, bar)),
                  card.class, card ? NSStringFromCGRect(SGFrameIn(card, bar)) : @"(none)");
        }
    }

    container.view.layer.backgroundColor = NULL;
    SGStripBackgrounds(bar);

    CGRect frame = card ? SGFrameIn(card, container.view) : contentBounds(bar, container.view);
    if (CGRectIsNull(frame)) return;
    CGRect whole = frame;
    frame = withoutAttachments(frame, container.view);
    static NSUInteger cuts;
    if (!CGRectEqualToRect(whole, frame) && cuts++ < 2) {
        SGLog(@"now playing card: attachments cut %@ to %@", NSStringFromCGRect(whole), NSStringFromCGRect(frame));
    }
    frame.size.height = MIN(frame.size.height, 80);
    if (frame.size.height < 30 || frame.size.width < 100) return;

    CGFloat radius = MIN(kCardRadius, frame.size.height / 2);
    if (card) {
        roundView(card, radius);
        restyleCardContent(card);
    }
    frame = withHat(frame, bar, container.view);

    UIVisualEffectView *glass = SGGlassFor(container.view, &kGlassKey);
    // Dark whatever the system is set to: the bar is outside the navigation stacks Spotify makes dark, and
    // took the system's light glass on a phone in light mode (TabBar.x).
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    sg_cardGlass = glass;
    glass.frame = frame;
    SGShapeGlass(glass, radius, NO);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"now playing card %@ at %@ (bar %@, container %@)", card.class, NSStringFromCGRect(frame),
              NSStringFromCGRect(bar.frame), NSStringFromCGRect(container.view.bounds));
    });
}

%hook _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    styleNowPlayingBar((UIViewController *)self);
}
%end

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *parent = ((UIViewController *)self).parentViewController;
    if ([NSStringFromClass(parent.class) containsString:@"NowPlayingBarContainer"]) styleNowPlayingBar(parent);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController",
        @"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController",
    ]);
}
