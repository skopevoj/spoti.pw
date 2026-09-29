#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Onboarding.h"
#import "App/About/About.h"
#import "App/Pages.h"
#import "App/Donate/Donate.h"

static const CGFloat kMargin = 24;
static const CGFloat kCardRadius = 22;

#pragma mark - glass

// A view whose glass pane follows its bounds; the panes in SGGlass.m are laid out by their hosts.
@interface SGGlassView : UIView
@property (nonatomic) CGFloat radius;
@property (nonatomic) BOOL capsule;
@end

@implementation SGGlassView
static char kPaneKey;
- (void)layoutSubviews {
    [super layoutSubviews];
    UIVisualEffectView *pane = SGGlassFor(self, &kPaneKey);
    pane.frame = self.bounds;
    SGShapeGlass(pane, self.radius, self.capsule);
}
@end

static UIButton *glassButton(NSString *title) {
    UIButtonConfiguration *config;
    if (@available(iOS 26.0, *)) config = [UIButtonConfiguration prominentGlassButtonConfiguration];
    else config = [UIButtonConfiguration filledButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.baseBackgroundColor = SGGreen();
    config.baseForegroundColor = UIColor.blackColor;
    config.contentInsets = NSDirectionalEdgeInsetsMake(15, 20, 15, 20);
    config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]}];
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

#pragma mark - the choice

// One of the two looks, as a glass card: symbol, name, a line on what it brings, and a check
// when it is the one picked.
@interface SGLookCard : UIControl
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle;
// A look this phone cannot run: the card stays on the page, greyed and untappable, and says why.
- (void)makeUnavailable:(NSString *)reason;
@end

@implementation SGLookCard {
    SGGlassView *_glass;
    UIImageView *_check;
    UILabel *_line;
}

- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    UIImageView *icon = SGSymbolView(symbol, 17, UIImageSymbolWeightSemibold, 36);
    icon.tintColor = UIColor.whiteColor;
    icon.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    icon.layer.cornerRadius = 10;
    icon.layer.cornerCurve = kCACornerCurveContinuous;

    UILabel *name = [UILabel new];
    name.text = title;
    name.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    name.textColor = UIColor.whiteColor;
    UILabel *line = [UILabel new];
    line.text = subtitle;
    line.font = [UIFont systemFontOfSize:13];
    line.textColor = SGGrey();
    line.numberOfLines = 0;
    _line = line;
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[name, line]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;

    _check = SGSymbolView(@"circle", 22, UIImageSymbolWeightRegular, 26);

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text, _check]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 14;
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [text setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh - 1 forAxis:UILayoutConstraintAxisHorizontal];

    _glass = [SGGlassView new];
    _glass.radius = kCardRadius;
    _glass.userInteractionEnabled = NO;
    _glass.translatesAutoresizingMaskIntoConstraints = NO;
    self.clipsToBounds = YES;
    self.layer.cornerRadius = kCardRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderColor = SGGreen().CGColor;
    [self addSubview:_glass];
    [self addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [_glass.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [icon.widthAnchor constraintEqualToConstant:36],
        [icon.heightAnchor constraintEqualToConstant:36],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16],
    ]];
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    _check.image = [UIImage systemImageNamed:selected ? @"checkmark.circle.fill" : @"circle"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular]];
    _check.tintColor = selected ? SGGreen() : SGGrey();
    self.layer.borderWidth = selected ? 2 : 0;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (self.enabled) self.alpha = highlighted ? 0.6 : 1;
}

- (void)makeUnavailable:(NSString *)reason {
    self.selected = NO;
    self.enabled = NO;
    self.alpha = 0.45;
    _line.text = reason;
    _check.image = [UIImage systemImageNamed:@"lock.fill"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]];
    _check.tintColor = SGGrey();
}

@end

#pragma mark - the tour

// One page, the one choice worth making now: the redesign or Spotify's own look. Everything else
// waits in Mod Settings.
@interface SGOnboardingController : UIViewController
@end

@implementation SGOnboardingController {
    UIImageView *_hero;
    SGLookCard *_redesigned, *_legacy;
    UIView *_beta;
    UIButton *_primary;
}

- (instancetype)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    return self;
}

// Under the cards while the redesign is picked: it is a beta, and a bug report is the way to help.
- (UIView *)betaNote {
    UIImageView *icon = SGSymbolView(@"exclamationmark.triangle.fill", 15, UIImageSymbolWeightSemibold, 22);
    icon.tintColor = UIColor.systemYellowColor;
    UILabel *text = [UILabel new];
    text.text = @"The redesign is a beta. Expect lags, freezes and bugs, and if you find one, please report it.";
    text.font = [UIFont systemFontOfSize:13];
    text.textColor = SGGrey();
    text.numberOfLines = 0;
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text]];
    line.alignment = UIStackViewAlignmentTop;
    line.spacing = 10;

    UIButton *(^link)(NSString *, CGFloat, NSString *) = ^UIButton *(NSString *title, CGFloat lead, NSString *url) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.contentInsets = NSDirectionalEdgeInsetsMake(4, lead, 4, 0);
        config.baseForegroundColor = SGGreen();
        config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]}];
        return [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
            SGOpenURL(url);
        }]];
    };
    UIStackView *links = [[UIStackView alloc] initWithArrangedSubviews:@[
        link(@"Report a bug", 32, [SGRepoURL stringByAppendingString:@"/issues"]),
        link(@"Ask on Discord", 16, SGDiscordURL),
    ]];

    UIStackView *note = [[UIStackView alloc] initWithArrangedSubviews:@[line, links]];
    note.axis = UILayoutConstraintAxisVertical;
    note.alignment = UIStackViewAlignmentLeading;
    note.spacing = 2;
    note.layoutMargins = UIEdgeInsetsMake(4, 4, 0, 4);
    note.layoutMarginsRelativeArrangement = YES;
    return note;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];

    SGGlassView *halo = [SGGlassView new];
    halo.capsule = YES;
    halo.translatesAutoresizingMaskIntoConstraints = NO;
    _hero = SGSymbolView(@"music.note", 34, UIImageSymbolWeightMedium, 88);
    _hero.translatesAutoresizingMaskIntoConstraints = NO;
    [halo addSubview:_hero];
    // The column stretches its children to its width; the halo keeps its square inside a strip.
    UIView *strip = [UIView new];
    [strip addSubview:halo];

    BOOL glass = SGRedesignAvailable();
    UILabel *heading = [UILabel new];
    heading.text = glass ? @"Pick your look." : @"Your look.";
    heading.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    heading.textColor = UIColor.whiteColor;
    heading.numberOfLines = 0;

    _redesigned = [[SGLookCard alloc] initWithSymbol:@"sparkles" title:@"Redesigned" subtitle:@"Looks like Apple Music. Better lyrics, Live Activity."];
    _legacy = [[SGLookCard alloc] initWithSymbol:@"slider.horizontal.3" title:@"Legacy" subtitle:@"More options, still looks like Spotify."];
    for (SGLookCard *card in @[_redesigned, _legacy]) [card addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
    // The first launch offers the redesign; the tour again from the Mod page shows the stored look.
    BOOL redesign = glass && (SGFlag(SGKeyOnboardingSeen, NO) ? SGRedesignedUIStored() : YES);
    _redesigned.selected = redesign;
    _legacy.selected = !redesign;
    // Liquid Glass is drawn by iOS 26 and by nothing before it, so on an older phone the card stays
    // on the page to say so and the legacy look is the only one left.
    if (!glass) {
        [_redesigned makeUnavailable:[NSString stringWithFormat:@"Needs iOS 26. This phone runs iOS %@.", UIDevice.currentDevice.systemVersion]];
        _legacy.enabled = NO;
    }
    _beta = [self betaNote];
    _beta.hidden = !redesign;

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[strip, heading, _redesigned, _legacy, _beta]];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 12;
    [column setCustomSpacing:28 afterView:strip];
    [column setCustomSpacing:24 afterView:heading];
    column.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [UIScrollView new];
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:column];
    [self.view addSubview:scroll];

    _primary = glassButton(@"Start listening");
    [_primary addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];
    UILabel *footer = [UILabel new];
    footer.text = @"Hold Home to open settings.";
    footer.font = [UIFont systemFontOfSize:13];
    footer.textColor = SGGrey();
    footer.textAlignment = NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_primary];
    [self.view addSubview:footer];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *frame = scroll.frameLayoutGuide, *content = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:_primary.topAnchor constant:-12],
        [column.topAnchor constraintEqualToAnchor:content.topAnchor constant:48],
        [column.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [column.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:kMargin],
        [column.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-kMargin],
        [column.widthAnchor constraintEqualToAnchor:frame.widthAnchor constant:-2 * kMargin],
        [halo.leadingAnchor constraintEqualToAnchor:strip.leadingAnchor],
        [halo.topAnchor constraintEqualToAnchor:strip.topAnchor],
        [halo.bottomAnchor constraintEqualToAnchor:strip.bottomAnchor],
        [halo.widthAnchor constraintEqualToConstant:88],
        [halo.heightAnchor constraintEqualToConstant:88],
        [_hero.centerXAnchor constraintEqualToAnchor:halo.centerXAnchor],
        [_hero.centerYAnchor constraintEqualToAnchor:halo.centerYAnchor],
        [_primary.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kMargin],
        [_primary.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kMargin],
        [_primary.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-12],
        [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kMargin],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kMargin],
        [footer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
    ]];
    [self refresh];
}

// iOS 16 has no symbol effects and skips the bounce.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (@available(iOS 17.0, *)) [_hero addSymbolEffect:[NSClassFromString(@"NSSymbolBounceEffect") effect]];
}

- (void)picked:(SGLookCard *)card {
    _redesigned.selected = card == _redesigned;
    _legacy.selected = card == _legacy;
    BOOL hide = !_redesigned.selected;
    if (_beta.hidden != hide) {
        [UIView animateWithDuration:0.25 animations:^{
            self->_beta.hidden = hide;
            self->_beta.alpha = hide ? 0 : 1;
            [self.view layoutIfNeeded];
        }];
    }
    [self refresh];
}

// The look is picked at launch, so a choice that differs from the running one ends the tour in a restart.
- (BOOL)needsRestart {
    return _redesigned.selected != SGRedesignedUI();
}

- (void)refresh {
    UIButtonConfiguration *config = _primary.configuration;
    NSString *title = self.needsRestart ? @"Restart Spotify" : @"Start listening";
    config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]}];
    _primary.configuration = config;
}

- (void)finish {
    SGDonateAfterTour(self.needsRestart);
    SGSetEnabled(SGKeyOnboardingSeen, YES);
    SGSetRedesignedUI(_redesigned.selected);
    if (self.needsRestart) {
        SGRestartSpotify();
        return;
    }
    [self dismissViewControllerAnimated:YES completion:^{ SGShowSigningFixIfPending(); }];
}

@end

#pragma mark - entry

static __weak SGOnboardingController *sg_tour;

BOOL SGOnboardingShowing(void) {
    return sg_tour != nil;
}

void SGShowOnboarding(void) {
    if (sg_tour) return;
    UIViewController *top = SGTopController();
    // Presenting from an alert lands nowhere; the tour waits for it to go.
    if (!top || [top isKindOfClass:UIAlertController.class]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGShowOnboarding(); });
        return;
    }
    SGOnboardingController *tour = [SGOnboardingController new];
    sg_tour = tour;
    [top presentViewController:tour animated:YES completion:nil];
}
