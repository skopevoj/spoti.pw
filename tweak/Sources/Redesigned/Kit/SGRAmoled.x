// The redesign's AMOLED background in dark appearance; light appearance leaves native semantic surfaces alone.
// AMOLED background: Spotify paints its base surface #121212; with the switch on, that grey and
// the gradients fading into it go pure black. Lighter greys stay (#1F1F1F placeholders, #292929
// cards), so elevated surfaces still read against the black.
//
// Trees: #121212 sits on the Home, Search, Library and settings scroll views, on list rows, the
// message bar and the player's bottom gradient view.
#import "Core/SGCore.h"

// Neutral and darker than #1A1A1A, but not already black.
static BOOL isBaseGrey(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID()) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    if (n == 2) return c[0] > 0.01 && c[0] <= 0.10;
    if (n < 3) return NO;
    return c[0] > 0.01 && c[0] <= 0.10 && fabs(c[0] - c[1]) < 0.02 && fabs(c[1] - c[2]) < 0.02;
}

// Layers get set from background threads too, so no autoreleased UIColor here.
static CGColorRef copyBlack(CGColorRef color) {
    return CGColorCreateGenericGray(0, CGColorGetAlpha(color));
}

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (SGRedesignLightAppearance() || !isBaseGrey(color)) {
        %orig;
        return;
    }
    CGColorRef black = copyBlack(color);
    %orig(black);
    CGColorRelease(black);
}
%end

%hook CAGradientLayer
- (void)setColors:(NSArray *)colors {
    if (SGRedesignLightAppearance()) { %orig; return; }
    NSMutableArray *mapped = [[NSMutableArray alloc] initWithCapacity:colors.count];
    for (id entry in colors) {
        CGColorRef color = (__bridge CGColorRef)entry;
        if (SGRedesignLightAppearance() || !isBaseGrey(color)) {
            [mapped addObject:entry];
            continue;
        }
        CGColorRef black = copyBlack(color);
        [mapped addObject:(__bridge id)black];
        CGColorRelease(black);
    }
    %orig(colors ? mapped : nil);
}
%end

// Spotify's settings list paints nothing of its own and shows whatever sits under it, which is not
// the base grey the hooks above turn black. The list is the top surface, so it takes the black.
%hook _TtC21Settings_PlatformImpl26SettingsListViewController
- (void)viewDidLayoutSubviews {
    UIViewController *appearanceOwner = (UIViewController *)self;
    if (appearanceOwner.overrideUserInterfaceStyle != SGRedesignAppearanceStyle())
        appearanceOwner.overrideUserInterfaceStyle = SGRedesignAppearanceStyle();
    %orig;
    for (UIView *sub in ((UIViewController *)self).view.subviews) {
        if ([sub isKindOfClass:UICollectionView.class]) sub.backgroundColor = SGAppearanceColor(UIColor.whiteColor, UIColor.blackColor);
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
