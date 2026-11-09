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
#import "Redesigned/Kit/SGRBarGeometry.h"

static const CGFloat kCardRadius = 24;
static char kGlassKey, kRailConstraintKey;
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

static UIView *detectColoredCard(UIView *bar) {
    __block UIView *best = nil;
    __block CGFloat bestArea = 0;
    SGForEachView(bar, ^(UIView *v) {
        if ([v isKindOfClass:UIVisualEffectView.class] || SGKeepsColor(v) || !SGLooksLikeCard(v, v.layer.backgroundColor)) return;
        CGFloat area = v.bounds.size.width * v.bounds.size.height;
        if (area > bestArea) { bestArea = area; best = v; }
    });
    return best;
}

// Fallback when nothing is painted: the box around artwork, text and the small buttons.
static CGRect contentBounds(UIView *bar, UIView *target) {
    __block CGRect box = CGRectNull;
    SGForEachView(bar, ^(UIView *v) {
        if (v.hidden || v.alpha == 0) return;
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
        if (!square || v.layer.cornerRadius <= 0) return;
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
        if (f.size.height > 3 || f.size.width < 200 || v.superview.bounds.size.height < 40) return;
        CGRect target = CGRectMake(52, card.bounds.size.height - 6, 226, 2);
        if (CGRectEqualToRect(f, target)) return;
        v.frame = target;
        [v setNeedsLayout];
        [v layoutIfNeeded];
    });
}

// The miniplayer is separate chrome, not a child of the tab controller. Reserve the same
// native rail region in its content constraints, preserving and restoring Spotify's margins.
static void fitBesideRail(UIViewController *container) {
    UIView *content = container.childViewControllers.firstObject.viewIfLoaded;
    if (!content || content.superview != container.view) return;
    UIEdgeInsets inset = SGRVerticalBarContentInsets(container.view, SGRVerticalBarExtent);
    BOOL changed = NO;
    for (NSLayoutConstraint *constraint in container.view.constraints) {
        if (!constraint.active || constraint.relation != NSLayoutRelationEqual || constraint.multiplier != 1) continue;
        BOOL forward = constraint.firstItem == content && constraint.secondItem == container.view;
        BOOL reverse = constraint.secondItem == content && constraint.firstItem == container.view;
        if (!forward && !reverse) continue;
        NSLayoutAttribute attribute = forward ? constraint.firstAttribute : constraint.secondAttribute;
        NSLayoutAttribute other = forward ? constraint.secondAttribute : constraint.firstAttribute;
        if (attribute != other) continue;
        BOOL rtl = container.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        BOOL left = attribute == NSLayoutAttributeLeft || attribute == (rtl ? NSLayoutAttributeTrailing : NSLayoutAttributeLeading);
        BOOL right = attribute == NSLayoutAttributeRight || attribute == (rtl ? NSLayoutAttributeLeading : NSLayoutAttributeTrailing);
        if (!left && !right) continue;
        NSArray<NSNumber *> *record = objc_getAssociatedObject(constraint, &kRailConstraintKey);
        CGFloat adjustment = (left ? inset.left : -inset.right) * (forward ? 1 : -1);
        // No rail, no ownership: ordinary Spotify layouts must remain completely untouched.
        if (!record && adjustment == 0) continue;
        CGFloat current = constraint.constant;
        BOOL stillOurs = record && fabs(current - record[1].doubleValue) < 0.01;
        // A new constant written by Spotify becomes the new baseline, not something to undo.
        CGFloat baseline = stillOurs ? record[0].doubleValue : current;
        CGFloat value = baseline + adjustment;
        if (adjustment == 0) {
            objc_setAssociatedObject(constraint, &kRailConstraintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            objc_setAssociatedObject(constraint, &kRailConstraintKey, @[@(baseline), @(value)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (fabs(current - value) > 0.01) {
            constraint.constant = value;
            changed = YES;
        }
    }
    if (changed) [container.view setNeedsLayout];
}

static void styleNowPlayingBar(UIViewController *container) {
    fitBesideRail(container);
    UIViewController *barVC = container.childViewControllers.firstObject;
    UIView *bar = barVC.viewIfLoaded ?: container.view;
    sgr_nowPlayingRoot = bar;

    UIView *card = sgr_nowPlayingCard;
    if (!card || !SGIsInside(card, bar)) card = sgr_nowPlayingCard = detectColoredCard(bar);

    container.view.layer.backgroundColor = NULL;
    SGStripBackgrounds(bar);

    CGRect frame = card ? SGFrameIn(card, container.view) : contentBounds(bar, container.view);
    if (CGRectIsNull(frame)) return;
    frame.size.height = MIN(frame.size.height, 80);
    if (frame.size.height < 30 || frame.size.width < 100) return;

    CGFloat radius = MIN(kCardRadius, frame.size.height / 2);
    if (card) {
        roundView(card, radius);
        restyleCardContent(card);
    }

    UIVisualEffectView *glass = SGGlassFor(container.view, &kGlassKey);
    // Dark whatever the system is set to: the bar is outside the navigation stacks Spotify makes dark, and
    // took the system's light glass on a phone in light mode (TabBar.x).
    if (glass.overrideUserInterfaceStyle != SGRedesignAppearanceStyle()) glass.overrideUserInterfaceStyle = SGRedesignAppearanceStyle();
    sg_cardGlass = glass;
    static CGRect lastVerticalFrame = {{-1, -1}, {0, 0}};
    if (!CGRectIsNull(SGRVerticalBarFrameIn(container.view, 76)) && !CGRectEqualToRect(lastVerticalFrame, frame)) {
        lastVerticalFrame = frame;
        SGLog(@"vertical navigation miniplayer: card %@ container %@", NSStringFromCGRect(frame), NSStringFromCGRect(container.view.bounds));
    }
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
