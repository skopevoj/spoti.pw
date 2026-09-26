// The native look's appearance: the AMOLED background (Amoled.x), the accent colour in place of
// Spotify's green (Accent.x), the soft top edge (EdgeEffect.x) and Repaint.x, which keeps what the
// native tweaks stripped transparent when Spotify repaints it. The switches are off until asked for.
#import <UIKit/UIKit.h>

#define SGKeyAmoled @"spotifyglass.amoled"
#define SGKeyAccent @"spotifyglass.accent"   // 0xRRGGBB; unset or negative keeps Spotify's own green
#define SGKeyAccentChoice @"spotifyglass.accent.choice" // 0 = Spotify, 1 = Apple Music, 2 = Custom

typedef NS_ENUM(NSInteger, SGAccentChoice) {
    SGAccentChoiceSpotify = 0,
    SGAccentChoiceAppleMusic = 1,
    SGAccentChoiceCustom = 2,
};

UIColor *SGAccentColor(void);   // nil while Spotify's own green is kept
NSString *SGAccentLabel(void);  // the active accent as "#RRGGBB"
NSInteger SGCurrentAccentChoice(void); // the selected palette, migrating the old accent key
void SGRefreshAccent(void);      // apply a changed preset to colours created from now on
void SGPickAccent(void);        // the system colour picker; the checkmark stores it, close cancels

@class SGModRow;
NSArray<SGModRow *> *SGNativeAppearanceRows(void);   // AMOLED, palette and colour, for the Appearance page
