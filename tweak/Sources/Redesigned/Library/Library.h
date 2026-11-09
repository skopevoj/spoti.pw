// The Library redesign: Spotify's Your Library kept, with its controllers, its list and its rows, decluttered
// to a library on black and restyled from the Kit. No settings of its own.
//
//     LibraryHeader.x   the header the way Home and Search have theirs: a large title at the leading edge, the
//                       avatar at the trailing edge, with Spotify’s filter chips kept below it. A folder opened from the library is the same header, its back button and
//                       its own controls kept
//     LibraryRows.x     every row and grid card: the artwork at the Kit's radius with continuous corners, a
//                       circular one left round, and a hairline between the rows
//     LibrarySearch.x   the search inside the library: its field a glass capsule, the way the Search tab's is
//                       (Redesigned/Navbar/SearchField.x)
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI).
// Threading: main thread only.
#import <UIKit/UIKit.h>

// The list of every library page (trees/clean/library/03.txt:25).
extern NSString *const SGRLibraryListIdentifier;

// LibraryHeader.x. The scrim Spotify lays behind a library header taken out, so the soft scroll edge
// (Kit/SGREdgeEffect.x) is what keeps the header clear of the list under it. A header without one is left
// alone; the folder's has none.
void SGRLibraryClearScrim(UIView *header);
