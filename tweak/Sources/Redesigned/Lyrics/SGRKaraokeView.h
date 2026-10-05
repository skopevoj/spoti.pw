// The redesign's Apple Music style lyrics view, always on, over Spotify's full screen lyrics page
// (KaraokePage.x) and in the redesigned player itself (Redesigned/Player/PlayerLyrics.x). A track
// without synced lyrics keeps Spotify's own lines, where there are any next to it. The lines and the
// clock are Shared/Lyrics/Lyrics.h's.
//
// It takes the whole of whatever it is put in and dims every other view in there while it has lines
// to show, so a host it shares with anything else needs a view of its own for it.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

@interface SGRKaraokeView : UIView
// Hides Spotify's own lyrics next to this view while it has lyrics to show, and brings them back when not.
- (void)syncSiblings;
// The part of the view the lines are shown in, as insets from its edges (only top and bottom are
// read): the sung line rests in it, the lines fade out at its ends, the credit sits at its foot, and a
// touch outside it goes through the view. Zero, the whole view, unless set. The player lays the view
// over all of itself and moves these as its controls come and go (Redesigned/Player/PlayerLyrics.x).
@property (nonatomic, readonly) UIEdgeInsets lineInsets;
// duration 0 moves everything at once.
- (void)setLineInsets:(UIEdgeInsets)insets duration:(NSTimeInterval)duration;
// Asked as a tap lands on the lines, before it seeks or opens what a line means; NO leaves the tap to
// whoever else watches the touch. Nil takes every tap.
@property (nonatomic, copy) BOOL (^takesTap)(void);
@end
