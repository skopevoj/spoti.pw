// The redesign's navbar: the glass tab bar (TabBar.x) over Spotify's own, composed from its own list
// (Navbar.x, NavbarLayout.m), which the redesign keeps apart from the native look's: an ordered list of
// entries, each a dictionary. An entry with a URI is a tab of the mod's own; one without names
// one of Spotify's, by the label under its icon. No list at all is Spotify's order, all shown.
#import <UIKit/UIKit.h>

#define SGRKeyNavbar @"spotifyglass.redesign.navbar"
// Icons only on the glass bar. Off unless set; applies as soon as the bar lays out again.
#define SGRKeyNavbarHideLabels @"spotifyglass.redesign.navbar.hideLabels"
// The glass bar always dark, whatever the phone's appearance. Off unless set; applies as soon as the bar lays out again.
#define SGRKeyNavbarAlwaysDark @"spotifyglass.redesign.navbar.alwaysDark"

extern NSString *const SGRNavbarID;      // NSString, the entry's identity
extern NSString *const SGRNavbarTitle;   // NSString, the name in the settings list and under the icon
extern NSString *const SGRNavbarURI;     // NSString, the mod's own tabs only: what a tap opens
extern NSString *const SGRNavbarIcon;    // NSString, an SPTEncoreIcon class method such as "podcasts"
extern NSString *const SGRNavbarHidden;  // NSNumber
NSArray<NSDictionary *> *SGRNavbarLayout(void);
void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout);
// Spotify's own tabs in Spotify's order, as Navbar.x last saw them on the bar.
NSArray<NSString *> *SGRNavbarStock(void);
void SGRSetNavbarStock(NSArray<NSString *> *stock);

// Navbar.x, called from the tab bar's layout passes in TabBar.x.
void SGRComposeTabBar(UIView *tabBar);
void SGRLogTabBarRow(UIView *tabBar);
// Lays the bar out again after the Navbar page changes something, so it does not wait for a touch.
void SGRRefreshTabBar(void);

UIViewController *SGRNavbarSettingsPage(void);   // the tab editor, in Mod Settings
UIViewController *SGRNavbarEditorPage(void);     // the tab editor alone, for the welcome tour
