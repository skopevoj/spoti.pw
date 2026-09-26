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
// The player holds its chrome visible while lyric browsing or its menu is active.
@property (nonatomic, copy) void (^interactionChanged)(NSUInteger reason, BOOL held); // 1 browsing, 2 menu
@property (nonatomic) BOOL chromeHidden;
// Hides Spotify's own lyrics next to this view while it has lyrics to show, and brings them back when not.
- (void)syncSiblings;
@end
