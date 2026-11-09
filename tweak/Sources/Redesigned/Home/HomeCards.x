// Home redesign: every card Home keeps is the same Encore button, told apart where it lays out:
//   id=Shortcut.Card.Home          a shortcut tile 181x48 r=4 that clips, in a ConfigurableUIEventObservingView
//                                  r=4 (trees/clean/home/01.txt:36-37): the cover radius, continuous, and its
//                                  picture run across it (HomeTiles.m)
//   id=Components.UI.HomeCard      a shelf card, its picture Encore.ImageView 149x149 > UIImageView with no radius
//                                  of its own (10.txt:2280-2286): cut at the cover radius, continuous, over the
//                                  4pt Spotify bakes into the picture (an artist's round one sits inside it)
//   in Discovery_MediumDensityCardKit.DJMDCView   the DJ card 370x192 r=8 that clips (01.txt:477-478): the card
//                                  radius, and without the transcript Spotify's DJ talks through
//                                  (Discovery_MediumDensityCardKit.TranscriptView, :500) or the Beta badge (:503)
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

// Below this a card's picture is a glyph or a placeholder, not a cover.
static const CGFloat kCoverMinWidth = 80;

static char kImageKey;

static void roundCorners(UIView *view, CGFloat radius) {
    CALayer *layer = view.layer;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
}

static void roundCover(UIView *card) {
    UIView *holder = SGRFindByIdentifier(card, @"Encore.ImageView", &kImageKey);
    if (holder.bounds.size.width < kCoverMinWidth) return;
    for (UIView *sub in holder.subviews) {
        if (![sub isKindOfClass:UIImageView.class]) continue;
        roundCorners(sub, SGRRadiusCover);
        if (!sub.layer.masksToBounds) sub.layer.masksToBounds = YES;
    }
}

// The transcript's own labels are plain UILabels the Kit keeps transparent; the Swift views around them
// take their alpha again on every pass.
static void calmDJ(UIView *card) {
    SGRPreserveNativeSurface(card);
    for (UIView *sub in card.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if (![name containsString:@"TranscriptView"] && ![name containsString:@"BetaBadge"]) continue;
        if (sub.alpha != 0) sub.alpha = 0;
        sub.accessibilityElementsHidden = YES;
        SGForEachView(sub, ^(UIView *v) {
            if ([v isKindOfClass:UILabel.class]) SGRSuppress(v);
        });
    }
}

static void style(UIView *button) {
    NSString *identifier = button.accessibilityIdentifier;
    if ([identifier isEqualToString:@"Shortcut.Card.Home"]) {
        roundCorners(button, SGRRadiusCover);
        if (button.superview.layer.cornerRadius > 0) roundCorners(button.superview, SGRRadiusCover);
        SGRHomeStyleTile(button);
        return;
    }
    if ([identifier isEqualToString:@"Components.UI.HomeCard"]) {
        roundCover(button);
        return;
    }
    static Class dj;
    if (!dj) dj = NSClassFromString(@"_TtC30Discovery_MediumDensityCardKit9DJMDCView");
    if (dj && [button.superview isKindOfClass:dj]) {
        roundCorners(button, SGRRadiusCard);
        calmDJ(button);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign home: DJ card at the card radius, transcript gone"); });
    }
}

%hook _TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton
- (void)layoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    style((UIView *)self);
    SGRHomeProbeEnd(SGRHomeProbeCards, began);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton",
        @"_TtC30Discovery_MediumDensityCardKit9DJMDCView",
    ]);
}
