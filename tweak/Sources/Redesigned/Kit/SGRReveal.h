// A redesigned page coming in whole. Spotify fills a playlist, an album or an artist in pieces -- the cover
// straight away from the card that was tapped, the controls when its buttons arrive, the tracks once their
// rows have data -- and the redesign drew each piece as it came, so the page arrived in three steps.
//
// So a curtain of the page's black goes up over everything on the page on its first pass -- the field, the
// picture, the header's text and row, Spotify's list, the pinned ⋯ -- and once the page has all of it the
// page fades in from behind it: the field brightens out of the black into the page's colour, and the picture,
// the header and the list fade in over it where they are. The system's
// navigation bar is not in the page, so the back button is there throughout. What arrives after that comes
// in the way it always did.
//
// A page says what it waits for as parts, and the hook that sees a part arrive marks it. A page that has not
// got every part within SGRRevealCap of the curtain going up is shown as it is. A curtain nothing claims with
// its parts within a moment is lifted then: the album's template also builds a podcast's episode page, and an
// artist without a photo has a header the redesign does not lay out, and neither ever gets its parts.
//
// Ownership: the curtain and what the page is waiting for belong to the page (an associated object).
// Threading: main thread only.
#import <UIKit/UIKit.h>

typedef NS_OPTIONS(NSUInteger, SGRRevealPart) {
    SGRRevealPicture = 1 << 0,   // the hero has its picture
    SGRRevealColor   = 1 << 1,   // the field has the page's colour (SGRArtworkField's -whenColored:)
    SGRRevealHeader  = 1 << 2,   // the header has its text and Play
    SGRRevealList    = 1 << 3,   // the list has a row with its text, not a loading row
    SGRRevealPage    = SGRRevealPicture | SGRRevealColor | SGRRevealHeader | SGRRevealList,
};

// How long a page waits for its parts before it is shown as it is.
extern const NSTimeInterval SGRRevealCap;   // 1.2

// Puts the curtain up over `page` on the first call, and makes it wait for `parts` as well as what it waits for
// already; 0 puts it up unclaimed. Every call keeps the curtain the page's front view, so it is cheap to call
// from each of the page's passes. Does nothing once the curtain has lifted.
void SGRRevealHold(UIView *page, SGRRevealPart parts);
// `part` has arrived on `page`, remembered even before the curtain goes up. The last part the curtain waits for
// lifts it.
void SGRRevealMark(UIView *page, SGRRevealPart part);
// NO once `page` has shown itself or `part` has arrived: a hook that looks for a part on every pass asks this
// first, and stops looking.
BOOL SGRRevealWaitsFor(UIView *page, SGRRevealPart part);
// `view` in front of everything on `page` but the curtain, for a view of the redesign's own that keeps itself
// on top of the page (the pinned ⋯).
void SGRRevealBringToFront(UIView *page, UIView *view);
// YES when a label under `root` has text in it. A loading row draws grey bars with empty labels in them.
BOOL SGRRevealShowsText(UIView *root);
