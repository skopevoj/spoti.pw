// The album redesign: Spotify's album page kept, with its header, its track list and its controls, and laid
// out the way the Music app lays an album out -- the same page the playlist redesign gives a playlist, so
// the two read as one app.
//
// The album page is not the playlist's. It is built by the Creative Work Platform out of the element
// framework (trees/clean/album/01.txt: CreativeWorkPlatform.CreativeWorkTemplateView, a header element over
// one list), its header is a column of stack views rather than a plain block, and its play and shuffle
// float over the page instead of scrolling with the header. So none of Redesigned/Playlist/ is shared: only
// the Kit is, which is what keeps the look the same.
//
//     AlbumField.x     the artwork field behind the whole page, the artwork it is read from, the flags the
//                      screen forces
//     AlbumHeader.x    the header: the cover full bleed at the top dissolving into the field, and the Kit's
//                      SGRHeaderInfo over it -- title, artist, kind and date, shuffle, a white Play, add
//     AlbumRows.x      the track rows on the field with no surface of their own and a hairline between them
//     AlbumSections.x  Spotify's discovery sections and spacing kept; album length and copyright subdued
//     AlbumSettings.m  the Albums page of Mod Settings
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI); the native look's do not then.
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Apple Music's animated cover at the top of an album (AlbumHeader.x); on until switched off.
#define SGRKeyAnimatedCovers @"spotifyglass.redesign.animatedcovers"

UIViewController *SGRAlbumSettingsPage(void);

// The album page `view` is on, or nil: the CreativeWorkTemplateView that carries the header, the list and
// the two floating controls (trees/clean/album/01.txt:22).
UIView *SGRAlbumPageOf(UIView *view);

// AlbumRows.x. Header credits belong to this page, including while its header is off screen.
// A late/changed credit refreshes only the rows this page has already displayed.
void SGRAlbumSetArtist(UIView *page, NSString *artist);

// AlbumField.x. The field belongs to the page `view` is on, found by walking up from it, so two album pages
// on the navigation stack keep a field each.
//
// The colour the page's field is showing, SGRNeutralField() before one has been read: what the header's
// cover has to dissolve into for there to be no seam.
UIColor *SGRAlbumFieldColor(UIView *view);
// The cover of the page `view` is on, for its field to take its colour from. The same image again is a no-op.
void SGRAlbumSetArtwork(UIView *view, UIImage *image);
