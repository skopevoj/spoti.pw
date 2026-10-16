// Polls the player and sends the activity a new state only when what its view shows changes: the
// lyrics' line, what is up next, the control menu's tab, track, shuffle, repeat or sleep timer, or a
// pause. The view is read on every tick, so picking another one shows within a tick. Spotify keeps
// playing in the background, so the timer keeps running there too, and with it the sleep timer.
// The activity is started only while the app is in front, the one place ActivityKit allows it.
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/SGLibrary.h"
#import "Shared/Visualizer/Visualizer.h"
#import "Shared/Visualizer/SGCoverPalette.h"
#import "LiveActivity.h"

typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

API_AVAILABLE(ios(17.0))
@interface SGLiveActivityBridge : NSObject
@property (class, nonatomic, readonly) BOOL isShowing;
+ (void)showWithView:(NSInteger)view paused:(BOOL)paused line:(NSString *)line nextLine:(NSString *)nextLine
              titles:(NSArray<NSString *> *)titles artists:(NSArray<NSString *> *)artists uris:(NSArray<NSString *> *)uris
                 tab:(NSInteger)tab title:(NSString *)title artist:(NSString *)artist shuffle:(BOOL)shuffle repeatMode:(NSInteger)repeatMode
            timerEnd:(NSDate *)timerEnd timerEndOfTrack:(BOOL)timerEndOfTrack liked:(BOOL)liked
         translation:(NSString *)translation tint:(NSInteger)tint progress:(double)progress
          trackStart:(NSDate *)trackStart trackEnd:(NSDate *)trackEnd
                bars:(NSString *)bars barColours:(NSArray<NSNumber *> *)barColours coverGroup:(NSString *)coverGroup
            coverKey:(NSString *)coverKey coverThumbnail:(NSData *)coverThumbnail duration:(double)duration
           backlight:(BOOL)backlight;
+ (void)end;
@end

// The control menu's tabs, SGLyricsAttributes.Tab's values.
typedef NS_ENUM(NSInteger, SGLiveActivityTab) {
    SGLiveActivityTabControls = 0,
    SGLiveActivityTabQueue,
    SGLiveActivityTabTimer,
};

static const NSTimeInterval kTick = 0.25;
// Paused, the only thing on the card that still moves is the sleep timer, and a slower tick catches
// its end well within the second the card shows. Four ticks a second for a still card is a wake up
// eighty times a minute for a picture that does not change.
static const NSTimeInterval kPausedTick = 1;
// Past a line's sung end by this much, with the next line at least this far off, the line gives way to a note.
static const NSInteger kBreakMs = 4000;
// Seconds between attempts to start one, so a refused request (activities turned off) is not retried every tick.
static const NSTimeInterval kStartRetry = 10;
// Tracks up next: the queue view shows four on the lock screen (three in the Dynamic Island), the
// control menu's queue tab three.
static const NSUInteger kUpNextQueue = 4;
static const NSUInteger kUpNextPanel = 3;
// The end of track timer pauses this close to the end, so the next track never starts.
static const NSInteger kEndOfTrackMs = 500;

static NSTimer *sg_timer;
static NSTimeInterval sg_tickEvery;
static NSString *sg_shown;
static NSString *sg_missingLyrics;
static NSDate *sg_lastStart;
static SGLiveActivityTab sg_tab;
// The sleep timer: an end, or the end of the track it was set on.
// The tracks the card saved to Liked Songs this session, by their base62 id.
static NSMutableSet<NSString *> *sg_liked;
static NSDate *sg_sleepEnd;
static NSString *sg_sleepTrack;

static void tick(void) API_AVAILABLE(ios(17.0));

// An NSTimer cannot be asked to change pace, so changing it is putting one down and another up.
static void startTimer(NSTimeInterval every) API_AVAILABLE(ios(17.0)) {
    [sg_timer invalidate];
    sg_tickEvery = every;
    sg_timer = [NSTimer timerWithTimeInterval:every repeats:YES block:^(NSTimer *t) { tick(); }];
    [NSRunLoop.mainRunLoop addTimer:sg_timer forMode:NSRunLoopCommonModes];
}

// Sends `shown`, what the activity is to show as one string, unless it is showing that already; starts
// the activity when there is none and the app is in front.
static void send(NSString *shown, void (^show)(void)) API_AVAILABLE(ios(17.0)) {
    if (SGLiveActivityBridge.isShowing) {
        if ([shown isEqualToString:sg_shown]) return;
    } else {
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        if (sg_lastStart && -sg_lastStart.timeIntervalSinceNow < kStartRetry) return;
        sg_lastStart = [NSDate date];
    }
    sg_shown = shown;
    show();
}

// A track's URI as a string; the player hands out NSURL or NSString.
static NSString *uriOf(SPTPlayerTrack *track) {
    id uri = track.URI;
    if ([uri isKindOfClass:NSURL.class]) return [(NSURL *)uri absoluteString];
    return [uri isKindOfClass:NSString.class] ? uri : nil;
}

// The state's tracks up next, skipping what is not a track or has no title or URI.
static NSArray<SPTPlayerTrack *> *upNext(SPTPlayerState *state) {
    NSMutableArray<SPTPlayerTrack *> *tracks = [NSMutableArray array];
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    for (id track in [future isKindOfClass:NSArray.class] ? future : @[]) {
        if (![track isKindOfClass:objc_getClass("SPTPlayerTrack")]) continue;
        if (![(SPTPlayerTrack *)track trackTitle].length || !uriOf(track)) continue;
        [tracks addObject:track];
    }
    return tracks;
}

// 0 off, 1 the playlist or album, 2 the track.
static NSInteger repeatModeOf(SPTPlayerOptions *options) {
    return options.repeatingTrack ? 2 : options.repeatingContext ? 1 : 0;
}

// The cover's colour, the average of the artwork Spotify hands the system's now playing, worked out once per
// cover and brightened a little so a dark cover still tints the card. -1 until there is one.
static NSString *sg_tintTrack;
static BOOL sg_tinting;
static NSInteger sg_tint = -1;

// Spotify's artwork handler is not ours to call on the main thread: it can wait on that thread itself, which
// froze the app the moment a song started. The cover is read on a queue of its own and its tint kept for the
// next tick; the first ticks of a new cover carry the last one's.
static NSInteger tintOfImage(UIImage *image) {
    if (!image.CGImage) return -1;
    unsigned char pixel[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return -1;
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(context);
    CGFloat hue, saturation, brightness;
    UIColor *average = [UIColor colorWithRed:pixel[0] / 255.0 green:pixel[1] / 255.0 blue:pixel[2] / 255.0 alpha:1];
    [average getHue:&hue saturation:&saturation brightness:&brightness alpha:NULL];
    UIColor *lifted = [UIColor colorWithHue:hue saturation:MIN(1, saturation * 1.2) brightness:MAX(0.55, brightness) alpha:1];
    CGFloat r, g, b;
    [lifted getRed:&r green:&g blue:&b alpha:NULL];
    return (NSInteger)lround(r * 255) << 16 | (NSInteger)lround(g * 255) << 8 | (NSInteger)lround(b * 255);
}

static NSInteger coverTint(void) {
    // Once per track and one at a time: Spotify may hand over a new artwork object with every update.
    NSString *track = SGKaraokePlayingTrack();
    if (!track || sg_tinting || [track isEqualToString:sg_tintTrack]) return sg_tint;
    id artwork = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo[MPMediaItemPropertyArtwork];
    if (![artwork isKindOfClass:MPMediaItemArtwork.class]) return sg_tint;
    sg_tintTrack = [track copy];
    sg_tinting = YES;
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.cover-tint", DISPATCH_QUEUE_SERIAL); });
    MPMediaItemArtwork *cover = artwork;
    dispatch_async(queue, ^{
        NSInteger tint = tintOfImage([cover imageWithSize:CGSizeMake(32, 32)]);
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_tinting = NO;
            if (tint >= 0 && [track isEqualToString:sg_tintTrack]) sg_tint = tint;
        });
    });
    return sg_tint;
}

#pragma mark - the player view

// The cover for the player view: a file in the first App Group the app is entitled to (sorted, as the App
// Group shim sorts them, extension/AppGroups), which the widget reads if it may open that group too, and a
// small picture carried in the state for when it may not; with them, the cover's colours for the bars. Read
// once per track, off the main thread, from the artwork Spotify hands the system's now playing, as coverTint.
static const CGFloat kCoverSide = 240, kThumbnailSide = 40;
enum { kLiveBands = 24 };
static NSString *sg_coverTrack, *sg_coverGroup, *sg_coverKey;
static NSData *sg_coverThumbnail;
static NSArray<NSNumber *> *sg_barColours;
static BOOL sg_coverReading;
// The bars as last sent, and when.
static NSString *sg_barsText = @"";
static CFTimeInterval sg_barsAt;

static NSURL *coverFolder(NSString **groupOut) {
    static NSURL *folder;
    static NSString *group;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SecTaskRef task = SecTaskCreateFromSelf(NULL);
        NSArray *groups = nil;
        if (task) {
            groups = CFBridgingRelease(SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.security.application-groups"), NULL));
            CFRelease(task);
        }
        if (![groups isKindOfClass:NSArray.class]) return;
        for (NSString *candidate in [groups sortedArrayUsingSelector:@selector(compare:)]) {
            if (![candidate isKindOfClass:NSString.class]) continue;
            NSURL *container = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:candidate];
            if (!container) continue;
            folder = [container URLByAppendingPathComponent:@"Library/SpotifyGlass/LiveActivity" isDirectory:YES];
            [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
            group = candidate;
            break;
        }
        SGLog(@"live activity: the cover goes %@", group ? [@"into the App Group " stringByAppendingString:group] : @"only into the state (no App Group)");
    });
    if (groupOut) *groupOut = group;
    return folder;
}

static UIImage *scaled(UIImage *image, CGFloat side) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, side, side)];
    }];
}

static NSInteger rgbOf(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0;
    [color getRed:&r green:&g blue:&b alpha:NULL];
    return (NSInteger)lround(r * 255) << 16 | (NSInteger)lround(g * 255) << 8 | (NSInteger)lround(b * 255);
}

// The way the bars' colours were read for sg_coverTrack (SGCoverPaletteWay), and the artwork object they were
// read from: another of either is read again.
static NSInteger sg_coverColours;
static __weak MPMediaItemArtwork *sg_coverArtwork;
// A new track whose artwork is still the last track's, since when: Spotify hands the system the new track a
// moment before its cover, and read then the last song's cover would stay up for the whole of this one.
static CFTimeInterval sg_coverStaleSince;

static void refreshCover(NSString *trackID) {
    NSInteger colours = SGCoverPaletteWay();
    if (!trackID || sg_coverReading) return;
    id artwork = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo[MPMediaItemPropertyArtwork];
    if (![artwork isKindOfClass:MPMediaItemArtwork.class]) return;
    BOOL sameTrack = [trackID isEqualToString:sg_coverTrack];
    if (sameTrack && colours == sg_coverColours && artwork == sg_coverArtwork) return;
    if (!sameTrack && artwork == sg_coverArtwork) {
        CFTimeInterval now = CACurrentMediaTime();
        if (!sg_coverStaleSince) sg_coverStaleSince = now;
        if (now - sg_coverStaleSince < 4) return;
    }
    sg_coverStaleSince = 0;
    sg_coverArtwork = artwork;
    sg_coverTrack = [trackID copy];
    sg_coverColours = colours;
    sg_coverReading = YES;
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.liveactivity.cover", DISPATCH_QUEUE_SERIAL); });
    MPMediaItemArtwork *cover = artwork;
    NSString *track = sg_coverTrack;
    dispatch_async(queue, ^{
        UIImage *image = [cover imageWithSize:CGSizeMake(kCoverSide, kCoverSide)];
        NSString *group = nil, *key = nil;
        NSData *thumbnail = nil;
        NSMutableArray<NSNumber *> *colours = [NSMutableArray array];
        if (image.CGImage) {
            NSURL *folder = coverFolder(&group);
            if (folder) {
                // A name a track, so the widget never shows a cover the file has since been replaced with.
                key = track;
                NSData *data = UIImageJPEGRepresentation(scaled(image, kCoverSide), 0.8);
                NSURL *file = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"cover-%@.jpg", key]];
                if (![data writeToURL:file options:NSDataWritingAtomic error:nil]) group = key = nil;
                for (NSURL *old in [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil]) {
                    if (![old.lastPathComponent isEqualToString:file.lastPathComponent]) [NSFileManager.defaultManager removeItemAtURL:old error:nil];
                }
            }
            thumbnail = UIImageJPEGRepresentation(scaled(image, kThumbnailSide), 0.5);
            NSArray<UIColor *> *palette = SGCoverPaletteOfImage(image);
            NSArray<UIColor *> *ordered = SGVisualizerGradientStops(palette, SGVisualizerGradientAlong, NO, NO);
            for (UIColor *colour in palette.count > 1 ? ordered : palette) [colours addObject:@(rgbOf(colour))];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_coverReading = NO;
            if (![track isEqualToString:sg_coverTrack]) return;
            sg_coverGroup = group ?: @"";
            sg_coverKey = key ?: @"";
            sg_coverThumbnail = thumbnail;
            sg_barColours = colours;
        });
    });
}

// The bars for the player view: while it is the view, the bars are on, the song plays and Spotify is not in
// front (where the card is not seen), read as often as the rate asks, as a hex digit a band.
static NSString *liveBars(BOOL player, BOOL paused) {
    BOOL want = player && !paused && !SGOff("visualizer") && SGEnabled(SGKeyLiveActivityBars)
                && UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
    SGVisualizerSetLiveActivityListening(want);
    if (!want) {
        sg_barsText = @"";
        return sg_barsText;
    }
    static const double rates[] = {1, 2, 4};
    double rate = rates[MAX(0, MIN(2, SGInt(SGKeyLiveActivityBarsRate, 1)))];
    CFTimeInterval now = CACurrentMediaTime();
    if (sg_barsText.length && now - sg_barsAt < 1 / rate - 0.02) return sg_barsText;
    float levels[kLiveBands];
    SGVisualizerReadBars(levels, kLiveBands, (float)MIN(0.25, sg_barsAt > 0 ? now - sg_barsAt : 0.25));
    sg_barsAt = now;
    char digits[kLiveBands + 1];
    for (NSUInteger i = 0; i < kLiveBands; i++) digits[i] = "0123456789abcdef"[MAX(0, MIN(15, lroundf(levels[i] * 15)))];
    digits[kLiveBands] = 0;
    sg_barsText = @(digits);
    return sg_barsText;
}

// The translation of the line being sung, in the Lyrics page's language, where the lyrics have one.
static NSString *translationOf(NSString *trackID) {
    if (!SGEnabled(SGKeyLiveActivityTranslation)) return @"";
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(trackID);
    NSInteger index = lines ? SGKaraokeLeadLine(lines, SGKaraokePositionMs()) : -1;
    NSString *translation = index >= 0 ? lines[index].translation : nil;
    return translation.length ? translation : @"";
}

// The line being sung and the one after it; before the first line, between lines and without lyrics
// at all, a note holds the place.
static NSString *lyricsLine(NSString *trackID, NSString **next) {
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(trackID);
    if (!lines) {
        SGKaraokeRequestLyrics(trackID);
        if (trackID && ![trackID isEqualToString:sg_missingLyrics]) {
            sg_missingLyrics = trackID;
            SGLog(@"live activity: no lyrics yet for %@", trackID);
        }
    }
    // Plain text has no line being sung: the note, as for a track with no lyrics.
    if (lines && SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone) lines = nil;
    NSInteger position = SGKaraokePositionMs();
    // With two voices at once, the one that came in first, and the one singing over it as the next.
    NSInteger index = SGKaraokeLeadLine(lines, position);
    *next = index + 1 < (NSInteger)lines.count ? SGKaraokeLineText(lines[index + 1]) : @"";
    if (index < 0) return @"♪";
    SGKaraokeLine *current = lines[index];
    BOOL nextFarOff = index + 1 == (NSInteger)lines.count || lines[index + 1].start - position > kBreakMs;
    return position > current.end + kBreakMs && nextFarOff ? @"♪" : SGKaraokeLineText(current);
}

static void clearSleepTimer(void) {
    sg_sleepEnd = nil;
    sg_sleepTrack = nil;
}

// Pauses once the sleep timer is up: at its end, or just before the end of the track it was set on
// (on the next track, should the length not be known).
static void checkSleepTimer(id<SPTPlayer> player, SPTPlayerState *state, NSString *trackID) {
    BOOL up = NO;
    if (sg_sleepEnd) {
        up = sg_sleepEnd.timeIntervalSinceNow <= 0;
    } else if (sg_sleepTrack) {
        double duration = [state respondsToSelector:@selector(duration)] ? state.duration : 0;
        NSInteger position = SGKaraokePositionMs();
        up = ![trackID isEqualToString:sg_sleepTrack]
            || (duration > 0 && position >= 0 && duration * 1000 - position < kEndOfTrackMs);
    }
    if (!up) return;
    clearSleepTimer();
    if (!state.isPaused) [player pause:nil];
    SGLog(@"live activity: sleep timer up, paused");
}

static void tick(void) API_AVAILABLE(ios(17.0)) {
    id<SPTPlayer> player = SGKaraokePlayer();
    SPTPlayerState *state = player.state;
    SPTPlayerTrack *track = state.track;
    if (!track.trackTitle.length) return;
    NSString *trackID = SGKaraokePlayingTrack();
    checkSleepTimer(player, state, trackID);

    NSInteger view = SGInt(SGKeyLiveActivityView, SGLiveActivityLyrics);
    BOOL paused = state.isPaused;
    NSTimeInterval every = paused ? kPausedTick : kTick;
    if (sg_timer && sg_tickEvery != every) startTimer(every);
    NSString *line = @"", *next = @"";
    if (view == SGLiveActivityLyrics) line = lyricsLine(trackID, &next);

    NSMutableArray<NSString *> *titles = [NSMutableArray array], *artists = [NSMutableArray array], *uris = [NSMutableArray array];
    if (view == SGLiveActivityQueue || view == SGLiveActivityPanel) {
        NSUInteger limit = view == SGLiveActivityQueue ? kUpNextQueue : kUpNextPanel;
        for (SPTPlayerTrack *upcoming in upNext(state)) {
            if (titles.count == limit) break;
            [titles addObject:upcoming.trackTitle];
            [artists addObject:upcoming.artistName ?: @""];
            [uris addObject:uriOf(upcoming)];
        }
    }

    BOOL panel = view == SGLiveActivityPanel, playerView = view == SGLiveActivityPlayer;
    NSString *title = panel || playerView ? track.trackTitle : @"", *artist = panel || playerView ? track.artistName ?: @"" : @"";
    BOOL shuffle = panel && state.options.shufflingContext;
    NSInteger repeatMode = panel ? repeatModeOf(state.options) : 0;
    NSInteger tab = panel ? sg_tab : 0;
    NSDate *sleepEnd = sg_sleepEnd;
    BOOL endOfTrack = sg_sleepTrack != nil;
    BOOL liked = (panel || playerView) && trackID && [sg_liked containsObject:trackID];
    if (playerView) refreshCover(trackID);
    BOOL coverReady = playerView && [trackID isEqualToString:sg_coverTrack] && !sg_coverReading;
    NSString *bars = liveBars(playerView, paused);
    NSString *coverGroup = coverReady ? sg_coverGroup ?: @"" : @"", *coverKey = coverReady ? sg_coverKey ?: @"" : @"";
    NSData *coverThumbnail = coverReady ? sg_coverThumbnail : nil;
    NSArray<NSNumber *> *barColours = coverReady ? sg_barColours ?: @[] : @[];
    NSString *translation = view == SGLiveActivityLyrics && ![line isEqualToString:@"♪"] ? translationOf(trackID) : @"";
    NSInteger tint = coverTint();
    BOOL backlight = playerView && SGFlag(SGKeyVisualizerBacklight, NO);
    // The bar runs on its own from the track's start to its end while it plays, so only a seek, a pause or a
    // new track sends a new state; paused, it stands where it is.
    double duration = [state respondsToSelector:@selector(duration)] ? state.duration : 0;
    double position = MAX(0, SGKaraokePositionMs() / 1000.0);
    double progress = duration > 0 ? MIN(1, position / duration) : 0;
    NSDate *trackStart = !paused && duration > 0 ? [NSDate dateWithTimeIntervalSinceNow:-position] : nil;
    NSDate *trackEnd = trackStart ? [trackStart dateByAddingTimeInterval:duration] : nil;

    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObjects:@(view).stringValue, paused ? @"1" : @"0", line, next,
        @(tab).stringValue, title, artist, shuffle ? @"1" : @"0", @(repeatMode).stringValue,
        @((long long)sleepEnd.timeIntervalSince1970).stringValue, endOfTrack ? @"1" : @"0", liked ? @"1" : @"0", translation, @(tint).stringValue,
        paused ? @(lround(progress * 100)).stringValue : @(lround(trackStart.timeIntervalSince1970 / 2)).stringValue,
        bars, coverKey, @(coverThumbnail.length).stringValue, [barColours componentsJoinedByString:@","], backlight ? @"1" : @"0", nil];
    for (NSUInteger i = 0; i < titles.count; i++) [parts addObject:[NSString stringWithFormat:@"%@\t%@\t%@", titles[i], artists[i], uris[i]]];
    send([parts componentsJoinedByString:@"\n"], ^{
        [SGLiveActivityBridge showWithView:view paused:paused line:line nextLine:next titles:titles artists:artists uris:uris
                                        tab:tab title:title artist:artist shuffle:shuffle repeatMode:repeatMode
                                   timerEnd:sleepEnd timerEndOfTrack:endOfTrack liked:liked
                                translation:translation tint:tint progress:progress trackStart:trackStart trackEnd:trackEnd
                                       bars:bars barColours:barColours coverGroup:coverGroup coverKey:coverKey
                             coverThumbnail:coverThumbnail duration:duration backlight:backlight];
    });
}

// Like and dislike from the card (Shared/Player/SGLibrary.h). The card shows the change at once, the way
// its toggle already flipped, and goes back should Spotify say no.
static void saveTrack(NSString *trackID, BOOL save) {
    if (!trackID.length) return;
    if (save) [sg_liked addObject:trackID];
    else [sg_liked removeObject:trackID];
    BOOL asked = SGLibrarySaveTrack(trackID, save, ^(BOOL saved) {
        if (saved) [sg_liked addObject:trackID];
        else [sg_liked removeObject:trackID];
    });
    if (!asked && save) [sg_liked removeObject:trackID];
}

// A tap on a track up next: skips ahead to it, found again by its URI in case the queue moved since
// the card was drawn.
static void playQueued(NSString *uri) {
    id<SPTPlayer> player = SGKaraokePlayer();
    SPTPlayerTrack *target = nil;
    for (SPTPlayerTrack *track in upNext(player.state)) {
        if ([uriOf(track) isEqualToString:uri]) { target = track; break; }
    }
    if (!target || ![player respondsToSelector:@selector(skipToNextTrackWithOptions:track:)]) {
        SGLog(@"live activity: cannot play %@ (in the queue: %@, player %@)", uri, target ? @"yes" : @"no", player ? NSStringFromClass([player class]) : @"nil");
        return;
    }
    id result = [player skipToNextTrackWithOptions:nil track:target];
    SGLog(@"live activity: play %@ -> %@", uri, result);
}

// A tap in the control menu, one of SGLiveActivityActionIntent's actions.
static void runAction(NSString *action) {
    if (!sg_liked) sg_liked = [NSMutableSet set];
    id<SPTPlayer> player = SGKaraokePlayer();
    SPTPlayerState *state = player.state;
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@":"];
    NSString *name = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    id result = nil;
    if ([name isEqualToString:@"tab"]) {
        sg_tab = MAX(SGLiveActivityTabControls, MIN(SGLiveActivityTabTimer, value.integerValue));
    } else if ([name isEqualToString:@"toggle"]) {
        result = state.isPaused ? [player resume:nil] : [player pause:nil];
    } else if ([name isEqualToString:@"previous"]) {
        result = [player skipToPreviousTrackWithOptions:nil];
    } else if ([name isEqualToString:@"next"]) {
        result = [player skipToNextTrackWithOptions:nil];
    } else if ([name isEqualToString:@"shuffle"]) {
        result = [player setShufflingContext:!state.options.shufflingContext];
    } else if ([name isEqualToString:@"repeat"]) {
        // Off, then the playlist or album, then the track, then off again, the way Spotify's button goes.
        switch (repeatModeOf(state.options)) {
            case 0: result = [player setRepeatingContext:YES]; break;
            case 1: result = [player setRepeatingTrack:YES]; break;
            default:
                [player setRepeatingTrack:NO];
                result = [player setRepeatingContext:NO];
        }
    } else if ([name isEqualToString:@"like"]) {
        NSString *trackID = SGKaraokePlayingTrack();
        saveTrack(trackID, ![sg_liked containsObject:trackID]);
    } else if ([name isEqualToString:@"dislike"]) {
        NSString *trackID = SGKaraokePlayingTrack();
        if ([sg_liked containsObject:trackID]) saveTrack(trackID, NO);
        result = [player skipToNextTrackWithOptions:nil];
    } else if ([name isEqualToString:@"seek"]) {
        // A tap along the player view's bar: that share of the track.
        double duration = [state respondsToSelector:@selector(duration)] ? state.duration : 0;
        double share = MAX(0, MIN(1, value.doubleValue));
        if (duration <= 0 || ![player respondsToSelector:@selector(seekTo:)]) {
            SGLog(@"live activity: cannot seek (length %.0f s)", duration);
            return;
        }
        [player seekTo:share * duration];
        result = @(share * duration);
    } else if ([name isEqualToString:@"timer"]) {
        if ([value isEqualToString:@"cancel"]) {
            clearSleepTimer();
        } else if ([value isEqualToString:@"track"]) {
            clearSleepTimer();
            sg_sleepTrack = SGKaraokePlayingTrack();
        } else if ([value isEqualToString:@"add"]) {
            NSDate *from = sg_sleepEnd && sg_sleepEnd.timeIntervalSinceNow > 0 ? sg_sleepEnd : [NSDate date];
            sg_sleepEnd = [from dateByAddingTimeInterval:15 * 60];
        } else if (value.integerValue > 0) {
            clearSleepTimer();
            sg_sleepEnd = [NSDate dateWithTimeIntervalSinceNow:value.integerValue * 60];
        }
    } else {
        SGLog(@"live activity: unknown action %@", action);
        return;
    }
    SGLog(@"live activity: %@ -> %@", action, result);
}

void SGSetLiveActivityEnabled(BOOL on) {
    if (SGOff("liveactivity")) on = NO;
    if (@available(iOS 17.0, *)) {
        [sg_timer invalidate];
        sg_timer = nil;
        sg_shown = nil;
        sg_lastStart = nil;
        clearSleepTimer();
        if (!on) {
            SGVisualizerSetLiveActivityListening(NO);
            [SGLiveActivityBridge end];
            SGLog(@"live activity: off");
            return;
        }
        // iPadOS has no Live Activities: the timer would only ask ActivityKit, four times a second, for
        // nothing that can be shown.
        if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) {
            SGLog(@"live activity: not on this device");
            return;
        }
        static dispatch_once_t observing;
        dispatch_once(&observing, ^{
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            [center addObserverForName:@"SGLiveActivityPlay" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                if ([note.object isKindOfClass:NSString.class]) playQueued(note.object);
            }];
            // The new state goes out at once rather than on the next tick, the card being slow enough to redraw.
            [center addObserverForName:@"SGLiveActivityAction" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                if (![note.object isKindOfClass:NSString.class]) return;
                runAction(note.object);
                if (sg_timer) tick();
            }];
        });
        startTimer(kTick);
        SGLog(@"live activity: on");
    }
}

%ctor {
    if (@available(iOS 17.0, *)) {
        // It was the redesign's alone until it moved to Shared/; whoever had it on keeps it on.
        SGMigrateKey(SGKeyLiveActivityWas, SGKeyLiveActivity);
        SGMigrateKey(SGKeyLiveActivityViewWas, SGKeyLiveActivityView);
        BOOL on = SGFlag(SGKeyLiveActivity, NO);
        // Off, one left from a launch before the switch went off is ended.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (on) SGSetLiveActivityEnabled(YES);
            else [SGLiveActivityBridge end];
        });
    }
}
