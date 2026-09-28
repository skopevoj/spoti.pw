#import "Core/SGCore.h"
#import "SGRField.h"
#import "SGRWarp.h"
#import "SGRBridges.h"
#import "SGRPalette.h"
#import "SGRTokens.h"

NSNotificationName const SGRFieldColorDidChangeNotification = @"spotifyglass.redesign.fieldColorDidChange";

static const CGFloat kFallbackHeight = 874;   // a window-less field sizes for an iPhone 17 Pro

// Where the colour starts fading to black and where it is black, as shares of the window's height:
// the redesign is AMOLED throughout (SGRAmoled.x).
static const CGFloat kBlackFrom = 0.55, kBlackTo = 1;

static CGFloat windowHeight(UIView *view) {
    CGFloat height = view.window.bounds.size.height;
    return height > 0 ? height : kFallbackHeight;
}

// The field paints on sublayers of its own rather than on the view's layer: a repaint hook only clears
// the paint of a view's own layer, so the neutral colour cannot be taken for Spotify's base surface.
static NSDictionary *noActions(void) {
    static NSDictionary *none;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNull *off = NSNull.null;
        none = @{@"bounds": off, @"position": off, @"frame": off, @"contents": off, @"backgroundColor": off, @"hidden": off, @"locations": off};
    });
    return none;
}

@implementation SGRArtworkField {
    CALayer *_solid;
    CAGradientLayer *_black;
    SGRWarpLayer *_warp;
    BOOL _watching;
    UIColor *_color;
    UIColor *_preferred;   // the page's own colour, made fit; wins over the artwork's
    UIImage *_image;
    NSString *_identity;
    NSUInteger _generation;
    BOOL _read;
    BOOL _colored;   // a colour of the page's own is showing
    NSMutableArray<void (^)(void)> *_whenColored;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.clipsToBounds = NO;
    self.accessibilityElementsHidden = YES;
    _color = SGRNeutralField();
    _warpLook = SGRWarpDefaultLook;

    _solid = [CALayer layer];
    _solid.actions = noActions();
    _solid.backgroundColor = _color.CGColor;
    [self.layer addSublayer:_solid];

    _black = [CAGradientLayer layer];
    _black.actions = noActions();
    _black.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)UIColor.blackColor.CGColor];
    [self.layer addSublayer:_black];
    return self;
}

- (UIColor *)fieldColor {
    return _color;
}

- (void)setBleed:(UIEdgeInsets)bleed {
    _bleed = bleed;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    UIEdgeInsets bleed = _bleed;
    CGRect painted = CGRectMake(-bleed.left, -bleed.top, bounds.size.width + bleed.left + bleed.right, bounds.size.height + bleed.top + bleed.bottom);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _solid.frame = painted;
    CGFloat height = windowHeight(self), total = MAX(1, painted.size.height);
    CGFloat from = height * kBlackFrom + bleed.top;
    CGFloat to = MAX(from + 1, height * kBlackTo + bleed.top);
    _black.frame = painted;
    _black.locations = @[@(MIN(1, from / total)), @(MIN(1, to / total))];
    // Over the pull above the player too, where the picture's top edge carries on.
    _warp.frame = CGRectMake(0, -bleed.top, bounds.size.width, height + bleed.top);
    _warp.pictureFrame = CGRectMake(0, bleed.top, bounds.size.width, height);
    [CATransaction commit];
}

#pragma mark - the moving field

- (void)setMotion:(SGRFieldMotion)motion {
    if (motion == SGRFieldMotionWarp && !SGRWarpAvailable()) motion = SGRFieldMotionNone;
    if (motion == _motion) return;
    _motion = motion;
    if (motion == SGRFieldMotionWarp && !_warp) {
        _warp = [SGRWarpLayer layer];
        _warp.look = _warpLook;
        [self.layer insertSublayer:_warp above:_solid];
    }
    // A moving field is the whole picture, with no fade to black under it.
    _black.hidden = motion != SGRFieldMotionNone;
    _warp.hidden = motion != SGRFieldMotionWarp;
    [self watch];
    [self updateMotion];
    [self setNeedsLayout];
}

- (void)setWarpLook:(SGRWarpLook)look {
    _warpLook = look;
    _warp.look = look;
}

- (void)setMotionHeld:(BOOL)held {
    if (held == _motionHeld) return;
    _motionHeld = held;
    [self updateMotion];
}

- (void)setCovered:(BOOL)covered {
    if (covered == _covered) return;
    _covered = covered;
    [self updateMotion];
}

- (void)watch {
    if (_watching || _motion == SGRFieldMotionNone) return;
    _watching = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      UIApplicationDidEnterBackgroundNotification, UIApplicationWillEnterForegroundNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(updateMotionSoon) name:name object:nil];
    }
    SGRObservePlayerTransition(self, ^(id owner) { [owner updateMotion]; }, ^(id owner) { [owner updateMotion]; });
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// The power state is reported off the main thread.
- (void)updateMotionSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateMotion]; });
}

- (void)updateMotion {
    if (!_warp) return;
    // A locked phone keeps the player in its window, so being in front counts as much as being in one.
    UIApplicationState state = UIApplication.sharedApplication.applicationState;
    BOOL still = SGRReduceMotion() || NSProcessInfo.processInfo.lowPowerModeEnabled || _motionHeld;
    SGRWarpPace pace = SGRWarpPaceMoving;
    if (_motion != SGRFieldMotionWarp || !self.window || state == UIApplicationStateBackground) pace = SGRWarpPaceHidden;
    else if (state != UIApplicationStateActive || SGRPlayerIsTransitioning() || _covered) pace = SGRWarpPaceFrozen;
    else if (still) pace = SGRWarpPaceStill;
    _warp.pace = pace;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateMotion];
}

- (void)applyColor:(UIColor *)color animated:(BOOL)animated {
    if (!color || CGColorEqualToColor(color.CGColor, _color.CGColor)) return;
    CALayer *shown = _solid.presentationLayer ?: _solid;
    id from = (__bridge id)shown.backgroundColor;
    _color = color;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _solid.backgroundColor = color.CGColor;
    [CATransaction commit];
    if (animated && from) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        fade.fromValue = from;
        // Read back rather than the colour asked for: SGRAmoled.x may have swapped it for black.
        fade.toValue = (__bridge id)_solid.backgroundColor;
        fade.duration = SGRCrossfade;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [_solid addAnimation:fade forKey:@"backgroundColor"];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:SGRFieldColorDidChangeNotification object:self userInfo:@{@"color": color}];
}

- (void)whenColored:(void (^)(void))colored {
    if (!colored) return;
    if (_colored) {
        colored();
        return;
    }
    if (!_whenColored) _whenColored = [NSMutableArray array];
    [_whenColored addObject:[colored copy]];
}

- (void)didColor {
    if (_colored) return;
    _colored = YES;
    NSArray<void (^)(void)> *pending = _whenColored;
    _whenColored = nil;
    for (void (^colored)(void) in pending) colored();
}

- (void)setProvisionalColor:(UIColor *)color {
    if (_read || !color) return;
    [self applyColor:SGRFieldColorFor(color) animated:self.window != nil];
}

- (void)setPreferredColor:(UIColor *)color {
    if (!color) return;
    UIColor *fit = SGRFieldColorFor(color);
    if (_preferred && CGColorEqualToColor(fit.CGColor, _preferred.CGColor)) return;
    _preferred = fit;
    [self applyColor:fit animated:self.window != nil];
    [self didColor];
}

- (void)setArtwork:(UIImage *)image identity:(NSString *)identity animated:(BOOL)animated {
    if (!image || image == _image || (identity && [identity isEqualToString:_identity])) return;
    _image = image;
    _identity = [identity copy];
    NSUInteger generation = ++_generation;
    SGRPaletteRequest request = {NO};
    if (_motion == SGRFieldMotionWarp) [_warp setArtwork:image animated:animated];
    __weak SGRArtworkField *weakSelf = self;
    [SGRPalette paletteForImage:image request:request completion:^(SGRPalette *palette) {
        SGRArtworkField *field = weakSelf;
        if (!field || !palette || generation != field->_generation) return;
        [field applyPalette:palette animated:animated && field.window != nil];
    }];
}

- (void)applyPalette:(SGRPalette *)palette animated:(BOOL)animated {
    _read = YES;
    [self applyColor:_preferred ?: palette.fieldColor animated:animated];
    [self didColor];
}

@end
