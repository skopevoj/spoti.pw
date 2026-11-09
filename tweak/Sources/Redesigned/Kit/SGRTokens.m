#import <CoreText/SFNTLayoutTypes.h>
#import "Core/SGCore.h"
#import "SGRTokens.h"
#import "SGRAccent.h"

const CGFloat SGRSideMargin = 16;
const CGFloat SGRGrid = 8;
const CGFloat SGRRadiusArtwork = 12;
const CGFloat SGRRadiusCard = 16;
const CGFloat SGRRadiusCover = 8;
const CGFloat SGRRadiusThumb = 6;
const CGFloat SGRGlassCircleSize = 44;
const CGFloat SGRActionHeight = 48;
const CGFloat SGRActionSpacing = 12;
const CGFloat SGRGlassSpacing = 16;
const NSTimeInterval SGRCrossfade = 0.35;

// A layout spring settles in about this long without overshooting; a press gives a little back.
static const NSTimeInterval kLayoutDuration = 0.45, kPressDuration = 0.32;
static const CGFloat kPressDamping = 0.62;

UIColor *SGRPrimary(void) {
    return SGAppearanceColor([UIColor colorWithWhite:0.08 alpha:1], UIColor.whiteColor);
}

UIColor *SGRSecondary(void) {
    return SGAppearanceColor([UIColor colorWithWhite:SGRIncreaseContrast() ? 0.22 : 0.30 alpha:1],
        [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.80 : 0.65]);
}

UIColor *SGRTertiary(void) {
    return SGAppearanceColor([UIColor colorWithWhite:SGRIncreaseContrast() ? 0.30 : 0.40 alpha:1],
        [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.60 : 0.40]);
}

// Read per call: the accent is stored as it is picked, and the colour row reads it the same way.
UIColor *SGRAccent(void) {
    UIColor *color = SGRAccentColor() ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
    // Text and glyph accents on a pale field need a darker shade of the selected hue.
    CGFloat r, g, b, a;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return color;
    CGFloat maximum = MAX(r, MAX(g, b));
    CGFloat scale = maximum > 0.40 ? 0.40 / maximum : 1;
    return SGAppearanceColor([UIColor colorWithRed:r * scale green:g * scale blue:b * scale alpha:a], color);
}

UIColor *SGRNeutralField(void) {
    return SGAppearanceColor([UIColor colorWithWhite:0.97 alpha:1], [UIColor colorWithWhite:0x12 / 255.0 alpha:1]);
}

UIColor *SGRSolidGlassFill(void) {
    return SGAppearanceColor([UIColor colorWithWhite:0.92 alpha:1], [UIColor colorWithWhite:1 alpha:0.16]);
}

UIColor *SGRHairline(void) {
    CGFloat alpha = SGRIncreaseContrast() ? 0.20 : 0.12;
    return SGAppearanceColor([UIColor colorWithWhite:0 alpha:alpha], [UIColor colorWithWhite:1 alpha:alpha]);
}

UIColor *SGRElevated(UIColor *field) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![field getRed:&r green:&g blue:&b alpha:&a]) return SGAppearanceColor([UIColor colorWithWhite:0.92 alpha:1], [UIColor colorWithWhite:1 alpha:0.08]);
    // 12% towards white keeps a card on a black field clear of the greys SGRAmoled.x turns black.
    CGFloat lift = 0.12;
    return SGAppearanceColor([UIColor colorWithWhite:0.92 alpha:1],
        [UIColor colorWithRed:r + (1 - r) * lift green:g + (1 - g) * lift blue:b + (1 - b) * lift alpha:1]);
}

UIFont *SGRFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    UIContentSizeCategory current = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (largest && UIContentSizeCategoryCompareToCategory(current, largest) == NSOrderedDescending) current = largest;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:current];
    CGFloat size = [UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:traits].pointSize;
    return [UIFont systemFontOfSize:size weight:weight];
}

UIFont *SGRMonospacedDigitsFont(UIFont *font) {
    if (!font) return nil;
    NSArray *features = @[@{UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType), UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}];
    UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute: features}];
    return [UIFont fontWithDescriptor:descriptor size:font.pointSize];
}

BOOL SGRReduceMotion(void) {
    return UIAccessibilityIsReduceMotionEnabled();
}

BOOL SGRReduceTransparency(void) {
    return UIAccessibilityIsReduceTransparencyEnabled();
}

BOOL SGRIncreaseContrast(void) {
    return UIAccessibilityDarkerSystemColorsEnabled();
}

void SGRAnimate(SGRMotion motion, void (^animations)(void), void (^completion)(BOOL finished)) {
    if (!animations) return;
    if (motion != SGRMotionFade && SGRReduceMotion()) {
        [UIView performWithoutAnimation:animations];
        if (completion) completion(YES);
        return;
    }
    UIViewAnimationOptions options = UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;
    switch (motion) {
        case SGRMotionLayout:
            [UIView animateWithDuration:kLayoutDuration delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case SGRMotionPress:
            [UIView animateWithDuration:kPressDuration delay:0 usingSpringWithDamping:kPressDamping initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case SGRMotionFade:
            [UIView animateWithDuration:SGRCrossfade delay:0 options:options | UIViewAnimationOptionCurveEaseInOut animations:animations completion:completion];
            break;
    }
}

BOOL SGRIsBaseSurface(CGColorRef color) {
    if (SGIsBaseSurface(color)) return YES;
    if (!SGRedesignLightAppearance() || !color || CGColorGetAlpha(color) < 0.99) return NO;
    UIColor *value = [UIColor colorWithCGColor:color];
    CGFloat r, g, b, a;
    return [value getRed:&r green:&g blue:&b alpha:&a] && r >= 0.95 && fabs(r-g) < 0.01 && fabs(g-b) < 0.01;
}
