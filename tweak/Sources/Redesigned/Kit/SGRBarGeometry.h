// System-selected vertical navigation geometry, resolved at the window so translated pages and
// inherited content safe-area insets cannot move the rail. No model or size-class heuristics.
#import <UIKit/UIKit.h>

// Compact Duo navigation, shared by the rail and content clearance.
static const CGFloat SGRVerticalBarExtent = 52;

static inline CGFloat SGRVerticalBarNavigationRowHeight(BOOL hideLabels) {
    return hideLabels ? 48 : MAX(64, ceil([UIFont preferredFontForTextStyle:UIFontTextStyleCaption2].lineHeight) + 40);
}

// Native Back occupies the first 52pt. Keep a second 44pt menu with 8pt gaps only
// when a complete navigation row still fits. Reserve for labeled rows in either
// label mode so the menu and navigation agree without coupling Kit to a preference.
// In very short regions, navigation retains one row and the optional menu yields.
static inline CGFloat SGRVerticalBarTopReservation(CGFloat height) {
    CGFloat minimumNavigation = SGRVerticalBarNavigationRowHeight(NO) + 4;
    if (height >= 112 + minimumNavigation) return 112;
    return MIN(60, MAX(0, height - minimumNavigation));
}

static inline CGRect SGRVerticalBarFrameIn(UIView *view, CGFloat extent) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        UIWindow *window = [view isKindOfClass:UIWindow.class] ? (UIWindow *)view : view.window;
        if (!window) return CGRectNull;
        UIVerticalBarEdge edge = window.traitCollection.verticalBarEdge;
        if (edge != UIVerticalBarEdgeLeading && edge != UIVerticalBarEdgeTrailing) return CGRectNull;
        NSDirectionalRectEdge directional = edge == UIVerticalBarEdgeLeading ? NSDirectionalRectEdgeLeading : NSDirectionalRectEdgeTrailing;
        UIViewLayoutRegion *region = [UIViewLayoutRegion layoutRegionForBarOnDirectionalEdge:directional extent:extent];
        UIEdgeInsets insets = [window edgeInsetsForLayoutRegion:region];
        CGRect frame = UIEdgeInsetsInsetRect(window.bounds, insets);
        if (CGRectIsEmpty(frame)) return CGRectNull;
        return [view convertRect:frame fromView:window];
    }
#endif
    return CGRectNull;
}

static inline UIEdgeInsets SGRVerticalBarContentInsets(UIView *view, CGFloat extent) {
    CGRect frame = SGRVerticalBarFrameIn(view, extent);
    if (CGRectIsNull(frame) || CGRectGetMinX(frame) >= CGRectGetMaxX(view.bounds)
        || CGRectGetMaxX(frame) <= CGRectGetMinX(view.bounds)) return UIEdgeInsetsZero;
    // The region is directional; use its resolved physical location so RTL follows UIKit too.
    if (CGRectGetMidX(frame) < CGRectGetMidX(view.bounds))
        return UIEdgeInsetsMake(0, MAX(0, CGRectGetMaxX(frame) - CGRectGetMinX(view.bounds)) + 8, 0, 0);
    return UIEdgeInsetsMake(0, 0, 0, MAX(0, CGRectGetMaxX(view.bounds) - CGRectGetMinX(frame)) + 8);
}
