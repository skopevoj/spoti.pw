#import "AppFont.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import <CoreText/CoreText.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

SGAppFontMode SGAppFontModeValue(void) {
    NSInteger mode = SGInt(SGKeyAppFont, SGAppFontModeSpotify);
    return mode >= SGAppFontModeSpotify && mode <= SGAppFontModeCustom ? (SGAppFontMode)mode : SGAppFontModeSpotify;
}

NSString *SGAppFontLabel(void) {
    switch (SGAppFontModeValue()) {
        case SGAppFontModeSFPro: return @"SF Pro";
        case SGAppFontModeCustom: {
            NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontName];
            return name.length ? [NSString stringWithFormat:@"Custom: %@", name] : @"Custom font";
        }
        default: return @"Spotify font";
    }
}

static CGFloat fontWeight(UIFont *font) {
    NSDictionary *traits = [font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute];
    NSNumber *weight = traits[UIFontWeightTrait];
    return weight ? MAX(-1, MIN(1, weight.doubleValue)) : UIFontWeightRegular;
}

UIFont *SGAppFontReplacement(UIFont *font) {
    if (!font || SGAppFontModeValue() == SGAppFontModeSpotify) return font;
    if (SGAppFontModeValue() == SGAppFontModeSFPro) return [UIFont systemFontOfSize:font.pointSize weight:fontWeight(font)];
    NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontName];
    UIFont *custom = name.length ? [UIFont fontWithName:name size:font.pointSize] : nil;
    return custom ?: font;
}

static NSString *fontNameAtURL(NSURL *url) {
    if (!url) return nil;
    CFArrayRef descriptors = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
    if (!descriptors || CFArrayGetCount(descriptors) == 0) {
        if (descriptors) CFRelease(descriptors);
        return nil;
    }
    CTFontDescriptorRef descriptor = (CTFontDescriptorRef)CFArrayGetValueAtIndex(descriptors, 0);
    CFStringRef name = (CFStringRef)CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute);
    NSString *result = name ? [(__bridge NSString *)name copy] : nil;
    if (name) CFRelease(name);
    CFRelease(descriptors);
    return result;
}

static BOOL registerFontAtPath(NSString *path) {
    NSURL *url = path.length ? [NSURL fileURLWithPath:path] : nil;
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;
    CFErrorRef error = NULL;
    BOOL registered = CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error);
    if (error) CFRelease(error);
    return registered || fontNameAtURL(url) != nil;
}

void SGAppFontRegisterCustom(void) {
    if (SGAppFontModeValue() != SGAppFontModeCustom) return;
    NSString *path = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontPath];
    if (!registerFontAtPath(path)) return;
    NSString *name = fontNameAtURL([NSURL fileURLWithPath:path]);
    if (name.length) [NSUserDefaults.standardUserDefaults setObject:name forKey:SGKeyAppFontName];
}

@interface SGAppFontPicker : NSObject <UIDocumentPickerDelegate>
@end

@implementation SGAppFontPicker

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *source = urls.firstObject;
    if (!source) return;
    BOOL scoped = [source startAccessingSecurityScopedResource];
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"spoti.pw"];
    NSString *path = [directory stringByAppendingPathComponent:@"AppFont.font"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSData dataWithContentsOfURL:source];
    BOOL copied = data.length && [data writeToFile:path atomically:YES];
    if (scoped) [source stopAccessingSecurityScopedResource];
    if (!copied || !registerFontAtPath(path)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Font could not be loaded" message:@"Choose a valid .ttf or .otf font file." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSString *name = fontNameAtURL([NSURL fileURLWithPath:path]);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:SGAppFontModeCustom forKey:SGKeyAppFont];
    [defaults setObject:path forKey:SGKeyAppFontPath];
    if (name.length) [defaults setObject:name forKey:SGKeyAppFontName];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom font loaded" message:[NSString stringWithFormat:@"%@ will be used after Spotify restarts.", name.length ? name : @"The selected font"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

@end

void SGChooseAppFont(void) {
    static SGAppFontPicker *delegate;
    if (!delegate) delegate = [SGAppFontPicker new];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFont] asCopy:YES];
    picker.delegate = delegate;
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

UIViewController *SGAppFontSettingsPage(void) {
    SGModRow *font = SGChoiceRow(@"App-Font", nil, SGKeyAppFont,
                                 @[@"Spotify font", @"SF Pro", @"Custom font"], SGAppFontModeSpotify);
    font.choiceFooter = @"Spotify font keeps the original typeface. SF Pro uses Apple's system font. Custom font accepts .ttf and .otf files.";
    SGModRow *custom = SGActionRow(@"Import custom font", @"Choose a .ttf or .otf file", ^{ SGChooseAppFont(); });
    custom.visible = ^BOOL { return SGAppFontModeValue() == SGAppFontModeCustom; };
    return [[SGModPage alloc] initWithTitle:@"App-Font" intro:SGRestartNote
                                   sections:@[SGSection(nil, @[font, custom])]
                                      footer:@"The font hook covers UIKit text used by Spotify and the mod. Some text rendered by SwiftUI or custom drawing may keep its original font."];
}
