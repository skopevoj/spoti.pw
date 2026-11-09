#import <UIKit/UIKit.h>

static NSString *const SGRKeyAppearance = @"spotifyglass.redesign.appearance";
typedef NS_ENUM(NSInteger, SGRAppearanceMode) {
    SGRAppearanceDark = 0,
    SGRAppearanceLight = 1,
    SGRAppearanceSystem = 2,
};
BOOL SGRAppearanceBridgeAvailable(void);

BOOL SGRAppearanceNeedsRestart(void);
NSString *SGRAppearanceStatus(void);
