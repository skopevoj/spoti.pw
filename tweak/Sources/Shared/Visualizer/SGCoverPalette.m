// SGCoverPalette.h says what this does. The sampling is SGPalette.m's; this reads the picture into pixels for it.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "SGPalette.h"
#import "SGCoverPalette.h"
#import "Visualizer.h"

const NSInteger SGCoverPaletteColors = 5;
NSNotificationName const SGCoverPaletteDidChangeNotification = @"spotifyglass.coverPaletteChanged";

// Enough pixels for a cover's colours; more would only cost.
enum { kSide = 32 };

NSInteger SGCoverPaletteWay(void) {
    return SGInt(SGKeyVisualizerCoverColours, SGVisualizerCoverColoursSpots) * 2 + (SGFlag(SGKeyVisualizerCoverDark, NO) ? 1 : 0);
}

NSArray<UIColor *> *SGCoverPaletteOfImage(UIImage *image) {
    if (!image.CGImage) return nil;
    uint8_t pixels[kSide * kSide * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, kSide, kSide, 8, kSide * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, kSide, kSide), image.CGImage);
    CGContextRelease(context);
    float rgb[SGPaletteMaxColors * 3];
    NSInteger way = SGCoverPaletteWay();
    BOOL main = way / 2 == SGVisualizerCoverColoursMain;
    int count = (main ? SGPaletteCluster : SGPaletteSample)(pixels, kSide, kSide, kSide * 4, (int)SGCoverPaletteColors, (int)(way % 2), rgb);
    if (count < 1) return nil;
    NSMutableArray<UIColor *> *colors = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (int i = 0; i < count; i++) [colors addObject:[UIColor colorWithRed:rgb[i * 3] green:rgb[i * 3 + 1] blue:rgb[i * 3 + 2] alpha:1]];
    return colors;
}

#pragma mark - the playing track's

// What the palette was last read from: the track and the now playing artwork object, or the cover offered.
static NSString *sg_paletteTrack;
static __weak MPMediaItemArtwork *sg_paletteArtwork;
static BOOL sg_reading;
static NSArray<UIColor *> *sg_palette;
static CFTimeInterval sg_retryAt;
// The cover last offered, so the same one again does nothing, and when a cover was last offered: a ring on
// screen offers its cover twice a second, and while it does the now playing artwork is not read at all.
static const void *sg_offered;
static CFTimeInterval sg_offeredAt;
// A new track whose artwork is still the last track's, since when.
static CFTimeInterval sg_staleSince;
// How long a cover offered holds off the now playing artwork, and how long a new track waits for its own.
static const CFTimeInterval kOfferHolds = 2, kStaleWait = 4;

static BOOL offerHolds(void) {
    return sg_offeredAt > 0 && CACurrentMediaTime() - sg_offeredAt < kOfferHolds;
}

NSArray<UIColor *> *SGCoverPaletteForPlayingTrack(void) {
    NSString *track = SGKaraokePlayingTrack();
    CFTimeInterval now = CACurrentMediaTime();
    if (!track || sg_reading || now < sg_retryAt || offerHolds()) return sg_palette;
    id artwork = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo[MPMediaItemPropertyArtwork];
    if (![artwork isKindOfClass:MPMediaItemArtwork.class]) return sg_palette;
    BOOL sameTrack = [track isEqualToString:sg_paletteTrack];
    if (sameTrack && artwork == sg_paletteArtwork) return sg_palette;
    // Spotify hands the system the new track a moment before its cover: the artwork object still up is the
    // last track's, and read now its colours would stay for the whole song. It is waited out, up to a point
    // (two tracks of one album may well share the object).
    if (!sameTrack && artwork == sg_paletteArtwork) {
        if (!sg_staleSince) sg_staleSince = now;
        if (now - sg_staleSince < kStaleWait) return sg_palette;
    }
    sg_staleSince = 0;
    sg_reading = YES;
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.cover-palette", DISPATCH_QUEUE_SERIAL); });
    MPMediaItemArtwork *cover = artwork;
    NSString *wanted = [track copy];
    dispatch_async(queue, ^{
        NSArray<UIColor *> *colors = SGCoverPaletteOfImage([cover imageWithSize:CGSizeMake(64, 64)]);
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_reading = NO;
            // A cover was offered meanwhile: the one on screen wins.
            if (offerHolds()) return;
            // An image that could not be read is tried again the next time it is asked for.
            if (!colors) {
                sg_retryAt = CACurrentMediaTime() + 3;
                return;
            }
            sg_paletteTrack = wanted;
            sg_paletteArtwork = cover;
            sg_palette = colors;
            [NSNotificationCenter.defaultCenter postNotificationName:SGCoverPaletteDidChangeNotification object:nil];
        });
    });
    return sg_palette;
}

static dispatch_queue_t paletteQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.cover-palette.shown", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

void SGCoverPaletteOfferImage(UIImage *image) {
    if (!image.CGImage) return;
    sg_offeredAt = CACurrentMediaTime();
    if ((__bridge const void *)image == sg_offered) return;
    sg_offered = (__bridge const void *)image;
    dispatch_async(paletteQueue(), ^{
        NSArray<UIColor *> *colors = SGCoverPaletteOfImage(image);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!colors || sg_offered != (__bridge const void *)image) return;
            sg_palette = colors;
            // Read from the picture, not the artwork: the next read of the artwork, once no ring offers, is
            // a fresh one.
            sg_paletteTrack = nil;
            sg_paletteArtwork = nil;
            [NSNotificationCenter.defaultCenter postNotificationName:SGCoverPaletteDidChangeNotification object:nil];
        });
    });
}

void SGCoverPaletteReset(void) {
    sg_offered = NULL;
    sg_offeredAt = 0;
    sg_paletteTrack = nil;
    sg_paletteArtwork = nil;
    sg_staleSince = 0;
    sg_retryAt = 0;
}

#pragma mark - round the ring

NSArray<UIColor *> *SGCoverGradientStops(NSArray<UIColor *> *palette, BOOL mirror) {
    if (palette.count == 0) return nil;
    NSMutableArray<UIColor *> *stops = [palette mutableCopy];
    if (mirror) {
        for (NSInteger i = (NSInteger)palette.count - 2; i >= 0; i--) [stops addObject:palette[(NSUInteger)i]];
        if (palette.count == 1) [stops addObject:palette[0]];
    } else {
        [stops addObject:palette[0]];
    }
    return stops;
}

UIColor *SGCoverGradientColor(NSArray<UIColor *> *stops, CGFloat t) {
    if (stops.count == 0) return UIColor.whiteColor;
    if (stops.count == 1) return stops[0];
    t = MAX(0, MIN(1, t)) * (CGFloat)(stops.count - 1);
    NSUInteger from = MIN((NSUInteger)floor(t), stops.count - 2);
    CGFloat share = t - (CGFloat)from;
    CGFloat r0, g0, b0, r1, g1, b1;
    [stops[from] getRed:&r0 green:&g0 blue:&b0 alpha:NULL];
    [stops[from + 1] getRed:&r1 green:&g1 blue:&b1 alpha:NULL];
    return [UIColor colorWithRed:r0 + (r1 - r0) * share green:g0 + (g1 - g0) * share blue:b0 + (b1 - b0) * share alpha:1];
}

#pragma mark - the gradient colours

const NSInteger SGVisualizerRepeats = 4;

NSArray<UIColor *> *SGVisualizerSpectrumColours(void) {
    static NSArray<UIColor *> *hues;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];
        for (int i = 0; i < 6; i++) [list addObject:[UIColor colorWithHue:i / 6.0 saturation:0.75 brightness:1 alpha:1]];
        hues = list;
    });
    return hues;
}

NSArray<UIColor *> *SGVisualizerGradientColours(NSInteger colour, UIColor *accent) {
    if (colour == SGVisualizerColorSpectrum) return SGVisualizerSpectrumColours();
    if (colour != SGVisualizerColorCover) return nil;
    return SGCoverPaletteForPlayingTrack() ?: @[accent ?: UIColor.whiteColor];
}

static CGFloat luminance(UIColor *color) {
    CGFloat r = 1, g = 1, b = 1;
    [color getRed:&r green:&g blue:&b alpha:NULL];
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

const CGFloat SGVisualizerBacklightSplit = 0.45;

CGFloat SGVisualizerLuminance(NSArray<UIColor *> *colours) {
    if (!colours.count) return 1;
    CGFloat sum = 0;
    for (UIColor *colour in colours) sum += luminance(colour);
    return sum / colours.count;
}

UIColor *SGVisualizerBacklightColour(NSArray<UIColor *> *colours) {
    if (!SGFlag(SGKeyVisualizerBacklight, NO)) return nil;
    // White lifts what is behind dark bars less than black sinks what is behind light ones, to the eye, so
    // black is laid on stronger.
    return SGVisualizerLuminance(colours) < SGVisualizerBacklightSplit ? [UIColor colorWithWhite:1 alpha:0.42]
                                                                       : [UIColor colorWithWhite:0 alpha:0.62];
}

NSArray<UIColor *> *SGVisualizerGradientStops(NSArray<UIColor *> *colours, NSInteger gradient, BOOL mirror, BOOL spectrum) {
    if (!colours.count) return nil;
    if (colours.count == 1) return @[colours[0], colours[0]];
    switch (gradient) {
        case SGVisualizerGradientAround:
            if (spectrum && !mirror) return [colours arrayByAddingObject:colours[0]];
            return SGCoverGradientStops(colours, mirror);
        case SGVisualizerGradientRepeating: {
            // There and back, SGVisualizerRepeats times, ending where it began.
            NSMutableArray<UIColor *> *stops = [NSMutableArray array];
            for (NSInteger turn = 0; turn < SGVisualizerRepeats; turn++) {
                [stops addObjectsFromArray:colours];
                for (NSInteger i = (NSInteger)colours.count - 2; i >= 1; i--) [stops addObject:colours[(NSUInteger)i]];
            }
            [stops addObject:colours[0]];
            return stops;
        }
        case SGVisualizerGradientAlternating:
            return colours;
        default:
            // Along a bar: darkest inside, lightest at the tip, so every bar glows outward.
            if (spectrum) return colours;
            return [colours sortedArrayUsingComparator:^NSComparisonResult(UIColor *a, UIColor *b) {
                CGFloat x = luminance(a), y = luminance(b);
                return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
            }];
    }
}
