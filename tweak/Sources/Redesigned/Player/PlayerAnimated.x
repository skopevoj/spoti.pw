// Player redesign: Animated artwork, the track's Canvas or its album's Apple Music cover looping muted over
// Fluid artwork and under the rest of the player, found the way the lock screen finds its clip but in an
// order of its own. Fluid artwork shows until the clip can be drawn and for a track without one.
#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Shared/LockScreenArtwork/SGArtworkFile.h"
#import "Shared/LockScreenArtwork/SGCanvas.h"
#import "Player.h"

static const NSTimeInterval kFadeIn = 0.6, kFadeOut = 0.45, kDimChange = 0.3;
// The dim holds the brighter part of a clip (the 75th percentile of a few frames' linear luminance) under
// this, where white text keeps 4.5:1 (7:1 with Increase Contrast), as Fluid artwork holds its own; never
// less than the least, and more under the lyrics. The clip dissolves into its own dark colour below.
static const float kCeiling = 0.18f, kCeilingContrast = 0.09f, kUnknownLight = 0.35f;
static const float kDimLeast = 0.1f, kDimLyrics = 0.15f, kDimMost = 0.8f;
static const NSTimeInterval kReadyWithin = 5;

static char kReadyContext, kViewKey;

#define say(format, ...) SGLog(@"redesign player: animated: " format, ##__VA_ARGS__)

#pragma mark - a clip

// Read the light and bottom-edge colour together from three small frames. The footer keeps that colour
// for the whole clip, so its controls never sit over moving detail or flicker with the video.
// `done` is on the main queue; unreadable frames leave the neutral field and kUnknownLight.
static void readLight(NSURL *file, void (^done)(float light, UIColor *edgeColor)) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:file options:nil]];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(48, 48);
    NSMutableData *lights = [NSMutableData data];
    __block NSUInteger pending = 3;
    __block double red = 0, green = 0, blue = 0, samples = 0;
    for (NSNumber *second in @[@0, @1, @2]) {
        [generator generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(second.doubleValue, 600) completionHandler:^(CGImageRef frame, CMTime actual, NSError *error) {
            (void)generator;
            enum { kSide = 16 };
            uint8_t px[kSide * kSide * 4] = {0};
            CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = frame ? CGBitmapContextCreate(px, kSide, kSide, 8, kSide * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast) : NULL;
            CGColorSpaceRelease(space);
            if (context) CGContextDrawImage(context, CGRectMake(0, 0, kSide, kSide), frame);
            CGContextRelease(context);
            float read[kSide * kSide];
            for (int i = 0; context && i < kSide * kSide; i++) {
                float c[3];
                for (int k = 0; k < 3; k++) c[k] = powf(px[i * 4 + k] / 255.0f, 2.2f);
                read[i] = 0.2126f * c[0] + 0.7152f * c[1] + 0.0722f * c[2];
            }
            @synchronized (lights) {
                if (context) {
                    [lights appendBytes:read length:sizeof read];
                    // Bitmap rows run top to bottom, as in SGRPalette's edge sampling.
                    for (int i = kSide * (kSide * 3 / 4); i < kSide * kSide; i++) {
                        red += px[i * 4];
                        green += px[i * 4 + 1];
                        blue += px[i * 4 + 2];
                        samples += 255;
                    }
                }
                if (--pending) return;
            }
            NSUInteger count = lights.length / sizeof(float);
            float *values = lights.mutableBytes;
            float light = kUnknownLight;
            if (count) {
                qsort_b(values, count, sizeof(float), ^int(const void *a, const void *b) {
                    float x = *(const float *)a, y = *(const float *)b;
                    return x < y ? -1 : x > y;
                });
                light = values[count * 3 / 4];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                UIColor *edge = samples ? [UIColor colorWithRed:red / samples green:green / samples blue:blue / samples alpha:1] : nil;
                done(light, edge);
            });
        }];
    }
}

@interface SGRPlayerClip : NSObject
@property (nonatomic, readonly) NSURL *file;
@property (nonatomic, readonly) AVPlayerLayer *layer;
@property (nonatomic, readonly) float light;   // negative until read
@property (nonatomic, readonly) UIColor *edgeColor;
// Once, on the main queue, when its first frame can be drawn and its light has been read.
@property (nonatomic, copy) void (^ready)(SGRPlayerClip *clip);
- (instancetype)initWithFile:(NSURL *)file;
- (void)setPlaying:(BOOL)playing;
- (void)stop;
@end

@implementation SGRPlayerClip {
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    BOOL _observing;
}

// The album hero's player: muted, never on AirPlay, letting the screen lock.
- (instancetype)initWithFile:(NSURL *)file {
    if (!(self = [super init])) return nil;
    _file = file;
    AVQueuePlayer *player = [AVQueuePlayer new];
    player.muted = YES;
    player.allowsExternalPlayback = NO;
    player.preventsDisplaySleepDuringVideoPlayback = NO;
    _looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:[AVPlayerItem playerItemWithURL:file]];
    _player = player;
    _layer = [AVPlayerLayer playerLayerWithPlayer:player];
    _layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    NSNull *off = NSNull.null;
    _layer.actions = @{@"bounds": off, @"position": off, @"frame": off, @"opacity": off};
    [_layer addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionInitial context:&kReadyContext];
    _observing = YES;
    _light = -1;
    __weak SGRPlayerClip *weakSelf = self;
    readLight(file, ^(float light, UIColor *edgeColor) {
        SGRPlayerClip *clip = weakSelf;
        if (!clip) return;
        clip->_light = light;
        clip->_edgeColor = edgeColor;
        [clip checkReady];
    });
    return self;
}

- (void)checkReady {
    void (^ready)(SGRPlayerClip *) = _ready;
    if (!ready || _light < 0 || !_layer.readyForDisplay) return;
    _ready = nil;
    ready(self);
}

- (void)dealloc {
    [self stop];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kReadyContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    __weak SGRPlayerClip *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf checkReady]; });
}

- (void)setPlaying:(BOOL)playing {
    if (playing && _player.rate == 0) [_player play];
    else if (!playing && _player.rate != 0) [_player pause];
}

- (void)stop {
    if (_observing) [_layer removeObserver:self forKeyPath:@"readyForDisplay" context:&kReadyContext];
    _observing = NO;
    _ready = nil;
    [_player pause];
    [_looper disableLooping];
    [_layer removeFromSuperlayer];
}

@end

#pragma mark - the view

// The clip over the field, with the dim and the shade that keep the player's text readable on it. The
// view fades as a whole between the field and a clip; one clip replacing another fades in over it.
@interface SGRPlayerAnimatedView : UIView
@property (nonatomic, readonly) SGRPlayerClip *clip;   // shown or coming in
@property (nonatomic, readonly) BOOL covers;           // a clip lies opaque over the whole field
@property (nonatomic, readonly) BOOL shown;            // on screen or fading in
@property (nonatomic, readonly) CFTimeInterval fadeEnds;
@property (nonatomic, copy) void (^coversChanged)(BOOL covers);
@property (nonatomic, copy) void (^shownChanged)(BOOL shown, NSTimeInterval duration);
@property (nonatomic, copy) void (^windowChanged)(void);
@property (nonatomic, copy) void (^neverReady)(SGRPlayerClip *clip);
- (void)showClip:(SGRPlayerClip *)clip;
- (void)clear:(BOOL)animated;
- (void)setPlaying:(BOOL)playing;
- (void)setLyricsUp:(BOOL)up animated:(BOOL)animated;
@end

@implementation SGRPlayerAnimatedView {
    CALayer *_clips;
    CALayer *_dim;
    CAGradientLayer *_shade;
    NSMutableArray<SGRPlayerClip *> *_leaving;   // under the one coming in until it is in
    BOOL _playing, _lyricsUp, _hasFrame;
    float _light;   // the shown clip's
    UIColor *_edgeColor;   // also the shown clip's, while its replacement is still loading
    CGFloat _controlsTop;
    NSUInteger _generation, _visibilityGeneration;
}

// Blending black at `dim` over sRGB scales linear light by about (1 - dim)^2.2.
static float dimFor(float light, BOOL lyricsUp) {
    float ceiling = SGRIncreaseContrast() ? kCeilingContrast : kCeiling;
    float need = light > ceiling ? 1 - powf(ceiling / light, 1 / 2.2f) : 0;
    return MIN(kDimMost, MAX(kDimLeast, need) + (lyricsUp ? kDimLyrics : 0));
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;
    self.layer.opacity = 0;
    _leaving = [NSMutableArray array];
    NSNull *off = NSNull.null;
    NSDictionary *still = @{@"bounds": off, @"position": off, @"frame": off, @"opacity": off,
                            @"sublayers": off, @"colors": off, @"locations": off};
    _clips = [CALayer layer];
    _clips.actions = still;
    [self.layer addSublayer:_clips];
    _dim = [CALayer layer];
    _dim.actions = still;
    _dim.backgroundColor = UIColor.blackColor.CGColor;
    _light = kUnknownLight;
    _dim.opacity = dimFor(_light, NO);
    [self.layer addSublayer:_dim];
    _shade = [CAGradientLayer layer];
    _shade.actions = still;
    [self.layer addSublayer:_shade];
    [self updateShade:NO];
    return self;
}

- (void)dealloc {
    [_clip stop];
    for (SGRPlayerClip *clip in _leaving) [clip stop];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _clips.frame = bounds;
    _dim.frame = bounds;
    _shade.frame = bounds;
    // The artwork band ends at the information row. Anchor the dissolve there, rather than to one
    // phone's screen height. Keep that anchor while the lyrics move the cover into their thumbnail.
    CGRect area = SGRPlayerArtworkAreaIn(self);
    if (!_lyricsUp && !SGRPlayerIsTransitioning() && !CGRectIsNull(area) && !CGRectIsEmpty(area))
        _controlsTop = CGRectGetMaxY(area);
    CGFloat height = bounds.size.height;
    if (height > 0) {
        CGFloat end = MIN(height, MAX(height * 0.4, _controlsTop > 0 ? _controlsTop : height * 0.64));
        CGFloat start = MAX(0, end - MIN(220, height * 0.25));
        CGFloat span = end - start;
        _shade.locations = @[@(start / height), @((start + span * 0.35) / height),
                             @((start + span * 0.72) / height), @(end / height),
                             @(MIN(1, end / height + 0.14)), @1];
    }
    _clip.layer.frame = bounds;
    for (SGRPlayerClip *clip in _leaving) clip.layer.frame = bounds;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (_windowChanged) _windowChanged();
}

- (void)setCovers:(BOOL)covers {
    if (covers == _covers) return;
    _covers = covers;
    if (_coversChanged) _coversChanged(covers);
}

static float shownOpacity(CALayer *layer) {
    return ((CALayer *)layer.presentationLayer ?: layer).opacity;
}

// From wherever it is now, so a fade caught halfway turns back without a jump.
static void fade(CALayer *layer, float to, NSTimeInterval duration) {
    float from = shownOpacity(layer);
    layer.opacity = to;
    if (duration <= 0 || fabsf(from - to) < 0.001f) {
        [layer removeAnimationForKey:@"fade"];
        return;
    }
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = @(from);
    animation.toValue = @(to);
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:animation forKey:@"fade"];
}

// A broad, soft dissolve into an opaque, artwork-tinted footer, like Music's player. The title sits
// over the darker end; below it the colour opens out slightly instead of fading all the way to black.
- (void)updateShade:(BOOL)animated {
    UIColor *color = SGRFieldColorFor(_edgeColor);
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    // The page palette deliberately lifts chroma. Behind playback controls the reference is more
    // subdued: keep the hue, but mix in some of its grey and lower it slightly.
    CGFloat grey = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    r = (r * 0.6 + grey * 0.4) * 0.9;
    g = (g * 0.6 + grey * 0.4) * 0.9;
    b = (b * 0.6 + grey * 0.4) * 0.9;
    color = [UIColor colorWithRed:r green:g blue:b alpha:1];
    UIColor *title = [UIColor colorWithRed:r * 0.72 green:g * 0.72 blue:b * 0.72 alpha:1];
    UIColor *bottom = [UIColor colorWithRed:r * 0.95 green:g * 0.95 blue:b * 0.95 alpha:1];
    NSArray *colors = @[(id)[title colorWithAlphaComponent:0].CGColor,
                        (id)[title colorWithAlphaComponent:0.22].CGColor,
                        (id)[title colorWithAlphaComponent:0.82].CGColor,
                        (id)title.CGColor, (id)color.CGColor, (id)bottom.CGColor];
    NSArray *from = ((CAGradientLayer *)_shade.presentationLayer ?: _shade).colors;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shade.colors = colors;
    [CATransaction commit];
    if (animated && from) {
        CABasicAnimation *change = [CABasicAnimation animationWithKeyPath:@"colors"];
        change.fromValue = from;
        change.toValue = colors;
        change.duration = kFadeIn;
        change.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [_shade addAnimation:change forKey:@"colors"];
    } else {
        [_shade removeAnimationForKey:@"colors"];
    }
}

// The view's own fade, which the covers keep in step with.
- (void)fadeTo:(BOOL)shown duration:(NSTimeInterval)duration {
    NSUInteger generation = ++_visibilityGeneration;
    if (!shown) [self setCovers:NO];   // wake the artwork field before the clip starts leaving
    float to = shown ? 1 : 0;
    if (fabsf(shownOpacity(self.layer) - to) < 0.001f) duration = 0;
    __weak SGRPlayerAnimatedView *weakSelf = self;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        SGRPlayerAnimatedView *view = weakSelf;
        if (view && generation == view->_visibilityGeneration) [view setCovers:shown];
    }];
    fade(self.layer, to, duration);
    [CATransaction commit];
    _fadeEnds = CACurrentMediaTime() + duration;
    if (shown == _shown) return;
    _shown = shown;
    if (_shownChanged) _shownChanged(shown, duration);
}

- (void)showClip:(SGRPlayerClip *)clip {
    if (!clip || clip == _clip) return;
    NSUInteger generation = ++_generation;
    if (_clip) [_leaving addObject:_clip];
    _clip = clip;
    clip.layer.frame = self.bounds;
    clip.layer.opacity = 0;
    [_clips addSublayer:clip.layer];
    [clip setPlaying:_playing && !_lyricsUp];
    __weak SGRPlayerAnimatedView *weakSelf = self;
    clip.ready = ^(SGRPlayerClip *ready) { [weakSelf fadeIn:ready generation:generation]; };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kReadyWithin * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRPlayerAnimatedView *view = weakSelf;
        if (!view || view.clip != clip || clip.layer.readyForDisplay) return;
        if (view.neverReady) view.neverReady(clip);
    });
}

- (void)dropLeaving {
    for (SGRPlayerClip *clip in _leaving) [clip stop];
    [_leaving removeAllObjects];
}

- (void)fadeIn:(SGRPlayerClip *)clip generation:(NSUInteger)generation {
    if (clip != _clip || generation != _generation) return;
    __weak SGRPlayerAnimatedView *weakSelf = self;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        SGRPlayerAnimatedView *view = weakSelf;
        if (!view || generation != view->_generation) return;
        [view dropLeaving];
    }];
    _light = clip.light;
    _edgeColor = clip.edgeColor;
    _hasFrame = YES;
    [self updateShade:shownOpacity(self.layer) > 0.01f];
    fade(_dim, dimFor(_light, _lyricsUp), shownOpacity(self.layer) > 0.01f ? kFadeIn : 0);
    say(@"%@ fades in, its light %.2f dimmed by %.2f", clip.file.lastPathComponent, _light, dimFor(_light, _lyricsUp));
    // Over a clip still on screen the new one fades in on top of it; over the field the whole view does.
    if (_leaving.count && shownOpacity(self.layer) > 0.01f) {
        clip.layer.opacity = 0;
        fade(clip.layer, 1, kFadeIn);
    } else {
        clip.layer.opacity = 1;
        [self dropLeaving];
    }
    [self fadeTo:!_lyricsUp duration:kFadeIn];
    [CATransaction commit];
}

- (void)clear:(BOOL)animated {
    if (!_clip && !_leaving.count && shownOpacity(self.layer) < 0.001f) return;
    NSUInteger generation = ++_generation;
    _hasFrame = NO;
    if (_clip) [_leaving addObject:_clip];
    _clip.ready = nil;
    _clip = nil;
    __weak SGRPlayerAnimatedView *weakSelf = self;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        SGRPlayerAnimatedView *view = weakSelf;
        if (view && generation == view->_generation) [view dropLeaving];
    }];
    [self fadeTo:NO duration:animated && self.window ? kFadeOut : 0];
    [CATransaction commit];
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    [_clip setPlaying:playing && !_lyricsUp];
    for (SGRPlayerClip *clip in _leaving) [clip setPlaying:playing && !_lyricsUp];
}

- (void)setLyricsUp:(BOOL)up animated:(BOOL)animated {
    BOOL changed = _lyricsUp != up;
    _lyricsUp = up;
    // Use the same artwork field as the non-animated player. Keep the clip ready, paused behind it,
    // so leaving lyrics can crossfade straight back without fetching or restarting the video.
    if (changed) {
        [self fadeTo:_hasFrame && !up duration:animated && self.window ? kFadeIn : 0];
        [self setPlaying:_playing];
    }
    fade(_dim, dimFor(_light, up), animated && self.window ? kDimChange : 0);
    [self updateShade:animated && self.window];
}

@end

#pragma mark - finding the clip

// What a track's sources gave: the clip on disk, or none from any of them.
@interface SGRPlayerFound : NSObject
@property (nonatomic, strong) NSURL *file;
@property (nonatomic, copy) NSString *source, *note;
@property (nonatomic) BOOL hadCanvas;   // the track's metadata carried a Canvas when it was asked
@end

@implementation SGRPlayerFound
@end

static __weak SGRPlayerAnimatedView *sg_view;
static __weak SGRArtworkField *sg_field;
static NSString *sg_wanted;   // the playing track, once its clip is asked for
static NSString *sg_next;     // the track up next, once its clip is fetched ahead
static NSMutableDictionary<NSString *, SGRPlayerFound *> *sg_found;
static NSMutableSet<NSString *> *sg_looking;
static NSHashTable *sg_videos;   // Spotify's own video views with a video on them
static BOOL sg_lyricsUp;
// Read at launch and when the choice changes, not on each of the plane's layout passes.
static BOOL sg_picked;

static void update(void);


static NSString *nameOf(NSString *source) {
    if ([source isEqualToString:SGArtworkSourceSpotify]) return @"Spotify Canvas";
    if ([source isEqualToString:SGArtworkSourceApple]) return @"Apple Music";
    return source ?: @"no source";
}

static SGCanvas *canvasOf(SPTPlayerTrack *track) {
    return SGCanvasFromMetadata([track respondsToSelector:@selector(metadata)] ? track.metadata : nil);
}

static SPTPlayerTrack *upNext(SPTPlayerState *state) {
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    id next = [future isKindOfClass:NSArray.class] ? [(NSArray *)future firstObject] : nil;
    return [next isKindOfClass:objc_getClass("SPTPlayerTrack")] ? next : nil;
}

// Why no clip may play at all right now, or nil.
static NSString *heldBack(void) {
    if (!sg_picked) return @"Fluid artwork is picked";
    if (NSProcessInfo.processInfo.lowPowerModeEnabled) return @"Low Power Mode";
    if (SGRReduceMotion()) return @"Reduce Motion";
    if (sg_videos.allObjects.count) return @"Spotify's own video is showing";
    return nil;
}

static BOOL stillWanted(NSString *uri) {
    return [uri isEqualToString:sg_wanted] || [uri isEqualToString:sg_next];
}

// A download joined from the lock screen fails when the lock screen cancels it, so a failure is asked once more.
static void fetch(SGCanvas *clip, BOOL again, void (^done)(NSURL *file, NSString *note)) {
    SGArtworkFetchAside(clip.identifier, clip.address, ^(NSURL *file, NSString *note) {
        void (^answer)(void) = ^{
            if (!file && !again) fetch(clip, YES, done);
            else done(file, note);
        };
        if (NSThread.isMainThread) answer();
        else dispatch_async(dispatch_get_main_queue(), answer);
    });
}

// The sources in order until one has a clip on disk. A clip already at hand answers before this returns.
static void walk(NSString *uri, SPTPlayerTrack *track, SGCanvas *canvas, NSArray<NSString *> *order, NSUInteger at,
                 void (^done)(NSURL *file, NSString *source, NSString *note)) {
    if (at >= order.count) {
        done(nil, nil, order.count ? [NSString stringWithFormat:@"none from %@", [order componentsJoinedByString:@", "]] : @"no source is on");
        return;
    }
    NSString *source = order[at];
    SGArtworkAsk(source, track, canvas, YES, ^(SGCanvas *clip, NSString *note) {
        if (!stillWanted(uri)) {
            done(nil, nil, @"moved on");
            return;
        }
        if (!clip.video) {
            say(@"%@ has no clip for %@ (%@)", nameOf(source), uri, clip ? @"a still canvas" : note);
            walk(uri, track, canvas, order, at + 1, done);
            return;
        }
        fetch(clip, NO, ^(NSURL *file, NSString *fetched) {
            if (file) {
                done(file, source, [NSString stringWithFormat:@"%@, %@", note, fetched]);
                return;
            }
            say(@"%@'s clip for %@ not fetched: %@", nameOf(source), uri, fetched);
            if (stillWanted(uri)) walk(uri, track, canvas, order, at + 1, done);
            else done(nil, nil, @"moved on");
        });
    });
}

static void arrived(NSString *uri);
static void prefetchNext(void);

static void find(NSString *uri, SPTPlayerTrack *track, SGCanvas *canvas) {
    if (!uri || sg_found[uri] || [sg_looking containsObject:uri]) return;
    [sg_looking addObject:uri];
    walk(uri, track, canvas, SGArtworkOrderFor(SGRKeyPlayerArtworkSources), 0, ^(NSURL *file, NSString *source, NSString *note) {
        [sg_looking removeObject:uri];
        if (!stillWanted(uri)) return;
        SGRPlayerFound *found = [SGRPlayerFound new];
        found.file = file;
        found.source = source;
        found.note = note;
        found.hadCanvas = canvas != nil;
        sg_found[uri] = found;
        if ([uri isEqualToString:sg_wanted]) arrived(uri);
        else say(@"up next, %@: %@", uri, file ? [NSString stringWithFormat:@"%@ ready (%@)", nameOf(source), note] : note);
    });
}

static void playOrHold(void);

static void arrived(NSString *uri) {
    SGRPlayerAnimatedView *view = sg_view;
    SGRPlayerFound *found = sg_found[uri];
    if (!view || !found || ![uri isEqualToString:sg_wanted]) return;
    if (!found.file) {
        if (view.clip) say(@"fades to Fluid artwork, no clip for %@", uri);
        [view clear:YES];
        say(@"no clip for %@: %@", uri, found.note);
    } else if ([view.clip.file isEqual:found.file]) {
        say(@"%@ goes on with the same clip", uri);
    } else {
        say(@"%@ for %@ (%@), %@", nameOf(found.source), uri, found.note, view.clip ? @"crosses over from the last clip" : @"fades in over Fluid artwork");
        [view showClip:[[SGRPlayerClip alloc] initWithFile:found.file]];
        playOrHold();
    }
    prefetchNext();
}

// Once the playing track's clip is settled: the next track's is fetched ahead, so a skip can go straight to it.
static void prefetchNext(void) {
    if (!sg_view.window || heldBack() || !sg_wanted || !sg_found[sg_wanted]) return;
    SPTPlayerTrack *next = upNext(SGPlayerState());
    NSString *uri = SGURIString(next.URI);
    if (!uri || [uri isEqualToString:sg_wanted] || sg_found[uri] || [sg_looking containsObject:uri]) return;
    sg_next = uri;
    say(@"fetching ahead for %@", uri);
    find(uri, next, canvasOf(next));
}

// Metadata that lands after the lookup: a Canvas the sources were asked without is asked for again when
// Spotify comes before the source that answered.
static void canvasLanded(NSString *uri, SPTPlayerTrack *track, SGCanvas *canvas) {
    SGRPlayerFound *found = sg_found[uri];
    if (!canvas || !found || found.hadCanvas) return;
    NSArray<NSString *> *order = SGArtworkOrderFor(SGRKeyPlayerArtworkSources);
    NSUInteger spotifyAt = [order indexOfObject:SGArtworkSourceSpotify];
    if (spotifyAt == NSNotFound || (found.file && [order indexOfObject:found.source] < spotifyAt)) return;
    say(@"%@ names a Canvas it had not when asked, asked again", uri);
    [sg_found removeObjectForKey:uri];
    find(uri, track, canvas);
}

static void resolve(SPTPlayerState *state) {
    SPTPlayerTrack *track = state.track;
    NSString *uri = SGURIString(track.URI);
    if (!uri) return;
    SGCanvas *canvas = canvasOf(track);
    if ([uri isEqualToString:sg_wanted]) {
        canvasLanded(uri, track, canvas);
        prefetchNext();
        return;
    }
    sg_wanted = uri;
    for (NSString *kept in sg_found.allKeys) {
        if (![kept isEqualToString:uri] && ![kept isEqualToString:sg_next]) [sg_found removeObjectForKey:kept];
    }
    if ([sg_next isEqualToString:uri]) sg_next = nil;
    // Fetched ahead, the track may not have named its Canvas yet.
    canvasLanded(uri, track, canvas);
    BOOL ahead = sg_found[uri] != nil;
    // A walk that answers at once arrives by itself.
    find(uri, track, canvas);
    if (ahead) {
        arrived(uri);
    } else if (!sg_found[uri] && sg_view.clip) {
        say(@"fades to Fluid artwork while %@'s clip is found", uri);
        [sg_view clear:YES];
    }
}

#pragma mark - playing and holding

static void playOrHold(void) {
    SGRPlayerAnimatedView *view = sg_view;
    if (!view) return;
    UIApplicationState state = UIApplication.sharedApplication.applicationState;
    NSString *why = nil;
    if (!view.window) why = @"the player is not on screen";
    else if (state != UIApplicationStateActive) why = @"the app is not in front";
    else if (SGRPlayerIsTransitioning()) why = @"the player opens or closes";
    else if (SGPlayerState().isPaused) why = @"the song is paused";
    [view setPlaying:!why];
    static NSString *said;
    NSString *now = why ?: @"plays";
    if (!view.clip || [now isEqualToString:said]) return;
    said = now;
    say(@"%@", why ? [@"holds its frame, " stringByAppendingString:why] : @"plays");
}

static void update(void) {
    SGRPlayerAnimatedView *view = sg_view;
    if (!view) return;
    NSString *held = heldBack();
    if (held) {
        if (view.clip) say(@"fades to Fluid artwork: %@", held);
        [view clear:YES];
        sg_wanted = nil;
        sg_next = nil;
    } else if (view.window && UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) {
        resolve(SGPlayerState());
    }
    playOrHold();
}

static void covered(BOOL covers) {
    SGRArtworkField *field = sg_field;
    field.covered = covers;
    say(@"Fluid artwork %@", covers ? @"stops under the clip" : @"draws again");
}

// The cover goes as a clip fades in and comes back as it fades out, over the same time (PlayerArtwork.x).
static void shownChanged(BOOL shown, NSTimeInterval duration) {
    say(@"the cover %@ over %.2f s", shown ? @"goes as the clip fades in" : @"comes back as the clip fades out", duration);
    SGRPlayerCoversFollowClip(duration);
}

BOOL SGRPlayerAnimatedShowing(CGFloat *shown, NSTimeInterval *left) {
    SGRPlayerAnimatedView *view = sg_view;
    if (shown) *shown = view ? shownOpacity(view.layer) : 0;
    if (left) *left = view ? MAX(0, view.fadeEnds - CACurrentMediaTime()) : 0;
    return view.shown;
}

UIView *SGRPlayerAnimatedViewIn(UIView *plane, SGRArtworkField *field) {
    SGRPlayerAnimatedView *view = objc_getAssociatedObject(plane, &kViewKey);
    if (!sg_picked) {
        // Kept until it has faded out to the field.
        if (view && !view.clip && shownOpacity(view.layer) < 0.01f) {
            [view removeFromSuperview];
            objc_setAssociatedObject(plane, &kViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            field.covered = NO;
            return nil;
        }
        return view;
    }
    if (!view) {
        view = [[SGRPlayerAnimatedView alloc] initWithFrame:plane.bounds];
        objc_setAssociatedObject(plane, &kViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.coversChanged = ^(BOOL covers) { covered(covers); };
        view.shownChanged = ^(BOOL shown, NSTimeInterval duration) { shownChanged(shown, duration); };
        view.windowChanged = ^{ update(); };
        view.neverReady = ^(SGRPlayerClip *clip) {
            say(@"%@ could not be drawn, Fluid artwork stays", clip.file.lastPathComponent);
            SGRPlayerFound *found = sg_wanted ? sg_found[sg_wanted] : nil;
            if ([found.file isEqual:clip.file]) found.file = nil;
            [sg_view clear:YES];
        };
        [view setLyricsUp:sg_lyricsUp animated:NO];
        say(@"view made in the background plane");
    }
    sg_field = field;
    if (field.covered != view.covers) field.covered = view.covers;
    // Another player's plane: the covers follow its clip instead.
    if (sg_view != view) {
        sg_view = view;
        SGRPlayerCoversFollowClip(0);
    }
    return view;
}

void SGRPlayerAnimatedFollowLyrics(BOOL open, BOOL animated) {
    sg_lyricsUp = open;
    [sg_view setLyricsUp:open animated:animated];
}

#pragma mark - the player

@interface SGRPlayerAnimatedWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerAnimatedWatcher {
    NSString *_track;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    SGRPlayerAnimatedView *view = sg_view;
    // Out of sight nothing is looked up, and the last track's clip must not greet the player as it opens.
    if (uri && ![uri isEqualToString:_track]) {
        _track = uri;
        if (!view.window || UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
            [view clear:NO];
            sg_wanted = nil;
        }
    }
    update();
}

@end

static SGRPlayerAnimatedWatcher *sg_watcher;

// Switch to video puts a music video where the cover is, on one of these; the clip goes while it is on.
static void spotifyVideo(id owner, BOOL attached) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sg_videos) sg_videos = [NSHashTable weakObjectsHashTable];
        BOOL was = sg_videos.allObjects.count > 0;
        if (attached) [sg_videos addObject:owner];
        else [sg_videos removeObject:owner];
        BOOL now = sg_videos.allObjects.count > 0;
        if (now == was) return;
        say(@"Spotify's own video %@ (%@)", now ? @"shows" : @"is gone", NSStringFromClass([owner class]));
        update();
    });
}

%hook _TtC28NowPlaying_ContentLayersImpl24HorizontalVideoViewModel
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    spotifyVideo(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    spotifyVideo(self, NO);
}
%end

%hook _TtC28NowPlaying_ContentLayersImpl31VerticalVideoCellImplementation
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    spotifyVideo(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    spotifyVideo(self, NO);
}
%end

%hook _TtC22NowPlaying_ElementsKit14VideoElementUI
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    spotifyVideo(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    spotifyVideo(self, NO);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    sg_found = [NSMutableDictionary dictionary];
    sg_looking = [NSMutableSet set];
    sg_watcher = [SGRPlayerAnimatedWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    sg_picked = SGRPlayerBackgroundStyle() == SGRPlayerBackgroundAnimated;
    [center addObserverForName:SGRPlayerBackgroundDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        sg_picked = SGRPlayerBackgroundStyle() == SGRPlayerBackgroundAnimated;
        say(@"%@ picked", sg_picked ? @"Animated artwork" : @"Fluid artwork");
        update();
    }];
    // The main queue, since the power state is reported off it.
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      UIApplicationDidEnterBackgroundNotification, UIApplicationWillEnterForegroundNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { update(); }];
    }
    SGRObservePlayerTransition(sg_watcher, ^(id owner) { playOrHold(); }, ^(id owner) { playOrHold(); });
    SGRequireClasses(@[
        @"_TtC28NowPlaying_ContentLayersImpl24HorizontalVideoViewModel",
        @"_TtC28NowPlaying_ContentLayersImpl31VerticalVideoCellImplementation",
        @"_TtC22NowPlaying_ElementsKit14VideoElementUI",
    ]);
}
