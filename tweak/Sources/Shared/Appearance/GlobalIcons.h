#import <UIKit/UIKit.h>

#define SGKeyAppIconStyle @"spotifyglass.appIconStyle"

typedef NS_ENUM(NSInteger, SGAppIconStyle) {
    SGAppIconStyleEncore = 0,
    SGAppIconStyleSFSymbols = 1,
};

SGAppIconStyle SGAppIconStyleValue(void);
NSString *SGAppIconStyleLabel(void);
// Maps an Encore name to an SF Symbol. Unknown names deliberately use a visible fallback so a
// global SF Symbols setting never silently leaves an Encore glyph in the app.
NSString *SGAppIconSymbolForEncoreName(NSString *name);
