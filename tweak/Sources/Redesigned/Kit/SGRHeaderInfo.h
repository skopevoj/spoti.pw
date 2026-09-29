// The text and the controls of a redesigned page's header, under its full bleed picture, the way the Music
// app (iOS 26.4) sets a playlist or an album: the title, the creator and the length centred, one row of
// shuffle, a white Play capsule and one more round button, and the description under the row.
//
// A page conceals what Spotify draws in its header and puts this in its place, so nothing of Spotify's lays
// it out. It keeps no state of its own: the page hands it the text it read (from Spotify's model or from
// Spotify's concealed labels) and Spotify's own controls to draw from and fire, on every pass, and it lays
// itself out again only when something it shows changed.
//
// Its content sits on its bottom edge with SGRHeaderInfoBottom under it, whatever height the page gives it,
// so the buttons stay just above the first track; what does not fit rises over the picture. The page's
// picture reaches SGRHeaderInfoTitleRise below the content's top, so the title and the creator sit on the
// bottom of its dissolve.
//
// Ownership: the page that adds it; it keeps only weak references to Spotify's controls.
// Threading: main thread only.
#import <UIKit/UIKit.h>

extern const CGFloat SGRHeaderInfoBottom;     // 14, under the content
extern const CGFloat SGRHeaderInfoTitleRise;  // 56, of the content over the picture

@interface SGRHeaderInfo : UIView
// YES when anything shown changed. nil or empty hides that line.
- (BOOL)showTitle:(NSString *)title creator:(NSString *)creator length:(NSString *)length about:(NSString *)about;
// Spotify's own control behind the creator line -- the album's artist row, the playlist's collaborators
// button -- so a tap on the line opens whoever made it, and several of them open Spotify's own picker.
// The line keeps its colour: it is the page's one piece of secondary text, not a link to be tinted. nil
// leaves it as text.
- (void)showCreatorLink:(UIView *)control;
// For a trailing control that shows its state only as a word (the artist's Follow): SGRMirrorButton's
// readState and its two symbols. Set before the first -showShuffle:...; -trailingStateChanged redraws it.
@property (nonatomic, copy) BOOL (^trailingState)(BOOL *on);
@property (nonatomic, copy) NSString *trailingOffSymbol;
@property (nonatomic, copy) NSString *trailingOnSymbol;
- (void)trailingStateChanged;
// Spotify's controls, each drawn from and fired; nil hides that button. Play stays in the middle of the
// page whether the other two are there or not. `trailingFallback` is drawn when Spotify's trailing control
// has no image to copy. `playColor` is the colour of the capsule's glyph and word.
- (void)showShuffle:(UIView *)shuffle play:(UIView *)play trailing:(UIView *)trailing
   trailingFallback:(UIImage *)trailingFallback playColor:(UIColor *)playColor;
// The height the content wants at `width`, from the top of the title to the bottom of the description.
- (CGFloat)contentHeightForWidth:(CGFloat)width;
@end
