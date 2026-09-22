// The runtime list of Spotify's Encore glyphs, used by both navbar looks.
#import <UIKit/UIKit.h>

#define SGKeyNavbarIconLibrary @"spotifyglass.navbar.iconLibrary"

typedef NS_ENUM(NSInteger, SGNavbarIconLibrary) {
    SGNavbarIconLibraryEncore = 0,
    SGNavbarIconLibrarySFSymbols = 1,
};

NSInteger SGNavbarIconLibraryValue(void);
NSString *SGNavbarIconLibraryLabel(void);
UIViewController *SGNavbarIconPickerPage(void);
UIViewController *SGNavbarIconSettingsPage(void);
