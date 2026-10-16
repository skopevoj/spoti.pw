// Sing's microphone in the player's lyrics (SGRSingControl.h), the way the Music app has its Sing button: a
// round glass button with a microphone on it, and a capsule of glass growing up out of it that holds the
// vocal volume, filled from the bottom to the level. What Sing is doing shows on the button itself, never in
// words beside it:
//
//   off           glass and a white microphone
//   preparing     a ring turning round the microphone over a faint fill, up to the level it gets ready for
//   on            the fill solid white up to the level and the microphone dark on it; closed, a white disc
//   recovering    on, with the ring turning again, dark on the white, while the original covers a gap
//   turning off   off at once; the original audio still queued plays out behind it
//   stopped       off with the microphone dimmed; a tap says why and offers to try again
//
// A tap turns Sing on and opens the capsule. Open, a tap turns Sing off; closed while Sing is on, a tap
// opens it again. A drag anywhere on it sets the level, opening it first. The capsule closes by itself
// three seconds after the last touch while Sing is on. Sizes move on the Kit's layout spring and colours
// on its crossfade, so Reduce Motion keeps the fades and drops the movement, and the ring pulses in place
// instead of turning. VoiceOver reads the button and the slider out in full.
#import "Core/SGCore.h"
#import "SGRSingControl.h"
#import "Shared/Sing/SGSingController.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRTokens.h"
#import <objc/runtime.h>

static char kControlKey, kPanelGlass;

static const CGFloat kSide = 44;               // the button, and the capsule's width
static const CGFloat kOpenHeight = 144;        // the capsule with the slider out above the button
static const CGFloat kRingInset = 3.5, kRingWidth = 2.5;
static const CGFloat kFillWhite = 0.88;        // the fill while Sing is on
static const CGFloat kPendingAlpha = 0.3;      // how much of it shows while Sing prepares
static const CGFloat kStoppedAlpha = 0.45;     // the microphone while Sing has stopped
static const NSTimeInterval kCollapseAfter = 3, kBusyRecheck = 0.5;
static const float kSpokenStep = 0.1f;         // VoiceOver's step through the level

static UIColor *darkGlyph(void) { return [UIColor colorWithWhite:0.12 alpha:1]; }

static void singSparkle(CGPoint center, CGFloat radius) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(center.x, center.y - radius)];
    [path addQuadCurveToPoint:CGPointMake(center.x + radius, center.y) controlPoint:CGPointMake(center.x + radius * 0.18, center.y - radius * 0.18)];
    [path addQuadCurveToPoint:CGPointMake(center.x, center.y + radius) controlPoint:CGPointMake(center.x + radius * 0.18, center.y + radius * 0.18)];
    [path addQuadCurveToPoint:CGPointMake(center.x - radius, center.y) controlPoint:CGPointMake(center.x - radius * 0.18, center.y + radius * 0.18)];
    [path addQuadCurveToPoint:CGPointMake(center.x, center.y - radius) controlPoint:CGPointMake(center.x - radius * 0.18, center.y - radius * 0.18)];
    [path closePath]; [path fill];
}

static UIImage *singGlyph(void) {
    static UIImage *glyph;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(28, 28)];
        glyph = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            // A handheld microphone, drawn as a template so both the glass and white states
            // use the same crisp silhouette. The three sparkles keep distinct sizes at 28 pt.
            [UIColor.blackColor setFill]; [UIColor.blackColor setStroke];
            CGContextRef cg = context.CGContext;
            CGContextSaveGState(cg);
            CGContextTranslateCTM(cg, 11.5, 14.5);
            CGContextRotateCTM(cg, M_PI_4);
            UIBezierPath *handle = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(-1.6, -4, 3.2, 14.5) cornerRadius:1.6];
            handle.lineWidth = 1.5; [handle stroke];
            UIBezierPath *tip = [UIBezierPath bezierPath];
            [tip moveToPoint:CGPointMake(0, 10.5)]; [tip addLineToPoint:CGPointMake(0, 13)];
            tip.lineWidth = 1.8; tip.lineCapStyle = kCGLineCapRound; [tip stroke];
            UIBezierPath *neck = [UIBezierPath bezierPath];
            [neck moveToPoint:CGPointMake(-3.5, -9)]; [neck addLineToPoint:CGPointMake(-1.8, -4)];
            [neck addLineToPoint:CGPointMake(1.8, -4)]; [neck addLineToPoint:CGPointMake(3.5, -9)];
            [neck closePath]; [neck fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-4.5, -15.5, 9, 9)] fill];
            CGContextSetBlendMode(cg, kCGBlendModeClear);
            CGContextSetLineWidth(cg, 1.25);
            CGContextMoveToPoint(cg, -5, -11); CGContextAddLineToPoint(cg, 5, -11); CGContextStrokePath(cg);
            CGContextRestoreGState(cg);
            singSparkle(CGPointMake(4.5, 7.5), 3.3);
            singSparkle(CGPointMake(22.5, 18.7), 4.2);
            singSparkle(CGPointMake(14.5, 24), 2.2);
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    return glyph;
}

// What the button shows, worked out from the controller's state alone.
typedef struct { BOOL on, preparing, ring, stopped; } SGRSingLook;
static SGRSingLook lookOf(SGSingState state) {
    return (SGRSingLook){
        .on = SGSingStateIsOn(state),
        .preparing = state == SGSingPreparing,
        .ring = state == SGSingPreparing || state == SGSingRecovering,
        .stopped = state == SGSingFailed,
    };
}

// A vertical, thumb-free slider inside the glass capsule. Direct touch and VoiceOver both send
// the same value-changed event; UISlider's horizontal gesture recognizer is not involved.
@interface SGRVocalSlider : UIControl
@property (nonatomic) float value;
@end
@implementation SGRVocalSlider
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    return self;
}
- (void)setValue:(float)value {
    _value = SGSingClampLevel(value);
    // Rounded end labels must mean the actual endpoint, including subpixel touch coordinates.
    if (_value < SGSingMinimumVocalLevel + 0.005f) _value = SGSingMinimumVocalLevel;
    // The original mix and vocals only are where a finger means to stop, near enough.
    if (fabsf(_value - 1) < 0.01f) _value = 1;
    if (_value > SGSingVocalsOnlyLevel - 0.01f) _value = SGSingVocalsOnlyLevel;
}
- (void)accessibilityIncrement {
    if (!self.enabled) return;
    self.value += kSpokenStep;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)accessibilityDecrement {
    if (!self.enabled) return;
    self.value -= kSpokenStep;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)moveToTouch:(UITouch *)touch {
    self.value = SGSingLevelFromPosition(1 - [touch locationInView:self].y / MAX(1, self.bounds.size.height));
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self moveToTouch:touch]; return YES; }
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self moveToTouch:touch]; return YES; }
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { if (touch) [self moveToTouch:touch]; }
@end

// Spotify's player also pans to dismiss. A drag starting inside this control belongs to vocal
// volume, including a drag starting on the microphone, rather than to the enclosing player.
@interface SGRVocalPan : UIPanGestureRecognizer
@end
@implementation SGRVocalPan
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
@end

// The ring round the microphone while Sing gets ready: an arc turning once a second, or with Reduce Motion a
// whole ring pulsing where it is, a fade not being motion. It takes its colour from its tint.
@interface SGRSingRing : UIView
@property (nonatomic) BOOL turning;
@end
@implementation SGRSingRing {
    CAShapeLayer *_arc;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    _arc = [CAShapeLayer layer];
    _arc.fillColor = UIColor.clearColor.CGColor;
    _arc.lineWidth = kRingWidth;
    _arc.lineCap = kCALineCapRound;
    [self.layer addSublayer:_arc];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sgr_animate)
                                               name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat radius = MIN(bounds.size.width, bounds.size.height) / 2 - kRingInset;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _arc.frame = bounds;
    // From twelve o'clock, clockwise; the layer turns about its middle.
    _arc.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds)) radius:MAX(0, radius)
                                           startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES].CGPath;
    [CATransaction commit];
}
- (void)tintColorDidChange {
    [super tintColorDidChange];
    _arc.strokeColor = self.tintColor.CGColor;
}
// Core Animation drops a repeating animation when the layer leaves the window; it is put back on the way in.
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self sgr_animate];
}
- (void)setTurning:(BOOL)turning {
    if (_turning == turning) return;
    _turning = turning;
    [self sgr_animate];
}
- (void)sgr_animate {
    [_arc removeAllAnimations];
    if (!_turning || !self.window) return;
    BOOL still = SGRReduceMotion();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _arc.strokeEnd = still ? 1 : 0.28;
    [CATransaction commit];
    CABasicAnimation *animation;
    if (still) {
        animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue = @1;
        animation.toValue = @0.3;
        animation.duration = 0.9;
        animation.autoreverses = YES;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    } else {
        animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        animation.fromValue = @0;
        animation.toValue = @(2 * M_PI);
        animation.duration = 1;
    }
    animation.repeatCount = HUGE_VALF;
    [_arc addAnimation:animation forKey:@"sgr.ring"];
}
@end

@interface SGRSingControl : UIView <UIGestureRecognizerDelegate>
@property (nonatomic) UIButton *button;
@property (nonatomic) UIImageView *glyph, *glyphOn;   // the microphone white on the glass, and dark on the fill
@property (nonatomic) SGRSingRing *ring;
@property (nonatomic) UIView *panel, *fill;
@property (nonatomic) SGRVocalSlider *slider;
@property (nonatomic) SGRVocalPan *pan;
@property (nonatomic) UITapGestureRecognizer *outside;
@property (nonatomic, copy) void (^hold)(BOOL);
@property (nonatomic) CGPoint anchor;
@property (nonatomic) float dragLevel;
@property (nonatomic) CGPoint dragStart;
@property (nonatomic) CGFloat stretch;
@property (nonatomic) BOOL dragging, expanded, explaining, immersive, holding, wasOn;
@property (nonatomic) SGSingState shown;   // the state the button shows, so only a real change is animated
@property (nonatomic) float shownLevel;
@property (nonatomic) CFTimeInterval collapseDeadline;
@property (nonatomic) NSTimer *collapseTimer;
- (void)refresh;
- (void)updateHold;
@end

@implementation SGRSingControl

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _panel = [UIView new];
    _panel.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _panel.clipsToBounds = NO;
    [self addSubview:_panel];
    _pan = [[SGRVocalPan alloc] initWithTarget:self action:@selector(dragged:)];
    _pan.delegate = self;
    _pan.maximumNumberOfTouches = 1;
    [_panel addGestureRecognizer:_pan];
    _fill = [UIView new];
    _fill.userInteractionEnabled = NO;
    _fill.backgroundColor = [UIColor colorWithWhite:1 alpha:kFillWhite];
    _slider = [SGRVocalSlider new];
    _slider.accessibilityLabel = @"Vocal volume";
    _slider.accessibilityHint = @"Original vocals at the top, 20 percent at the bottom";
    _slider.accessibilityIdentifier = @"sing.vocalLevel";
    [_slider addTarget:self action:@selector(changed) forControlEvents:UIControlEventValueChanged];
    // The capsule draws on and off itself: a custom button, so UIKit adds no highlight or selected look.
    _button = [UIButton buttonWithType:UIButtonTypeCustom];
    _button.accessibilityIdentifier = @"sing.microphone";
    [_button addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [_button addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]];
    _ring = [SGRSingRing new];
    _glyph = [[UIImageView alloc] initWithImage:singGlyph()];
    _glyph.tintColor = SGRPrimary();
    _glyphOn = [[UIImageView alloc] initWithImage:singGlyph()];
    _glyphOn.tintColor = darkGlyph();
    for (UIView *view in @[_ring, _glyph, _glyphOn]) {
        view.userInteractionEnabled = NO;
        view.contentMode = UIViewContentModeCenter;
        [_button addSubview:view];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:SGSingDidChangeNotification object:nil];
    _shown = SGSingCurrentState();
    _shownLevel = SGSingVocalLevel();
    [self refreshAnimated:NO];
    return self;
}

- (void)dealloc {
    [_collapseTimer invalidate];
    [_outside.view removeGestureRecognizer:_outside];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - what it shows

// The capsule is open, preparing, turning off or explaining itself: the player keeps its controls meanwhile.
- (void)updateHold {
    SGSingState state = SGSingCurrentState();
    BOOL held = _expanded || _explaining || state == SGSingPreparing || state == SGSingDraining;
    if (!_hold) return;
    // Re-layout of a collapsed control must not keep restarting the lyrics' inactivity clock.
    if (held || held != _holding) _hold(held);
    _holding = held;
}

// With the controls away the microphone stays only while Sing is on.
- (void)updateVisibility {
    BOOL visible = !_immersive || SGSingStateIsOn(SGSingCurrentState());
    self.alpha = visible ? 1 : 0;
    self.accessibilityElementsHidden = !visible;
}

// The colours: the fill's strength, which microphone shows, the ring. Crossfaded, so kept under Reduce Motion.
- (void)applyLook {
    SGRSingLook look = lookOf(_shown);
    _fill.alpha = look.on ? 1 : look.preparing ? kPendingAlpha : 0;
    _glyphOn.alpha = look.on ? 1 : 0;
    _glyph.alpha = look.on ? 0 : look.stopped ? kStoppedAlpha : 1;
    _ring.alpha = look.ring ? 1 : 0;
    _ring.tintColor = look.on ? darkGlyph() : SGRPrimary();
}

- (void)describe {
    SGSingState state = _shown;
    SGRSingLook look = lookOf(state);
    BOOL original = _slider.value == 1, vocalsOnly = _slider.value >= SGSingVocalsOnlyLevel;
    NSString *spoken = vocalsOnly ? @"Vocals only" : original ? @"Original"
        : _slider.value > 1 ? [NSString stringWithFormat:@"Instrumental %.0f percent", (SGSingVocalsOnlyLevel - _slider.value) * 100]
        : [NSString stringWithFormat:@"%.0f percent", _slider.value * 100];
    _slider.accessibilityValue = spoken;
    _button.accessibilityLabel = @"Sing";
    _button.accessibilityValue = state == SGSingPreparing ? @"Preparing Sing" : state == SGSingRecovering ? @"Restoring Sing"
        : state == SGSingDraining ? @"Turning Sing off" : state == SGSingFailed ? @"Sing stopped"
        : look.on ? (original ? @"On, original vocals" : [@"On, " stringByAppendingString:spoken.lowercaseString])
        : @"Off";
    _button.accessibilityHint = state == SGSingPreparing ? @"Tap to cancel." : state == SGSingDraining ? @"Tap to turn Sing back on."
        : state == SGSingFailed ? @"Tap to hear why Sing stopped."
        : look.on ? (_expanded ? @"Tap to turn Sing off. Drag to adjust the vocals." : @"Tap for the vocal volume.")
        : @"Turns the song's vocals down on this iPhone.";
    _button.accessibilityTraits = UIAccessibilityTraitButton | (look.on ? UIAccessibilityTraitSelected : 0);
    // Off from wherever the button is, without opening the capsule first.
    __weak typeof(self) weak = self;
    _button.accessibilityCustomActions = look.on || look.preparing ? @[[[UIAccessibilityCustomAction alloc]
        initWithName:@"Turn Off Sing" actionHandler:^BOOL(UIAccessibilityCustomAction *action) { [weak turnOff]; return YES; }]] : nil;
}

- (void)refresh { [self refreshAnimated:self.window != nil]; }

- (void)refreshAnimated:(BOOL)animated {
    SGSingState state = SGSingCurrentState();
    SGRSingLook look = lookOf(state);
    if (look.on && !_wasOn) [self interacted];
    _wasOn = look.on;
    BOOL changed = state != _shown;
    float level = SGSingVocalLevel();
    BOOL moved = level != _shownLevel;
    _shown = state;
    _shownLevel = level;
    _slider.enabled = look.on || look.preparing;
    _slider.value = level;
    [self describe];
    // Off, stopped or turning off, the capsule has nothing to hold open.
    if (!look.on && !look.preparing) self.expanded = NO;
    [self updateHold];
    [self updateVisibility];
    [self setNeedsLayout];
    // A drag lays out as it goes; anything else moves on the Kit's motion.
    if (_dragging || !animated) {
        [self applyLook];
        _ring.turning = look.ring;
        [self layoutIfNeeded];
        return;
    }
    if (changed || moved) SGRAnimate(SGRMotionLayout, ^{ [self layoutIfNeeded]; }, nil);
    if (!changed) return;
    // The ring starts before it fades in and stops only once it has faded out.
    if (look.ring) _ring.turning = YES;
    __weak typeof(self) weak = self;
    SGRAnimate(SGRMotionFade, ^{ [self applyLook]; }, ^(BOOL finished) {
        typeof(self) self = weak;
        if (self) self.ring.turning = lookOf(self.shown).ring;
    });
}

#pragma mark - opening and closing

- (void)setAnchor:(CGPoint)anchor {
    if (CGPointEqualToPoint(_anchor, anchor) && self.frame.size.width > 0) return;
    _anchor = anchor;
    [self placeAnimated:NO];
}

// The capsule grows up out of the button, which stays where it is.
- (void)placeAnimated:(BOOL)animated {
    void (^place)(void) = ^{
        CGFloat height = self.expanded ? kOpenHeight : kSide;
        self.frame = CGRectMake(self.anchor.x, self.anchor.y + kSide - height, kSide, height);
        [self layoutIfNeeded];
    };
    if (animated) SGRAnimate(SGRMotionLayout, place, nil);
    else place();
}

- (void)setExpanded:(BOOL)expanded {
    if (_expanded == expanded) return;
    _expanded = expanded;
    if (expanded) [self interacted];
    else { [_collapseTimer invalidate]; _collapseTimer = nil; }
    [self describe];
    [self updateHold];
    // Direct dragging always tracks the finger at once; only opening and closing move on the spring.
    [self placeAnimated:!_dragging && self.window];
}

- (void)interacted {
    _collapseDeadline = CACurrentMediaTime() + kCollapseAfter;
    [self scheduleCollapse:kCollapseAfter];
}

- (void)scheduleCollapse:(NSTimeInterval)wait {
    [_collapseTimer invalidate];
    _collapseTimer = nil;
    if (!_expanded) return;
    __weak typeof(self) weak = self;
    _collapseTimer = [NSTimer timerWithTimeInterval:MAX(wait, 0.1) repeats:NO block:^(NSTimer *timer) { [weak collapseIfIdle]; }];
    [NSRunLoop.mainRunLoop addTimer:_collapseTimer forMode:NSRunLoopCommonModes];
}

// Closes three seconds after the last touch while Sing is on, but never under a finger, while Sing prepares,
// or for VoiceOver, which has no other way back to the slider.
- (void)collapseIfIdle {
    _collapseTimer = nil;
    if (!_expanded || !self.window) return;
    BOOL busy = !SGSingStateIsOn(SGSingCurrentState()) || _dragging || _slider.tracking || _button.tracking || UIAccessibilityIsVoiceOverRunning();
    for (UIGestureRecognizer *gesture in _button.gestureRecognizers)
        busy |= gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged;
    NSTimeInterval left = _collapseDeadline - CACurrentMediaTime();
    if (!busy && left <= 0) self.expanded = NO;
    else [self scheduleCollapse:busy ? kBusyRecheck : left];
}

- (void)dismissControls { self.expanded = NO; }

#pragma mark - layout

- (void)layoutSubviews {
    [super layoutSubviews];
    // The value uses stationary page coordinates; stretching the glass must never move the
    // slider's numeric endpoints. A bounded response follows the finger in either direction.
    CGFloat stretch = _expanded && !SGRReduceMotion() ? _stretch : 0;
    CGFloat extension = fabs(stretch) * 16, width = kSide + fabs(stretch) * 2;
    _panel.frame = CGRectMake((kSide - width) / 2, -extension / 2 + stretch * 6, width, CGRectGetHeight(self.bounds) + extension);
    UIView *glass = SGRGlassCapsuleInside(_panel, &kPanelGlass, _panel.bounds.size, NO);
    UIView *content = glass;
    if ([glass isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *pane = (id)glass;
        if (@available(iOS 26.0, *)) {
            if ([pane.effect isKindOfClass:UIGlassEffect.class] && !((UIGlassEffect *)pane.effect).interactive) {
                UIGlassEffect *effect = [(UIGlassEffect *)pane.effect copy];
                effect.interactive = YES; pane.effect = effect;
            }
        }
        content = pane.contentView;
    }
    glass.userInteractionEnabled = YES;
    glass.accessibilityElementsHidden = NO;
    content.clipsToBounds = YES;
    content.layer.cornerRadius = width / 2;
    for (UIView *view in @[_fill, _button]) if (view.superview != content) [content addSubview:view];
    // Interactive glass exposes its content as an accessibility container. Remove the folded
    // slider from that container instead of leaving a zero-height adjustable element in it.
    if (_expanded) { if (_slider.superview != content) [content insertSubview:_slider belowSubview:_button]; }
    else [_slider removeFromSuperview];
    CGFloat height = CGRectGetHeight(_panel.bounds);
    // The fill rises to the level while Sing is on or getting ready: over the whole button when closed.
    SGRSingLook look = lookOf(_shown);
    CGFloat fill = look.on || look.preparing ? kSide + (height - kSide) * SGSingPositionFromLevel(SGSingVocalLevel()) : 0;
    _fill.frame = CGRectMake(0, height - fill, width, fill);
    _slider.frame = CGRectMake(0, 0, width, height - kSide);
    _button.frame = CGRectMake(0, height - kSide, width, kSide);
    CGRect square = CGRectMake((width - kSide) / 2, 0, kSide, kSide);
    for (UIView *view in @[_ring, _glyph, _glyphOn]) view.frame = square;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(_panel.frame, point);
}

#pragma mark - touches

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (gesture == _outside) return _expanded && ![touch.view isDescendantOfView:self];
    [self interacted];
    SGSingState state = SGSingCurrentState();
    _dragStart = [touch locationInView:self.superview];
    _dragLevel = [touch.view isDescendantOfView:_slider] ?
        SGSingLevelFromPosition(1 - [touch locationInView:_slider].y / MAX(1, _slider.bounds.size.height)) : SGSingVocalLevel();
    return SGSingStateIsOn(state) || state == SGSingPreparing || state == SGSingIdle;
}

- (void)tapped {
    [self interacted];
    SGSingState state = SGSingCurrentState();
    if (state == SGSingFailed) [self showExplanation];
    else if (state == SGSingPreparing || (SGSingStateIsOn(state) && _expanded)) [self turnOff];
    else if (SGSingStateIsOn(state)) self.expanded = YES;
    else if (state == SGSingIdle || state == SGSingDraining) [self turnOn];
}

- (void)turnOn {
    SGSingSetVocalLevel(SGSingReducedLevel());
    SGSingSetEnabled(YES);
    if (SGSingCurrentState() == SGSingFailed) [self showExplanation];
    else self.expanded = YES;
}

- (void)turnOff {
    SGSingSetEnabled(NO);
    self.expanded = NO;
}

// A drag or a long press: opens the capsule, turning Sing on first when it is off.
- (void)expand {
    SGSingState state = SGSingCurrentState();
    if (state == SGSingIdle) [self turnOn];
    else if (SGSingStateIsOn(state) || state == SGSingPreparing) self.expanded = YES;
}

- (void)dragged:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _dragging = YES;
        [self expand];
    }
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) {
        // Measure from touch-down, including the travel before UIPan recognizes the gesture.
        // Stationary page coordinates also keep capsule expansion from changing the value.
        CGFloat travel = [gesture locationInView:self.superview].y - _dragStart.y;
        _stretch = travel / (kSide + fabs(travel));
        _slider.value = _dragLevel - travel * (1 - SGSingMinimumVocalLevel) / 100;
        [self changed];
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        _dragging = NO;
        _stretch = 0;
        [self setNeedsLayout];
        SGRAnimate(SGRMotionLayout, ^{ [self layoutIfNeeded]; }, nil);
    }
}

- (void)held:(UILongPressGestureRecognizer *)gesture {
    [self interacted];
    if (gesture.state == UIGestureRecognizerStateBegan) [self expand];
    if (gesture.state == UIGestureRecognizerStateChanged && SGSingStateIsOn(SGSingCurrentState())) {
        CGPoint point = [gesture locationInView:_slider];
        _slider.value = SGSingLevelFromPosition(1 - point.y / MAX(1, _slider.bounds.size.height));
        [self changed];
    }
}

- (void)changed {
    [self interacted];
    SGSingSetVocalLevel(_slider.value);
}

#pragma mark - explaining

- (UIViewController *)presenter {
    for (UIResponder *r = self; r; r = r.nextResponder) if ([r isKindOfClass:UIViewController.class]) return (id)r;
    return nil;
}

- (void)finishedExplaining {
    _explaining = NO;
    [self updateHold];
}

- (void)showExplanation {
    UIViewController *presenter = [self presenter];
    if (!presenter || presenter.presentedViewController || _explaining) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sing" message:SGSingExplanation() preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weak = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [weak finishedExplaining];
    }]];
    if (SGSingCanRetry()) [alert addAction:[UIAlertAction actionWithTitle:@"Try again" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weak finishedExplaining];
        // Thermal state and the playback route can change while the alert is on screen.
        if (SGSingCanRetry()) [weak turnOn];
    }]];
    if (SGSingCurrentState() == SGSingFailed) [alert addAction:[UIAlertAction actionWithTitle:@"Turn off Sing" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weak finishedExplaining];
        [weak turnOff];
    }]];
    _explaining = YES;
    [self updateHold];   // records the hold, so finishing the explanation releases it
    [presenter presentViewController:alert animated:YES completion:nil];
}

// Taken away with Sing unavailable: its hold goes with it.
- (void)retireFrom:(UIView *)page {
    if (_holding && _hold) _hold(NO);
    _holding = NO;
    [_collapseTimer invalidate];
    _collapseTimer = nil;
    [_outside.view removeGestureRecognizer:_outside];
    [self removeFromSuperview];
    objc_setAssociatedObject(page, &kControlKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

UIView *SGRSingControlForPage(UIView *page, CGRect lyrics, BOOL immersive, void (^hold)(BOOL)) {
    SGRSingControl *control = page ? objc_getAssociatedObject(page, &kControlKey) : nil;
    if (!SGSingAvailable()) {
        [control retireFrom:page];
        return nil;
    }
    if (!page || CGRectIsEmpty(lyrics)) return nil;
    if (!control) {
        control = [[SGRSingControl alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(page, &kControlKey, control, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [page addSubview:control];
        control.outside = [[UITapGestureRecognizer alloc] initWithTarget:control action:@selector(dismissControls)];
        control.outside.cancelsTouchesInView = NO;
        control.outside.delegate = control;
    }
    // The embedded lyrics overlay passes header/transport touches through to its siblings.
    // Observe their shared player surface too, so those touches can collapse the capsule.
    UIView *surface = page.superview ?: page;
    if (control.outside.view != surface) [surface addGestureRecognizer:control.outside];
    control.hold = hold;
    control.immersive = immersive;
    [control updateHold];
    [control updateVisibility];
    // Trailing edge, opposite the pronunciation/translation control in the lyrics viewport.
    control.anchor = CGPointMake(CGRectGetMaxX(lyrics) - 56, CGRectGetMaxY(lyrics) - 56);
    [page bringSubviewToFront:control];
    return control;
}

void SGRSingControlDismiss(UIView *page) {
    SGRSingControl *control = objc_getAssociatedObject(page, &kControlKey);
    [control dismissControls];
}
