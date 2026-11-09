#import <UIKit/UIKit.h>

static NSString *const SGRKeyAppearance = @"spotifyglass.redesign.appearance";
typedef NS_ENUM(NSInteger, SGRAppearanceMode) {
    SGRAppearanceDark = 0,
    SGRAppearanceLight = 1,
    SGRAppearanceSystem = 2,
};
BOOL SGRAppearanceBridgeAvailable(void);
BOOL SGRAppearanceNeedsRestart(void); // compatibility: indicates an unapplied selection
NSString *SGRAppearanceStatus(void);
// Main-thread transaction used by the picker and system observer. Stores verify before any
// rendered appearance changes. The request form coalesces rapid preference/scene changes.
BOOL SGRAppearanceApplyMode(NSInteger mode, BOOL animated);
void SGRAppearanceApplyPreference(void);
