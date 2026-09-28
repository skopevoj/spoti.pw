// What a redesigned page takes from its artwork, worked out off the main thread in one pass: the
// colour along the artwork's bottom edge, the field colour made from its main colour, and a blurred
// bitmap to draw instead of a live blur.
//
// The field colour keeps its hue, with its OKLab lightness held to 0.34 (0.30 with Increase Contrast)
// and its chroma lifted by 1.3 up to 0.14. On anything that dark white text is past 11:1 and SGRSecondary
// (white 65%) past 4.5:1, WCAG AA, whatever the hue.
//
// Threading: +paletteForImage: may be called from the main thread only and calls back on it. The work
// runs on one serial background queue; UIImage and CoreImage are read there, UIKit views are not.
#import <UIKit/UIKit.h>

typedef struct {
    // A blurred copy at the artwork's own aspect, transparent down to 55% of its height and opaque
    // from 85%, to lay over the sharp picture with the same aspect fill.
    BOOL dissolve;
} SGRPaletteRequest;

@interface SGRPalette : NSObject
@property (nonatomic, readonly) UIColor *edgeColor;
@property (nonatomic, readonly) UIColor *fieldColor;
@property (nonatomic, readonly) UIImage *dissolve;   // nil unless asked for, 96px wide
// nil to the completion when the image has no bitmap to read (a symbol, a CIImage).
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *palette))completion;

// `surface` tinted a little towards the artwork's dominant colour (brought down to a luminance of 0.05, then
// 35% of it mixed in), so a tile or row on the surface quietly takes its cover's colour while white text on
// it keeps its contrast. Never dimmer than `surface`: a mix that came out darker is lifted back to its
// luminance keeping its hue, so a near-black cover cannot cost the tile the step of elevation it stands on,
// nor sink it into the grey band SGRAmoled.x turns pure black. nil to the completion when the image has no
// bitmap to read.
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface completion:(void (^)(UIColor *tint))completion;
@end

// Any colour made fit to be a field, the same way the edge colour is: for a colour Spotify hands over
// before the artwork is read. Main thread.
UIColor *SGRFieldColorFor(UIColor *color);
