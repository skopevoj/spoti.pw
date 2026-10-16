// Spotify's now playing info passes through with the artist swapped for the current line, and a timer
// sends it again each time the line changes. Spotify itself only ever sees its own dictionary back.
//
// The timer follows the playback rate rather than running from launch: a paused player's line does not
// move, so working it out ten times a second only wakes the phone. The lock screen keeps the line it
// was left on until the sound starts again.
//
// The lock screen visualizer (Shared/Visualizer/Visualizer.h) goes out the same way: while Spotify is not on
// screen and the sound moves, a second timer reads the bars, draws a frame on a queue of its own (the cover,
// fetched there and never on the main thread, in a ring of bars over it blurred, with the line under it
// when the line shows as the artwork) and sends the info again with that frame as the artwork.
#import <MediaPlayer/MediaPlayer.h>
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "LockScreenLyrics.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Sing/SGSingController.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Visualizer/Visualizer.h"
#import "Shared/Visualizer/SGCoverPalette.h"

// A tenth of a second: a new line is on the lock screen within that of being sung.
static const NSTimeInterval kTick = 0.1;
// Past a line's sung end by this much, with the next line at least this far off, the artist comes back.
static const NSInteger kBreakMs = 4000;
// About what the lock screen's artist row fits before it cuts the text off.
static const NSUInteger kMaxChars = 30;

// Spotify may set the info from any thread; the timer reads it on the main one.
static NSObject *sg_lock;
static NSDictionary *sg_spotifyInfo;
static CFAbsoluteTime sg_spotifyInfoAt;
static NSString *sg_shownLine;
static SGLockScreenLyricsPlace sg_place;
static BOOL sg_resending;
static NSTimer *sg_timer;
// Which of the two is on, read at launch, and the visualizer for CarPlay; the frame timer, the frame on show
// and whether one is being drawn.
static BOOL sg_lyricsOn, sg_visualizerOn, sg_carPlayOn, sg_playing, sg_rendering;
static NSTimer *sg_frameTimer;
static MPMediaItemArtwork *sg_frameArtwork;
static CFTimeInterval sg_frameAt;

static NSString *textOf(NSArray<SGKaraokeWord *> *words) {
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    return SGKaraokeLineText(line);
}

// A line longer than the artist row holds, split into even pieces rather than a full one and a stub.
// Each piece shows from its first word's estimated start.
static NSArray<NSArray<SGKaraokeWord *> *> *piecesOf(SGKaraokeLine *line) {
    NSUInteger length = textOf(line.words).length;
    NSUInteger count = MAX((length + kMaxChars - 1) / kMaxChars, 1);
    NSUInteger target = (length + count - 1) / count;
    NSMutableArray<NSArray<SGKaraokeWord *> *> *pieces = [NSMutableArray array];
    NSMutableArray<SGKaraokeWord *> *piece = [NSMutableArray array];
    NSUInteger pieceLength = 0;
    for (SGKaraokeWord *word in line.words) {
        NSUInteger gap = pieceLength && !word.joined ? 1 : 0;
        NSUInteger withWord = pieceLength ? pieceLength + gap + word.text.length : word.text.length;
        if (pieceLength && (withWord > kMaxChars || (withWord > target && pieces.count + 1 < count))) {
            [pieces addObject:piece];
            piece = [NSMutableArray array];
            withWord = word.text.length;
        }
        [piece addObject:word];
        pieceLength = withWord;
    }
    if (piece.count) [pieces addObject:piece];
    return pieces;
}

// Seconds into the track at `now`, run on from what Spotify last reported.
static double elapsedAt(NSDictionary *info, CFAbsoluteTime reportedAt, CFAbsoluteTime now) {
    SPTPlayerState *state = SGPlayerState();
    double position;
    if ([state.track.trackTitle isEqualToString:info[MPMediaItemPropertyTitle]] && SGSingPosition(state, &position)) return position;
    double rate = [info[MPNowPlayingInfoPropertyPlaybackRate] doubleValue];
    return [info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue] + rate * (now - reportedAt);
}

// nil between lines and for a track without synced lyrics, plain text included. `full` and `next` are the
// whole line and the one after it, for the artwork.
static NSString *lineFor(NSDictionary *info, double elapsed, NSString **full, NSString **next) {
    if (full) *full = nil;
    if (next) *next = nil;
    if (!sg_lyricsOn) return nil;
    SPTPlayerState *state = [(id<SPTPlayer>)SGKaraokePlayer() state];
    // The player's track can lag behind the now playing info; its lyrics would then be another song's.
    if (![state.track.trackTitle isEqualToString:info[MPMediaItemPropertyTitle]]) return nil;
    NSString *trackID = SGKaraokePlayingTrack();
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(trackID);
    if (!lines) {
        SGKaraokeRequestLyrics(trackID);
        return nil;
    }
    // Plain text has no line being sung to show.
    if (SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone) return nil;
    NSInteger position = (NSInteger)(elapsed * 1000);
    NSInteger index = SGKaraokeLeadLine(lines, position);
    if (index < 0) return nil;
    BOOL nextFarOff = index + 1 == (NSInteger)lines.count || lines[index + 1].start - position > kBreakMs;
    if (position > lines[index].end + kBreakMs && nextFarOff) return nil;
    if (full) *full = SGKaraokeLineText(lines[index]);
    if (next && !nextFarOff) *next = SGKaraokeLineText(lines[index + 1]);
    NSString *shown = nil;
    for (NSArray<SGKaraokeWord *> *piece in piecesOf(lines[index])) {
        if (!shown || piece.firstObject.start <= position) shown = textOf(piece);
    }
    return shown;
}

#pragma mark - the lyrics as the artwork

// The cover blurred and darkened, made once per cover Spotify hands over.
static NSObject *sg_artworkLock;
static __weak MPMediaItemArtwork *sg_backdropOf;
static UIImage *sg_backdrop;
static const CGFloat kArtworkSide = 600;

// The cover itself, asked of Spotify's artwork once per cover and never on the main thread, where Spotify's
// handler can wait on that thread.
static __weak MPMediaItemArtwork *sg_coverOf;
static UIImage *sg_cover;

static UIImage *coverFor(MPMediaItemArtwork *cover) {
    if (!cover || NSThread.isMainThread) return nil;
    @synchronized (sg_artworkLock) {
        if (cover == sg_coverOf && sg_cover) return sg_cover;
    }
    UIImage *image = [cover imageWithSize:CGSizeMake(kArtworkSide, kArtworkSide)];
    @synchronized (sg_artworkLock) {
        sg_coverOf = cover;
        sg_cover = image;
    }
    return image;
}

// The cover's colours for the Cover gradient, worked out once per artwork object and way of reading them, on
// the frame queue.
static __weak MPMediaItemArtwork *sg_paletteOf;
static NSArray<UIColor *> *sg_paletteColors;
static NSInteger sg_paletteReading;

static NSArray<UIColor *> *paletteFor(MPMediaItemArtwork *cover) {
    if (!cover) return nil;
    NSInteger reading = SGCoverPaletteWay();
    @synchronized (sg_artworkLock) {
        if (cover == sg_paletteOf && reading == sg_paletteReading && sg_paletteColors) return sg_paletteColors;
    }
    NSArray<UIColor *> *colors = SGCoverPaletteOfImage(coverFor(cover));
    @synchronized (sg_artworkLock) {
        sg_paletteOf = cover;
        sg_paletteReading = reading;
        sg_paletteColors = colors;
    }
    return colors;
}

static UIImage *backdropFor(MPMediaItemArtwork *cover) {
    @synchronized (sg_artworkLock) {
        if (cover && cover == sg_backdropOf && sg_backdrop) return sg_backdrop;
    }
    UIImage *image = coverFor(cover);
    UIImage *backdrop = nil;
    if (image.CGImage) {
        static CIContext *context;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ context = [CIContext contextWithOptions:nil]; });
        CIImage *input = [[CIImage imageWithCGImage:image.CGImage] imageByClampingToExtent];
        CIImage *blurred = [input imageByApplyingGaussianBlurWithSigma:28];
        CGRect extent = [CIImage imageWithCGImage:image.CGImage].extent;
        CGImageRef cg = [context createCGImage:blurred fromRect:extent];
        if (cg) {
            backdrop = [UIImage imageWithCGImage:cg];
            CGImageRelease(cg);
        }
    }
    @synchronized (sg_artworkLock) {
        sg_backdropOf = cover;
        sg_backdrop = backdrop;
    }
    return backdrop;
}

static UIImage *lyricsImage(UIImage *backdrop, NSString *line, NSString *next) {
    CGSize size = CGSizeMake(kArtworkSide, kArtworkSide);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect bounds = (CGRect){CGPointZero, size};
        if (backdrop) [backdrop drawInRect:bounds];
        [[UIColor colorWithWhite:0 alpha:backdrop ? 0.5 : 1] setFill];
        UIRectFillUsingBlendMode(bounds, kCGBlendModeNormal);
        CGFloat side = 44, width = size.width - 2 * side;
        NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
        paragraph.lineBreakMode = NSLineBreakByWordWrapping;
        paragraph.lineSpacing = 2;
        NSDictionary *lineStyle = @{NSFontAttributeName: [UIFont systemFontOfSize:52 weight:UIFontWeightBold],
                                    NSForegroundColorAttributeName: UIColor.whiteColor, NSParagraphStyleAttributeName: paragraph};
        NSDictionary *nextStyle = @{NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold],
                                    NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.45], NSParagraphStyleAttributeName: paragraph};
        CGRect lineBox = [line boundingRectWithSize:CGSizeMake(width, size.height * 0.62) options:NSStringDrawingUsesLineFragmentOrigin attributes:lineStyle context:nil];
        CGRect nextBox = next.length ? [next boundingRectWithSize:CGSizeMake(width, size.height * 0.25) options:NSStringDrawingUsesLineFragmentOrigin attributes:nextStyle context:nil] : CGRectZero;
        CGFloat gap = next.length ? 22 : 0;
        CGFloat lineHeight = MIN(ceil(lineBox.size.height), size.height * 0.62), nextHeight = MIN(ceil(nextBox.size.height), size.height * 0.25);
        CGFloat top = MAX(side, (size.height - lineHeight - gap - nextHeight) / 2);
        [line drawWithRect:CGRectMake(side, top, width, lineHeight) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine attributes:lineStyle context:nil];
        if (next.length) {
            [next drawWithRect:CGRectMake(side, top + lineHeight + gap, width, nextHeight) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine attributes:nextStyle context:nil];
        }
    }];
}

// The line and the next one over the cover, drawn when the lock screen asks for the picture.
static MPMediaItemArtwork *lyricsArtwork(MPMediaItemArtwork *cover, NSString *line, NSString *next) {
    CGSize size = CGSizeMake(kArtworkSide, kArtworkSide);
    return [[MPMediaItemArtwork alloc] initWithBoundsSize:size requestHandler:^UIImage *(CGSize wanted) {
        // Spotify's own handler can wait on the main thread, so it is never asked from there.
        if (NSThread.isMainThread) {
            @synchronized (sg_artworkLock) {
                return lyricsImage(sg_backdropOf == cover ? sg_backdrop : nil, line, next);
            }
        }
        return lyricsImage(backdropFor(cover), line, next);
    }];
}

static NSDictionary *withLine(NSDictionary *info, NSString *line, NSString *full, NSString *next, double elapsed) {
    NSMutableDictionary *shown = [info mutableCopy];
    if (line && sg_place != SGLockScreenLyricsArtwork) shown[MPMediaItemPropertyArtist] = line;
    // The visualizer's frame is the artwork while it draws, with the line in it.
    if (sg_frameArtwork) shown[MPMediaItemPropertyArtwork] = sg_frameArtwork;
    else if (full.length && sg_place != SGLockScreenLyricsArtist) {
        id cover = info[MPMediaItemPropertyArtwork];
        shown[MPMediaItemPropertyArtwork] = lyricsArtwork([cover isKindOfClass:MPMediaItemArtwork.class] ? cover : nil, full, next);
    }
    // iOS reads a resent elapsed time as the position now, so Spotify's older one would jump the bar back.
    shown[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(elapsed);
    return shown;
}

static void tick(void) {
    NSDictionary *info;
    CFAbsoluteTime reportedAt;
    @synchronized (sg_lock) {
        info = sg_spotifyInfo;
        reportedAt = sg_spotifyInfoAt;
    }
    if (!info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double elapsed = elapsedAt(info, reportedAt, now);
    NSString *full, *next;
    NSString *line = lineFor(info, elapsed, &full, &next);
    // What is on show: the artist row's piece and, for the artwork, the whole line and the next.
    NSString *key = [NSString stringWithFormat:@"%@\n%@\n%@", line ?: @"", sg_place != SGLockScreenLyricsArtist ? full ?: @"" : @"", sg_place != SGLockScreenLyricsArtist ? next ?: @"" : @""];
    if ([key isEqualToString:sg_shownLine]) return;
    sg_shownLine = key;
    sg_resending = YES;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = withLine(info, line, full, next, elapsed);
    sg_resending = NO;
}

// Sends Spotify's info again as it should show now, whether or not the line moved.
static void resend(void) {
    NSDictionary *info;
    CFAbsoluteTime reportedAt;
    @synchronized (sg_lock) {
        info = sg_spotifyInfo;
        reportedAt = sg_spotifyInfoAt;
    }
    if (!info) return;
    double elapsed = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] ? elapsedAt(info, reportedAt, CFAbsoluteTimeGetCurrent()) : 0;
    NSString *full, *next;
    NSString *line = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] ? lineFor(info, elapsed, &full, &next) : nil;
    sg_shownLine = [NSString stringWithFormat:@"%@\n%@\n%@", line ?: @"", sg_place != SGLockScreenLyricsArtist ? full ?: @"" : @"", sg_place != SGLockScreenLyricsArtist ? next ?: @"" : @""];
    NSMutableDictionary *shown = [withLine(info, line, full, next, elapsed) mutableCopy];
    if (!info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) [shown removeObjectForKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    sg_resending = YES;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = shown;
    sg_resending = NO;
}

#pragma mark - the visualizer as the artwork

static dispatch_queue_t frameQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.lockscreen.visualizer", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// One frame: the bars now, drawn off the main thread, then sent. A frame still being drawn is not waited on;
// the next tick takes the newest bars instead.
static void frameTick(void) {
    if (sg_rendering) return;
    NSDictionary *info;
    CFAbsoluteTime reportedAt;
    @synchronized (sg_lock) {
        info = sg_spotifyInfo;
        reportedAt = sg_spotifyInfoAt;
    }
    if (!info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) return;
    CFTimeInterval now = CACurrentMediaTime();
    float elapsed = sg_frameAt > 0 ? (float)(now - sg_frameAt) : 1 / 10.0f;
    sg_frameAt = now;
    // The frame draws a stroke a bar, so a ring of a thousand is drawn with half as many.
    NSInteger bands = MIN(SGVisualizerBarCount(), (NSInteger)512);
    if (SGEnabled(SGKeyVisualizerMirror)) bands = MAX(8, bands / 2);
    float bars[512];
    SGVisualizerReadBars(bars, bands, elapsed);
    NSData *levels = [NSData dataWithBytes:bars length:sizeof(float) * (NSUInteger)bands];
    NSString *full = nil, *next = nil;
    if (sg_place != SGLockScreenLyricsArtist) lineFor(info, elapsedAt(info, reportedAt, CFAbsoluteTimeGetCurrent()), &full, &next);
    id cover = info[MPMediaItemPropertyArtwork];
    MPMediaItemArtwork *artwork = [cover isKindOfClass:MPMediaItemArtwork.class] ? cover : nil;
    BOOL coloured = SGInt(SGKeyVisualizerColor, SGVisualizerColorAccent) == SGVisualizerColorCover;
    sg_rendering = YES;
    dispatch_async(frameQueue(), ^{
        UIImage *frame = SGVisualizerDrawFrame(kArtworkSide, coverFor(artwork), backdropFor(artwork), levels.bytes, bands,
                                               [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1],
                                               coloured ? paletteFor(artwork) : nil, full, next);
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_rendering = NO;
            if (!sg_frameTimer || !frame) return;
            sg_frameArtwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(kArtworkSide, kArtworkSide)
                                                             requestHandler:^UIImage *(CGSize wanted) { return frame; }];
            resend();
        });
    });
}

// CarPlay is connected: the sound goes to the car, or Spotify has a CarPlay scene up (CarPlay's role for a
// scene, by name, as the CarPlay framework is not linked).
static BOOL carPlayConnected(void) {
    for (AVAudioSessionPortDescription *port in AVAudioSession.sharedInstance.currentRoute.outputs) {
        if ([port.portType isEqualToString:AVAudioSessionPortCarAudio]) return YES;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene.session.role isEqualToString:@"CPTemplateApplicationSceneSessionRoleApplication"]) return YES;
    }
    return NO;
}

// Frames are drawn while the sound moves and either Spotify is not what is on screen (the lock screen
// visualizer) or CarPlay is connected (the CarPlay visualizer).
static void updateFrames(void) {
    BOOL away = sg_visualizerOn && UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
    BOOL car = sg_carPlayOn && carPlayConnected();
    BOOL run = sg_playing && (away || car);
    if (run == (sg_frameTimer != nil)) return;
    SGVisualizerSetLockScreenListening(run);
    if (run) {
        sg_frameAt = 0;
        sg_frameTimer = [NSTimer timerWithTimeInterval:1.0 / MAX(1, SGLockScreenVisualizerFramesPerSecond()) repeats:YES
                                                 block:^(NSTimer *t) { frameTick(); }];
        sg_frameTimer.tolerance = 0.01;
        [NSRunLoop.mainRunLoop addTimer:sg_frameTimer forMode:NSRunLoopCommonModes];
        return;
    }
    [sg_frameTimer invalidate];
    sg_frameTimer = nil;
    // Back to the cover, or the lyrics' artwork, as the frames stop.
    if (sg_frameArtwork) {
        sg_frameArtwork = nil;
        resend();
    }
}

// Main thread, as everything the timer touches is.
static void setTicking(BOOL on) {
    if (on != sg_playing) {
        sg_playing = on;
        updateFrames();
    }
    if (!sg_lyricsOn) on = NO;
    if (on == (sg_timer != nil)) return;
    if (!on) {
        [sg_timer invalidate];
        sg_timer = nil;
        return;
    }
    sg_timer = [NSTimer timerWithTimeInterval:kTick repeats:YES block:^(NSTimer *t) { tick(); }];
    [NSRunLoop.mainRunLoop addTimer:sg_timer forMode:NSRunLoopCommonModes];
}

// Whether the sound is moving. A rate Spotify did not report at all counts as moving: the line would
// stand still either way, and a missing key is no reason to leave the feature switched off for good.
static BOOL playingBy(NSDictionary *info) {
    NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
    return !rate || rate.doubleValue > 0;
}

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    if (sg_resending) {
        %orig;
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @synchronized (sg_lock) {
        sg_spotifyInfo = info;
        sg_spotifyInfoAt = now;
    }
    BOOL playing = playingBy(info) && info[MPNowPlayingInfoPropertyElapsedPlaybackTime] != nil;
    // Karaoke's lyrics are main-thread state; off it the info goes out as it is and the next tick adds the line.
    if (!NSThread.isMainThread || !info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_shownLine = nil;
            setTicking(playing);
        });
        %orig;
        return;
    }
    setTicking(playing);
    double elapsed = elapsedAt(info, now, now);
    NSString *full, *next;
    NSString *line = lineFor(info, elapsed, &full, &next);
    sg_shownLine = [NSString stringWithFormat:@"%@\n%@\n%@", line ?: @"", sg_place != SGLockScreenLyricsArtist ? full ?: @"" : @"", sg_place != SGLockScreenLyricsArtist ? next ?: @"" : @""];
    %orig(withLine(info, line, full, next, elapsed));
}

- (NSDictionary *)nowPlayingInfo {
    NSDictionary *info;
    @synchronized (sg_lock) {
        info = sg_spotifyInfo;
    }
    return info ?: %orig;
}
%end

%ctor {
    sg_lyricsOn = !SGOff("lockscreen") && SGFlag(SGKeyLockScreenLyrics, NO);
    sg_visualizerOn = !SGOff("visualizer") && SGFlag(SGKeyLockScreenVisualizer, NO);
    sg_carPlayOn = !SGOff("visualizer") && SGFlag(SGKeyVisualizerCarPlay, NO);
    if (!sg_lyricsOn && !sg_visualizerOn && !sg_carPlayOn) return;
    sg_lock = [NSObject new];
    sg_artworkLock = [NSObject new];
    // Without lock screen lyrics the line has nowhere to go but the visualizer's frame, and only if asked.
    sg_place = sg_lyricsOn ? (SGLockScreenLyricsPlace)MAX(0, MIN(2, SGInt(SGKeyLockScreenLyricsPlace, SGLockScreenLyricsArtist)))
                           : SGLockScreenLyricsArtist;
    %init;
    if (sg_visualizerOn || sg_carPlayOn) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // The app going to and from the screen, and CarPlay coming and going: its audio route, and its scene.
            for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                              UIApplicationDidEnterBackgroundNotification, UIApplicationWillEnterForegroundNotification,
                                              AVAudioSessionRouteChangeNotification, UISceneWillConnectNotification,
                                              UISceneDidDisconnectNotification]) {
                // A scene going is still among the connected ones as it says so: looked at again a moment later.
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *note) {
                    updateFrames();
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ updateFrames(); });
                }];
            }
        });
    }
    // The timers wait for Spotify to report a playing track; nothing before that has a line or a sound to show.
    SGLog(@"lock screen: lyrics %@, visualizer %@, CarPlay visualizer %@", sg_lyricsOn ? @"on" : @"off",
          sg_visualizerOn ? @"on" : @"off", sg_carPlayOn ? @"on" : @"off");
}
