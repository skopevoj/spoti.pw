// The artwork itself as a moving background, ported from kawarp (MIT, Better Lyrics; Mod > Licenses): the
// cover is Kawase blurred at 128px once, then each frame warped by slow noise and held under a luminance
// white text reads on. Metal, compiled from source off the main thread; until it is ready, or without
// Metal, nothing is drawn and the owner's colour shows through. Main thread only.
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>

typedef struct {
    float speed;        // 1 is kawarp's pace
    float warp;         // 0 still ... 1 kawarp's full strength
    float blur;         // Kawase passes, 1 ... 40
    float saturation;   // 1 leaves the colours as they are
    float brightness;   // 1 is held under the white-text ceiling; more goes past it
} SGRWarpLook;

// kawarp's own defaults, and the ceiling at full brightness.
extern const SGRWarpLook SGRWarpDefaultLook;

typedef NS_ENUM(NSInteger, SGRWarpPace) {
    SGRWarpPaceHidden,   // out of sight: nothing is drawn, and a change waits until it shows
    SGRWarpPaceFrozen,   // a change is drawn in a single frame; nothing runs frame after frame
    SGRWarpPaceStill,    // crossfades play, the picture does not move
    SGRWarpPaceMoving,
};

// Starts compiling the shaders, if it has not started, so the first layer draws at once.
void SGRWarpPrepare(void);
// NO where this device has no Metal.
BOOL SGRWarpAvailable(void);
// A picture of soft colour to warp when there is no artwork.
UIImage *SGRWarpSampleArtwork(void);

@interface SGRWarpLayer : CAMetalLayer
@property (nonatomic) SGRWarpLook look;
// Hidden until the owner says otherwise.
@property (nonatomic) SGRWarpPace pace;
// Where the picture lies in the bounds; past it the picture's edge carries on. CGRectNull is the bounds.
@property (nonatomic) CGRect pictureFrame;
// Shrinks the image off the main thread, then crossfades to it (at once when not `animated`, when it
// is the first, or when a second has gone by before the layer could draw it).
- (void)setArtwork:(UIImage *)image animated:(BOOL)animated;
@end

// A view drawing an SGRWarpLayer that sets its own pace: moving while in a window with the app in front
// (still under Reduce Motion), hidden otherwise. For a preview.
@interface SGRWarpView : UIView
@property (nonatomic, readonly) SGRWarpLayer *warpLayer;
@end
