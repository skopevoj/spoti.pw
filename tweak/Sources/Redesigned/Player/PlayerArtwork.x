// Player redesign: the cover sits on the field with continuous corners and a soft shadow, and shrinks
// back while playback is paused, the way the Music app's does; the lyric preview under it is gone.
//
// Tree (trees/clean/player/01.txt:36-43): CoverArtCellImpl > ... > CoverArtTiltView 354x354 > an
// ElementView the same size > ImageViewProxy > Encore.ImageView (clips) > UIImageView, with
// Lyrics_NPVContainerKit.LyricsContainerView under the tilt view. The ElementView is what gets the
// corners and the scale: the tilt view's own transform is left to the tilt Spotify gives it when the
// cover is inspected. The image clips, so the shadow is a plate of the Kit's behind it.
//
// A paused cover stays shrunk while the player opens or closes: the morph (PlayerMorph.x) flies to the
// frame the cover is seen at, so growing it for the transition only made it jump afterwards.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"
#import "Settings/SGModPage.h"
#import "Shared/Visualizer/Visualizer.h"
#import "Shared/Visualizer/SGVisualizerView.h"

static const CGFloat kPausedScale = 0.84, kPausedScaleReduceMotion = 0.92;
// The bar's 40pt cover lives in a tilt view of its own; the player's is 354.
static const CGFloat kCoverMinWidth = 200;

static char kPlateKey, kRingKey;
// With the visualizer the circle is this share of the cover's square, leaving the rest to the bars.
static const CGFloat kVisualizerShare = 0.64;
// One turn of the spinning cover, in seconds.
static const CFTimeInterval kSpinTurn = 24;

static BOOL visualizing(void) {
    return SGFlag(SGRKeyPlayerVisualizer, NO);
}
static NSHashTable<UIView *> *sg_tilts;
// The cover of each tilt view once found. A frame Spotify sets on a scaled view becomes its scaled
// size, leaving bounds that no longer match the tilt view's, so the cover is not looked for by size again.
static NSMapTable<UIView *, UIView *> *sg_covers;

static CGFloat currentScale(void) {
    SPTPlayerState *state = SGPlayerState();
    CGFloat share = visualizing() ? kVisualizerShare : 1;
    if (!state.isPaused) return share;
    return share * (SGRReduceMotion() ? kPausedScaleReduceMotion : kPausedScale);
}

// The child of the tilt view the size of the cover.
static UIView *coverIn(UIView *tilt) {
    UIView *cover = [sg_covers objectForKey:tilt];
    if (cover.superview == tilt) return cover;
    for (UIView *sub in tilt.subviews) {
        if (![sub isKindOfClass:SGRShadowPlate.class] && CGSizeEqualToSize(sub.bounds.size, tilt.bounds.size)) {
            [sg_covers setObject:sub forKey:tilt];
            return sub;
        }
    }
    return nil;
}

static BOOL inCoverCell(UIView *tilt) {
    static Class cell;
    if (!cell) cell = NSClassFromString(@"_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl");
    for (UIView *v = tilt.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell]) return YES;
    }
    return NO;
}

// The ring of a tilt view, made the first time the visualizer is on for it, behind the cover and its plate.
static SGVisualizerView *ringIn(UIView *tilt, BOOL make) {
    SGVisualizerView *ring = objc_getAssociatedObject(tilt, &kRingKey);
    if (ring || !make) return ring;
    ring = [[SGVisualizerView alloc] initWithFrame:tilt.bounds];
    [tilt insertSubview:ring atIndex:0];
    objc_setAssociatedObject(tilt, &kRingKey, ring, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return ring;
}

// The spin turns what is inside the circle, not the cover itself, whose layer carries the paused shrink's
// animation; it is held still while paused by stopping that layer's clock.
static void spinCover(UIView *cover, BOOL spin, BOOL paused) {
    CALayer *layer = cover.subviews.firstObject.layer;
    if (!layer) return;
    CAAnimation *existing = [layer animationForKey:@"sg.spin"];
    if (!spin) {
        if (existing) [layer removeAnimationForKey:@"sg.spin"];
        layer.speed = 1;
        layer.timeOffset = 0;
        return;
    }
    if (!existing) {
        CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        turn.fromValue = @0;
        turn.toValue = @(2 * M_PI);
        turn.duration = kSpinTurn;
        turn.repeatCount = HUGE_VALF;
        turn.additive = YES;
        turn.removedOnCompletion = NO;
        [layer addAnimation:turn forKey:@"sg.spin"];
    }
    // Paused, the layer's clock stops where it is; playing again, it runs on from there.
    if (paused && layer.speed != 0) {
        CFTimeInterval at = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
        layer.speed = 0;
        layer.timeOffset = at;
    } else if (!paused && layer.speed == 0) {
        CFTimeInterval at = layer.timeOffset;
        layer.speed = 1;
        layer.timeOffset = 0;
        layer.beginTime = 0;
        layer.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] - at;
    }
}

static void scaleCover(UIView *tilt, CGFloat scale) {
    UIView *cover = coverIn(tilt);
    if (!cover) return;
    SGRShadowPlate *plate = SGRShadowPlateIn(tilt, &kPlateKey);
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    cover.transform = transform;
    plate.transform = transform;
    BOOL ringed = visualizing();
    SGVisualizerView *ring = ringIn(tilt, ringed);
    ring.hidden = !ringed;
    ring.innerRadius = ringed ? cover.bounds.size.width / 2 * scale : 0;
    spinCover(cover, ringed && SGEnabled(SGRKeyPlayerVisualizerSpin), SGPlayerState().isPaused);
}

#pragma mark - where the cover is

// The tilt view of the cover on screen: the queue is a cover per cell and the cells out of view are
// kept hidden (player/02.txt:521), so the one showing is the one in a window with nothing hidden over it.
static UIView *showingTilt(void) {
    for (UIView *tilt in sg_tilts) {
        if (!tilt.window) continue;
        BOOL hidden = NO;
        for (UIView *v = tilt; v && !hidden; v = v.superview) hidden = v.hidden;
        if (!hidden) return tilt;
    }
    return nil;
}

UIView *SGRPlayerCoverList(void) {
    for (UIView *v = showingTilt(); v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) return v;
    }
    return nil;
}

CGRect SGRPlayerCoverFrameIn(UIView *host) {
    UIView *tilt = showingTilt();
    UIView *cover = coverIn(tilt);
    // The cover's own transform is the paused shrink, which is what the eye sees it at.
    return cover && host ? [host convertRect:cover.bounds fromView:cover] : CGRectNull;
}

CGRect SGRPlayerArtworkAreaIn(UIView *host) {
    UIView *tilt = showingTilt();
    if (!tilt || !host) return CGRectNull;
    // The band is the first view over the cover as wide as the player: the cover sits inset inside it
    // (01.txt:33-36, CoverArtCellImpl > UIView {0, 110, 402, 466.67} > UIView {24, 8, ...} > the tilt view).
    for (UIView *v = tilt.superview; v; v = v.superview) {
        if (v == host) break;
        if (v.bounds.size.width >= host.bounds.size.width - 1) return [host convertRect:v.bounds fromView:v];
    }
    return CGRectNull;
}

#pragma mark - hidden

// The cover hidden for a stand-in, so the same one comes back if the list moved on meanwhile.
static __weak UIView *sg_hiddenCover;
// The tilt views whose cover this file took away, the only ones it gives back: any alpha Spotify sets on
// a cover itself is left alone.
static NSHashTable<UIView *> *sg_gone;

// With a clip over the field no cover shows, in any cell (PlayerAnimated.x). Only the cover and its plate
// go, never the list or anything over it: UIKit hit tests nothing under alpha 0.01, and a swipe on the
// list is what skips. The tilt view is the element VoiceOver names the cover by.
static void showCover(UIView *tilt) {
    UIView *cover = coverIn(tilt);
    if (!cover) return;
    BOOL clip = SGRPlayerAnimatedShowing(NULL, NULL), gone = clip || cover == sg_hiddenCover;
    if (gone) [sg_gone addObject:tilt];
    else if ([sg_gone containsObject:tilt]) [sg_gone removeObject:tilt];
    else return;
    UIView *plate = SGRShadowPlateIn(tilt, &kPlateKey), *ring = ringIn(tilt, NO);
    CGFloat alpha = gone ? 0 : 1;
    if (cover.alpha != alpha) cover.alpha = alpha;
    if (plate.alpha != alpha) plate.alpha = alpha;
    if (ring && ring.alpha != alpha) ring.alpha = alpha;
    if (tilt.accessibilityElementsHidden != clip) tilt.accessibilityElementsHidden = clip;
}

static void fadeCovers(NSArray<UIView *> *tilts, NSTimeInterval duration) {
    void (^apply)(void) = ^{
        for (UIView *tilt in tilts) showCover(tilt);
    };
    if (duration <= 0) {
        [UIView performWithoutAnimation:apply];
        return;
    }
    [UIView animateWithDuration:duration delay:0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:apply completion:nil];
}

void SGRPlayerCoversFollowClip(NSTimeInterval duration) {
    fadeCovers(sg_tilts.allObjects, duration);
}

void SGRPlayerSetCoverHidden(BOOL hidden) {
    UIView *was = sg_hiddenCover;
    sg_hiddenCover = nil;
    if (was) {
        // Given back halfway through a clip's fade, it joins the fade where the clip has got to.
        CGFloat shown = 0;
        NSTimeInterval left = 0;
        SGRPlayerAnimatedShowing(&shown, &left);
        UIView *tilt = was.superview, *plate = SGRShadowPlateIn(tilt, &kPlateKey), *ring = ringIn(tilt, NO);
        if (left > 0) {
            [UIView performWithoutAnimation:^{
                was.alpha = 1 - shown;
                plate.alpha = 1 - shown;
                ring.alpha = 1 - shown;
            }];
        }
        if (tilt) fadeCovers(@[tilt], left);
    }
    if (!hidden) return;
    UIView *tilt = showingTilt();
    UIView *cover = coverIn(tilt);
    if (!cover) return;
    sg_hiddenCover = cover;
    [UIView performWithoutAnimation:^{ showCover(tilt); }];
}

#pragma mark - the paused shrink

static void scaleEveryCover(BOOL animated) {
    CGFloat scale = currentScale();
    NSArray<UIView *> *tilts = sg_tilts.allObjects;
    void (^apply)(void) = ^{
        for (UIView *tilt in tilts) scaleCover(tilt, scale);
    };
    if (animated) SGRAnimate(SGRMotionLayout, apply, nil);
    else apply();
}

%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)layoutSubviews {
    %orig;
    UIView *tilt = (UIView *)self;
    if (tilt.bounds.size.width < kCoverMinWidth || !inCoverCell(tilt)) return;
    UIView *cover = coverIn(tilt);
    if (!cover) return;
    [sg_tilts addObject:tilt];
    // The cover fills the tilt view (01.txt:37); bounds and center, unlike a frame, hold under the scale.
    CGRect bounds = tilt.bounds;
    CGPoint middle = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    if (!CGSizeEqualToSize(cover.bounds.size, bounds.size)) cover.bounds = (CGRect){cover.bounds.origin, bounds.size};
    if (!CGPointEqualToPoint(cover.center, middle)) cover.center = middle;

    // With the visualizer the cover is a circle, and so is its shadow.
    CGFloat radius = visualizing() ? bounds.size.width / 2 : SGRRadiusArtwork;
    cover.layer.cornerRadius = radius;
    cover.layer.cornerCurve = visualizing() ? kCACornerCurveCircular : kCACornerCurveContinuous;
    cover.clipsToBounds = YES;
    SGRShadowPlate *plate = SGRShadowPlateIn(tilt, &kPlateKey);
    if (plate.cornerRadius != radius) plate.cornerRadius = radius;
    plate.bounds = cover.bounds;
    SGVisualizerView *ring = ringIn(tilt, visualizing());
    if (ring) {
        ring.bounds = (CGRect){CGPointZero, bounds.size};
        ring.center = middle;
        ring.accent = SGRAccentColor() ?: [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
        // The Cover gradient reads the cover as it is shown here.
        ring.coverView = cover;
        if (ring.superview == tilt && tilt.subviews.firstObject != ring) [tilt sendSubviewToBack:ring];
    }
    plate.center = cover.center;
    // The same value an animation in flight is heading to, so a layout pass never cuts one short.
    scaleCover(tilt, currentScale());
    // A cell laid out later, or reused, takes the rule as it stands.
    [UIView performWithoutAnimation:^{ showCover(tilt); }];

    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: cover %@ rounded %.0f with a shadow plate, scale %.2f", NSStringFromClass(cover.class), SGRRadiusArtwork, currentScale()); });
}
%end

// Spotify shows and hides the preview as lyrics come and go; it stays hidden, the way
// Native/Player/PlayerDeclutter.x has shipped it (its parent is a plain view, 01.txt:35, not a stack).
%hook _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (void)setHidden:(BOOL)hidden {
    %orig(YES);
}
- (void)didMoveToWindow {
    %orig;
    ((UIView *)self).hidden = YES;
}
%end

@interface SGRPlayerArtworkWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerArtworkWatcher {
    NSInteger _paused;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _paused = -1;
    return self;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSInteger paused = state.isPaused ? 1 : 0;
    if (paused == _paused) return;
    _paused = paused;
    scaleEveryCover(YES);
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"redesign player: state paused=%d loading=%d, %lu covers scaled", state.isPaused, state.isLoading, (unsigned long)sg_tilts.count);
}

@end

static SGRPlayerArtworkWatcher *sg_artworkWatcher;

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    sg_tilts = [NSHashTable weakObjectsHashTable];
    sg_covers = [NSMapTable weakToWeakObjectsMapTable];
    sg_gone = [NSHashTable weakObjectsHashTable];
    sg_artworkWatcher = [SGRPlayerArtworkWatcher new];
    // The switch, the spin and the ring's own settings apply at once to every cover.
    [NSNotificationCenter.defaultCenter addObserverForName:SGVisualizerSettingsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        for (UIView *tilt in sg_tilts.allObjects) [tilt setNeedsLayout];
        scaleEveryCover(YES);
    }];
    SGAddPlayerStateObserver(sg_artworkWatcher);
    SGRObservePlayerTransition(sg_artworkWatcher, ^(id owner) {
        scaleEveryCover(YES);
    }, ^(id owner) {
        scaleEveryCover(YES);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign player: transition over, cover scale %.2f", currentScale()); });
    });
    SGRequireClasses(@[
        @"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView",
        @"_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl",
        @"_TtC22Lyrics_NPVContainerKit19LyricsContainerView",
    ]);
}
