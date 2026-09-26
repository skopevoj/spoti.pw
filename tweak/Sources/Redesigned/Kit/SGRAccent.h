// The redesign's accent colour in place of Spotify's green (SGRAccent.x), chosen apart from the native
// look's and stored under its own key; unset is #37F200, negative keeps Spotify's own green.
#import <UIKit/UIKit.h>

#define SGRKeyAccent @"spotifyglass.redesign.accent"   // 0xRRGGBB
#define SGRKeyAccentChoice @"spotifyglass.redesign.accent.choice" // 0 = Spotify, 1 = Apple Music, 2 = Custom

typedef NS_ENUM(NSInteger, SGRAccentChoice) {
    SGRAccentChoiceSpotify = 0,
    SGRAccentChoiceAppleMusic = 1,
    SGRAccentChoiceCustom = 2,
};

UIColor *SGRAccentColor(void);   // nil while Spotify's own green is kept
NSString *SGRAccentLabel(void);  // the active accent as "#RRGGBB"
NSInteger SGRCurrentAccentChoice(void); // the selected palette, migrating the old accent key
void SGRRefreshAccent(void);      // apply a changed preset to colours created from now on
void SGRPickAccent(void);        // the system colour picker; the checkmark stores it, close cancels

@class SGModRow;
NSArray<SGModRow *> *SGRAppearanceRows(void);   // the accent palette and colour, for the Appearance page
