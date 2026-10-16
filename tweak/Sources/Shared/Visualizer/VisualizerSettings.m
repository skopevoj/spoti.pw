// The visualizer's rows (Visualizer.h): the same strength and choice of what to follow as Music Haptics, or
// Music Haptics' own with a switch, then how many bars, their style and colour, and the mirror. Each row
// applies at once and tells every ring.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Haptics/Haptics.h"
#import "SGCoverPalette.h"
#import "Visualizer.h"

NSNotificationName const SGVisualizerSettingsDidChangeNotification = @"spotifyglass.visualizerChanged";

// Appended to, never reordered: the stored value is an index.
static NSArray<NSNumber *> *counts(void) { return @[@48, @64, @96, @128, @256, @512, @1024]; }

NSInteger SGVisualizerBarCount(void) {
    NSArray<NSNumber *> *list = counts();
    NSInteger index = SGInt(SGKeyVisualizerBars, 1);
    return list[(NSUInteger)MAX(0, MIN((NSInteger)list.count - 1, index))].integerValue;
}

CGFloat SGVisualizerWidthFactor(void) {
    switch (SGInt(SGKeyVisualizerWidth, SGVisualizerWidthNormal)) {
        case SGVisualizerWidthThin: return 0.6;
        case SGVisualizerWidthThick: return 1.4;
        default: return 1;
    }
}

// An index stored under `key` into `list`, `fallback` unset, kept inside it.
static double pick(NSString *key, NSArray<NSNumber *> *list, NSInteger fallback) {
    NSInteger index = SGInt(key, fallback);
    return list[(NSUInteger)MAX(0, MIN((NSInteger)list.count - 1, index))].doubleValue;
}

float SGVisualizerBassShare(void) {
    return (float)pick(SGKeyVisualizerBassShare, @[@0, @0.2, @0.25, @(1.0 / 3)], 1);
}

CGFloat SGVisualizerHeightFactor(void) {
    return pick(SGKeyVisualizerHeight, @[@0.55, @0.78, @1], 2);
}

void SGVisualizerResponse(float *rise, float *fall) {
    // Snappy drops away at once, Normal is the analyzer's own, Smooth glides both ways.
    NSInteger index = MAX(0, MIN(2, SGInt(SGKeyVisualizerResponse, 1)));
    static const float rises[] = {0.95f, 0.8f, 0.4f}, falls[] = {0.5f, 0.3f, 0.1f};
    if (rise) *rise = rises[index];
    if (fall) *fall = falls[index];
}

NSTimeInterval SGVisualizerRotationPeriod(void) {
    return pick(SGKeyVisualizerRotation, @[@0, @40, @12], 0);
}

static void changed(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGVisualizerSettingsDidChangeNotification object:nil];
}

NSArray<SGModSection *> *SGVisualizerSections(NSString *waitsOnKey) {
    BOOL (^own)(void) = ^BOOL { return !SGFlag(SGKeyVisualizerLikeHaptics, NO); };
    SGModRow *likeHaptics = SGOptionRow(@"Same as Music Haptics", @"Its strength and what it follows", SGKeyVisualizerLikeHaptics);
    likeHaptics.changed = ^(BOOL on) { changed(); };
    SGModRow *strength = SGSliderRow(@"Strength", nil, SGMusicStrengthMin, SGMusicStrengthMax, SGStrengthStep,
        ^double { return SGInt(SGKeyVisualizerStrength, 100); },
        ^(double value) { SGSetInt(SGKeyVisualizerStrength, (NSInteger)lround(value)); changed(); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%ld %%", lround(value)]; });
    strength.visible = own;
    SGModRow *follows = SGChoiceRow(@"Follows", nil, SGKeyVisualizerFollows, @[@"Everything", @"Beat", @"Bass"], SGMusicFollowsEverything);
    follows.choiceNotes = @[@"Every band at its level", @"The drums jump out of the rest", @"The low end, all the way round"];
    follows.chosen = ^(NSInteger index) { changed(); };
    follows.visible = own;
    SGModRow *bass = SGChoiceRow(@"Bass area", nil, SGKeyVisualizerBassShare, @[@"Even", @"A fifth", @"A quarter", @"A third"], 1);
    bass.choiceNotes = @[@"One scale from 40 Hz up, so the lows get little room", @"20 to 100 Hz across a fifth of the ring, the rest after it",
                         @"20 to 100 Hz across a quarter", @"20 to 100 Hz across a third"];
    bass.choiceFooter = @"The rest of the ring runs from 100 Hz up, spread the same way. With Follows set to Bass the whole ring is the low end already.";
    bass.chosen = ^(NSInteger index) { changed(); };
    // Gone while the ring follows the bass, read the way the tap reads it.
    bass.visible = ^BOOL {
        NSInteger following = SGFlag(SGKeyVisualizerLikeHaptics, NO) ? SGMusicHapticsFollows() : SGInt(SGKeyVisualizerFollows, SGMusicFollowsEverything);
        return following != SGMusicFollowsBass;
    };
    SGModRow *response = SGChoiceRow(@"Movement", nil, SGKeyVisualizerResponse, @[@"Snappy", @"Normal", @"Smooth"], 1);
    response.choiceNotes = @[@"Up on the hit and straight back down", @"Quick both ways", @"Gliding, slower to rise and to fall"];
    response.chosen = ^(NSInteger index) { changed(); };
    SGModRow *bars = SGChoiceRow(@"Bars", nil, SGKeyVisualizerBars, @[@"48", @"64", @"96", @"128", @"256", @"512", @"1024"], 1);
    bars.choiceNotes = @[@"Chunky", @"The default", @"Detailed", @"Dense", @"Fine", @"Very fine", @"A smooth circle"];
    bars.choiceFooter = @"From 256 on the bars are read between the sound's bins and smoothed into one another, so the ring turns into a curve. "
                         "Past 256 the lock screen's frames and the ring cost more to draw.";
    bars.chosen = ^(NSInteger index) { changed(); };
    SGModRow *width = SGChoiceRow(@"Bar width", nil, SGKeyVisualizerWidth, @[@"Thin", @"Normal", @"Thick"], SGVisualizerWidthNormal);
    width.chosen = ^(NSInteger index) { changed(); };
    SGModRow *height = SGChoiceRow(@"Bar height", nil, SGKeyVisualizerHeight, @[@"Short", @"Medium", @"Full"], 2);
    height.choiceNotes = @[@"About half the way to the edge", @"Three quarters of the way", @"All the way to the edge"];
    height.chosen = ^(NSInteger index) { changed(); };
    SGModRow *style = SGChoiceRow(@"Style", nil, SGKeyVisualizerStyle, @[@"Bars", @"Wave", @"Dots"], SGVisualizerStyleBars);
    style.chosen = ^(NSInteger index) { changed(); };
    SGModRow *color = SGChoiceRow(@"Colour", nil, SGKeyVisualizerColor, @[@"Accent", @"White", @"Spectrum", @"Cover gradient"], SGVisualizerColorAccent);
    color.choiceNotes = @[@"The look's accent colour", @"Plain white", @"Every hue, round the ring", @"A gradient of the cover's own colours, changing with each song"];
    color.chosen = ^(NSInteger index) { changed(); };
    SGModRow *reading = SGChoiceRow(@"Cover colours", nil, SGKeyVisualizerCoverColours, @[@"Spots", @"Main colours"], SGVisualizerCoverColoursSpots);
    reading.choiceNotes = @[@"The blurred cover at its centre and each quarter: the colours it is mostly made of",
                            @"The cover's main colours over the whole of it, vivid ones first, even small"];
    reading.chosen = ^(NSInteger index) {
        SGCoverPaletteReset();
        changed();
    };
    reading.visible = ^BOOL { return SGInt(SGKeyVisualizerColor, SGVisualizerColorAccent) == SGVisualizerColorCover; };
    SGModRow *dark = SGOptionRow(@"Dark colours", @"Keeps the cover's darks and black as they are", SGKeyVisualizerCoverDark);
    dark.changed = ^(BOOL on) {
        SGCoverPaletteReset();
        changed();
    };
    dark.visible = reading.visible;
    SGModRow *gradient = SGChoiceRow(@"Gradient", nil, SGKeyVisualizerGradient, @[@"Along each bar", @"Around the ring", @"Repeating", @"Bar by bar"],
                                     SGVisualizerGradientAlong);
    gradient.choiceNotes = @[@"Every bar goes through the colours from the inside out", @"Once round the whole ring",
                             @"There and back round the ring, four times over", @"Each bar one colour, the next bar the next"];
    gradient.chosen = ^(NSInteger index) { changed(); };
    gradient.visible = ^BOOL {
        NSInteger colour = SGInt(SGKeyVisualizerColor, SGVisualizerColorAccent);
        return colour == SGVisualizerColorSpectrum || colour == SGVisualizerColorCover;
    };
    SGModRow *backlight = SGOptionRow(@"Backlight", @"A glow behind the bars, white or black, so they stand out", SGKeyVisualizerBacklight);
    backlight.changed = ^(BOOL on) { changed(); };
    SGModRow *mirror = SGSwitchRow(@"Mirror", @"Each side the other's reflection", SGKeyVisualizerMirror);
    mirror.changed = ^(BOOL on) { changed(); };
    SGModRow *peaks = SGOptionRow(@"Peaks", @"A cap at each bar's peak that falls slowly", SGKeyVisualizerPeaks);
    peaks.changed = ^(BOOL on) { changed(); };
    peaks.visible = ^BOOL { return SGInt(SGKeyVisualizerStyle, SGVisualizerStyleBars) == SGVisualizerStyleBars; };
    SGModRow *rotation = SGChoiceRow(@"Rotation", nil, SGKeyVisualizerRotation, @[@"Off", @"Slow", @"Fast"], 0);
    rotation.choiceNotes = @[@"The ring stays put", @"A turn every 40 seconds", @"A turn every 12 seconds"];
    rotation.chosen = ^(NSInteger index) { changed(); };
    NSArray<NSArray<SGModRow *> *> *groups = @[@[likeHaptics, strength, follows, bass, response],
                                               @[bars, width, height, style, mirror, peaks, rotation],
                                               @[color, reading, dark, gradient, backlight]];
    if (waitsOnKey) for (NSArray<SGModRow *> *group in groups) for (SGModRow *row in group) SGWaitsOn(row, waitsOnKey, NO);
    return @[
        SGNotedSection(@"Sound", groups[0], @"Strength and Follows work as Music Haptics' do. Bass area is how much of the ring the "
                                             "lowest notes, 20 to 100 Hz, get; the rest runs from 100 Hz up."),
        SGNotedSection(@"Shape", groups[1], @"Peaks and Rotation are the player's only."),
        SGNotedSection(@"Colour", groups[2], @"Cover gradient takes its colours from the cover on screen, lightened to show on "
                                              "black. Spots reads the cover blurred, so a small detail never becomes a colour; Main "
                                              "colours picks out the cover's own colours, the vivid ones first. Dark colours keeps a dark cover dark, black "
                                              "included. Backlight lays a soft glow behind the bars, white when they are dark and "
                                              "black when they are light, so they stand out from what is behind them."),
    ];
}

UIViewController *SGVisualizerSettingsPage(NSArray<SGModSection *> *leading, NSString *waitsOnKey, NSString *intro) {
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithArray:leading ?: @[]];
    [sections addObjectsFromArray:SGVisualizerSections(waitsOnKey)];
    [sections addObject:SGNotedSection(@"Lock screen", SGLockScreenVisualizerRows(),
        @"The lock screen's artwork becomes the cover in the ring, drawn again several times a second while the song plays, in the "
         "style and colour above. With lock screen lyrics showing the line as the artwork, the line sits under the ring. An animated "
         "cover (Canvas) shows over it. Applies after you restart Spotify.")];
    SGModRow *carPlay = SGOptionRow(@"CarPlay visualizer", @"The ring on CarPlay's Now Playing", SGKeyVisualizerCarPlay);
    [sections addObject:SGNotedSection(@"CarPlay", @[carPlay],
        @"While CarPlay is connected, the artwork on CarPlay's Now Playing becomes the cover in the ring, at the lock screen's "
         "frames a second, even with Spotify open on your iPhone. CarPlay only lets an app show the screens Apple draws, so the "
         "ring goes there as the artwork, and the car may update it less often than the lock screen does. Applies after you "
         "restart Spotify.")];
    return [[SGModPage alloc] initWithTitle:@"Visualizer" intro:intro sections:sections footer:nil];
}

static NSArray<NSNumber *> *rates(void) { return @[@6, @10, @15]; }

NSInteger SGLockScreenVisualizerFramesPerSecond(void) {
    NSArray<NSNumber *> *list = rates();
    NSInteger index = SGInt(SGKeyLockScreenVisualizerRate, 1);
    return list[(NSUInteger)MAX(0, MIN((NSInteger)list.count - 1, index))].integerValue;
}

NSArray<SGModRow *> *SGLockScreenVisualizerRows(void) {
    SGModRow *on = SGOptionRow(@"Lock screen visualizer", @"The cover in a ring of bars, as the artwork", SGKeyLockScreenVisualizer);
    SGModRow *rate = SGChoiceRow(@"Lock screen frames", nil, SGKeyLockScreenVisualizerRate, @[@"6 a second", @"10 a second", @"15 a second"], 1);
    rate.choiceNotes = @[@"Lightest on the battery", @"Smooth enough to follow the beat", @"Smoothest, and the most battery"];
    rate.choiceFooter = @"The lock screen draws a new picture each time, so it never moves as smoothly as the ring in the player.";
    SGWaitsOn(rate, SGKeyLockScreenVisualizer, NO);
    return @[on, rate];
}
