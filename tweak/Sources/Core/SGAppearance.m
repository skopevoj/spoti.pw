#import "SGAppearance.h"

// Dark is the safe fallback until the bridge has verified Spotify's semantic theme provider.
static UIUserInterfaceStyle appearance = UIUserInterfaceStyleDark;
UIUserInterfaceStyle SGRedesignAppearanceStyle(void) { return appearance; }
void SGConfigureRedesignAppearance(UIUserInterfaceStyle style) {
    appearance = style == UIUserInterfaceStyleLight ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
}
BOOL SGRedesignLightAppearance(void) { return appearance == UIUserInterfaceStyleLight; }
UIColor *SGAppearanceColor(UIColor *light, UIColor *dark) { return SGRedesignLightAppearance() ? light : dark; }
