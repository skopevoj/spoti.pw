#import "Core/SGCore.h"
#import "SGRSingControl.h"
#import "Shared/Sing/SGSingController.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRTokens.h"

static char kControlKey, kPanelGlass;

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
    if (_value > 0.995f) _value = 1;
}
- (void)accessibilityIncrement {
    if (!self.enabled) return;
    self.value += 0.1f;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)accessibilityDecrement {
    if (!self.enabled) return;
    self.value -= 0.1f;
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
@interface SGRSingControl : UIView <UIGestureRecognizerDelegate>
@property (nonatomic) UIButton *button, *off;
@property (nonatomic) UIView *panel, *fill;
@property (nonatomic) SGRVocalSlider *slider;
@property (nonatomic) UIActivityIndicatorView *spinner;
@property (nonatomic) UILabel *status;
@property (nonatomic) SGRVocalPan *pan;
@property (nonatomic) float dragLevel;
@property (nonatomic) CGPoint dragStart;
@property (nonatomic) CGFloat stretch;
@property (nonatomic) BOOL dragging;
@property (nonatomic) BOOL expanded, explaining;
@property (nonatomic) BOOL immersive, holding, wasActive;
@property (nonatomic) CFTimeInterval collapseDeadline;
@property (nonatomic) NSTimer *collapseTimer;
@property (nonatomic) CGPoint anchor;
@property (nonatomic, copy) void (^hold)(BOOL);
@property (nonatomic) UITapGestureRecognizer *outside;
- (void)refresh;
- (void)updateHold;
@end
@implementation SGRSingControl
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _button = [UIButton buttonWithType:UIButtonTypeSystem];
    _button.accessibilityIdentifier = @"sing.microphone";
    [_button addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [_button addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.userInteractionEnabled = NO;
    [_button addSubview:_spinner];
    _panel = [UIView new];
    _panel.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self addSubview:_panel];
    _panel.clipsToBounds = NO;
    _panel.layer.cornerRadius = 22;
    _pan = [[SGRVocalPan alloc] initWithTarget:self action:@selector(dragged:)];
    _pan.delegate = self;
    _pan.maximumNumberOfTouches = 1;
    [_panel addGestureRecognizer:_pan];
    _fill = [UIView new];
    _fill.userInteractionEnabled = NO;
    _fill.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.88];
    [_panel addSubview:_fill];
    _slider = [SGRVocalSlider new];
    _slider.accessibilityLabel = @"Vocal volume";
    _slider.accessibilityHint = @"Original vocals at the top, 20 percent at the bottom";
    _slider.accessibilityIdentifier = @"sing.vocalLevel";
    [_slider addTarget:self action:@selector(changed) forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:_slider];
    [_panel addSubview:_button];
    _off = [UIButton buttonWithType:UIButtonTypeSystem];
    [_off setTitle:@"Off" forState:UIControlStateNormal];
    _off.tintColor = SGRSecondary();
    _off.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _off.titleLabel.adjustsFontForContentSizeCategory = YES;
    _off.accessibilityIdentifier = @"sing.level";
    _off.accessibilityLabel = @"Turn off Sing";
    [_off addTarget:self action:@selector(turnOff) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_off];
    _status = [UILabel new];
    _status.accessibilityIdentifier = @"sing.status";
    _status.textColor = SGRPrimary();
    _status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _status.adjustsFontForContentSizeCategory = YES;
    _status.textAlignment = NSTextAlignmentRight;
    _status.numberOfLines = 2;
    _status.userInteractionEnabled = NO;
    [self addSubview:_status];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:SGSingDidChangeNotification object:nil];
    [self refresh];
    return self;
}
- (void)dealloc { [_collapseTimer invalidate]; [_outside.view removeGestureRecognizer:_outside]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)updateHold {
    SGSingState state = SGSingCurrentState();
    BOOL held = _expanded || _explaining || state == SGSingPreparing || state == SGSingDraining;
    if (!_hold) return;
    // Re-layout of a collapsed control must not keep restarting the lyrics' inactivity clock.
    if (held || held != _holding) _hold(held);
    _holding = held;
}
- (void)interacted { _collapseDeadline = CACurrentMediaTime() + 3; }
- (void)checkIdle {
    if (!_expanded || !self.window) { [_collapseTimer invalidate]; _collapseTimer = nil; return; }
    if ((SGSingCurrentState() != SGSingActive && SGSingCurrentState() != SGSingReady && SGSingCurrentState() != SGSingRecovering) || _dragging || _slider.tracking || _button.tracking || UIAccessibilityIsVoiceOverRunning()) return;
    for (UIGestureRecognizer *gesture in _button.gestureRecognizers)
        if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) return;
    if (CACurrentMediaTime() >= _collapseDeadline) self.expanded = NO;
}
- (void)updateVisibility {
    BOOL visible = !_immersive || SGSingCurrentState() == SGSingActive || SGSingCurrentState() == SGSingReady || SGSingCurrentState() == SGSingRecovering;
    self.alpha = visible ? 1 : 0;
    self.accessibilityElementsHidden = !visible;
}
- (void)setExpanded:(BOOL)expanded {
    if (_expanded == expanded) return;
    _expanded = expanded;
    [_collapseTimer invalidate]; _collapseTimer = nil;
    if (expanded) {
        [self interacted];
        __weak typeof(self) weak = self;
        _collapseTimer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) { [weak checkIdle]; }];
        [NSRunLoop.mainRunLoop addTimer:_collapseTimer forMode:NSRunLoopCommonModes];
    }
    [self updateHold];
    // Keep the microphone anchored while the capsule grows above it. Direct dragging always
    // tracks the finger immediately; only discrete open/close actions use the project's motion.
    [self setNeedsLayout];
    if (_dragging || !self.window) [self layoutIfNeeded];
    else SGRAnimate(SGRMotionLayout, ^{ [self layoutIfNeeded]; }, nil);
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(_panel.frame, point) || (_expanded && CGRectContainsPoint(_off.frame, point));
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (gesture == _outside) return _expanded && ![touch.view isDescendantOfView:self];
    [self interacted];
    SGSingState state = SGSingCurrentState();
    _dragStart = [touch locationInView:self.superview];
    _dragLevel = [touch.view isDescendantOfView:_slider] ?
        SGSingLevelFromPosition(1 - [touch locationInView:_slider].y / MAX(1, _slider.bounds.size.height)) : SGSingVocalLevel();
    return state == SGSingActive || state == SGSingReady || state == SGSingRecovering || state == SGSingPreparing || state == SGSingIdle;
}
- (void)dismissControls { self.expanded = NO; }
- (void)relax {
    _stretch = 0;
    [self setNeedsLayout];
    SGRAnimate(SGRMotionLayout, ^{ [self layoutIfNeeded]; }, nil);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = _expanded ? 196 : 44;
    self.frame = CGRectMake(_anchor.x, _anchor.y + 44 - height, 44, height);
    // The value uses stationary page coordinates; stretching the glass must never move the
    // slider's numeric endpoints. A bounded response follows the finger in either direction.
    CGFloat stretch = _expanded && !SGRReduceMotion() ? _stretch : 0;
    CGFloat extension = fabs(stretch) * 16, width = 44 + fabs(stretch) * 2;
    _panel.frame = CGRectMake((44 - width) / 2, (_expanded ? 52 : 0) - extension / 2 + stretch * 6,
                             width, (_expanded ? 144 : 44) + extension);
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
    CGFloat level = SGSingVocalLevel();
    BOOL active = SGSingCurrentState() == SGSingActive || SGSingCurrentState() == SGSingReady || SGSingCurrentState() == SGSingRecovering;
    BOOL preparing = SGSingCurrentState() == SGSingPreparing;
    BOOL reducing = active && level < 1;
    CGFloat fill = _expanded && (active || preparing) ? 44 + (CGRectGetHeight(_panel.bounds) - 44) * SGSingPositionFromLevel(level) : reducing ? 44 : 0;
    _fill.frame = CGRectMake(0, CGRectGetHeight(_panel.bounds) - fill, width, fill);
    _slider.frame = CGRectMake(0, 0, width, CGRectGetHeight(_panel.bounds) - 44);
    _slider.hidden = !_expanded;
    _button.frame = CGRectMake(0, CGRectGetHeight(_panel.bounds) - 44, width, 44);
    _button.tintColor = fill >= 44 ? [UIColor colorWithWhite:0.12 alpha:1] : SGRPrimary();
    _spinner.color = _button.tintColor;
    _spinner.center = CGPointMake(width / 2, 22);
    _off.frame = CGRectMake(0, CGRectGetMinY(_panel.frame) - 52, 44, 44);
    _off.hidden = !_expanded;
    CGSize statusSize = [_status sizeThatFits:CGSizeMake(180, 60)];
    _status.hidden = !_status.text.length || (!_expanded && (SGSingCurrentState() == SGSingReady || SGSingCurrentState() == SGSingRecovering));
    _status.frame = CGRectMake(-statusSize.width - 12, height - 22 - statusSize.height / 2, statusSize.width, statusSize.height);
}
- (void)refresh {
    SGSingState state = SGSingCurrentState();
    BOOL preparing = state == SGSingPreparing;
    BOOL ready = state == SGSingReady;
    BOOL recovering = state == SGSingRecovering;
    BOOL active = state == SGSingActive || ready || recovering;
    BOOL draining = state == SGSingDraining;
    if (active && !_wasActive) [self interacted];
    _wasActive = active;
    _button.enabled = YES;
    _slider.enabled = active || preparing;
    _slider.value = SGSingVocalLevel();
    _slider.accessibilityValue = _slider.value >= 1 ? @"Original" : [NSString stringWithFormat:@"%.0f percent", _slider.value * 100];
    [_button setImage:preparing || draining || recovering ? nil : singGlyph() forState:UIControlStateNormal];
    // The capsule draws selection itself. UIButton's selected appearance adds another opaque
    // background over the white fill, so expose selection to accessibility without that styling.
    _button.accessibilityTraits = UIAccessibilityTraitButton | (active && _slider.value < 1 ? UIAccessibilityTraitSelected : 0);
    _button.accessibilityLabel = @"Vocal volume";
    _button.accessibilityValue = preparing ? @"Preparing Sing" : recovering ? @"Restoring Sing" : draining ? @"Turning Sing off" : state == SGSingFailed ? @"Sing stopped" : active ? _slider.accessibilityValue : state == SGSingUnavailable ? @"Unavailable" : @"Off";
    _button.accessibilityHint = preparing ? @"Tap to cancel" : draining ? @"Tap to turn Sing back on" : active ? @"Drag to adjust vocals. Tap for controls or to hear original vocals." : @"Reduce the song's vocals on this iPhone.";
    NSString *percentage = [NSString stringWithFormat:@"%.0f%%", _slider.value * 100];
    [_off setTitle:preparing ? @"Cancel" : active ? percentage : @"Off" forState:UIControlStateNormal];
    _off.accessibilityLabel = preparing ? @"Cancel Sing" : @"Turn off Sing";
    _off.accessibilityValue = active ? _slider.accessibilityValue : nil;
    _status.text = preparing ? @"Preparing Sing…" : recovering ? @"Restoring Sing…" : ready ? @"Ready when you play" : draining ? @"Turning Sing off…" : nil;
    _status.hidden = !_status.text.length;
    if (preparing || draining || recovering) [_spinner startAnimating]; else [_spinner stopAnimating];
    if (preparing) self.expanded = YES;
    if (!active && !preparing) self.expanded = NO;
    [self updateHold];
    [self updateVisibility];
    [self setNeedsLayout];
    if (_dragging) [self layoutIfNeeded];
}
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
        if (SGSingCanRetry()) SGSingSetEnabled(YES);
    }]];
    if (SGSingCurrentState() == SGSingFailed) [alert addAction:[UIAlertAction actionWithTitle:@"Turn off Sing" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weak finishedExplaining];
        SGSingSetEnabled(NO);
        weak.expanded = NO;
    }]];
    _explaining = YES;
    if (_hold) _hold(YES);
    [presenter presentViewController:alert animated:YES completion:nil];
}
- (void)tapped {
    [self interacted];
    SGSingState state = SGSingCurrentState();
    if (state == SGSingUnavailable || state == SGSingFailed) {
        [self showExplanation];
    } else if (state == SGSingActive || state == SGSingReady || state == SGSingRecovering) {
        if (!_expanded) { [self expand]; return; }
        float level = SGSingVocalLevel();
        if (level < 1) SGSingSetVocalLevel(1);
        else SGSingSetVocalLevel(SGSingReducedLevel());
        [self expand];
    } else if (state == SGSingPreparing) {
        [self turnOff];
    } else if (state == SGSingIdle || state == SGSingDraining) {
        SGSingSetVocalLevel(SGSingReducedLevel()); SGSingSetEnabled(YES);
        if (SGSingCurrentState() == SGSingFailed) [self showExplanation];
    }
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
        _stretch = travel / (44 + fabs(travel));
        _slider.value = _dragLevel - travel * (1 - SGSingMinimumVocalLevel) / 100;
        [self changed];
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        _dragging = NO;
        [self refresh];
        [self relax];
    }
}
- (void)held:(UILongPressGestureRecognizer *)gesture {
    [self interacted];
    if (gesture.state == UIGestureRecognizerStateBegan) [self expand];
    if (gesture.state == UIGestureRecognizerStateChanged && (SGSingCurrentState() == SGSingActive || SGSingCurrentState() == SGSingReady || SGSingCurrentState() == SGSingRecovering)) {
        CGPoint point = [gesture locationInView:_slider];
        _slider.value = SGSingLevelFromPosition(1 - point.y / MAX(1, _slider.bounds.size.height));
        [self changed];
    }
}
- (void)expand {
    if (SGSingCurrentState() == SGSingIdle) { SGSingSetVocalLevel(SGSingReducedLevel()); SGSingSetEnabled(YES); }
    if (SGSingCurrentState() != SGSingActive && SGSingCurrentState() != SGSingReady && SGSingCurrentState() != SGSingRecovering && SGSingCurrentState() != SGSingPreparing) return;
    self.expanded = YES;
}
- (void)changed {
    [self interacted];
    SGSingSetVocalLevel(_slider.value);
}
- (void)turnOff { SGSingSetEnabled(NO); self.expanded = NO; }
@end
UIView *SGRSingControlForPage(UIView *page, UIView *host, BOOL immersive, void (^hold)(BOOL)) {
    if (!SGSingConfigured() || !host) return nil;
    SGRSingControl *control = objc_getAssociatedObject(page, &kControlKey);
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
    CGRect lyrics = [host convertRect:host.bounds toView:page];
    // Trailing edge, opposite the pronunciation/translation control in the lyrics viewport.
    control.anchor = CGPointMake(CGRectGetMaxX(lyrics) - 56, CGRectGetMaxY(lyrics) - 56);
    [control setNeedsLayout];
    [page bringSubviewToFront:control];
    return control;
}

void SGRSingControlDismiss(UIView *page) {
    SGRSingControl *control = objc_getAssociatedObject(page, &kControlKey);
    [control dismissControls];
}
