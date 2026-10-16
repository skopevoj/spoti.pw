// The player's background on Mod Settings' Player page: Fluid artwork or Animated artwork picked in place,
// and under it the settings of the one picked: Fluid artwork's sliders under a preview drawn by the same
// renderer as the player's field, or Animated artwork's sources.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Player.h"

NSNotificationName const SGRPlayerFluidLookDidChangeNotification = @"spotifyglass.redesign.player.fluidLookDidChange";
NSNotificationName const SGRPlayerBackgroundDidChangeNotification = @"spotifyglass.redesign.player.backgroundDidChange";

static const SGRPlayerBackground kDefaultBackground = SGRPlayerBackgroundFluid;

// A slider of the page: its key, range, step and default, in the whole numbers it stores.
typedef struct {
    __unsafe_unretained NSString *key, *title;
    NSInteger minimum, maximum, step, fallback;
    BOOL percent;
} SGRFluidSlider;

static const SGRFluidSlider kSpeed = {SGRKeyFluidSpeed, @"Speed", 25, 300, 25, 100, YES};
static const SGRFluidSlider kWarp = {SGRKeyFluidWarp, @"Warp", 0, 100, 5, 100, YES};
static const SGRFluidSlider kBlur = {SGRKeyFluidBlur, @"Blur", 2, 24, 1, 8, NO};
static const SGRFluidSlider kSaturation = {SGRKeyFluidSaturation, @"Saturation", 0, 250, 10, 150, YES};
static const SGRFluidSlider kBrightness = {SGRKeyFluidBrightness, @"Brightness", 40, 150, 5, 100, YES};

static NSInteger stored(SGRFluidSlider slider) {
    return MAX(slider.minimum, MIN(slider.maximum, SGInt(slider.key, slider.fallback)));
}

// Still artwork, Colour flow and the Moving background switch are gone, and whatever they stored reads as
// Fluid artwork, the default: the old keys only have to go.
static void migrate(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[SGRKeyPlayerBackgroundWas, SGRKeyPlayerMotionWas]) {
        id was = [store objectForKey:key];
        if (!was) continue;
        [store removeObjectForKey:key];
        SGLog(@"redesign player: %@ was %@, now Fluid artwork", key, was);
    }
}

SGRPlayerBackground SGRPlayerBackgroundStyle(void) {
    migrate();
    NSInteger style = SGInt(SGRKeyPlayerBackground, kDefaultBackground);
    return style >= SGRPlayerBackgroundFluid && style <= SGRPlayerBackgroundAnimated ? (SGRPlayerBackground)style : kDefaultBackground;
}

SGRWarpLook SGRPlayerFluidLook(void) {
    return (SGRWarpLook){
        .speed = stored(kSpeed) / 100.0f,
        .warp = stored(kWarp) / 100.0f,
        .blur = stored(kBlur),
        .saturation = stored(kSaturation) / 100.0f,
        .brightness = stored(kBrightness) / 100.0f,
    };
}

static void lookChanged(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerFluidLookDidChangeNotification object:nil];
}

#pragma mark - the preview

static const CGFloat kPreviewHeight = 240, kPreviewRadius = 26;

// A band across the middle of the player at the player's own scale, so the blur and the warp look the
// size they will there.
@interface SGRFluidPreview : SGRWarpView
@end

@implementation SGRFluidPreview {
    CGSize _laidOutFor;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.layer.cornerRadius = kPreviewRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.warpLayer.look = SGRPlayerFluidLook();
    [self showArtwork];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(showLook) name:SGRPlayerFluidLookDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(showArtwork) name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (CGSizeEqualToSize(size, _laidOutFor) || size.width < 1) return;
    _laidOutFor = size;
    CGSize screen = self.window.bounds.size.width > 0 ? self.window.bounds.size : UIScreen.mainScreen.bounds.size;
    CGFloat pictureHeight = size.width * screen.height / MAX(1, screen.width);
    self.warpLayer.pictureFrame = CGRectMake(0, (size.height - pictureHeight) / 2, size.width, pictureHeight);
}

- (void)showLook {
    self.warpLayer.look = SGRPlayerFluidLook();
}

- (void)showArtwork {
    UIImage *artwork = SGRNowPlayingArtwork(NULL, NULL);
    [self.warpLayer setArtwork:artwork ?: SGRWarpSampleArtwork() animated:self.window != nil];
}

@end

#pragma mark - the rows

static SGModRow *sliderRow(SGRFluidSlider slider) {
    return SGSliderRow(slider.title, nil, slider.minimum, slider.maximum, slider.step,
        ^double { return stored(slider); },
        ^(double value) {
            SGSetInt(slider.key, lround(value));
            lookChanged();
        },
        ^NSString *(double value) {
            return slider.percent ? [NSString stringWithFormat:@"%ld%%", lround(value)] : [NSString stringWithFormat:@"%ld", lround(value)];
        });
}

static NSArray<SGModRow *> *shownFor(SGRPlayerBackground background, NSArray<SGModRow *> *rows) {
    for (SGModRow *row in rows) row.visible = ^BOOL { return SGRPlayerBackgroundStyle() == background; };
    return rows;
}

NSArray<SGModSection *> *SGRPlayerBackgroundSections(void) {
    migrate();
    NSArray<SGModRow *> *choices = SGChoiceListRows(SGRKeyPlayerBackground, @[@"Fluid artwork", @"Animated artwork"],
        @[@"The cover itself, blurred and slowly warped", @"The track's Canvas or the album's animated cover, looping"],
        kDefaultBackground, ^(NSInteger index) {
            [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerBackgroundDidChangeNotification object:nil];
        });

    SGModRow *preview = SGViewRow([SGRFluidPreview new], kPreviewHeight);
    NSArray<SGModRow *> *sliders = @[sliderRow(kSpeed), sliderRow(kWarp), sliderRow(kBlur), sliderRow(kSaturation), sliderRow(kBrightness)];
    SGModRow *reset = SGActionRow(@"Reset", nil, ^{
        for (NSString *key in @[SGRKeyFluidSpeed, SGRKeyFluidWarp, SGRKeyFluidBlur, SGRKeyFluidSaturation, SGRKeyFluidBrightness]) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        }
        lookChanged();
    });
    reset.color = SGRed();
    reset.symbol = @"arrow.counterclockwise";

    SGModRow *sources = SGArtworkSourcesRow(SGRKeyPlayerArtworkSources,
        @"Asked top to bottom until one has a clip. Apple Music gets only the artist and album name.");

    return @[
        SGNotedSection(@"Background", choices, @"A paused song holds the background still."),
        SGSection(nil, shownFor(SGRPlayerBackgroundFluid, @[preview])),
        SGNotedSection(nil, shownFor(SGRPlayerBackgroundFluid, sliders),
                       @"The player follows these as they move. Brightness past 100% can make white text harder to read on a light cover."),
        SGSection(nil, shownFor(SGRPlayerBackgroundFluid, @[reset])),
        SGNotedSection(nil, shownFor(SGRPlayerBackgroundAnimated, @[sources]),
                       @"A track without a clip shows Fluid artwork, and so does every track in Low Power Mode or with Reduce Motion on."),
    ];
}
