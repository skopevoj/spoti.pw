// One font for the whole app (Mod Settings > Appearance > Font), under either look: the system's text and
// Spotify's own (its SpotifyMix and Circular faces) are drawn in the family picked instead, each at its
// size, as close to its weight as the family has, italic where it was. Spotify's icons are not text and
// stay as they are. Read at launch, so a change shows after a restart.
//
//     AppFont.x          the UIFont hooks
//     AppFontSettings.m  the Appearance card's row and its list of families
#import <UIKit/UIKit.h>

// The family's name as UIFont.familyNames has it, or one of the system's designs below; unset is Spotify's own.
#define SGKeyAppFont @"spotifyglass.appFont"
#define SGKeyAppFontIndex @"spotifyglass.appFont.index"   // the list's checkmark, kept in step with the name

#define SGAppFontSystem @"design:default"
#define SGAppFontRounded @"design:rounded"
#define SGAppFontSerif @"design:serif"
#define SGAppFontMono @"design:monospaced"

@class SGModRow;
SGModRow *SGAppFontRow(void);
