// Presentation policy only: never change the user's saved navbar composition or switches.
#import <UIKit/UIKit.h>

static inline BOOL SGRNavbarHidesLabels(NSString *bundle, BOOL fullyOpen,
                                      UIInterfaceOrientation orientation, BOOL userHidesLabels) {
    if (![bundle isEqualToString:@"com.kyle.spotipw.duo"]) return userHidesLabels;
    return !(fullyOpen && UIInterfaceOrientationIsPortrait(orientation)) || userHidesLabels;
}

// Used only when a source icon does not expose its authoritative isActive state.
// Spotify's semantic primary is white in Dark and near-black in Light. Require
// opaque primary ink so a translucent secondary label cannot look selected.
static inline BOOL SGRNavbarLabelIsActive(UIColor *color, UITraitCollection *traits, BOOL light) {
    color = [color resolvedColorWithTraitCollection:traits];
    CGFloat r, g, b, a;
    if (![color getRed:&r green:&g blue:&b alpha:&a] || a < 0.95) return NO;
    return light ? MAX(r, MAX(g, b)) < 0.15 : MIN(r, MIN(g, b)) > 0.95;
}
