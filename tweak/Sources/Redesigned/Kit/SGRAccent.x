// The redesign's accent colour, chosen apart from the native look's: its copy of Native/Appearance/Accent.x.
// Accent colour: Spotify's green, #1ED760, is one token. Its three components occur once in the
// whole binary, and every green the app draws, from the play button to the "Zobrazit vše" links
// and the progress bar, is that token or a state blended from it. So it is swapped where it is
// born, in the UIColor initialiser, and the blends follow. Lottie animations carry their own green
// and are caught at the layer, below. Image assets with green baked in, the logo above all, are
// out of reach.
#import "Core/SGCore.h"
#import "SGRAccent.h"
#import "Settings/SGPageStyle.h"

// The greens the app is known to build from literals: the token, and the older brand green the
// upsell backend still names.
static const uint32_t kGreens[] = {0x1ED760, 0x1DB954};
static const NSInteger kAppleMusicAccent = 0xFF375F;

static NSInteger sg_accent = -1;   // 0xRRGGBB once chosen, read at launch

// Preserve the redesign's old custom value while new installs start on Spotify's green.
static const NSInteger kDefaultAccent = 0x37F200;

static NSInteger currentChoice(void) {
    NSInteger choice = SGInt(SGRKeyAccentChoice, -1);
    if (choice >= SGRAccentChoiceSpotify && choice <= SGRAccentChoiceCustom) return choice;
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyAccent];
    return stored && [stored integerValue] >= 0 ? SGRAccentChoiceCustom : SGRAccentChoiceSpotify;
}

NSInteger SGRCurrentAccentChoice(void) {
    return currentChoice();
}

static NSInteger chosen(void) {
    switch (currentChoice()) {
        case SGRAccentChoiceAppleMusic: return kAppleMusicAccent;
        case SGRAccentChoiceCustom: {
            NSInteger rgb = SGInt(SGRKeyAccent, kDefaultAccent);
            return rgb >= 0 && rgb <= 0xFFFFFF ? rgb : kDefaultAccent;
        }
        default: return -1;
    }
}

static void unpack(uint32_t rgb, CGFloat *r, CGFloat *g, CGFloat *b) {
    *r = ((rgb >> 16) & 0xFF) / 255.0;
    *g = ((rgb >> 8) & 0xFF) / 255.0;
    *b = (rgb & 0xFF) / 255.0;
}

UIColor *SGRAccentColor(void) {
    NSInteger rgb = chosen();
    if (rgb < 0) return nil;
    CGFloat r, g, b;
    unpack((uint32_t)rgb, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

NSString *SGRAccentLabel(void) {
    switch (currentChoice()) {
        case SGRAccentChoiceAppleMusic: return @"#FF375F";
        case SGRAccentChoiceCustom: return [NSString stringWithFormat:@"#%06lX", (long)chosen()];
        default: return @"#1ED760";
    }
}

void SGRRefreshAccent(void) {
    sg_accent = chosen();
}

#pragma mark - picker

@interface SGRAccentPicker : NSObject <UIColorPickerViewControllerDelegate>
@property (nonatomic, weak) UIColorPickerViewController *activePicker;
@end

@implementation SGRAccentPicker

- (void)applyPicker:(UIColorPickerViewController *)picker {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [picker.selectedColor getRed:&r green:&g blue:&b alpha:&a];
    uint32_t rgb = ((uint32_t)lround(MIN(1, MAX(0, r)) * 255) << 16)
                 | ((uint32_t)lround(MIN(1, MAX(0, g)) * 255) << 8)
                 | (uint32_t)lround(MIN(1, MAX(0, b)) * 255);
    SGSetInt(SGRKeyAccent, rgb);
    SGSetInt(SGRKeyAccentChoice, SGRAccentChoiceCustom);
    SGRRefreshAccent();
}

- (void)confirm:(UIBarButtonItem *)item {
    [self applyPicker:self.activePicker];
    [self.activePicker.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    // The system's close button cancels. The explicit checkmark above is the only way to apply a colour.
}

@end

void SGRPickAccent(void) {
    static SGRAccentPicker *delegate;
    if (!delegate) delegate = [SGRAccentPicker new];
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.supportsAlpha = NO;
    picker.selectedColor = SGRAccentColor() ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
    picker.delegate = delegate;
    delegate.activePicker = picker;
    picker.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]
                                                                                    style:UIBarButtonItemStyleDone
                                                                                   target:delegate
                                                                                   action:@selector(confirm:)];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:picker];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [SGTopController() presentViewController:navigation animated:YES completion:nil];
}

// A darker green than the token comes out as the accent darkened by the same amount, so the two
// keep their relation.
static BOOL swap(CGFloat *r, CGFloat *g, CGFloat *b) {
    if (sg_accent < 0) return NO;
    for (size_t i = 0; i < sizeof(kGreens) / sizeof(kGreens[0]); i++) {
        CGFloat gr, gg, gb;
        unpack(kGreens[i], &gr, &gg, &gb);
        if (fabs(*r - gr) > 0.01 || fabs(*g - gg) > 0.01 || fabs(*b - gb) > 0.01) continue;
        CGFloat ar, ag, ab;
        unpack((uint32_t)sg_accent, &ar, &ag, &ab);
        CGFloat factor = MAX(gr, MAX(gg, gb)) / (0xD7 / 255.0);
        *r = MIN(1, ar * factor);
        *g = MIN(1, ag * factor);
        *b = MIN(1, ab * factor);
        return YES;
    }
    return NO;
}

%hook UIColor
- (UIColor *)initWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    swap(&r, &g, &b);
    return %orig(r, g, b, a);
}
+ (UIColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    swap(&r, &g, &b);
    return %orig(r, g, b, a);
}
%end

// Lottie draws its animations, the play indicator and the checkmarks among them, from colours
// in the animation file straight onto shape layers, or into colour keyframes, never through
// UIColor. The same swap goes on the CGColor. Layers get set off the main thread too, so the
// copy is made with CoreGraphics alone; NULL when the colour is not one of the greens.
static CGColorRef swappedCopy(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID() || CGColorGetNumberOfComponents(color) != 4) return NULL;
    const CGFloat *c = CGColorGetComponents(color);
    CGFloat r = c[0], g = c[1], b = c[2];
    if (!swap(&r, &g, &b)) return NULL;
    CGFloat out[] = {r, g, b, c[3]};
    return CGColorCreate(CGColorGetColorSpace(color), out);
}

static id swappedValue(id value) {
    CGColorRef swapped = swappedCopy((__bridge CGColorRef)value);
    if (!swapped) return value;
    id boxed = (__bridge_transfer id)swapped;
    return boxed;
}

%hook CAShapeLayer
- (void)setFillColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
- (void)setStrokeColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
%end

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
%end

%hook CABasicAnimation
- (void)setFromValue:(id)value {
    id used = swappedValue(value);
    %orig(used);
}
- (void)setToValue:(id)value {
    id used = swappedValue(value);
    %orig(used);
}
%end

%hook CAKeyframeAnimation
- (void)setValues:(NSArray *)values {
    NSMutableArray *mapped = nil;
    for (NSUInteger i = 0; i < values.count; i++) {
        id swapped = swappedValue(values[i]);
        if (swapped == values[i] && !mapped) continue;
        if (!mapped) mapped = [values mutableCopy];
        mapped[i] = swapped;
    }
    NSArray *used = mapped ?: values;
    %orig(used);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    SGRRefreshAccent();
    %init;
}
