// AppFont.h says what this does. Every way UIKit and Spotify make a text font is hooked: the system font
// constructors, and fontWithName:size: and fontWithDescriptor:size:, which Spotify's Encore fonts go
// through. The new font is made with the hooks stood down (a thread's own flag), and kept, so the same
// size and weight is looked up once.
#import <pthread.h>
#import "Core/SGCore.h"
#import "AppFont.h"

static NSString *sg_family;
static NSCache<NSString *, UIFont *> *sg_fonts;
static pthread_key_t sg_busyKey;

static BOOL busy(void) { return pthread_getspecific(sg_busyKey) != NULL; }
static void setBusy(BOOL value) { pthread_setspecific(sg_busyKey, value ? (void *)1 : NULL); }

// Spotify's text faces, and the system's own names for San Francisco.
static BOOL textFace(NSString *name) {
    if (!name.length) return NO;
    static NSArray<NSString *> *prefixes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefixes = @[@"SpotifyMix", @"CircularSp", @"Circular-", @"CircularStd", @".SFUI", @".SF", @"SFUI", @"SFPro", @".AppleSystemUIFont"];
    });
    for (NSString *prefix in prefixes) if ([name hasPrefix:prefix]) return YES;
    return NO;
}

static UIFontWeight weightOf(UIFont *font) {
    NSDictionary *traits = [font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute];
    NSNumber *weight = [traits isKindOfClass:NSDictionary.class] ? traits[UIFontWeightTrait] : nil;
    if (weight) return weight.doubleValue;
    NSString *name = font.fontName.lowercaseString;
    if ([name containsString:@"black"] || [name containsString:@"heavy"]) return UIFontWeightHeavy;
    if ([name containsString:@"extrabold"]) return UIFontWeightHeavy;
    if ([name containsString:@"bold"]) return UIFontWeightBold;
    if ([name containsString:@"semibold"]) return UIFontWeightSemibold;
    if ([name containsString:@"medium"]) return UIFontWeightMedium;
    if ([name containsString:@"light"]) return UIFontWeightLight;
    return UIFontWeightRegular;
}

// The picked family's font for one of the app's: nil leaves the app's own.
static UIFont *replacement(CGFloat size, UIFontWeight weight, BOOL italic) {
    if (!sg_family || busy() || size <= 0) return nil;
    NSString *key = [NSString stringWithFormat:@"%.1f|%.2f|%d", size, weight, italic];
    UIFont *kept = [sg_fonts objectForKey:key];
    if (kept) return kept;
    setBusy(YES);
    UIFont *font = nil;
    if ([sg_family hasPrefix:@"design:"]) {
        UIFontDescriptorSystemDesign design = [sg_family isEqualToString:SGAppFontRounded] ? UIFontDescriptorSystemDesignRounded
            : [sg_family isEqualToString:SGAppFontSerif] ? UIFontDescriptorSystemDesignSerif
            : [sg_family isEqualToString:SGAppFontMono] ? UIFontDescriptorSystemDesignMonospaced : UIFontDescriptorSystemDesignDefault;
        UIFontDescriptor *descriptor = [[UIFont systemFontOfSize:size weight:weight].fontDescriptor fontDescriptorWithDesign:design];
        if (descriptor && italic) descriptor = [descriptor fontDescriptorWithSymbolicTraits:descriptor.symbolicTraits | UIFontDescriptorTraitItalic] ?: descriptor;
        if (descriptor) font = [UIFont fontWithDescriptor:descriptor size:size];
    } else {
        UIFontDescriptor *descriptor = [UIFontDescriptor fontDescriptorWithFontAttributes:@{
            UIFontDescriptorFamilyAttribute: sg_family,
            UIFontDescriptorTraitsAttribute: @{UIFontWeightTrait: @(weight)},
        }];
        if (italic) descriptor = [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic] ?: descriptor;
        font = [UIFont fontWithDescriptor:descriptor size:size];
        // A family that is not on this iPhone comes back as the system's; that is not what was picked.
        if (![font.familyName isEqualToString:sg_family]) font = nil;
    }
    setBusy(NO);
    if (font) [sg_fonts setObject:font forKey:key];
    return font;
}

static UIFont *swap(UIFont *original) {
    if (!original || !sg_family || busy() || !textFace(original.fontName)) return original;
    BOOL italic = (original.fontDescriptor.symbolicTraits & UIFontDescriptorTraitItalic) != 0;
    return replacement(original.pointSize, weightOf(original), italic) ?: original;
}

%hook UIFont

+ (UIFont *)systemFontOfSize:(CGFloat)size {
    UIFont *font = %orig;
    return busy() ? font : (replacement(size, UIFontWeightRegular, NO) ?: font);
}

+ (UIFont *)systemFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    UIFont *font = %orig;
    return busy() ? font : (replacement(size, weight, NO) ?: font);
}

+ (UIFont *)boldSystemFontOfSize:(CGFloat)size {
    UIFont *font = %orig;
    return busy() ? font : (replacement(size, UIFontWeightBold, NO) ?: font);
}

+ (UIFont *)italicSystemFontOfSize:(CGFloat)size {
    UIFont *font = %orig;
    return busy() ? font : (replacement(size, UIFontWeightRegular, YES) ?: font);
}

+ (UIFont *)preferredFontForTextStyle:(UIFontTextStyle)style {
    UIFont *font = %orig;
    return swap(font);
}

+ (UIFont *)preferredFontForTextStyle:(UIFontTextStyle)style compatibleWithTraitCollection:(UITraitCollection *)traits {
    UIFont *font = %orig;
    return swap(font);
}

+ (UIFont *)fontWithName:(NSString *)name size:(CGFloat)size {
    UIFont *font = %orig;
    return swap(font);
}

+ (UIFont *)fontWithDescriptor:(UIFontDescriptor *)descriptor size:(CGFloat)size {
    UIFont *font = %orig;
    return swap(font);
}

%end

%ctor {
    NSString *family = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFont];
    if (!family.length) return;
    pthread_key_create(&sg_busyKey, NULL);
    sg_fonts = [NSCache new];
    sg_fonts.countLimit = 400;
    sg_family = [family copy];
    %init;
    SGLog(@"app font: %@", family);
}
