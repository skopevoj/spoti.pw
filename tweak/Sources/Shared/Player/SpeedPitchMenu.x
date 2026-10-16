// The player's more menu gets Speed and pitch, under either look: one row in Spotify's own context menu
// sheet that opens, right there in the sheet, onto two sliders, the playback speed and the pitch
// (SpeedPitch.x applies them).
//
// The sheet is Spotify's ContextMenu_InternalImpl.ContextMenuViewController, a table of its rows
// (ContextMenuTableView, sized to its content). Its rows come from Swift item factories with no way in,
// so the block is the table's header view, or its footer when Spotify already uses the header, and is
// laid out by hand at the table's width. Opening and closing it resizes the header inside a table update,
// so the rows under it move with it, and the table's intrinsic size is invalidated for the sheet to
// follow.
//
// Only the menu the player's more button opens gets it: the button (id=Context menu,
// trees/lyrics.txt:183, an Encore Tertiary button) is watched from the redesign's PlayerHeader.x, and a
// menu shown within a few seconds of its tap, or presented from a now playing controller, is the
// player's. Under the native look nothing hands the button over, so the block rides on the second test
// alone, the presenter being Spotify's own now playing controller. The first time, the menu's structure
// is logged, since no recorded tree shows it yet.
//
// The block is drawn from its own measures and type (below), not from the redesign's Kit, so it sits on
// Spotify's sheet under either look.
//
// The block keeps whether it was open for the rest of the session; speed and pitch last until Spotify
// quits.
//
// The redesign's player menu draws a row of its own and takes the two sliders alone
// (SGSpeedPitchPanelMake): the same view with its row left out and its panel always open.
//
// Under the switch, Reverb picks one of the audio effects' rooms or none (Shared/AudioEffects), turning the
// effects on for it if they were off; it applies at once and lasts, as the Audio effects page's own does.
//
// Between the sliders, a switch has pitch follow speed (issue plus#5): the pitch slider folds away, and
// the panel with it, since the pitch is the speed's. The sheet's block resizes itself in its table; the
// redesign's menu is told through SGSpeedPitchChangedNotification and reads SGSpeedPitchPanelHeight().
#import <CoreText/SFNTLayoutTypes.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/AudioEffects/AudioEffects.h"
#import "SpeedPitch.h"
#import "SpeedPitchPresets.h"

// A menu this soon after the more button's tap is the player's.
static const NSTimeInterval kMenuAfterTap = 3;
static const CGFloat kRowHeight = 56, kSliderBlockHeight = 72, kFollowHeight = 44, kPanelBottom = 12;
// The panel's lines: the preset, speed, the switch, reverb and pitch.
static const NSInteger kSwitchLines = 3;
// The block's own measures and type, so it stands on Spotify's sheet under either look rather than on
// the redesign's Kit: the sheet's side margin, the gap everything else is a multiple of, and a spring
// that settles without overshooting.
static const CGFloat kSideMargin = 16, kGrid = 8;
static const NSTimeInterval kOpenDuration = 0.45;

static UIColor *primary(void) {
    return UIColor.whiteColor;
}

// White at the weight the sheet's own secondary text is, a step firmer with Increase Contrast.
static UIColor *secondary(void) {
    return [UIColor colorWithWhite:1 alpha:UIAccessibilityDarkerSystemColorsEnabled() ? 0.80 : 0.65];
}

// The system font at a text style's size, which stops growing past `largest` so the row still fits.
static UIFont *font(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    UIContentSizeCategory current = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (largest && UIContentSizeCategoryCompareToCategory(current, largest) == NSOrderedDescending) current = largest;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:current];
    CGFloat size = [UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:traits].pointSize;
    return [UIFont systemFontOfSize:size weight:weight];
}

// Digits of one width, so a value does not shuffle as it counts.
static UIFont *monospacedDigits(UIFont *base) {
    if (!base) return nil;
    NSArray *features = @[@{UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType), UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}];
    UIFontDescriptor *descriptor = [base.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute: features}];
    return [UIFont fontWithDescriptor:descriptor size:base.pointSize];
}

static void animateOpen(void (^animations)(void), void (^completion)(BOOL finished)) {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:animations];
        if (completion) completion(YES);
        return;
    }
    [UIView animateWithDuration:kOpenDuration delay:0 usingSpringWithDamping:1 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:animations completion:completion];
}
static const float kMinSpeed = 0.5f, kMaxSpeed = 2, kSpeedStep = 0.05f;
static const float kMaxPitch = 12;
// Speed is applied at most this often while the slider moves.
static const NSTimeInterval kSpeedInterval = 0.05;

static NSTimeInterval sg_moreTappedAt;
static BOOL sg_open;
static char kBlockKey, kDecidedKey, kWatchedKey, kShownAtKey, kRowsInKey;

#pragma mark - the block

NSNotificationName const SGSpeedPitchChangedNotification = @"SGSpeedPitchChangedNotification";

@interface SGSpeedPitchView : UIView
@property (nonatomic, weak) UITableView *table;
@property (nonatomic) BOOL inFooter;
// The sliders alone: no row, the panel at the top and always open.
@property (nonatomic) BOOL panelOnly;
@end

@implementation SGSpeedPitchView {
    UIControl *_row;
    UIImageView *_icon, *_chevron;
    UILabel *_title, *_summary;
    UIView *_panel;
    UILabel *_speedName, *_pitchName, *_followName, *_reverbName, *_presetName;
    UIButton *_speedValue, *_pitchValue, *_reverb, *_preset;
    id _presetsObserver, _valuesObserver;
    UISlider *_speed, *_pitch;
    UISwitch *_follow;
    float _shownSpeed, _shownPitch;
    NSTimeInterval _speedSentAt;
    BOOL _speedPending;
}

static UIImage *symbol(NSString *name, CGFloat size, UIImageSymbolWeight weight) {
    return [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
}

// A glyph with its colour drawn in, so it never passes through a tint on its way to the screen.
static UIImage *paintedSymbol(NSString *name, CGFloat size, UIImageSymbolWeight weight, UIColor *color) {
    return [symbol(name, size, weight) imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UILabel *makeLabel(UIFont *font, UIColor *color) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.adjustsFontForContentSizeCategory = NO;
    return label;
}

- (UIButton *)valueButton:(SEL)reset {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.titleLabel.font = monospacedDigits(font(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge));
    button.tintColor = primary();
    [button setTitleColor:primary() forState:UIControlStateNormal];
    [button setTitleColor:[primary() colorWithAlphaComponent:0.4] forState:UIControlStateHighlighted];
    [button setTitleColor:primary() forState:UIControlStateDisabled];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    button.accessibilityHint = @"Resets it";
    [button addTarget:self action:reset forControlEvents:UIControlEventTouchUpInside];
    return button;
}

// A glyph centred in a box of one size, so both sliders' tracks start and end at the same x.
static UIImage *endImage(NSString *name, CGFloat size) {
    UIImage *glyph = paintedSymbol(name, size, UIImageSymbolWeightMedium, secondary());
    CGSize box = CGSizeMake(24, 24);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:box] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [glyph drawAtPoint:CGPointMake((box.width - glyph.size.width) / 2, (box.height - glyph.size.height) / 2)];
    }];
}

// Both sliders have their normal in the middle of the range rather than at one end, so neither track
// fills: a tick marks where normal is, under the thumb until it moves away.
- (UISlider *)slider:(float)min max:(float)max normal:(float)normal minImage:(NSString *)minImage maxImage:(NSString *)maxImage {
    UISlider *slider = [UISlider new];
    slider.minimumValue = min;
    slider.maximumValue = max;
    UIColor *track = [UIColor colorWithWhite:1 alpha:0.2];
    slider.minimumTrackTintColor = track;
    slider.maximumTrackTintColor = track;
    slider.minimumValueImage = endImage(minImage, 13);
    slider.maximumValueImage = endImage(maxImage, 17);
    UIView *tick = [UIView new];
    tick.backgroundColor = secondary();
    tick.layer.cornerRadius = 1;
    tick.userInteractionEnabled = NO;
    tick.tag = (NSInteger)(normal * 1000);
    [slider insertSubview:tick atIndex:0];
    [slider addTarget:self action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(sliderReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return slider;
}

// The tick at the normal value's x on the track, found the way the thumb is placed.
static void placeTick(UISlider *slider) {
    UIView *tick = slider.subviews.firstObject;
    if (tick.subviews.count || tick.class != UIView.class) return;
    CGRect track = [slider trackRectForBounds:slider.bounds];
    float normal = tick.tag / 1000.0f;
    CGRect thumb = [slider thumbRectForBounds:slider.bounds trackRect:track value:normal];
    tick.frame = CGRectMake(roundf(CGRectGetMidX(thumb)) - 1, CGRectGetMidY(track) - 6, 2, 12);
    [slider sendSubviewToBack:tick];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    self.backgroundColor = UIColor.clearColor;
    // Nothing here draws in the tint: every colour is set on the view that draws it, and the glyphs have
    // theirs painted in rather than tinted. The row came up in the system blue for a moment as the sheet
    // appeared on the phone (issue #68), which is the tint a view inherits when nothing up the sheet sets
    // one. The block's own tint is white as well, for whatever UIKit draws in it (the sliders' parts).
    self.tintColor = primary();

    _row = [UIControl new];
    [_row addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [_row addTarget:self action:@selector(rowHighlight) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_row addTarget:self action:@selector(rowUnhighlight) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    _row.isAccessibilityElement = YES;
    _row.accessibilityTraits = UIAccessibilityTraitButton;
    [self addSubview:_row];

    _icon = [[UIImageView alloc] initWithImage:paintedSymbol(@"slider.horizontal.3", 20, UIImageSymbolWeightRegular, secondary())];
    _icon.contentMode = UIViewContentModeCenter;
    _title = makeLabel(font(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryExtraLarge), primary());
    _title.text = @"Speed and pitch";
    _summary = makeLabel(monospacedDigits(font(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraLarge)), secondary());
    _summary.textAlignment = NSTextAlignmentRight;
    _chevron = [[UIImageView alloc] initWithImage:paintedSymbol(@"chevron.down", 13, UIImageSymbolWeightSemibold, secondary())];
    _chevron.contentMode = UIViewContentModeCenter;
    for (UIView *view in @[_icon, _title, _summary, _chevron]) {
        view.userInteractionEnabled = NO;
        [_row addSubview:view];
    }

    _panel = [UIView new];
    [self addSubview:_panel];
    UIFont *nameFont = font(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
    _speedName = makeLabel(nameFont, secondary());
    _speedName.text = @"Speed";
    _pitchName = makeLabel(nameFont, secondary());
    _pitchName.text = @"Pitch";
    _speedValue = [self valueButton:@selector(resetSpeed)];
    _pitchValue = [self valueButton:@selector(resetPitch)];
    _speed = [self slider:kMinSpeed max:kMaxSpeed normal:1 minImage:@"tortoise.fill" maxImage:@"hare.fill"];
    _speed.accessibilityLabel = @"Speed";
    _pitch = [self slider:-kMaxPitch max:kMaxPitch normal:0 minImage:@"arrow.down" maxImage:@"arrow.up"];
    _pitch.accessibilityLabel = @"Pitch";
    _followName = makeLabel(nameFont, secondary());
    _followName.text = @"Pitch follows speed";
    _followName.adjustsFontSizeToFitWidth = YES;
    _followName.minimumScaleFactor = 0.8;
    _followName.isAccessibilityElement = NO;
    _follow = [UISwitch new];
    _follow.onTintColor = SGGreen();
    _follow.accessibilityLabel = @"Pitch follows speed";
    _follow.accessibilityHint = @"Faster plays higher, as a record does";
    [_follow addTarget:self action:@selector(followChanged) forControlEvents:UIControlEventValueChanged];
    _reverbName = makeLabel(nameFont, secondary());
    _reverbName.text = @"Reverb";
    _reverbName.isAccessibilityElement = NO;
    UIButtonConfiguration *reverb = [UIButtonConfiguration plainButtonConfiguration];
    reverb.image = paintedSymbol(@"chevron.up.chevron.down", 11, UIImageSymbolWeightSemibold, secondary());
    reverb.imagePlacement = NSDirectionalRectEdgeTrailing;
    reverb.imagePadding = 6;
    reverb.contentInsets = NSDirectionalEdgeInsetsZero;
    reverb.baseForegroundColor = primary();
    _reverb = [UIButton buttonWithConfiguration:reverb primaryAction:nil];
    _reverb.tintColor = primary();
    _reverb.showsMenuAsPrimaryAction = YES;
    _reverb.accessibilityLabel = @"Reverb";
    _presetName = makeLabel(nameFont, secondary());
    _presetName.text = @"Preset";
    _presetName.isAccessibilityElement = NO;
    UIButtonConfiguration *preset = [UIButtonConfiguration plainButtonConfiguration];
    preset.image = paintedSymbol(@"chevron.up.chevron.down", 11, UIImageSymbolWeightSemibold, secondary());
    preset.imagePlacement = NSDirectionalRectEdgeTrailing;
    preset.imagePadding = 6;
    preset.contentInsets = NSDirectionalEdgeInsetsZero;
    preset.baseForegroundColor = primary();
    _preset = [UIButton buttonWithConfiguration:preset primaryAction:nil];
    _preset.tintColor = primary();
    _preset.showsMenuAsPrimaryAction = YES;
    _preset.accessibilityLabel = @"Preset";
    for (UIView *view in @[_presetName, _preset, _speedName, _speedValue, _speed, _followName, _follow, _reverbName, _reverb, _pitchName, _pitchValue, _pitch]) [_panel addSubview:view];

    // A preset used from Siri or a shortcut, or saved from Mod Settings, shows here at once.
    __weak SGSpeedPitchView *weakSelf = self;
    _presetsObserver = [NSNotificationCenter.defaultCenter addObserverForName:SGSpeedPitchPresetsChangedNotification object:nil
                                                                        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [weakSelf refreshPresets];
    }];
    _valuesObserver = [NSNotificationCenter.defaultCenter addObserverForName:SGSpeedPitchValuesChangedNotification object:nil
                                                                       queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        SGSpeedPitchView *view = weakSelf;
        if (!view) return;
        [view refresh];
        if (view.window) [view resize];
    }];

    [self refresh];
    return self;
}

- (void)dealloc {
    if (_presetsObserver) [NSNotificationCenter.defaultCenter removeObserver:_presetsObserver];
    if (_valuesObserver) [NSNotificationCenter.defaultCenter removeObserver:_valuesObserver];
}

// The sliders' part: the preset, speed, the switch, reverb, and pitch unless it follows speed.
static CGFloat panelHeight(void) {
    return kSliderBlockHeight + kSwitchLines * kFollowHeight + (SGPlayerPitchFollowsSpeed() ? 0 : kSliderBlockHeight) + kPanelBottom;
}

// Reverb's choices: none, then the audio effects' rooms.
static NSInteger reverbChoice(void) {
    if (!SGDSPSwitch(SGKeyDSP) || !SGDSPSwitch(SGKeyDSPReverb)) return -1;
    return (NSInteger)SGDSPNumber(SGKeyDSPReverbPreset);
}

static void setReverbChoice(NSInteger preset) {
    if (preset < 0) {
        SGDSPSetSwitch(SGKeyDSPReverb, NO);
    } else {
        SGDSPSetNumber(SGKeyDSPReverbPreset, preset);
        SGDSPSetSwitch(SGKeyDSPReverb, YES);
        if (!SGDSPSwitch(SGKeyDSP)) SGDSPSetSwitch(SGKeyDSP, YES);
    }
    SGLog(@"speed and pitch: reverb %ld", (long)preset);
}

+ (CGFloat)heightOpen:(BOOL)open {
    return kRowHeight + (open ? panelHeight() : 0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, side = kSideMargin;
    _row.frame = CGRectMake(0, 0, width, kRowHeight);
    _icon.frame = CGRectMake(side, (kRowHeight - 24) / 2, 24, 24);
    _chevron.frame = CGRectMake(width - side - 20, (kRowHeight - 20) / 2, 20, 20);
    CGFloat titleX = side + 24 + side;
    CGFloat titleWidth = MIN([_title sizeThatFits:CGSizeMake(CGFLOAT_MAX, kRowHeight)].width, CGRectGetMinX(_chevron.frame) - titleX - kGrid);
    _title.frame = CGRectMake(titleX, 0, titleWidth, kRowHeight);
    CGFloat summaryX = CGRectGetMaxX(_title.frame) + kGrid;
    _summary.frame = CGRectMake(summaryX, 0, MAX(0, CGRectGetMinX(_chevron.frame) - kGrid - summaryX), kRowHeight);

    _row.hidden = self.panelOnly;
    // Pitch stays laid out under the switch when it folds away, so it fades where it was rather than moving.
    _panel.frame = CGRectMake(0, self.panelOnly ? 0 : kRowHeight, width, kSliderBlockHeight + kSwitchLines * kFollowHeight + kSliderBlockHeight + kPanelBottom);
    CGFloat y = 0;
    for (NSArray<UIView *> *line in @[@[_presetName, _preset], @[_speedName, _speedValue, _speed], @[_followName, _follow], @[_reverbName, _reverb], @[_pitchName, _pitchValue, _pitch]]) {
        if (line.count == 2) {
            CGSize toggle = [line[1] sizeThatFits:CGSizeMake(width / 2, kFollowHeight)];
            toggle.width = MIN(toggle.width, width / 2);
            line[1].frame = CGRectMake(width - side - toggle.width, y + roundf((kFollowHeight - toggle.height) / 2), toggle.width, toggle.height);
            line[0].frame = CGRectMake(side, y, MAX(0, CGRectGetMinX(line[1].frame) - kGrid - side), kFollowHeight);
            y += kFollowHeight;
            continue;
        }
        line[0].frame = CGRectMake(side, y + 4, width / 2 - side, 24);
        line[1].frame = CGRectMake(width / 2, y + 4, width / 2 - side, 24);
        line[2].frame = CGRectMake(side, y + 30, width - 2 * side, 36);
        [line[2] layoutIfNeeded];
        placeTick((UISlider *)line[2]);
        y += kSliderBlockHeight;
    }
}

#pragma mark state

static float snappedSpeed(float value) {
    float speed = roundf(value / kSpeedStep) * kSpeedStep;
    return fabsf(speed - 1) < kSpeedStep * 0.6f ? 1 : speed;
}

static NSString *speedText(float speed) {
    return [NSString stringWithFormat:@"%.2f×", speed];
}

static NSString *pitchText(float pitch) {
    if (pitch == 0) return @"0";
    return [NSString stringWithFormat:@"%@%.0f", pitch > 0 ? @"+" : @"−", fabsf(pitch)];
}

// The semitones a speed moves the pitch by while it follows, to a tenth (+3.9 at 1.25×, +12 at 2×).
static NSString *followedPitchText(float speed) {
    float semitones = roundf(12 * log2f(speed) * 10) / 10;
    if (semitones == 0) return nil;
    BOOL whole = semitones == roundf(semitones);
    return [NSString stringWithFormat:whole ? @"%@%.0f st" : @"%@%.1f st", semitones > 0 ? @"+" : @"−", fabsf(semitones)];
}

// What the row says beside its name: the speed, and the pitch where it is moved, set or followed.
static NSString *summaryText(float speed, BOOL speedShown, float pitch, BOOL follows) {
    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    if (speedShown && speed != 1) [changed addObject:speedText(speed)];
    NSString *moved = follows ? (speedShown ? followedPitchText(speed) : nil) : pitch != 0 ? [pitchText(pitch) stringByAppendingString:@" st"] : nil;
    if (moved) [changed addObject:moved];
    return changed.count ? [changed componentsJoinedByString:@"  "] : nil;
}

// What the player and the pitch say now, onto the controls (not while a finger is on one).
- (void)refresh {
    BOOL speedAllowed = SGPlayerSpeedAllowed(), pitchAvailable = SGPlayerPitchAvailable();
    if (!_speed.tracking) _shownSpeed = snappedSpeed(SGPlayerSpeed());
    if (!_pitch.tracking) _shownPitch = SGPlayerPitch();
    _speed.value = _shownSpeed;
    _pitch.value = _shownPitch;
    _speed.enabled = speedAllowed;
    _pitch.enabled = pitchAvailable;
    _speed.alpha = speedAllowed ? 1 : 0.4;
    // It only means anything where speed applies, so elsewhere it is off and cannot be turned on.
    _follow.on = SGPlayerPitchFollowsSpeed();
    _follow.enabled = speedAllowed;
    _followName.alpha = speedAllowed ? 1 : 0.4;
    [self refreshReverb];
    [self refreshPresets];
    [self showValues];
}

- (void)showValues {
    BOOL speedAllowed = SGPlayerSpeedAllowed(), pitchAvailable = SGPlayerPitchAvailable();
    [UIView performWithoutAnimation:^{
        [_speedValue setTitle:speedAllowed ? speedText(_shownSpeed) : @"Unavailable here" forState:UIControlStateNormal];
        [_pitchValue setTitle:pitchAvailable ? [pitchText(_shownPitch) stringByAppendingString:_shownPitch ? @" st" : @""] : @"Unavailable" forState:UIControlStateNormal];
        [_speedValue layoutIfNeeded];
        [_pitchValue layoutIfNeeded];
    }];
    _speedValue.enabled = speedAllowed && _shownSpeed != 1;
    _pitchValue.enabled = pitchAvailable && _shownPitch != 0;
    BOOL follows = SGPlayerPitchFollowsSpeed();
    NSString *followed = follows ? followedPitchText(_shownSpeed) : nil;
    _speed.accessibilityValue = !speedAllowed ? @"Unavailable" : followed ? [NSString stringWithFormat:@"%@, pitch %@", speedText(_shownSpeed), followed] : speedText(_shownSpeed);
    _pitch.accessibilityValue = _shownPitch == 0 ? @"Original pitch" : [NSString stringWithFormat:@"%.0f semitones %@", fabsf(_shownPitch), _shownPitch > 0 ? @"up" : @"down"];

    NSString *summary = summaryText(_shownSpeed, YES, _shownPitch, follows);
    _summary.text = sg_open ? nil : summary;
    _row.accessibilityLabel = summary ? [@"Speed and pitch, " stringByAppendingString:[summary stringByReplacingOccurrencesOfString:@"  " withString:@", "]] : @"Speed and pitch";
    _row.accessibilityValue = sg_open ? @"Expanded" : @"Collapsed";
    _chevron.transform = sg_open ? CGAffineTransformMakeRotation(M_PI) : CGAffineTransformIdentity;
    BOOL showsPanel = sg_open || self.panelOnly;
    _panel.alpha = showsPanel ? 1 : 0;
    _panel.accessibilityElementsHidden = !showsPanel;
    for (UIView *view in @[_pitchName, _pitchValue]) view.alpha = follows ? 0 : 1;
    _pitch.alpha = follows ? 0 : SGPlayerPitchAvailable() ? 1 : 0.4;
    for (UIView *view in @[_pitchName, _pitchValue, _pitch]) view.accessibilityElementsHidden = follows;
    [NSNotificationCenter.defaultCenter postNotificationName:SGSpeedPitchChangedNotification object:nil
                                                    userInfo:summary ? @{@"summary": summary} : nil];
}

// The preset button reads the preset the speed and pitch are, or Custom, and offers the saved ones, a check
// against the one set, then saving the current as a new one and deleting.
- (void)refreshPresets {
    NSArray<SGSpeedPitchPreset *> *presets = SGSpeedPitchPresets();
    SGSpeedPitchPreset *current = nil;
    for (SGSpeedPitchPreset *preset in presets) if (SGSpeedPitchPresetIsCurrent(preset)) { current = preset; break; }
    BOOL normal = SGPlayerSpeed() == 1 && SGPlayerPitch() == 0;
    NSString *title = current ? current.name : normal ? (presets.count ? @"None" : @"None saved") : @"Custom";
    UIButtonConfiguration *configuration = _preset.configuration;
    configuration.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: font(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge),
        NSForegroundColorAttributeName: primary(),
    }];
    [UIView performWithoutAnimation:^{
        self->_preset.configuration = configuration;
        [self->_preset layoutIfNeeded];
    }];
    _preset.accessibilityValue = title;
    __weak SGSpeedPitchView *weakSelf = self;
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    for (SGSpeedPitchPreset *preset in presets) {
        UIAction *use = [UIAction actionWithTitle:preset.name image:nil identifier:nil handler:^(UIAction *action) {
            SGSpeedPitchPresetApply(preset);
            [weakSelf refresh];
        }];
        use.subtitle = SGSpeedPitchPresetSummary(preset);
        use.state = preset == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:use];
    }
    NSMutableArray<UIMenuElement *> *groups = [NSMutableArray array];
    if (items.count) [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:items]];
    NSMutableArray<UIMenuElement *> *more = [NSMutableArray array];
    UIAction *save = [UIAction actionWithTitle:@"Save current as preset…" image:[UIImage systemImageNamed:@"plus"] identifier:nil handler:^(UIAction *action) {
        SGSpeedPitchPresetPromptSave(^(SGSpeedPitchPreset *saved) { [weakSelf refreshPresets]; });
    }];
    [more addObject:save];
    if (presets.count) {
        NSMutableArray<UIMenuElement *> *deletes = [NSMutableArray array];
        for (SGSpeedPitchPreset *preset in presets) {
            UIAction *remove = [UIAction actionWithTitle:preset.name image:nil identifier:nil handler:^(UIAction *action) {
                SGSpeedPitchPresetDelete(preset);
            }];
            remove.attributes = UIMenuElementAttributesDestructive;
            [deletes addObject:remove];
        }
        [more addObject:[UIMenu menuWithTitle:@"Delete preset" image:[UIImage systemImageNamed:@"trash"] identifier:nil options:0 children:deletes]];
    }
    [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:more]];
    _preset.menu = [UIMenu menuWithTitle:@"Preset" children:groups];
}

// The reverb button reads the room it is set to and offers the others, a check against the one set.
- (void)refreshReverb {
    NSArray<NSString *> *rooms = SGDSPReverbPresetNames();
    NSInteger current = reverbChoice();
    NSString *title = current >= 0 && current < (NSInteger)rooms.count ? rooms[(NSUInteger)current] : @"Off";
    UIButtonConfiguration *configuration = _reverb.configuration;
    configuration.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: font(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge),
        NSForegroundColorAttributeName: primary(),
    }];
    [UIView performWithoutAnimation:^{
        self->_reverb.configuration = configuration;
        [self->_reverb layoutIfNeeded];
    }];
    _reverb.accessibilityValue = title;
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    __weak SGSpeedPitchView *weakSelf = self;
    UIAction *off = [UIAction actionWithTitle:@"Off" image:nil identifier:nil handler:^(UIAction *action) {
        setReverbChoice(-1);
        [weakSelf refreshReverb];
        [weakSelf setNeedsLayout];
    }];
    off.state = current < 0 ? UIMenuElementStateOn : UIMenuElementStateOff;
    [items addObject:off];
    [rooms enumerateObjectsUsingBlock:^(NSString *room, NSUInteger index, BOOL *stop) {
        UIAction *pick = [UIAction actionWithTitle:room image:nil identifier:nil handler:^(UIAction *action) {
            setReverbChoice((NSInteger)index);
            [weakSelf refreshReverb];
            [weakSelf setNeedsLayout];
        }];
        pick.state = (NSInteger)index == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:pick];
    }];
    _reverb.menu = [UIMenu menuWithTitle:@"Reverb" children:items];
}

#pragma mark actions

- (void)rowHighlight {
    _row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
}

- (void)rowUnhighlight {
    [UIView animateWithDuration:0.2 animations:^{ _row.backgroundColor = UIColor.clearColor; }];
}

// To its height for sg_open and the switch, in the sheet's table, the rows under it moving with it; the
// redesign's menu sizes the panel itself, on the notification showValues posts.
- (void)resize {
    UITableView *table = self.table;
    CGRect frame = self.frame;
    frame.size.height = [SGSpeedPitchView heightOpen:sg_open];
    BOOL inTable = table && !self.panelOnly;
    animateOpen(^{
        if (inTable) {
            [table beginUpdates];
            self.frame = frame;
            if (self.inFooter) table.tableFooterView = self;
            else table.tableHeaderView = self;
        }
        [self showValues];
        [self setNeedsLayout];
        [self layoutIfNeeded];
        if (inTable) [table endUpdates];
    }, ^(BOOL finished) {
        if (sg_open && inTable) [table scrollRectToVisible:[table convertRect:self.bounds fromView:self] animated:YES];
    });
    if (!inTable) return;
    [table invalidateIntrinsicContentSize];
    UIView *sheet = table.superview;
    for (int i = 0; sheet && i < 4; i++, sheet = sheet.superview) [sheet setNeedsLayout];
}

- (void)toggle {
    sg_open = !sg_open;
    if (sg_open) [self refresh];
    [self resize];
    UITableView *table = self.table;
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, sg_open ? _speed : nil);
    SGLog(@"speed and pitch: speed and pitch %@, table %.0f tall showing %.0f", sg_open ? @"opened" : @"closed", table.contentSize.height, table.bounds.size.height);
}

- (void)followChanged {
    SGSetPlayerPitchFollowsSpeed(_follow.on);
    _shownPitch = SGPlayerPitch();
    _pitch.value = _shownPitch;
    [self resize];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
    SGLog(@"speed and pitch: pitch %@ speed at %.2fx", SGPlayerPitchFollowsSpeed() ? @"follows" : @"no longer follows", _shownSpeed);
}

- (void)sendSpeed {
    _speedPending = NO;
    _speedSentAt = CACurrentMediaTime();
    SGSetPlayerSpeed(_shownSpeed);
}

- (void)sliderMoved:(UISlider *)slider {
    if (slider == _speed) {
        float speed = snappedSpeed(slider.value);
        if (speed == _shownSpeed) return;
        if (speed == 1 || _shownSpeed == 1) SGPlayFeedback(SGFeedbackDetent);
        _shownSpeed = speed;
        NSTimeInterval wait = kSpeedInterval - (CACurrentMediaTime() - _speedSentAt);
        if (wait <= 0) [self sendSpeed];
        else if (!_speedPending) {
            _speedPending = YES;
            __weak SGSpeedPitchView *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SGSpeedPitchView *view = weakSelf;
                if (view && view->_speedPending) [view sendSpeed];
            });
        }
    } else {
        float pitch = roundf(slider.value);
        if (pitch == _shownPitch) return;
        if (pitch == 0 || _shownPitch == 0) SGPlayFeedback(SGFeedbackDetent);
        _shownPitch = pitch;
        SGSetPlayerPitch(pitch);
    }
    [self showValues];
}

- (void)sliderReleased:(UISlider *)slider {
    if (slider == _speed) {
        slider.value = _shownSpeed;
        if (_speedPending || snappedSpeed(SGPlayerSpeed()) != _shownSpeed) [self sendSpeed];
    } else {
        slider.value = _shownPitch;
    }
}

- (void)resetSpeed {
    _shownSpeed = 1;
    [self sendSpeed];
    [_speed setValue:1 animated:YES];
    [self showValues];
}

- (void)resetPitch {
    _shownPitch = 0;
    SGSetPlayerPitch(0);
    [_pitch setValue:0 animated:YES];
    [self showValues];
}

@end

#pragma mark - the sliders for a menu of a look's own

CGFloat SGSpeedPitchPanelHeight(void) {
    return panelHeight();
}

UIView *SGSpeedPitchPanelMake(void) {
    SGSpeedPitchView *panel = [[SGSpeedPitchView alloc] initWithFrame:CGRectMake(0, 0, 320, SGSpeedPitchPanelHeight())];
    panel.panelOnly = YES;
    [panel refresh];
    return panel;
}

NSString *SGSpeedPitchSummary(void) {
    return summaryText(snappedSpeed(SGPlayerSpeed()), SGPlayerSpeedAllowed(), SGPlayerPitch(), SGPlayerPitchFollowsSpeed());
}

#pragma mark - the player's more button

@interface SGMoreTapWatcher : NSObject <UIGestureRecognizerDelegate>
@end

@implementation SGMoreTapWatcher
- (void)tapped {
    sg_moreTappedAt = CACurrentMediaTime();
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end

void SGPlayerMenuWatchMoreButton(UIView *button) {
    if (!button || objc_getAssociatedObject(button, &kWatchedKey)) return;
    static SGMoreTapWatcher *watcher;
    if (!watcher) watcher = [SGMoreTapWatcher new];
    objc_setAssociatedObject(button, &kWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // An Encore button may read its touches through a gesture recognizer rather than as a control, so
    // both are watched.
    if ([button isKindOfClass:UIControl.class]) {
        [(UIControl *)button addTarget:watcher action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside | UIControlEventPrimaryActionTriggered];
    }
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:watcher action:@selector(tapped)];
    tap.cancelsTouchesInView = NO;
    tap.delaysTouchesEnded = NO;
    tap.delegate = watcher;
    [button addGestureRecognizer:tap];
}

#pragma mark - the menu

// The presenter or one of its parents is a now playing controller. Only the chain up is looked at: the
// root's children include the now playing bar's, which every menu would match.
static BOOL presentedFromPlayer(UIViewController *menu) {
    UIViewController *presenter = menu.navigationController.presentingViewController ?: menu.presentingViewController;
    for (UIViewController *vc = presenter; vc; vc = vc.parentViewController) {
        if ([NSStringFromClass(vc.class) containsString:@"NowPlaying"]) return YES;
    }
    return NO;
}

static void logStructure(UIView *view, int depth, NSMutableString *out) {
    if (depth > 6 || out.length > 3000) return;
    [out appendFormat:@"\n%*s%@ %@", depth * 2, "", NSStringFromClass(view.class), NSStringFromCGRect(view.frame)];
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UITableViewCell.class]) {
            [out appendFormat:@"\n%*scell %@", (depth + 1) * 2, "", NSStringFromCGRect(child.frame)];
            continue;
        }
        logStructure(child, depth + 1, out);
    }
}

static UITableView *findTable(UIView *root, int depth) {
    if ([root isKindOfClass:UITableView.class]) return (UITableView *)root;
    if (depth > 5) return nil;
    for (UIView *child in root.subviews) {
        UITableView *table = findTable(child, depth + 1);
        if (table) return table;
    }
    return nil;
}

static BOOL isPlayerMenu(UIViewController *menu) {
    NSNumber *decided = objc_getAssociatedObject(menu, &kDecidedKey);
    if (decided) return decided.boolValue;
    BOOL tapped = sg_moreTappedAt && CACurrentMediaTime() - sg_moreTappedAt < kMenuAfterTap;
    BOOL fromPlayer = presentedFromPlayer(menu);
    BOOL ours = tapped || fromPlayer;
    if (tapped) sg_moreTappedAt = 0;
    objc_setAssociatedObject(menu, &kDecidedKey, @(ours), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIViewController *presenter = menu.navigationController.presentingViewController ?: menu.presentingViewController;
    SGLog(@"speed and pitch: a context menu, %@ (tapped %d, presented by %@)", ours ? @"the player's" : @"not the player's", tapped,
          presenter ? NSStringFromClass(presenter.class) : @"nothing");
    return ours;
}

#pragma mark - Spotify's rows

// The sheet keeps its spinner up until Spotify's rows are in, and they are in when every item factory
// has answered or run out of time: ContextMenuItemFactory holds a timer, and the timeout is the remote
// config's ios-feature-contextmenu-platform.timeout (SPTContextMenu_InternalImplProperties reads it
// between 1 and 60 s, 10 when the server says nothing). The block takes no part in that: it goes into
// the table's header once and stays, and a sheet that gets its rows seconds later shows them under it
// (harness/menu `loading`). So a menu that waits is timed from here, to tell a wait on Spotify's
// factories from a main thread kept busy: each check says how late it ran.
static NSInteger rowCount(UITableView *table) {
    NSInteger rows = 0;
    for (NSInteger section = 0; section < table.numberOfSections; section++) rows += [table numberOfRowsInSection:section];
    return rows;
}

static BOOL spinning(UIView *view, int depth) {
    if ([view isKindOfClass:UIActivityIndicatorView.class]) return ((UIActivityIndicatorView *)view).isAnimating && !view.isHidden && view.alpha > 0.01;
    if (depth > 6) return NO;
    for (UIView *child in view.subviews) {
        if (spinning(child, depth + 1)) return YES;
    }
    return NO;
}

// Once, when the rows are first seen, and said only when they were late.
static void noteRows(UIViewController *menu, UITableView *table) {
    NSNumber *shownAt = objc_getAssociatedObject(menu, &kShownAtKey);
    if (!shownAt || objc_getAssociatedObject(menu, &kRowsInKey) || !table || rowCount(table) == 0) return;
    objc_setAssociatedObject(menu, &kRowsInKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSTimeInterval after = CACurrentMediaTime() - shownAt.doubleValue;
    if (after > 0.5) SGLog(@"speed and pitch: Spotify's rows came in %.1f s after the menu appeared", after);
}

static void watchRows(UIViewController *menu) {
    if (objc_getAssociatedObject(menu, &kShownAtKey)) return;
    objc_setAssociatedObject(menu, &kShownAtKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UITableView *table = findTable(menu.view, 0);
    if (table && rowCount(table)) {
        objc_setAssociatedObject(menu, &kRowsInKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    __weak UIViewController *weakMenu = menu;
    for (NSNumber *wait in @[@2, @6, @15, @40]) {
        CFTimeInterval due = CACurrentMediaTime() + wait.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *shown = weakMenu;
            if (!shown.viewIfLoaded.window || objc_getAssociatedObject(shown, &kRowsInKey)) return;
            UITableView *rows = findTable(shown.view, 0);
            noteRows(shown, rows);
            if (objc_getAssociatedObject(shown, &kRowsInKey)) return;
            SGLog(@"speed and pitch: no rows of Spotify's %@ s after the menu appeared (this check ran %.2f s late), spinner %@, table %.0fx%.0f holding %.0f",
                  wait, CACurrentMediaTime() - due, spinning(shown.view, 0) ? @"spinning" : @"not spinning",
                  rows.bounds.size.width, rows.bounds.size.height, rows.contentSize.height);
        });
    }
}

static void install(UIViewController *menu) {
    UIView *root = menu.viewIfLoaded;
    if (!root || !isPlayerMenu(menu)) return;
    UITableView *table = findTable(root, 0);
    SGSpeedPitchView *block = objc_getAssociatedObject(menu, &kBlockKey);
    if (!table) {
        static int logged;
        if (logged++ < 3) SGLog(@"speed and pitch: no table in %@, speed and pitch left out", NSStringFromClass(menu.class));
        return;
    }
    CGFloat width = table.bounds.size.width;
    if (width <= 0) return;
    if (!block) {
        static BOOL described;
        if (!described) {
            described = YES;
            NSMutableString *structure = [NSMutableString string];
            logStructure(root, 0, structure);
            SGLog(@"speed and pitch: table %@ header %@ footer %@, structure:%@", NSStringFromClass(table.class),
                  table.tableHeaderView ? NSStringFromClass(table.tableHeaderView.class) : @"none",
                  table.tableFooterView ? NSStringFromClass(table.tableFooterView.class) : @"none", structure);
        }
        BOOL headerFree = !table.tableHeaderView || table.tableHeaderView.bounds.size.height < 1;
        BOOL footerFree = !table.tableFooterView || table.tableFooterView.bounds.size.height < 1;
        if (!headerFree && !footerFree) {
            SGLog(@"speed and pitch: the table's header and footer are both Spotify's, speed and pitch left out");
            objc_setAssociatedObject(menu, &kDecidedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        block = [[SGSpeedPitchView alloc] initWithFrame:CGRectMake(0, 0, width, [SGSpeedPitchView heightOpen:sg_open])];
        block.table = table;
        block.inFooter = !headerFree;
        objc_setAssociatedObject(menu, &kBlockKey, block, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (block.inFooter) table.tableFooterView = block;
        else table.tableHeaderView = block;
        [table invalidateIntrinsicContentSize];
        return;
    }
    noteRows(menu, table);
    // Spotify replaced the view, or the table changed width: put it back at the table's width.
    UIView *placed = block.inFooter ? table.tableFooterView : table.tableHeaderView;
    if (placed != block) {
        static int logged;
        if (logged++ < 3) SGLog(@"speed and pitch: the table's %@ became %@, speed and pitch put back", block.inFooter ? @"footer" : @"header",
                                placed ? NSStringFromClass(placed.class) : @"nothing");
    }
    if (placed != block || fabs(block.frame.size.width - width) > 0.5) {
        block.frame = CGRectMake(0, block.frame.origin.y, width, [SGSpeedPitchView heightOpen:sg_open]);
        if (block.inFooter) table.tableFooterView = block;
        else table.tableHeaderView = block;
        [table invalidateIntrinsicContentSize];
    }
}

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLayoutSubviews {
    %orig;
    install((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SGSpeedPitchView *block = objc_getAssociatedObject(self, &kBlockKey);
    [block refresh];
    if (block) watchRows((UIViewController *)self);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC24ContextMenu_InternalImpl25ContextMenuViewController"]);
}
