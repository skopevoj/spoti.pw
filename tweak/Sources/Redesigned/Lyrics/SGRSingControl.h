#import <UIKit/UIKit.h>
// Owned by the lyrics overlay in Now Playing (Redesigned/Player/PlayerLyrics.x). `lyrics` is the lines'
// band in the page's coordinates, and the microphone sits in its bottom trailing corner. `immersive` is
// the controls away: the microphone stays only while Sing is on. `hold` is called with YES while it is
// open, preparing or explaining itself, and with NO once it is none of them. While Sing is unavailable
// (switched off, or without its voice model) there is no microphone: a control already there is taken
// away, its hold let go, and this answers nil.
UIView *SGRSingControlForPage(UIView *page, CGRect lyrics, BOOL immersive, void (^hold)(BOOL));
void SGRSingControlDismiss(UIView *page);
