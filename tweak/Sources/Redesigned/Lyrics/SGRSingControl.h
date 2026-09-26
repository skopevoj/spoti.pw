#import <UIKit/UIKit.h>
#define SGRKeySing @"spotifyglass.redesign.sing"
// Owned by the lyrics overlay in Now Playing; stays independent of the idle setting.
UIView *SGRSingControlForPage(UIView *page, UIView *lyricsHost, BOOL immersive, void (^hold)(BOOL));
void SGRSingControlDismiss(UIView *page);
