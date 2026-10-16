#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "SGCardSheet.h"

UIColor *SGColorHex(uint32_t v, CGFloat alpha) {
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:alpha];
}

static UIColor *mix(UIColor *color, UIColor *with, CGFloat amount, CGFloat alpha) {
    CGFloat r, g, b, a, r2, g2, b2, a2;
    [color getRed:&r green:&g blue:&b alpha:&a];
    [with getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return [UIColor colorWithRed:r + (r2 - r) * amount green:g + (g2 - g) * amount blue:b + (b2 - b) * amount alpha:alpha];
}

#pragma mark - button

static const CGFloat kRimWidth = 1.5, kGlowWidth = 6, kGlowRadius = 9, kGlowBleed = 22;
static const CFTimeInterval kTurn = 3.2, kBreath = 1.8;

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

// The colour most of the way round, with one bright streak that runs along the rim as the colours turn.
static CAGradientLayer *newRimColors(UIColor *color) {
    UIColor *light = mix(color, UIColor.whiteColor, 0.55, 1);
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.type = kCAGradientLayerConic;
    gradient.startPoint = CGPointMake(0.5, 0.5);
    gradient.endPoint = CGPointMake(0.5, 0);
    gradient.colors = @[(id)[color colorWithAlphaComponent:0.55].CGColor, (id)color.CGColor, (id)light.CGColor,
                        (id)UIColor.whiteColor.CGColor, (id)light.CGColor, (id)color.CGColor,
                        (id)[color colorWithAlphaComponent:0.55].CGColor];
    gradient.locations = @[@0, @0.5, @0.64, @0.72, @0.8, @0.9, @1];
    return gradient;
}

static CAShapeLayer *newStroke(CGFloat width) {
    CAShapeLayer *stroke = [CAShapeLayer layer];
    stroke.fillColor = UIColor.clearColor.CGColor;
    stroke.strokeColor = UIColor.blackColor.CGColor;
    stroke.lineWidth = width;
    return stroke;
}

@implementation SGGlowButton {
    BOOL _prominent;
    UIVisualEffectView *_glass;
    CAGradientLayer *_fill;
    CALayer *_rim, *_glow, *_glowShape;
    CAShapeLayer *_rimMask, *_glowMask;
    CAGradientLayer *_rimColors, *_glowColors;
    UIImpactFeedbackGenerator *_haptic;
}

- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol color:(UIColor *)color prominent:(BOOL)prominent {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _prominent = prominent;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = title;

    _glow = [CALayer layer];
    _glowShape = [CALayer layer];
    _glowMask = newStroke(kGlowWidth);
    _glowShape.mask = _glowMask;
    _glowColors = newRimColors(color);
    [_glowShape addSublayer:_glowColors];
    [_glow addSublayer:_glowShape];
    Class filter = NSClassFromString(@"CAFilter");
    CAFilter *blur = [filter respondsToSelector:@selector(filterWithType:)] ? [filter filterWithType:@"gaussianBlur"] : nil;
    if (blur) {
        [blur setValue:@(kGlowRadius) forKey:@"inputRadius"];
        _glow.filters = @[blur];
    }
    [self.layer addSublayer:_glow];

    UIVisualEffect *effect = SGGlassEffect();
    BOOL glass = NSClassFromString(@"UIGlassEffect") && [effect respondsToSelector:@selector(setTintColor:)];
    if (glass && prominent) {
        effect = [NSClassFromString(@"UIGlassEffect") effectWithStyle:0];
        [(id)effect setTintColor:[color colorWithAlphaComponent:0.85]];
    }
    _glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    _glass.userInteractionEnabled = NO;
    _glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self addSubview:_glass];
    if (prominent && !glass) {
        _fill = [CAGradientLayer layer];
        _fill.colors = @[(id)mix(color, UIColor.whiteColor, 0.12, 1).CGColor, (id)mix(color, UIColor.blackColor, 0.1, 1).CGColor];
        _fill.startPoint = CGPointMake(0, 0);
        _fill.endPoint = CGPointMake(1, 1);
        [self.layer addSublayer:_fill];
    }

    _rim = [CALayer layer];
    _rimMask = newStroke(kRimWidth);
    _rim.mask = _rimMask;
    _rimColors = newRimColors(color);
    [_rim addSublayer:_rimColors];
    [self.layer addSublayer:_rim];

    UIImageView *glyph = SGSymbolView(symbol, 17, UIImageSymbolWeightSemibold, 24);
    glyph.tintColor = prominent ? UIColor.whiteColor : color;
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.8;
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[glyph, label]];
    content.alignment = UIStackViewAlignmentCenter;
    content.spacing = 8;
    content.userInteractionEnabled = NO;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:22],
        [content.topAnchor constraintEqualToAnchor:self.topAnchor constant:prominent ? 16 : 13],
        [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:prominent ? -16 : -13],
    ]];
    // Hugs its content unless its host stretches it.
    NSLayoutConstraint *hug = [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:22];
    hug.priority = UILayoutPriorityDefaultLow;
    hug.active = YES;

    _haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)tapped {
    [_haptic impactOccurred];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat radius = bounds.size.height / 2;
    _glass.frame = bounds;
    SGShapeGlass(_glass, radius, YES);
    UIBezierPath *capsule = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(bounds, kRimWidth / 2, kRimWidth / 2) cornerRadius:radius];
    CGFloat side = ceil(hypot(bounds.size.width, bounds.size.height)) + 2;
    CGRect square = CGRectMake(CGRectGetMidX(bounds) - side / 2, CGRectGetMidY(bounds) - side / 2, side, side);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.frame = bounds;
    _fill.cornerRadius = radius;
    _rim.frame = bounds;
    _rimMask.frame = bounds;
    _rimMask.path = capsule.CGPath;
    _rimColors.frame = square;
    _glow.frame = CGRectInset(bounds, -kGlowBleed, -kGlowBleed);
    _glowShape.frame = _glow.bounds;
    _glowMask.frame = _glow.bounds;
    UIBezierPath *glowPath = [capsule copy];
    [glowPath applyTransform:CGAffineTransformMakeTranslation(kGlowBleed, kGlowBleed)];
    _glowMask.path = glowPath.CGPath;
    _glowColors.frame = CGRectOffset(square, kGlowBleed, kGlowBleed);
    [CATransaction commit];
}

- (void)setHighlighted:(BOOL)highlighted {
    BOOL changed = highlighted != self.highlighted;
    [super setHighlighted:highlighted];
    if (!changed) return;
    [UIView animateWithDuration:highlighted ? 0.18 : 0.45 delay:0 usingSpringWithDamping:highlighted ? 1 : 0.55
          initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.95, 0.95) : CGAffineTransformIdentity;
    } completion:nil];
}

- (void)updateMotion {
    _glow.hidden = UIAccessibilityIsReduceTransparencyEnabled();
    BOOL moving = self.window && !UIAccessibilityIsReduceMotionEnabled();
    for (CAGradientLayer *colors in @[_rimColors, _glowColors]) {
        if (!moving) {
            [colors removeAllAnimations];
            continue;
        }
        if ([colors animationForKey:@"turn"]) continue;
        CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        turn.fromValue = @0;
        turn.toValue = @(M_PI * 2);
        turn.duration = kTurn;
        turn.repeatCount = HUGE_VALF;
        [colors addAnimation:turn forKey:@"turn"];
    }
    if (!moving) {
        [_glow removeAllAnimations];
        _glow.opacity = _prominent ? 0.8 : 0.6;
        return;
    }
    if ([_glow animationForKey:@"breathe"]) return;
    CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"opacity"];
    breathe.fromValue = @(_prominent ? 0.55 : 0.35);
    breathe.toValue = @1;
    breathe.duration = kBreath;
    breathe.autoreverses = YES;
    breathe.repeatCount = HUGE_VALF;
    breathe.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_glow addAnimation:breathe forKey:@"breathe"];
}

// Backgrounding drops layer animations; they start again on the way back.
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    if (self.window) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateMotion) name:UIApplicationWillEnterForegroundNotification object:nil];
    [self updateMotion];
}

@end

#pragma mark - disc

UIView *SGCardSheetDisc(UIColor *top, UIColor *bottom, UIColor *glow) {
    UIView *disc = [UIView new];
    disc.translatesAutoresizingMaskIntoConstraints = NO;
    CAGradientLayer *fill = [CAGradientLayer layer];
    fill.frame = CGRectMake(0, 0, 80, 80);
    fill.cornerRadius = 40;
    fill.colors = @[(id)top.CGColor, (id)bottom.CGColor];
    fill.startPoint = CGPointMake(0.2, 0);
    fill.endPoint = CGPointMake(0.8, 1);
    [disc.layer addSublayer:fill];
    disc.layer.shadowColor = glow.CGColor;
    disc.layer.shadowOpacity = UIAccessibilityIsReduceTransparencyEnabled() ? 0 : 0.75;
    disc.layer.shadowRadius = 24;
    disc.layer.shadowOffset = CGSizeZero;
    disc.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:fill.frame].CGPath;
    [NSLayoutConstraint activateConstraints:@[
        [disc.widthAnchor constraintEqualToConstant:80],
        [disc.heightAnchor constraintEqualToConstant:80],
    ]];
    return disc;
}

#pragma mark - sheet

static const CGFloat kCardMargin = 10, kCardPadding = 26;
static char kCardGlassKey;
static __weak SGCardSheet *sg_showing;

@implementation SGCardSheet {
    UIView *_backdrop, *_card;
    CAGradientLayer *_warmth;
    BOOL _leaving;
}

- (instancetype)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    return self;
}

- (void)present {
    UIViewController *top = SGTopController();
    if (sg_showing || !top || [top isKindOfClass:UIAlertController.class]) return;
    sg_showing = self;
    [top presentViewController:self animated:NO completion:nil];
}

- (CGFloat)cardRadius {
    if (@available(iOS 26.0, *)) return 44;
    return 28;
}

- (UILabel *)label:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    return label;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    UIColor *color = self.color ?: UIColor.systemBlueColor;

    _backdrop = [UIView new];
    _backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _backdrop.alpha = 0;
    _backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [_backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissCard)]];
    [self.view addSubview:_backdrop];

    _card = [UIView new];
    _card.clipsToBounds = YES;
    _card.layer.cornerRadius = self.cardRadius;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    if (!NSClassFromString(@"UIGlassEffect")) _card.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.6];
    _warmth = [CAGradientLayer layer];
    _warmth.type = kCAGradientLayerRadial;
    _warmth.colors = @[(id)[color colorWithAlphaComponent:0.32].CGColor, (id)[color colorWithAlphaComponent:0].CGColor];
    _warmth.startPoint = CGPointMake(0.5, 0);
    _warmth.endPoint = CGPointMake(1.15, 0.75);
    [_card.layer addSublayer:_warmth];
    [self.view addSubview:_card];

    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    if (self.hero) [rows addObject:self.hero];
    UILabel *eyebrow = nil;
    if (self.eyebrow.length) {
        eyebrow = [self label:nil font:[UIFont systemFontOfSize:12 weight:UIFontWeightBold] color:color];
        eyebrow.attributedText = [[NSAttributedString alloc] initWithString:self.eyebrow attributes:@{NSKernAttributeName: @1.4}];
        [rows addObject:eyebrow];
    }
    UILabel *title = [self label:self.heading font:[UIFont systemFontOfSize:26 weight:UIFontWeightBold] color:UIColor.whiteColor];
    UILabel *body = [self label:self.body font:[UIFont systemFontOfSize:15] color:[UIColor colorWithWhite:1 alpha:0.72]];
    SGGlowButton *act = [[SGGlowButton alloc] initWithTitle:self.actionTitle symbol:self.actionSymbol color:color prominent:YES];
    [act addTarget:self action:@selector(act) forControlEvents:UIControlEventTouchUpInside];

    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.baseForegroundColor = [UIColor colorWithWhite:1 alpha:0.6];
    config.attributedTitle = [[NSAttributedString alloc] initWithString:self.dismissTitle ?: @"Not now"
                                                             attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]}];
    UIButton *later = [UIButton buttonWithConfiguration:config primaryAction:nil];
    [later addTarget:self action:@selector(dismissCard) forControlEvents:UIControlEventTouchUpInside];
    [rows addObjectsFromArray:@[title, body, act, later]];
    UILabel *note = nil;
    if (self.note.length) {
        note = [self label:self.note font:[UIFont systemFontOfSize:12] color:[UIColor colorWithWhite:1 alpha:0.4]];
        [rows addObject:note];
    }

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:rows];
    column.axis = UILayoutConstraintAxisVertical;
    column.alignment = UIStackViewAlignmentCenter;
    column.spacing = 8;
    if (self.hero) [column setCustomSpacing:22 afterView:self.hero];
    if (eyebrow) [column setCustomSpacing:4 afterView:eyebrow];
    [column setCustomSpacing:26 afterView:body];
    [column setCustomSpacing:6 afterView:act];
    if (note) [column setCustomSpacing:2 afterView:later];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:column];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_backdrop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_backdrop.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_backdrop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_backdrop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_card.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:kCardMargin],
        [_card.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-kCardMargin],
        [_card.widthAnchor constraintLessThanOrEqualToConstant:460],
        [_card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_card.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-kCardMargin],
        [_card.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:kCardMargin],
        [column.topAnchor constraintEqualToAnchor:_card.topAnchor constant:36],
        [column.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:kCardPadding],
        [column.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-kCardPadding],
        [column.bottomAnchor constraintLessThanOrEqualToAnchor:_card.bottomAnchor constant:-kCardPadding],
        [act.widthAnchor constraintEqualToAnchor:column.widthAnchor],
        [body.widthAnchor constraintLessThanOrEqualToAnchor:column.widthAnchor],
    ]];
    // Clear of the home indicator; without one the card's own padding wins.
    NSLayoutConstraint *indicator = [column.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8];
    indicator.priority = UILayoutPriorityDefaultHigh;
    indicator.active = YES;
    _card.transform = CGAffineTransformMakeTranslation(0, 700);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIVisualEffectView *pane = SGGlassFor(_card, &kCardGlassKey);
    pane.frame = _card.bounds;
    SGShapeGlass(pane, self.cardRadius, NO);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _warmth.frame = _card.bounds;
    [CATransaction commit];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [UIView animateWithDuration:0.3 animations:^{ self->_backdrop.alpha = 1; }];
    [UIView animateWithDuration:0.62 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_card.transform = CGAffineTransformIdentity;
    } completion:nil];
    if (self.appeared) self.appeared();
}

- (void)leaveThen:(void (^)(void))then {
    if (_leaving) return;
    _leaving = YES;
    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_backdrop.alpha = 0;
        self->_card.transform = CGAffineTransformMakeTranslation(0, self->_card.bounds.size.height + 40);
    } completion:^(BOOL finished) {
        [self dismissViewControllerAnimated:NO completion:then];
    }];
}

- (void)act {
    [self leaveThen:self.action];
}

- (void)dismissCard {
    [self leaveThen:nil];
}

@end
