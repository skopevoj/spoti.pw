// The artwork field: one continuous colour taken from the artwork's main colour (SGRPalette.h) behind
// a whole redesigned page, with no card and no seam anywhere. The player's field is the artwork itself
// instead, blurred and warped (motion).
//
// Still, nothing is blurred live and nothing is masked: the view draws a solid colour layer and a black
// gradient layer (the redesign is AMOLED throughout, fading the colour to black down the page), so it
// costs a few composited layers while the page moves. A new colour crossfades over SGRCrossfade; the
// same image again is a no-op.
//
// Ownership: the screen that installs a field owns it (usually retained by its superview and an
// associated object). The field retains its last image and palette only.
// Threading: main thread only; the palette work it starts runs off it.
#import <UIKit/UIKit.h>
#import "SGRWarp.h"

// Posted on the main thread by a field whose colour changed, with the field as the object and the
// new colour under "color".
extern NSNotificationName const SGRFieldColorDidChangeNotification;

typedef NS_ENUM(NSInteger, SGRFieldMotion) {
    SGRFieldMotionNone,   // the colour alone
    SGRFieldMotionWarp,   // the artwork itself blurred and warped (SGRWarp.h)
};

@interface SGRArtworkField : UIView
// Where the colour, the fade to black and the moving field reach past the bounds (overscroll, a plane
// that does not clip): positive values draw outside. The field never clips.
@property (nonatomic) UIEdgeInsets bleed;
// The player's moving field, over the whole of the bounds with no fade to black. It moves only while the
// field is in a window, the app is in front, the player is not opening or closing, Reduce Motion and Low
// Power Mode are off and nothing holds it (motionHeld); otherwise it stays still where it was. Without
// Metal it is the colour alone.
@property (nonatomic) SGRFieldMotion motion;
@property (nonatomic) SGRWarpLook warpLook;
// Held still by the owner (the player while playback is paused).
@property (nonatomic) BOOL motionHeld;
// Something of the owner's lies opaque over the whole field (the player's Animated artwork): the moving
// field stops where it is and draws only what changes, in a single frame.
@property (nonatomic) BOOL covered;
// SGRNeutralField until a colour arrives.
@property (nonatomic, readonly) UIColor *fieldColor;

// A colour Spotify already has for the page (the player's background colour), made fit to be a field
// and shown until the first artwork has been read; ignored after that.
- (void)setProvisionalColor:(UIColor *)color;
// A colour the page already picked for itself, made fit to be a field; it wins over the one read from the
// artwork. nil keeps what is set.
- (void)setPreferredColor:(UIColor *)color;
// Reads the artwork off the main thread and crossfades the result in (without animation when
// `animated` is NO or the field is not in a window). The same image, or the same non-nil identity,
// as the last call is a no-op, and a result that lands after a newer call is dropped. nil keeps
// what the field shows.
- (void)setArtwork:(UIImage *)image identity:(NSString *)identity animated:(BOOL)animated;
// `colored` once, as soon as the field shows a colour of the page's own -- read from the artwork, or the
// page's preferred one -- rather than the neutral it starts with; at once if it already does. For a page
// that waits to be shown until it has its colour (SGRReveal.h).
- (void)whenColored:(void (^)(void))colored;
@end
