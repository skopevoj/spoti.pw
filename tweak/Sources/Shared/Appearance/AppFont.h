#import <UIKit/UIKit.h>

#define SGKeyAppFont @"spotifyglass.appFont"
#define SGKeyAppFontName @"spotifyglass.appFont.name"
#define SGKeyAppFontPath @"spotifyglass.appFont.path"

typedef NS_ENUM(NSInteger, SGAppFontMode) {
    SGAppFontModeSpotify = 0,
    SGAppFontModeSFPro = 1,
    SGAppFontModeCustom = 2,
};

SGAppFontMode SGAppFontModeValue(void);
NSString *SGAppFontLabel(void);
UIFont *SGAppFontReplacement(UIFont *font);
void SGAppFontRegisterCustom(void);
void SGChooseAppFont(void);
UIViewController *SGAppFontSettingsPage(void);
