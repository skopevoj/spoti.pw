#import "AppFont.h"

%hook UILabel
- (void)setFont:(UIFont *)font {
    %orig(SGAppFontReplacement(font));
}
%end

%hook UITextField
- (void)setFont:(UIFont *)font {
    %orig(SGAppFontReplacement(font));
}
%end

%hook UITextView
- (void)setFont:(UIFont *)font {
    %orig(SGAppFontReplacement(font));
}
%end

%ctor {
    SGAppFontRegisterCustom();
    %init;
}
