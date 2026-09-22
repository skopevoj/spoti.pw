// The pages of Mod Settings that bring the layers together: what each look offers is its own
// (Shared/, Native/, Redesigned/), and which of it a page shows is decided here, from the stored
// Redesigned UI switch, so a page opened after flipping it shows what the restart will bring.
#import <UIKit/UIKit.h>

@class SGModSection;

// Redesigned UI, the one switch between the two looks, and what its ⓘ reads out.
void SGSetRedesignedUI(BOOL on);
extern NSString *const SGRedesignedUIInfo;

UIViewController *SGAppearancePage(void); // Appearance and its font/icon sub-pages
UIViewController *SGPlayerSettingsPage(void);
UIViewController *SGNavbarPage(void);       // the tab editor of whichever look is stored
