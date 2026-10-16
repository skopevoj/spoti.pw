// Player redesign: previous, play and next as bare glyphs, the way the Music app draws them, and the
// timestamps under the slider in digits of one width, so they stop twitching every second. A tap on the
// bar seeks there.
//
// The glyphs are drawn over Spotify's controls rather than instead of them: each button keeps its
// action, its enabled state, its accessibility and the Gestures zones around it, and the glyph takes no
// touches. Previous and next get theirs inside the button's content view, so the button's own press
// and disabled look carry over; Spotify's icon under it goes transparent on every pass (SPTEncoreIconView
// is a Swift class, which SGRSuppress cannot keep). Play loses its white disc, a plain UIImageView the
// size of the button, which SGRSuppress keeps transparent, and the glyph over it follows the player's state.
//
// Tree (trees/clean/player/01.txt): PlaybackControlsElementsUnit's view holds
// id=SPTNowPlayingPreviousTrackButton 56x56 > UIView > StackView > StackView > SPTEncoreIconView (:257),
// id=SPTNowPlayingPlayButton (PlayButtonView 64x64, :266) > CondensedButton (a UIButton,
// objc-meta-Spotify.txt:207312) > UIImageView 64x64 and a hidden SpinnerView, next to a hidden UIView
// holding a UIImageView (:277), and id=SPTNowPlayingNextTrackButton. DurationElementUnit's view holds
// id=now-playing-time-take-label and id=now-playing-time-remaning-label, SPTEncoreLabels whose UILabel
// is id=...-internal (:227). The sticky header has a play button of its own (:492), which a search
// inside the unit's view never reaches.
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Haptics/Haptics.h"
#import "Player.h"

static const CGFloat kSkipGlyphSize = 32, kPlayGlyphSize = 44;
// A spinner that is still up this long after a state change is buffering, not a track starting.
static const NSTimeInterval kSpinnerCheck = 0.6;

// After a tap the glyph shows what the tap asked for, and a state still saying the opposite is taken for
// one sent before the player caught up, for this long; after it the player's word is final.
static const NSTimeInterval kTapTrust = 1.2;

static char kPreviousKey, kNextKey, kPlayKey, kGlyphKey, kTakeKey, kRemainingKey;
static __weak UIView *sg_playView;
static __weak UIButton *sg_playButton;
static CFTimeInterval sg_tappedUntil;
static BOOL sg_tappedPaused;
static __weak SGRGlyphView *sg_playGlyph;
static __weak UIView *sg_controlsHost;

void SGRPlayerVanish(UIView *view) {
    if (!view) return;
    if (view.alpha != 0) view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static void logMissing(NSString *what) {
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    if ([logged containsObject:what]) return;
    [logged addObject:what];
    SGLog(@"redesign player: %@ not found, left as Spotify's", what);
}

static SGRGlyphView *glyphFor(UIView *owner, NSString *symbol, CGFloat size) {
    SGRGlyphView *glyph = objc_getAssociatedObject(owner, &kGlyphKey);
    if (!glyph) {
        glyph = [[SGRGlyphView alloc] initWithSymbol:symbol pointSize:size weight:UIImageSymbolWeightRegular];
        objc_setAssociatedObject(owner, &kGlyphKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return glyph;
}

// Centred by the autoresizing mask as well as here: the unit lays out before the buttons in its row
// have a size, so a centre set then is the middle of nothing, (0, 0), and no later pass of the unit's
// comes to move it (trees/continuous/1.txt, 2026-09-17: glyphs at {-23.7, -14.7} in 56pt buttons).
static void keepOnTop(UIView *view, UIView *host) {
    if (view.superview != host) {
        view.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                              | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [host addSubview:view];
    } else if (host.subviews.lastObject != view) {
        [host bringSubviewToFront:view];
    }
    view.center = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds));
}

#pragma mark - previous and next

static void skipGlyph(UIView *host, NSString *identifier, const void *findKey, NSString *symbol) {
    UIView *button = SGRFindByIdentifier(host, identifier, findKey);
    UIView *content = button.subviews.firstObject;
    if (!content) {
        logMissing(identifier);
        return;
    }
    static Class icon;
    if (!icon) icon = NSClassFromString(@"SPTEncoreIconView");
    SGRGlyphView *glyph = glyphFor(button, symbol, kSkipGlyphSize);
    SGForEachView(content, ^(UIView *view) {
        if (view != glyph && [view isKindOfClass:icon]) SGRPlayerVanish(view);
    });
    keepOnTop(glyph, content);
}

#pragma mark - play

static BOOL spinnerShowing(UIButton *button) {
    for (UIView *sub in button.subviews) {
        if (!sub.hidden && sub.alpha > 0.01 && [NSStringFromClass(sub.class) containsString:@"SpinnerView"]) return YES;
    }
    return NO;
}

static NSString *symbolFor(BOOL paused) {
    return paused ? @"play.fill" : @"pause.fill";
}

static void refreshPlayGlyph(BOOL animated) {
    SGRGlyphView *glyph = sg_playGlyph;
    SPTPlayerState *state = SGPlayerState();
    if (!glyph || !state) return;
    glyph.alpha = spinnerShowing(sg_playButton) ? 0 : 1;
    CFTimeInterval now = CACurrentMediaTime();
    if (now < sg_tappedUntil) {
        if (state.isPaused != sg_tappedPaused) return;
        sg_tappedUntil = 0;
    }
    [glyph setSymbol:symbolFor(state.isPaused) animated:animated];
}

// The player's state reaches the glyph a beat after the tap (the request goes through the player core
// and comes back as a state), which read as a slow button; Spotify's own disc turns at the touch. So the
// glyph turns at the touch too, to the opposite of what it shows, and the state settles it after.
static void playTapped(void) {
    SGRGlyphView *glyph = sg_playGlyph;
    if (!glyph || glyph.alpha == 0) return;
    sg_tappedPaused = ![glyph.symbol isEqualToString:@"play.fill"];
    sg_tappedUntil = CACurrentMediaTime() + kTapTrust;
    [glyph setSymbol:symbolFor(sg_tappedPaused) animated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTapTrust * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ refreshPlayGlyph(YES); });
}

static void playGlyph(UIView *host) {
    UIView *play = SGRFindByIdentifier(host, @"SPTNowPlayingPlayButton", &kPlayKey);
    if (!play) {
        logMissing(@"SPTNowPlayingPlayButton");
        return;
    }
    // Before the player has reported a state the glyph could only guess, so the disc stays.
    SPTPlayerState *state = SGPlayerState();
    if (!state) return;
    UIButton *button = nil;
    for (UIView *sub in play.subviews) {
        if ([sub isKindOfClass:UIButton.class]) button = (UIButton *)sub;
    }
    UIImageView *disc = nil;
    for (UIView *sub in button.subviews) {
        if ([sub isKindOfClass:UIImageView.class] && CGSizeEqualToSize(sub.bounds.size, button.bounds.size)) disc = (UIImageView *)sub;
    }
    if (!disc) {
        logMissing(@"the play button's disc");
        return;
    }
    SGRSuppress(disc);
    // The holder Spotify crossfades a snapshot of the disc in when play turns to pause.
    for (UIView *sub in play.subviews) {
        if (object_getClass(sub) != UIView.class) continue;
        for (UIView *image in sub.subviews) {
            if ([image isKindOfClass:UIImageView.class]) SGRSuppress(image);
        }
    }

    // Inside the button, over the disc it replaces, so it follows the button's own press.
    SGRGlyphView *glyph = glyphFor(play, symbolFor(state.isPaused), kPlayGlyphSize);
    keepOnTop(glyph, button);
    sg_playView = play;
    sg_playButton = button;
    sg_playGlyph = glyph;
    refreshPlayGlyph(NO);

    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: play glyph over %@ (disc %@ suppressed), spinner %@", NSStringFromClass(play.class), NSStringFromClass(disc.class), spinnerShowing(button) ? @"showing" : @"hidden"); });
}

static void layOutControls(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    // The unit lays out before its row does, and the glyphs are centred on the buttons in it.
    [SGRowIn(host) layoutIfNeeded];
    sg_controlsHost = host;
    skipGlyph(host, @"SPTNowPlayingPreviousTrackButton", &kPreviousKey, @"backward.fill");
    skipGlyph(host, @"SPTNowPlayingNextTrackButton", &kNextKey, @"forward.fill");
    playGlyph(host);
}

%hook _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    layOutControls((UIViewController *)self);
}
%end

// Spotify Free's player builds the same elements into units of its own (Player.h).
%hook _TtC32ReinventFree_ReinventFreeNpvImpl40ReinventFreePlaybackControlsElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    layOutControls((UIViewController *)self);
}
%end

@interface SGRPlayerControlsWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerControlsWatcher

- (void)playerStateDidChange:(SPTPlayerState *)state {
    // The first state can land after the controls laid out, which left the disc for want of one.
    if (!sg_playGlyph) [sg_controlsHost setNeedsLayout];
    refreshPlayGlyph(YES);
    // Spotify raises its spinner a moment after a state says loading, and drops it a moment after.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSpinnerCheck * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ refreshPlayGlyph(YES); });
}

@end

static SGRPlayerControlsWatcher *sg_controlsWatcher;

#pragma mark - times

static UILabel *monospaced(UIView *host, NSString *identifier, const void *findKey) {
    UILabel *label = (UILabel *)SGRFindByIdentifier(host, identifier, findKey);
    if (![label isKindOfClass:UILabel.class]) {
        logMissing(identifier);
        return nil;
    }
    SGRMonospacedDigits(label);
    return label;
}

// The action the play button's own UIButton sends (objc-methods.txt: -[PlayButtonView uiButtonTapped]).
// Only the player's button turns the glyph: the sticky header and every page with a play button of
// its own use the same class.
%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)uiButtonTapped {
    %orig;
    if ((UIView *)self != sg_playView) return;
    playTapped();
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: play glyph turned at the tap"); });
}
%end

#pragma mark - tap to seek

// Spotify's position slider (NowPlaying_ECMKit.ProgressBar.Slider) moves only under a drag of its thumb.
// A tap elsewhere on the bar is played to it as that drag: its unit seeks on the control events a drag
// sends and leaves a tracking slider alone when the position comes in, so the thumb stays where it went.
static const CGFloat kTapSlop = 10;                 // further than this and the finger is dragging
static const NSTimeInterval kTapLongest = 0.5;
static const CGFloat kBarReach = 12;                // past either end of the bar a tap still counts

static char kSliderKey, kSeekWatcherKey;
static __weak UISlider *sg_seekingSlider;           // answers isTracking while a tap plays its drag
static __weak UITouch *sg_tapTouch;                 // the touch the watcher follows
static BOOL sg_sliderTookTap;                       // and the slider began tracking it too (its thumb)

static BOOL seekable(UISlider *slider) {
    return slider.window && slider.enabled && slider.userInteractionEnabled && !slider.hidden && slider.alpha > 0.01
        && slider.maximumValue > slider.minimumValue;
}

// Where the thumb's middle would be under `point`, in the slider's own space.
static float valueAt(UISlider *slider, CGPoint point) {
    CGRect track = [slider trackRectForBounds:slider.bounds];
    CGFloat from = CGRectGetMidX([slider thumbRectForBounds:slider.bounds trackRect:track value:slider.minimumValue]);
    CGFloat to = CGRectGetMidX([slider thumbRectForBounds:slider.bounds trackRect:track value:slider.maximumValue]);
    if (fabs(to - from) < 1) return slider.value;
    CGFloat share = MIN(MAX((point.x - from) / (to - from), 0), 1);
    return slider.minimumValue + (float)share * (slider.maximumValue - slider.minimumValue);
}

static void seekOnTap(UISlider *slider, CGPoint point) {
    float value = valueAt(slider, point), was = slider.value;
    CGRect thumb = [slider thumbRectForBounds:slider.bounds trackRect:[slider trackRectForBounds:slider.bounds] value:was];
    // A tap on the thumb is the thumb's, as it always was.
    if (sg_sliderTookTap && fabs(point.x - CGRectGetMidX(thumb)) <= thumb.size.width / 2 + 2) return;
    // Still holding a touch it took itself (a bar that scrubs from anywhere), it seeks where it is put
    // when it lets go.
    BOOL own = sg_sliderTookTap && slider.isTracking;
    if (own) {
        [slider setValue:value animated:NO];
        [slider sendActionsForControlEvents:UIControlEventValueChanged];
    } else {
        sg_seekingSlider = slider;
        [slider sendActionsForControlEvents:UIControlEventTouchDown];
        [slider setValue:value animated:NO];
        [slider sendActionsForControlEvents:UIControlEventValueChanged];
        // What its endTrackingWithTouch: sends, then the touch up the unit seeks on.
        [slider sendActionsForControlEvents:UIControlEventTouchCancel];
        [slider sendActionsForControlEvents:UIControlEventTouchUpInside];
        sg_seekingSlider = nil;
    }
    SGPlayFeedback(SGFeedbackSkip);
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"redesign player: tap to seek from %.3f to %.3f (%@), now %.3f", was, value, own ? @"its own touch" : @"played as a drag", slider.value);
}

// Watches the band around the bar for a tap and never recognizes, so it holds up, cancels and stands in
// the way of nothing: the slider's own drag and the pull that closes the player go on as they did.
@interface SGRSeekTapWatcher : UIGestureRecognizer
@property (nonatomic, weak) UISlider *slider;
@property (nonatomic, weak) UIView *taken, *remaining;
@end

@implementation SGRSeekTapWatcher {
    __weak UITouch *_touch;
    CGPoint _start;
    NSTimeInterval _began;
}

// The times under the bar are not the bar: the remaining time turns into the length when tapped.
- (BOOL)takes:(UITouch *)touch {
    UISlider *slider = self.slider;
    UIView *band = self.view;
    if (!seekable(slider) || ![slider isDescendantOfView:band]) return NO;
    CGPoint point = [touch locationInView:band];
    CGRect bar = [band convertRect:slider.bounds fromView:slider];
    if (point.x < CGRectGetMinX(bar) - kBarReach || point.x > CGRectGetMaxX(bar) + kBarReach) return NO;
    UIView *times[] = {self.taken, self.remaining};
    for (size_t i = 0; i < sizeof(times) / sizeof(*times); i++) {
        UIView *view = times[i];
        if (!view.window || view.alpha < 0.01) continue;
        if (CGRectContainsPoint(CGRectInset([band convertRect:view.bounds fromView:view], -kTapSlop / 2, 0), point)) return NO;
    }
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    UITouch *touch = touches.anyObject;
    if (_touch || event.allTouches.count > 1 || ![self takes:touch]) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    _touch = touch;
    _start = [touch locationInView:self.view];
    _began = touch.timestamp;
    sg_tapTouch = touch;
    sg_sliderTookTap = NO;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    UITouch *touch = _touch;
    if (!touch || ![touches containsObject:touch]) return;
    CGPoint now = [touch locationInView:self.view];
    if (hypot(now.x - _start.x, now.y - _start.y) > kTapSlop) self.state = UIGestureRecognizerStateFailed;
}

// Gesture recognizers hear of the touch before the views do, and a scroll view above the slider may
// hand it its touch only now, so the seek waits until the slider has had it.
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    UITouch *touch = _touch;
    UISlider *slider = self.slider;
    if (touch && [touches containsObject:touch] && touch.timestamp - _began <= kTapLongest && seekable(slider)) {
        CGPoint now = [touch locationInView:self.view], onBar = [touch locationInView:slider];
        if (hypot(now.x - _start.x, now.y - _start.y) <= kTapSlop) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (seekable(slider)) seekOnTap(slider, onBar);
            });
        }
    }
    self.state = UIGestureRecognizerStateFailed;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    self.state = UIGestureRecognizerStateFailed;
}

- (void)reset {
    [super reset];
    _touch = nil;
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other { return NO; }

@end

%hook _TtCO17NowPlaying_ECMKit11ProgressBar6Slider
- (BOOL)isTracking {
    return (UISlider *)self == sg_seekingSlider || %orig;
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL tracking = %orig;
    if (tracking && touch == sg_tapTouch) sg_sliderTookTap = YES;
    return tracking;
}
%end

static void watchForSeekTaps(UIView *host, UILabel *taken, UILabel *remaining) {
    UISlider *slider = (UISlider *)SGRFindByIdentifier(host, @"SPTNowPlayingSliderV2", &kSliderKey);
    if (![slider isKindOfClass:UISlider.class]) {
        logMissing(@"the position slider");
        return;
    }
    SGRSeekTapWatcher *watcher = objc_getAssociatedObject(host, &kSeekWatcherKey);
    if (!watcher) {
        watcher = [[SGRSeekTapWatcher alloc] initWithTarget:nil action:NULL];
        watcher.cancelsTouchesInView = NO;
        watcher.delaysTouchesEnded = NO;
        [host addGestureRecognizer:watcher];
        objc_setAssociatedObject(host, &kSeekWatcherKey, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign player: tap to seek on %@ over %@ in %@", NSStringFromClass(slider.class),
              NSStringFromCGRect([host convertRect:slider.bounds fromView:slider]), NSStringFromCGRect(host.bounds));
    }
    watcher.slider = slider;
    watcher.taken = taken;
    watcher.remaining = remaining;
}

static void layOutTimes(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    UILabel *taken = monospaced(host, @"now-playing-time-take-label-internal", &kTakeKey);
    UILabel *remaining = monospaced(host, @"now-playing-time-remaning-label-internal", &kRemainingKey);
    watchForSeekTaps(host, taken, remaining);
    // Whether Spotify's font has digits of one width shows in the descriptor's feature settings.
    if (!taken) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: monospaced times in %@ %.0fpt, features %@", taken.font.fontName, taken.font.pointSize, taken.font.fontDescriptor.fontAttributes[UIFontDescriptorFeatureSettingsAttribute]); });
}

%hook _TtC20NowPlaying_ModesImpl19DurationElementUnit
- (void)viewDidLayoutSubviews {
    %orig;
    layOutTimes((UIViewController *)self);
}
%end

%hook _TtC32ReinventFree_ReinventFreeNpvImpl20DurationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    layOutTimes((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    sg_controlsWatcher = [SGRPlayerControlsWatcher new];
    SGAddPlayerStateObserver(sg_controlsWatcher);
    SGRequireClasses(@[
        @"_TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit",
        @"_TtC20NowPlaying_ModesImpl19DurationElementUnit",
        @"_TtC32ReinventFree_ReinventFreeNpvImpl40ReinventFreePlaybackControlsElementsUnit",
        @"_TtC32ReinventFree_ReinventFreeNpvImpl20DurationElementsUnit",
        @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView",
        @"_TtCO17NowPlaying_ECMKit11ProgressBar6Slider",
        @"SPTEncoreIconView",
    ]);
}
