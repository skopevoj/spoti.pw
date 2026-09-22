#import "AppFont.h"

static BOOL sgApplyingAppFont = NO;

static NSAttributedString *SGAppFontMappedAttributedString(NSAttributedString *text) {
    if (!text.length || SGAppFontModeValue() == SGAppFontModeSpotify) return text;
    NSMutableAttributedString *mapped = nil;
    [text enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(UIFont *font, NSRange range, BOOL *stop) {
        if (!font) return;
        UIFont *replacement = SGAppFontReplacement(font);
        if (replacement == font) return;
        if (!mapped) mapped = [text mutableCopy];
        [mapped addAttribute:NSFontAttributeName value:replacement range:range];
    }];
    return mapped ?: text;
}

static void SGAppFontRefreshLabel(UILabel *label) {
    if (sgApplyingAppFont || SGAppFontModeValue() == SGAppFontModeSpotify) return;
    sgApplyingAppFont = YES;
    UIFont *font = SGAppFontReplacement(label.font);
    if (font && font != label.font) [label setFont:font];
    NSAttributedString *text = label.attributedText;
    NSAttributedString *mapped = SGAppFontMappedAttributedString(text);
    if (mapped != text) [label setAttributedText:mapped];
    sgApplyingAppFont = NO;
}

static UIFont *SGAppFontSystemFont(CGFloat size, CGFloat weight) {
    if (SGAppFontModeValue() != SGAppFontModeCustom) return nil;
    NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontName];
    return name.length ? [UIFont fontWithName:name size:size] : nil;
}

// Some of Spotify's settings and Swift UI bridges ask UIFont for a system font directly, so a label
// setter alone misses them. These factories are changed only for a loaded custom font; the native and
// SF Pro choices keep UIKit's own factories intact.
%hook UIFont
+ (UIFont *)systemFontOfSize:(CGFloat)size {
    return SGAppFontSystemFont(size, UIFontWeightRegular) ?: %orig;
}

+ (UIFont *)systemFontOfSize:(CGFloat)size weight:(CGFloat)weight {
    return SGAppFontSystemFont(size, weight) ?: %orig;
}

+ (UIFont *)boldSystemFontOfSize:(CGFloat)size {
    return SGAppFontSystemFont(size, UIFontWeightBold) ?: %orig;
}

+ (UIFont *)preferredFontForTextStyle:(UIFontTextStyle)style {
    UIFont *original = %orig(style);
    return SGAppFontSystemFont(original.pointSize, UIFontWeightRegular) ?: original;
}
%end

%hook UILabel
- (void)setFont:(UIFont *)font {
    %orig(SGAppFontReplacement(font));
}

- (void)setText:(NSString *)text {
    %orig(text);
    SGAppFontRefreshLabel(self);
}

- (void)setAttributedText:(NSAttributedString *)text {
    %orig(SGAppFontMappedAttributedString(text));
}

- (void)didMoveToWindow {
    %orig;
    SGAppFontRefreshLabel(self);
}
%end

// Encore labels are UILabel subclasses but some Spotify versions override the inherited setters.
// Hooking the concrete class closes that gap for song titles, artist names and row labels.
%hook SPTEncoreLabel
- (void)setFont:(UIFont *)font {
    %orig(SGAppFontReplacement(font));
}

- (void)setText:(NSString *)text {
    %orig(text);
    SGAppFontRefreshLabel(self);
}

- (void)setAttributedText:(NSAttributedString *)text {
    %orig(SGAppFontMappedAttributedString(text));
}

- (void)didMoveToWindow {
    %orig;
    SGAppFontRefreshLabel(self);
}
%end

%hook UITextField
- (void)setFont:(UIFont *)font {
    %orig(SGAppFontReplacement(font));
}

- (void)setAttributedText:(NSAttributedString *)text {
    %orig(SGAppFontMappedAttributedString(text));
}

- (void)didMoveToWindow {
    %orig;
    if (!sgApplyingAppFont && SGAppFontModeValue() != SGAppFontModeSpotify) {
        sgApplyingAppFont = YES;
        self.font = SGAppFontReplacement(self.font);
        self.attributedText = SGAppFontMappedAttributedString(self.attributedText);
        sgApplyingAppFont = NO;
    }
}
%end

%hook UITextView
- (void)setFont:(UIFont *)font {
    %orig(SGAppFontReplacement(font));
}

- (void)setAttributedText:(NSAttributedString *)text {
    %orig(SGAppFontMappedAttributedString(text));
}

- (void)didMoveToWindow {
    %orig;
    if (!sgApplyingAppFont && SGAppFontModeValue() != SGAppFontModeSpotify) {
        sgApplyingAppFont = YES;
        self.font = SGAppFontReplacement(self.font);
        self.attributedText = SGAppFontMappedAttributedString(self.attributedText);
        sgApplyingAppFont = NO;
    }
}
%end

%ctor {
    SGAppFontRegisterCustom();
    %init;
}
