// SGVisualizerView.h says what it is. One shape layer holds every bar, its path made again each frame from
// the bars SGVisualizerReadBars hands back. A gradient colour (Spectrum, or the Cover gradient, the playing
// cover's main colours, SGCoverPalette.h) is a gradient layer the shape masks: radial along every bar, from
// the darkest colour inside to the lightest at the tip, or conic round the ring, once or there and back several
// times. Alternating gives each colour a shape layer of its own, every bar going to the next colour's. The display link runs
// the way the lyrics' does (Redesigned/Lyrics/SGRKaraokeView.m): it asks for 60 to 120 frames a second, is
// put down while the player opens or closes (Shared/Player/PlayerEvents.h) and whenever the view is not in a
// window or the app is not in front, so a locked phone is not woken to draw what nobody sees.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerEvents.h"
#import "SGCoverPalette.h"
#import "SGPalette.h"
#import "SGSpectrum.h"
#import "Visualizer.h"
#import "SGVisualizerView.h"

static const CGFloat kOuterInset = 2, kGap = 4;
static NSInteger sg_showing;

static void showing(NSInteger change) {
    sg_showing = MAX(0, sg_showing + change);
    SGVisualizerSetListening(sg_showing > 0);
}

@implementation SGVisualizerView {
    CAShapeLayer *_shape;
    CAGradientLayer *_spectrum;
    CADisplayLink *_link;
    CFTimeInterval _last;
    float _bars[SGSpectrumMaxBands];
    NSInteger _count;
    SGVisualizerStyle _style;
    SGVisualizerColor _color;
    BOOL _mirror, _counted, _covered;
    NSUInteger _frames;
    CGFloat _widthFactor, _heightFactor;
    NSTimeInterval _rotation;
    // Each band's cap, where Peaks has it: the highest the bar has been lately, falling back slowly.
    BOOL _peaks;
    float _peak[SGSpectrumMaxBands];
    // The bars' directions, made again when their number changes.
    float _cos[SGSpectrumMaxBands], _sin[SGSpectrumMaxBands];
    NSInteger _angles;
    SGVisualizerGradient _gradient;
    // Alternating's layers, one a colour; the radial gradient's span, inside to tip, as last laid.
    NSArray<CAShapeLayer *> *_alternates;
    CGFloat _radialFrom, _radialTo;
    // The Backlight: a radial glow under everything, and how far out it is solid, as last laid.
    CAGradientLayer *_backlight;
    CGFloat _backlightSolid;
}

// Shown as far as its ancestors go: none hidden or faded out (a queue cell's ring, a closed player's).
static BOOL onScreen(UIView *view) {
    for (UIView *at = view; at; at = at.superview) if (at.hidden || at.alpha < 0.01) return NO;
    return view.window != nil;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.backgroundColor = UIColor.clearColor;
    _shape = [CAShapeLayer layer];
    _shape.fillColor = nil;
    _shape.lineCap = kCALineCapRound;
    _shape.lineJoin = kCALineJoinRound;
    _spectrum = [CAGradientLayer layer];
    _spectrum.type = kCAGradientLayerConic;
    _spectrum.startPoint = CGPointMake(0.5, 0.5);
    _spectrum.endPoint = CGPointMake(0.5, 0);
    _backlight = [CAGradientLayer layer];
    _backlight.type = kCAGradientLayerRadial;
    _backlight.startPoint = CGPointMake(0.5, 0.5);
    _backlight.endPoint = CGPointMake(1, 1);
    _backlight.hidden = YES;
    [self.layer addSublayer:_backlight];
    [self.layer addSublayer:_shape];
    [self readSettings];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(readSettings) name:SGVisualizerSettingsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(paletteChanged) name:SGCoverPaletteDidChangeNotification object:nil];
    for (NSNotificationName name in @[SGPlayerTransitionNotification, SGPlayerTransitionEndedNotification,
                                      UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleLink) name:name object:nil];
    }
    return self;
}

- (void)dealloc {
    [_link invalidate];
    if (_counted) showing(-1);
}

- (void)readSettings {
    _count = SGVisualizerBarCount();
    _style = (SGVisualizerStyle)SGInt(SGKeyVisualizerStyle, SGVisualizerStyleBars);
    _color = (SGVisualizerColor)SGInt(SGKeyVisualizerColor, SGVisualizerColorAccent);
    _mirror = SGEnabled(SGKeyVisualizerMirror);
    _widthFactor = SGVisualizerWidthFactor();
    _heightFactor = SGVisualizerHeightFactor();
    _peaks = SGFlag(SGKeyVisualizerPeaks, NO);
    _rotation = SGVisualizerRotationPeriod();
    _gradient = (SGVisualizerGradient)SGInt(SGKeyVisualizerGradient, SGVisualizerGradientAlong);
    _radialFrom = _radialTo = 0;
    memset(_bars, 0, sizeof _bars);
    memset(_peak, 0, sizeof _peak);
    [self applyColor:NO];
    [self applyRotation];
}

// Rotation turns the whole ring, gradient and all, on an animation of its own that the layer keeps; the
// host's frame and the bars drawn each frame are untouched by it.
- (void)applyRotation {
    static NSString *const key = @"sg.ring.turn";
    CABasicAnimation *existing = (CABasicAnimation *)[self.layer animationForKey:key];
    if (_rotation <= 0 || UIAccessibilityIsReduceMotionEnabled()) {
        if (existing) [self.layer removeAnimationForKey:key];
        return;
    }
    if (existing && existing.duration == _rotation) return;
    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    turn.fromValue = @0;
    turn.toValue = @(2 * M_PI);
    turn.duration = _rotation;
    turn.repeatCount = HUGE_VALF;
    turn.additive = YES;
    turn.removedOnCompletion = NO;
    [self.layer addAnimation:turn forKey:key];
}

// A new track's colours fade in rather than cut.
- (void)paletteChanged {
    if (_color == SGVisualizerColorCover) [self applyColor:YES];
}

- (void)setAccent:(UIColor *)accent {
    if (accent == _accent || [accent isEqual:_accent]) return;
    _accent = accent;
    [self applyColor:NO];
}

- (void)applyColor:(BOOL)animated {
    UIColor *color = _color == SGVisualizerColorWhite ? UIColor.whiteColor : (_accent ?: UIColor.whiteColor);
    NSArray<UIColor *> *colours = SGVisualizerGradientColours(_color, color);
    BOOL alternating = colours.count > 1 && _gradient == SGVisualizerGradientAlternating;
    [CATransaction begin];
    if (animated) [CATransaction setAnimationDuration:0.8];
    else [CATransaction setDisableActions:YES];
    if (alternating) {
        [self useLayers:2];
        if (_alternates.count != colours.count) {
            for (CAShapeLayer *layer in _alternates) [layer removeFromSuperlayer];
            NSMutableArray<CAShapeLayer *> *layers = [NSMutableArray array];
            for (NSUInteger i = 0; i < colours.count; i++) {
                CAShapeLayer *layer = [CAShapeLayer layer];
                layer.lineCap = kCALineCapRound;
                layer.lineJoin = kCALineJoinRound;
                layer.frame = self.bounds;
                [self.layer addSublayer:layer];
                [layers addObject:layer];
            }
            _alternates = layers;
        }
        [colours enumerateObjectsUsingBlock:^(UIColor *colour, NSUInteger i, BOOL *stop) {
            CAShapeLayer *layer = self->_alternates[i];
            BOOL dots = self->_style == SGVisualizerStyleDots;
            layer.strokeColor = dots ? nil : colour.CGColor;
            layer.fillColor = dots ? colour.CGColor : nil;
        }];
    } else if (colours) {
        [self useLayers:1];
        BOOL along = _gradient == SGVisualizerGradientAlong || _gradient == SGVisualizerGradientAlternating;
        _spectrum.type = along ? kCAGradientLayerRadial : kCAGradientLayerConic;
        _spectrum.startPoint = CGPointMake(0.5, 0.5);
        _spectrum.endPoint = along ? CGPointMake(1, 1) : CGPointMake(0.5, 0);
        NSMutableArray *stops = [NSMutableArray array];
        for (UIColor *stop in SGVisualizerGradientStops(colours, along ? SGVisualizerGradientAlong : _gradient, _mirror,
                                                        _color == SGVisualizerColorSpectrum)) {
            [stops addObject:(id)stop.CGColor];
        }
        _spectrum.colors = stops;
        if (!along) _spectrum.locations = nil;
        else [self placeRadialFrom:_radialFrom to:_radialTo force:YES];
        _shape.strokeColor = UIColor.whiteColor.CGColor;
        _shape.fillColor = _style == SGVisualizerStyleDots ? UIColor.whiteColor.CGColor : nil;
    } else {
        [self useLayers:0];
        _shape.strokeColor = color.CGColor;
        _shape.fillColor = _style == SGVisualizerStyleDots ? color.CGColor : nil;
    }
    UIColor *glow = SGVisualizerBacklightColour(colours ?: @[color]);
    _backlight.hidden = glow == nil;
    if (glow) {
        // Solid from the middle (under the cover) to past the bars' middle, fading out by the ring's edge.
        _backlight.colors = @[(id)glow.CGColor, (id)glow.CGColor, (id)[glow colorWithAlphaComponent:0].CGColor];
        [self placeBacklight:_backlightSolid force:YES];
    }
    [CATransaction commit];
}

// The Backlight's solid part reaching `solid` points out from the centre, then fading to nothing at the edge
// of the ring's square; laid again only when that moves by more than a point.
- (void)placeBacklight:(CGFloat)solid force:(BOOL)force {
    if (!force && fabs(solid - _backlightSolid) < 1) return;
    _backlightSolid = solid;
    CGFloat half = MIN(self.bounds.size.width, self.bounds.size.height) / 2;
    if (half <= 0 || _backlight.hidden) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _backlight.locations = @[@0, @(MIN(0.95, MAX(0.05, solid / half))), @1];
    [CATransaction commit];
}

// Which layers draw: 0 the shape in one colour, 1 the gradient through the shape, 2 Alternating's own.
- (void)useLayers:(int)which {
    if (which != 2 && _alternates) {
        for (CAShapeLayer *layer in _alternates) [layer removeFromSuperlayer];
        _alternates = nil;
    }
    if (which == 1) {
        if (_spectrum.superlayer != self.layer) {
            [_shape removeFromSuperlayer];
            [self.layer addSublayer:_spectrum];
            _spectrum.mask = _shape;
        }
        return;
    }
    if (_spectrum.superlayer) {
        _spectrum.mask = nil;
        [_spectrum removeFromSuperlayer];
    }
    if (which == 0 && _shape.superlayer != self.layer) [self.layer addSublayer:_shape];
    if (which == 2) {
        [_shape removeFromSuperlayer];
        _shape.path = nil;
    }
}

// The radial gradient spread over the bars' length, inside to tip, as a share of the layer's half side; laid
// again only when that moves by more than a point.
- (void)placeRadialFrom:(CGFloat)from to:(CGFloat)to force:(BOOL)force {
    if (!force && fabs(from - _radialFrom) < 1 && fabs(to - _radialTo) < 1) return;
    _radialFrom = from;
    _radialTo = to;
    CGFloat half = MIN(self.bounds.size.width, self.bounds.size.height) / 2;
    NSUInteger count = _spectrum.colors.count;
    if (half <= 0 || to <= from || count < 2 || _spectrum.type != kCAGradientLayerRadial) return;
    NSMutableArray<NSNumber *> *locations = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [locations addObject:@((from + (to - from) * i / (count - 1)) / half)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _spectrum.locations = locations;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shape.frame = self.bounds;
    _spectrum.frame = self.bounds;
    _backlight.frame = self.bounds;
    for (CAShapeLayer *layer in _alternates) layer.frame = self.bounds;
    [CATransaction commit];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self applyRotation];
    [self scheduleLink];
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self scheduleLink];
}

// Runs while it can be seen; whether it is counted as a ring on screen follows the link.
- (void)scheduleLink {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(scheduleLink) object:nil];
    BOOL visible = self.window && !self.hidden && UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
    NSTimeInterval wait = SGPlayerTransitionEnds() - CACurrentMediaTime();
    BOOL run = visible && wait <= 0;
    if (visible && wait > 0) [self performSelector:@selector(scheduleLink) withObject:nil afterDelay:wait + 0.05 inModes:@[NSRunLoopCommonModes]];
    if (visible != _counted) {
        _counted = visible;
        showing(visible ? 1 : -1);
    }
    if (run && !_link) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        _link.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        _last = 0;
    } else if (!run && _link) {
        [_link invalidate];
        _link = nil;
    }
}

- (void)tick:(CADisplayLink *)link {
    // Faded out with the cover (a clip over the field, the lyrics in the player), or inside something hidden
    // or faded (asked twice a second, a walk up the views being too dear for every frame): nothing to draw.
    if (_frames++ % 30 == 0) {
        _covered = !onScreen(self);
        // A new track's cover is noticed here: the read is kicked off and the notification brings it in. The
        // picture on screen is read when there is one, the now playing artwork otherwise. Only the ring that
        // shows hands its cover over: the player keeps a ring round the songs either side too, hidden, and
        // theirs are other songs' covers.
        if (_color == SGVisualizerColorCover && !_covered) {
            __block UIImageView *largest = nil;
            UIView *cover = self.coverView;
            if (cover) SGForEachView(cover, ^(UIView *view) {
                if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image
                    && view.bounds.size.width > largest.bounds.size.width) largest = (UIImageView *)view;
            });
            if (largest.image && largest.bounds.size.width >= 80) SGCoverPaletteOfferImage(largest.image);
            else SGCoverPaletteForPlayingTrack();
        }
    }
    if (self.alpha < 0.01 || _covered) {
        _last = 0;
        return;
    }
    float elapsed = _last > 0 ? (float)(link.targetTimestamp - _last) : 1 / 60.0f;
    _last = link.targetTimestamp;
    // A mirrored ring shows each band twice, so it reads half as many.
    NSInteger bands = _mirror ? MAX(8, _count / 2) : _count;
    SGVisualizerReadBars(_bars, bands, elapsed);
    if (_peaks) {
        // A cap falls a third of the way in a second, and is pushed up by its bar.
        float drop = elapsed * 0.33f;
        for (NSInteger b = 0; b < bands; b++) _peak[b] = MAX(_bars[b], _peak[b] - drop);
    }
    [self drawBands:bands];
}

- (void)drawBands:(NSInteger)bands {
    CGRect bounds = self.bounds;
    CGPoint centre = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGFloat outer = MIN(bounds.size.width, bounds.size.height) / 2 - kOuterInset;
    CGFloat inner = MAX(4, MIN(self.innerRadius + kGap, outer - 8));
    NSInteger count = _mirror ? bands * 2 : bands;
    if (count <= 0 || outer - inner <= 0) return;
    CGFloat step = 2 * M_PI / count;
    // A bar is a share of the room it has, never wider than that room, and at a thousand bars never thinner
    // than a hairline; the width choice is a bigger or smaller share.
    CGFloat room = inner * step;
    CGFloat width = MIN(8 * _widthFactor, room * 0.55 * _widthFactor);
    width = MIN(width, MAX(0.75, room * 0.95));
    width = MAX(width, MIN(1.5, room * 1.1));
    // The caps want room of their own past the tallest bar.
    BOOL caps = _peaks && _style == SGVisualizerStyleBars;
    CGFloat reach = MAX(0, outer - inner - (caps ? width * 2.5 : 0)) * _heightFactor;
    if (reach <= 0) return;
    if (count != _angles) {
        for (NSInteger i = 0; i < count; i++) {
            CGFloat angle = -M_PI_2 + (i + 0.5) * step;
            _cos[i] = (float)cos(angle);
            _sin[i] = (float)sin(angle);
        }
        _angles = count;
    }
    // Alternating draws into a path a colour, every bar into the next one's; a wave is one line, so it stays one.
    NSUInteger paths = _alternates.count && _style != SGVisualizerStyleWave ? _alternates.count : 1;
    UIBezierPath *all[SGPaletteMaxColors + 1];
    for (NSUInteger p = 0; p < paths; p++) all[p] = [UIBezierPath bezierPath];
    if (_spectrum.superlayer && _spectrum.type == kCAGradientLayerRadial) [self placeRadialFrom:inner to:inner + reach force:NO];
    if (!_backlight.hidden) [self placeBacklight:inner + reach * 0.6 force:NO];
    for (NSInteger i = 0; i < count; i++) {
        UIBezierPath *path = all[(NSUInteger)i % paths];
        // Mirrored, the lowest band is at the top and the highest meets itself at the bottom.
        NSInteger band = _mirror ? (i < bands ? i : count - 1 - i) : i;
        CGFloat value = _bars[band];
        CGFloat dx = _cos[i], dy = _sin[i];
        CGFloat out = inner + MAX(width * 0.5, value * reach);
        switch (_style) {
            case SGVisualizerStyleBars:
                [path moveToPoint:CGPointMake(centre.x + dx * inner, centre.y + dy * inner)];
                [path addLineToPoint:CGPointMake(centre.x + dx * out, centre.y + dy * out)];
                if (caps) {
                    // A dot (a stroke of almost no length, its round caps making it round) a little past the peak.
                    CGFloat cap = inner + MAX(width * 0.5, _peak[band] * reach) + width * 1.5;
                    [path moveToPoint:CGPointMake(centre.x + dx * cap, centre.y + dy * cap)];
                    [path addLineToPoint:CGPointMake(centre.x + dx * (cap + 0.01), centre.y + dy * (cap + 0.01))];
                }
                break;
            case SGVisualizerStyleWave:
                if (i == 0) [path moveToPoint:CGPointMake(centre.x + dx * out, centre.y + dy * out)];
                else [path addLineToPoint:CGPointMake(centre.x + dx * out, centre.y + dy * out)];
                break;
            case SGVisualizerStyleDots: {
                CGFloat r = width * 0.6;
                CGPoint at = CGPointMake(centre.x + dx * out, centre.y + dy * out);
                [path moveToPoint:CGPointMake(at.x + r, at.y)];
                [path addArcWithCenter:at radius:r startAngle:0 endAngle:2 * M_PI clockwise:YES];
                break;
            }
        }
    }
    if (_style == SGVisualizerStyleWave) [all[0] closePath];
    CGFloat lineWidth = _style == SGVisualizerStyleWave ? MAX(1.5, 2.5 * _widthFactor) : _style == SGVisualizerStyleDots ? 0 : width;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (_alternates.count) {
        for (NSUInteger p = 0; p < _alternates.count; p++) {
            _alternates[p].lineWidth = lineWidth;
            _alternates[p].path = p < paths ? all[p].CGPath : nil;
        }
    } else {
        _shape.lineWidth = lineWidth;
        _shape.path = all[0].CGPath;
    }
    [CATransaction commit];
}

@end
