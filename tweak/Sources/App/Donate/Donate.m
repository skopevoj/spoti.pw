#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "App/About/About.h"
#import "App/Onboarding/Onboarding.h"
#import "Donate.h"

NSString *const SGKofiURL = @"https://ko-fi.com/darkksh";

// Outside the "spotifyglass." prefix, so Reset all settings does not bring the sheet back early.
static NSString *const kNextKey = @"spotipw.donate.next";
static NSString *const kAfterTourKey = @"spotipw.donate.aftertour";
static const NSTimeInterval kDay = 86400;
static const NSTimeInterval kFirstAsk = 2 * kDay, kEvery = 14 * kDay, kAfterDonating = 90 * kDay;
static const NSTimeInterval kSettle = 20, kRetry = 5;
static const NSInteger kTries = 24;

static UIColor *rgb(uint32_t v, CGFloat alpha) {
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:alpha];
}

UIColor *SGKofiColor(void) { return rgb(0xFF5E5B, 1); }

#pragma mark - button

static const CGFloat kRimWidth = 1.5, kGlowWidth = 6, kGlowRadius = 9, kGlowBleed = 22;
static const CFTimeInterval kTurn = 3.2, kBreath = 1.8;

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

// Ko-fi red most of the way round, with one bright streak that runs along the rim as the colours turn.
static CAGradientLayer *newRimColors(void) {
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.type = kCAGradientLayerConic;
    gradient.startPoint = CGPointMake(0.5, 0.5);
    gradient.endPoint = CGPointMake(0.5, 0);
    gradient.colors = @[(id)rgb(0xFF5E5B, 0.55).CGColor, (id)rgb(0xFF5E5B, 1).CGColor, (id)rgb(0xFFB4A2, 1).CGColor,
                        (id)UIColor.whiteColor.CGColor, (id)rgb(0xFFB4A2, 1).CGColor, (id)rgb(0xFF5E5B, 1).CGColor,
                        (id)rgb(0xFF5E5B, 0.55).CGColor];
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

@implementation SGKofiButton {
    BOOL _prominent;
    UIVisualEffectView *_glass;
    CAGradientLayer *_fill;
    CALayer *_rim, *_glow, *_glowShape;
    CAShapeLayer *_rimMask, *_glowMask;
    CAGradientLayer *_rimColors, *_glowColors;
    UIImpactFeedbackGenerator *_haptic;
}

- (instancetype)initWithTitle:(NSString *)title prominent:(BOOL)prominent {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _prominent = prominent;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = title;

    _glow = [CALayer layer];
    _glowShape = [CALayer layer];
    _glowMask = newStroke(kGlowWidth);
    _glowShape.mask = _glowMask;
    _glowColors = newRimColors();
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
        [(id)effect setTintColor:rgb(0xFF5E5B, 0.85)];
    }
    _glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    _glass.userInteractionEnabled = NO;
    _glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self addSubview:_glass];
    if (prominent && !glass) {
        _fill = [CAGradientLayer layer];
        _fill.colors = @[(id)rgb(0xFF7A73, 1).CGColor, (id)rgb(0xE8434B, 1).CGColor];
        _fill.startPoint = CGPointMake(0, 0);
        _fill.endPoint = CGPointMake(1, 1);
        [self.layer addSublayer:_fill];
    }

    _rim = [CALayer layer];
    _rimMask = newStroke(kRimWidth);
    _rim.mask = _rimMask;
    _rimColors = newRimColors();
    [_rim addSublayer:_rimColors];
    [self.layer addSublayer:_rim];

    UIImageView *cup = SGSymbolView(@"cup.and.saucer.fill", 17, UIImageSymbolWeightSemibold, 24);
    cup.tintColor = prominent ? UIColor.whiteColor : SGKofiColor();
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.8;
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[cup, label]];
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

#pragma mark - schedule

static NSTimeInterval now(void) {
    return NSDate.date.timeIntervalSince1970;
}

static NSTimeInterval nextAsk(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    double next = [store doubleForKey:kNextKey];
    if (next <= 0) {
        next = now() + kFirstAsk;
        [store setDouble:next forKey:kNextKey];
    }
    return next;
}

static void askAgainIn(NSTimeInterval wait) {
    [NSUserDefaults.standardUserDefaults setDouble:now() + wait forKey:kNextKey];
}

BOOL SGDonateAfterTourPending(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:kAfterTourKey];
}

#pragma mark - sheet

static const CGFloat kCardMargin = 10, kCardPadding = 26;

@interface SGDonateController : UIViewController
@end

@implementation SGDonateController {
    UIView *_backdrop, *_card;
    CAGradientLayer *_warmth;
    UIImageView *_cup, *_heart;
    BOOL _leaving;
}

static char kCardGlassKey;

- (instancetype)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    return self;
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

// The cup on a warm Ko-fi disc that glows into the card, with a heart badge on its shoulder.
- (UIView *)hero {
    UIView *disc = [UIView new];
    disc.translatesAutoresizingMaskIntoConstraints = NO;
    CAGradientLayer *fill = [CAGradientLayer layer];
    fill.frame = CGRectMake(0, 0, 80, 80);
    fill.cornerRadius = 40;
    fill.colors = @[(id)rgb(0xFF8A7A, 1).CGColor, (id)rgb(0xE8434B, 1).CGColor];
    fill.startPoint = CGPointMake(0.2, 0);
    fill.endPoint = CGPointMake(0.8, 1);
    [disc.layer addSublayer:fill];
    disc.layer.shadowColor = SGKofiColor().CGColor;
    disc.layer.shadowOpacity = UIAccessibilityIsReduceTransparencyEnabled() ? 0 : 0.75;
    disc.layer.shadowRadius = 24;
    disc.layer.shadowOffset = CGSizeZero;
    disc.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:fill.frame].CGPath;

    _cup = SGSymbolView(@"cup.and.saucer.fill", 32, UIImageSymbolWeightSemibold, 80);
    _cup.tintColor = UIColor.whiteColor;
    _cup.translatesAutoresizingMaskIntoConstraints = NO;
    [disc addSubview:_cup];

    _heart = SGSymbolView(@"heart.fill", 13, UIImageSymbolWeightBold, 28);
    _heart.tintColor = SGKofiColor();
    _heart.backgroundColor = UIColor.whiteColor;
    _heart.layer.cornerRadius = 14;
    _heart.translatesAutoresizingMaskIntoConstraints = NO;
    [disc addSubview:_heart];

    [NSLayoutConstraint activateConstraints:@[
        [disc.widthAnchor constraintEqualToConstant:80],
        [disc.heightAnchor constraintEqualToConstant:80],
        [_cup.centerXAnchor constraintEqualToAnchor:disc.centerXAnchor],
        [_cup.centerYAnchor constraintEqualToAnchor:disc.centerYAnchor],
        [_heart.widthAnchor constraintEqualToConstant:28],
        [_heart.heightAnchor constraintEqualToConstant:28],
        [_heart.trailingAnchor constraintEqualToAnchor:disc.trailingAnchor constant:4],
        [_heart.bottomAnchor constraintEqualToAnchor:disc.bottomAnchor constant:2],
    ]];
    return disc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    _backdrop = [UIView new];
    _backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _backdrop.alpha = 0;
    _backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [_backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(later)]];
    [self.view addSubview:_backdrop];

    _card = [UIView new];
    _card.clipsToBounds = YES;
    _card.layer.cornerRadius = self.cardRadius;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    if (!NSClassFromString(@"UIGlassEffect")) _card.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.6];
    _warmth = [CAGradientLayer layer];
    _warmth.type = kCAGradientLayerRadial;
    _warmth.colors = @[(id)rgb(0xFF5E5B, 0.32).CGColor, (id)rgb(0xFF5E5B, 0).CGColor];
    _warmth.startPoint = CGPointMake(0.5, 0);
    _warmth.endPoint = CGPointMake(1.15, 0.75);
    [_card.layer addSublayer:_warmth];
    [self.view addSubview:_card];

    UIView *hero = [self hero];
    UILabel *eyebrow = [self label:@"A STUDENT PROJECT" font:[UIFont systemFontOfSize:12 weight:UIFontWeightBold] color:SGKofiColor()];
    eyebrow.attributedText = [[NSAttributedString alloc] initWithString:eyebrow.text attributes:@{NSKernAttributeName: @1.4}];
    UILabel *title = [self label:@"Enjoying spoti.pw?" font:[UIFont systemFontOfSize:26 weight:UIFontWeightBold] color:UIColor.whiteColor];
    UILabel *body = [self label:@"I'm a student and I build it for free, in my spare time. If it made your music better, a coffee helps me keep going."
                           font:[UIFont systemFontOfSize:15] color:[UIColor colorWithWhite:1 alpha:0.72]];

    SGKofiButton *donate = [[SGKofiButton alloc] initWithTitle:@"Buy me a coffee" prominent:YES];
    [donate addTarget:self action:@selector(donate) forControlEvents:UIControlEventTouchUpInside];

    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.baseForegroundColor = [UIColor colorWithWhite:1 alpha:0.6];
    config.attributedTitle = [[NSAttributedString alloc] initWithString:@"Maybe later" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]}];
    UIButton *later = [UIButton buttonWithConfiguration:config primaryAction:nil];
    [later addTarget:self action:@selector(later) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[hero, eyebrow, title, body, donate, later]];
    column.axis = UILayoutConstraintAxisVertical;
    column.alignment = UIStackViewAlignmentCenter;
    column.spacing = 8;
    [column setCustomSpacing:22 afterView:hero];
    [column setCustomSpacing:4 afterView:eyebrow];
    [column setCustomSpacing:26 afterView:body];
    [column setCustomSpacing:6 afterView:donate];
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
        [donate.widthAnchor constraintEqualToAnchor:column.widthAnchor],
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
    if (@available(iOS 17.0, *)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self->_cup addSymbolEffect:[NSClassFromString(@"NSSymbolBounceEffect") effect]];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self->_heart addSymbolEffect:[NSClassFromString(@"NSSymbolBounceEffect") effect]];
        });
    }
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

- (void)donate {
    askAgainIn(kAfterDonating);
    SGLog(@"donate: opened Ko-fi");
    [self leaveThen:^{ SGOpenURL(SGKofiURL); }];
}

- (void)later {
    [self leaveThen:nil];
}

@end

#pragma mark - entry

static __weak SGDonateController *sg_sheet;
static BOOL sg_offered;

void SGShowDonateSheet(void) {
    UIViewController *top = SGTopController();
    if (sg_sheet || !top || [top isKindOfClass:UIAlertController.class]) return;
    SGDonateController *sheet = [SGDonateController new];
    sg_sheet = sheet;
    [top presentViewController:sheet animated:NO completion:nil];
}

SGModRow *SGDonateRow(void) {
    SGModRow *row = SGWithSymbol(SGActionRow(@"Support spoti.pw", @"Buy the student behind it a coffee", ^{ SGShowDonateSheet(); }), @"cup.and.saucer.fill");
    row.color = SGKofiColor();
    return row;
}

// Never over the tour or an alert. On schedule it also stays out of an update-notice run and asks once
// a run; after a tour, first or replayed from the Mod page, it always comes.
static void offerWhenClear(NSInteger tries) {
    BOOL afterTour = SGDonateAfterTourPending();
    if (!afterTour && (sg_offered || now() < nextAsk() || SGUpdateNoticeShown())) return;
    UIViewController *top = SGTopController();
    BOOL busy = !top || SGOnboardingShowing() || [top isKindOfClass:UIAlertController.class]
        || UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
    if (busy) {
        if (tries > 0)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ offerWhenClear(tries - 1); });
        return;
    }
    sg_offered = YES;
    askAgainIn(kEvery);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kAfterTourKey];
    SGShowDonateSheet();
    SGLog(@"donate: asked over %@%@", NSStringFromClass(top.class), afterTour ? @", after the tour" : @"");
}

void SGDonateAfterTour(BOOL restarting) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kAfterTourKey];
    if (!restarting) SGOfferDonate();
}

void SGOfferDonate(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ offerWhenClear(kTries); });
}

void SGWatchForDonate(void) {
    nextAsk();
    __block id observer = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                          object:nil
                                                                           queue:NSOperationQueue.mainQueue
                                                                      usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ offerWhenClear(kTries); });
    }];
}
