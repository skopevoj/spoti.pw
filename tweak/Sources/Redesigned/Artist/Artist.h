// The artist redesign: Spotify's artist page kept, with its list and its controls, decluttered and given the
// header the playlist and album pages have, so the three read as one app.
//
// The page is TemplateKit's TemplateView, id=creator-page (trees/clean/artist/01.txt:26, recorded
// 2026-09-16), not the album's CreativeWorkTemplateView: its header is an ImageHeaderView, the photo, the
// name, the listeners and a row of explore, follow, more, shuffle and play, which Spotify shrinks to a 100pt
// bar pinned at the top as the page scrolls; under it a strip of Music / Video / Merch tabs, each a list.
//
//     ArtistField.x     the photo's field behind the whole page, the page kept clear on it, the tab strip
//                       gone (the Music list is the page), the flags the screen forces
//     ArtistHeader.x    the header: the photo full bleed dissolving into the field, and the Kit's
//                       SGRHeaderInfo over it -- the name, the listeners, shuffle, a white Play and Follow
//     ArtistSections.x  the sections the Music list carries that are not the artist's music: its videos
//     ArtistFollow.x    whether the artist is followed, from Spotify's collection, for Follow's glyph
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI); the native look's do not then.
// Threading: main thread only.
#import <UIKit/UIKit.h>

// The artist page `view` is on, or nil: the TemplateView with the identifier creator-page.
UIView *SGRArtistPageOf(UIView *view);

// ArtistField.x. The field belongs to the page `view` is on.
//
// The colour the page's field is showing, SGRNeutralField() before one has been read.
UIColor *SGRArtistFieldColor(UIView *view);
// The artist's photo, for the page's field to take its colour from. The same image again is a no-op.
void SGRArtistSetArtwork(UIView *view, UIImage *image);

// ArtistFollow.x. YES once Spotify's collection has said whether the user follows the page's artist, with
// the answer; NO until then. The first call subscribes for the page's lifetime, and `changed` runs on the
// main thread whenever the answer changes.
BOOL SGRArtistFollowing(UIView *page, NSString *moreIdentifier, BOOL *following, void (^changed)(void));
