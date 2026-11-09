// Resolved once at launch by the redesign's native theme bridge. Kept in Core so settings can
// use the same appearance without importing a higher layer. Native UI retains its existing look.
#import <UIKit/UIKit.h>

UIUserInterfaceStyle SGRedesignAppearanceStyle(void);
void SGConfigureRedesignAppearance(UIUserInterfaceStyle style);
BOOL SGRedesignLightAppearance(void);
UIColor *SGAppearanceColor(UIColor *light, UIColor *dark);
