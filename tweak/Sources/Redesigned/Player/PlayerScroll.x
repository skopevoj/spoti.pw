// Player redesign: the player never scrolls up. Scrolling stays on because Spotify's dismiss pull rides on
// the list's own pan and starts only at its top, so the offset is clamped instead; the insets stay
// Spotify's, since changing one mid-drag moves the offset under the finger.
//
// Scrubbing the trackbar: when the user drags the progress bar, slight vertical finger movement would
// otherwise trigger the list's dismiss pull and close the player tab. Disabling the list's pan gesture
// while the slider is tracking touches keeps the touch on the slider until released.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static NSString *const kListIdentifier = @"scrolling_npv_collection_view_accessibility_identifier";

static __weak UIScrollView *sg_loggedList;
static __weak UIScrollView *sg_lockedScroll;

static void holdAtTop(UIScrollView *list) {
    if (![list.accessibilityIdentifier isEqualToString:kListIdentifier]) return;
    CGFloat top = -list.adjustedContentInset.top;
    CGPoint offset = list.contentOffset;
    if (offset.y <= top) return;
    CGFloat past = offset.y - top;
    list.contentOffset = CGPointMake(offset.x, top);

    if (sg_loggedList == list) return;
    sg_loggedList = list;
    SGLog(@"redesign player: scroll held at the top, %.0fpt up taken back (%@)", past, list.isDragging ? @"drag" : @"no finger");
}

static UIScrollView *enclosingScroll(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v isKindOfClass:UIScrollView.class]) return (UIScrollView *)v;
    }
    return nil;
}

static void lockScroll(UISlider *slider) {
    UIScrollView *scroll = enclosingScroll(slider);
    if (scroll && scroll.panGestureRecognizer.enabled) {
        scroll.panGestureRecognizer.enabled = NO;
        sg_lockedScroll = scroll;
    }
}

static void unlockScroll(void) {
    UIScrollView *scroll = sg_lockedScroll;
    if (scroll) {
        scroll.panGestureRecognizer.enabled = YES;
        sg_lockedScroll = nil;
    }
}

%hook _TtC21NowPlaying_ScrollImpl23NPVScrollViewController
- (void)scrollViewDidScroll:(UIScrollView *)list {
    holdAtTop(list);
    %orig;
}
%end

%hook _TtCO17NowPlaying_ECMKit11ProgressBar6Slider
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL tracking = %orig;
    if (tracking) lockScroll((UISlider *)self);
    return tracking;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    %orig;
    unlockScroll();
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    %orig;
    unlockScroll();
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC21NowPlaying_ScrollImpl23NPVScrollViewController",
        @"_TtCO17NowPlaying_ECMKit11ProgressBar6Slider",
    ]);
}
