// Player redesign: the lyrics come to the player itself, the way the Music app shows them. The player
// is one screen and does not scroll (PlayerScroll.x), so the footer's lyrics glyph is the only way to
// them: it shrinks the cover into a thumbnail at the top of the artwork band, lifts the track's title
// up beside it, and fades the Apple Music style lines (Redesigned/Lyrics/SGRKaraokeView.h) into the
// room that frees between the title and the progress bar. Tapping it again, or the thumbnail, puts the
// cover back. Over a clip (PlayerAnimated.x), where the player shows no cover, the thumbnail comes up and
// goes where it sits instead.
//
// Nothing of Spotify's is taken apart for it. The cover is the Kit's now playing artwork drawn again
// in a view of the redesign's own, flown from where Spotify's cover is drawn to where the thumbnail
// belongs, while Spotify's list of covers goes to alpha 0 underneath: one view to move instead of a
// paging list of them, and the two pictures are the same one, so the swap is not seen. The title row
// is Spotify's own unit translated, the way PlayerFooter.x moves the footer's controls -- a transform
// survives the stack view laying its arranged views out again -- with a mask over it where the controls
// it moved towards begin, so a long title fades out before them instead of running under them. The row
// of chips over it (Switch to video) goes while the lines are up, since they take the room it sits in.
//
// Tree (trees/clean/player/01.txt): SPTNowPlayingView (:26) holds the content layers, the header row
// (:91), and id=npv.bottomStackView {0, 576.67, 402, 236} (:127) whose arranged views are the
// information unit {0, 0, 402, 64} (:160, the title, the artist and the add button), the duration unit
// {0, 64, 402, 40} (:209), the controls (:240) and the footer (:295). The title is
// id=now-playing-title-label and the artist id=now-playing-subtitle-label (:174, :185), both inside one
// arranged element view {12, 2.33, 304, 43.33} of the unit's row. Every measurement here is taken from
// the views themselves, since a player with a volume row or another mode's units has other numbers.
//
// The geometry is re-applied on every layout pass of the units, since a new track rebuilds the
// elements inside them, and it is undone before the player closes: the bar morphs back into a full
// size cover, which a thumbnail would not match.
//
// With the lines up and the song playing, the controls go after a few seconds untouched and the lines
// have more room: only the bottom controls fade out. The header, thumbnail and song details stay in
// place, and the lines' room grows down from below them to the home indicator. The
// lines' view is laid over all of that room from the start and only its band moves
// (SGRKaraokeView's lineInsets), so the lines spring to the new anchor as they move on to a new line,
// rather than riding a view resized under them. A tap brings the controls back, while a scroll leaves
// them away. A tap that restores them does not seek to the line under it. Pausing brings
// them back as well, and they stay while the song is paused. VoiceOver keeps them.
//
// With Sing available (Shared/Sing: switched on in Mod Settings > Karaoke, its voice model downloaded), its
// microphone (Redesigned/Lyrics/SGRSingControl.h) sits in the bottom trailing corner of the lines' band,
// opposite their own glass button, and goes down with the band when the controls go. While it is open,
// preparing or explaining itself the controls do not go, but ones that are away already stay away: a
// touch on the microphone is for it and brings nothing back, since the band it sits in would move it out
// from under the finger. The lines open with Sing available even for a song without lyrics, so the
// microphone can always be reached; switched off, or without its model, there is no microphone and a song
// without lyrics keeps its cover. Both follow the switch and the model as they change.
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Redesigned/Lyrics/SGRSingControl.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Sing/SGSingController.h"
#import "Player.h"

static const CGFloat kThumbSide = 72;          // the cover once the lyrics are up
static const CGFloat kThumbGap = 16;           // between the thumbnail and the title beside it
static const CGFloat kTitleGap = 12;           // between the title and the controls at the trailing edge
static const CGFloat kTitleFade = 20;          // over how much of its end a title too long to fit fades out
static const CGFloat kThumbTop = 8;            // below the top of the artwork band
static const CGFloat kLyricsTop = 20;          // between the title row and the first line
static const CGFloat kLyricsBottom = 8;        // above the progress bar
// The lines are a surface arriving, not something moving: they come up from just under full size as the
// room for them opens, and go at once when it closes. An exit the eye waits through reads as a stall.
static const CGFloat kLyricsEnterScale = 0.96;
static const NSTimeInterval kLyricsIn = 0.3, kLyricsInDelay = 0.12, kLyricsOut = 0.16;
// A track that changes while the lines are up has this long to bring its own before they are put away.
static const NSTimeInterval kLyricsGrace = 3;
// Below this the player has not laid out yet and nothing can be measured from it.
static const CGFloat kLivingHeight = 200;
// The lines alone: this long untouched while they play, and the controls go. They go slowly, being
// nothing the eye waits for, and come back quickly, since a touch asked for them.
static const NSTimeInterval kAloneAfter = 4;
static const NSTimeInterval kAloneOut = 0.6, kAloneBack = 0.3;
// Lighter than the Kit's glyph buttons: a picture dimmed to half reads as gone, not pressed.
static const CGFloat kThumbPressScale = 0.94, kThumbPressAlpha = 0.8;
// Over a clip the thumbnail grows in from this in its place, and shrinks back to it going.
static const CGFloat kThumbAppearScale = 0.8;

static char kOverlayKey, kPlateKey, kTitleKey, kWatcherKey;
static BOOL sg_open;
static BOOL sg_moving;                      // the transition is in flight, so no layout pass may re-place it
static BOOL sg_alone;                       // the controls are away and the lines have the player
static BOOL sg_tapBroughtBack;              // the touch going on began with them away, so its tap seeks nowhere
static NSTimer *sg_aloneTimer;
static BOOL sg_singHeld;                    // Sing's microphone is open, preparing or explaining itself
static __weak UIView *sg_sing;              // the microphone, when Sing is on
static __weak UIView *sg_host;              // SPTNowPlayingView
static __weak UIViewController *sg_player;  // its controller
static __weak UIViewController *sg_info, *sg_duration, *sg_floating;
static __weak UIView *sg_titleElement;      // the arranged element view holding the title and the artist
static void touched(UIView *view);

#pragma mark - the overlay

// The thumbnail puts the cover back when tapped, the way the Music app's small artwork does. Its own
// transform is the flight, so the press goes on the face inside it.
@interface SGRPlayerLyricsThumb : UIControl
@property (nonatomic, readonly) UIView *face;        // the cover and its shadow
@end

@implementation SGRPlayerLyricsThumb {
    UIView *_face;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _face = [[UIView alloc] initWithFrame:self.bounds];
    _face.userInteractionEnabled = NO;
    [self addSubview:_face];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Hide lyrics";
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (UIView *)face { return _face; }

- (void)tapped {
    SGLog(@"redesign player: the thumbnail tapped, the cover goes back");
    SGRPlayerToggleLyrics();
}

// VoiceOver's double tap, which reaches a UIControl of one's own no other way.
- (BOOL)accessibilityActivate {
    [self tapped];
    return YES;
}

// The thumbnail remains available with the bottom controls away; only its flight blocks touches.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return sg_open && !sg_moving && [super pointInside:point withEvent:event];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    UIView *face = _face;
    SGRAnimate(SGRMotionPress, ^{
        face.alpha = highlighted ? kThumbPressAlpha : 1;
        face.transform = highlighted ? CGAffineTransformMakeScale(kThumbPressScale, kThumbPressScale) : CGAffineTransformIdentity;
    }, nil);
}

@end

// The thumbnail and the lines, side by side under one view so the lines' own view has no sibling of
// ours to hide: SGRKaraokeView takes the whole of whatever it is put in and dims what is next to it.
@interface SGRPlayerLyricsOverlay : UIView
@property (nonatomic, readonly) SGRPlayerLyricsThumb *thumb;   // the cover, at full size, moved by its transform
@property (nonatomic, readonly) UIImageView *cover;
@property (nonatomic, readonly) UIView *stage;       // holds the lines' view alone
@property (nonatomic, readonly) UILabel *empty;      // Sing's "no lyrics"
@property (nonatomic, readonly) SGRKaraokeView *lyrics;
@end

@implementation SGRPlayerLyricsOverlay {
    SGRPlayerLyricsThumb *_thumb;
    UIView *_stage;
    UIImageView *_cover;
    UILabel *_empty;
    SGRKaraokeView *_lyrics;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _thumb = [[SGRPlayerLyricsThumb alloc] initWithFrame:CGRectZero];
    _cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_thumb.face addSubview:_cover];
    _stage = [[UIView alloc] initWithFrame:CGRectZero];
    // What the lines leave when a song has none, which only Sing opens them for. A sibling of the lines'
    // view, so it goes whenever they have something to show (SGRKaraokeView's syncSiblings).
    _empty = [UILabel new];
    _empty.text = @"Lyrics aren't available for this song.";
    _empty.textColor = SGRSecondary();
    _empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _empty.adjustsFontForContentSizeCategory = YES;
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.numberOfLines = 0;
    [_stage addSubview:_empty];
    [self addSubview:_stage];
    [self addSubview:_thumb];
    return self;
}

- (SGRPlayerLyricsThumb *)thumb { return _thumb; }
- (UIImageView *)cover { return _cover; }
- (UIView *)stage { return _stage; }
- (UILabel *)empty { return _empty; }

// The lines seek when they are tapped and the thumbnail puts the cover back, so everywhere else the
// overlay would only swallow touches: a view that takes touches does, even with nothing on it.
//
// What it hands them to instead is the title row. Translated to the top of the player it is drawn well
// outside the stack view it is arranged in, and UIKit stops looking at a view whose bounds the touch is
// not in, so the add button and the menu that rode up with it are past Spotify's own reach. Asked here
// directly, the row answers for where it is drawn.
//
// The stage is as tall as the lines' room with the controls away, and the lines take touches only in
// the part they have now, so the stage swallows none either. The song row stays reachable in either mode.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit != self && hit != _stage) return hit;
    UIView *row = SGRPlayerLyricsOpen() ? sg_info.viewIfLoaded : nil;
    UIView *inRow = row ? [row hitTest:[row convertPoint:point fromView:self] withEvent:event] : nil;
    return inRow == row ? nil : inRow;
}

// Made on the first tap and kept afterwards: it measures the song for its width before it can place a
// line, so a view built again on every tap would show nothing for the first frames. Out of the window
// it costs nothing -- its display link only runs while it is in one.
- (SGRKaraokeView *)lyrics {
    if (!_lyrics) {
        _lyrics = [[SGRKaraokeView alloc] initWithFrame:_stage.bounds];
        _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _lyrics.takesTap = ^BOOL {
            // The lyric recognizer and the player's watcher may finish in either order.
            if (sg_alone) touched(nil);
            return !sg_tapBroughtBack;
        };
    }
    if (_lyrics.superview != _stage) [_stage addSubview:_lyrics];
    _lyrics.frame = _stage.bounds;
    return _lyrics;
}

@end

static SGRPlayerLyricsOverlay *overlayIn(UIView *host) {
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    if (!overlay) {
        overlay = [[SGRPlayerLyricsOverlay alloc] initWithFrame:host.bounds];
        objc_setAssociatedObject(host, &kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // On top of the player: it reaches from under the header row down to the progress bar, so it is over
    // the covers and the gradients and clear of every control. Under them instead, the mixing background
    // Spotify keeps between the two (01.txt:72) would be free to draw over the lines.
    if (overlay.superview != host) [host addSubview:overlay];
    return overlay;
}

#pragma mark - the measurements

typedef struct {
    BOOL ok;
    CGRect cover;     // where Spotify draws the cover now, in the player
    CGRect thumb;     // where it goes
    CGRect stage;     // where the lines go
    CGRect room;      // where they go with the controls away, which is the stage's frame throughout
    CGFloat lift;     // how far the title row rises
    CGFloat shift;    // how far the title slides right to clear the thumbnail, 0 when it sits under it
} SGRLyricsLayout;

// What a view's frame would be with the translation this file put on it left out.
static CGRect untransformed(UIView *view, UIView *host) {
    CGRect frame = SGFrameIn(view, host);
    CGAffineTransform t = view.transform;
    return CGRectOffset(frame, -t.tx, -t.ty);
}

static SGRLyricsLayout layoutIn(UIView *host) {
    SGRLyricsLayout l = {0};
    UIView *info = sg_info.viewIfLoaded, *duration = sg_duration.viewIfLoaded, *title = sg_titleElement;
    if (!host || host.bounds.size.height < kLivingHeight || !info || !duration) return l;
    CGRect area = SGRPlayerArtworkAreaIn(host), cover = SGRPlayerCoverFrameIn(host);
    if (CGRectIsNull(area) || CGRectIsNull(cover)) return l;
    CGRect row = untransformed(info, host), bar = untransformed(duration, host);
    // The thumbnail takes the title's own leading edge, so the two line up down the page.
    CGFloat leading = title ? CGRectGetMinX(untransformed(title, host)) : CGRectGetMinX(area) + SGRSideMargin;
    l.cover = cover;
    l.thumb = CGRectMake(leading, CGRectGetMinY(area) + kThumbTop, kThumbSide, kThumbSide);
    // Beside the thumbnail when the title can be moved clear of it, under it when it cannot be found.
    CGFloat top = title ? CGRectGetMidY(l.thumb) - row.size.height / 2 : CGRectGetMaxY(l.thumb) + SGRGrid;
    l.lift = top - CGRectGetMinY(row);
    l.shift = title ? kThumbSide + kThumbGap : 0;
    CGFloat lines = MAX(CGRectGetMaxY(l.thumb), top + row.size.height) + kLyricsTop;
    l.stage = CGRectMake(CGRectGetMinX(area), lines, area.size.width, CGRectGetMinY(bar) - kLyricsBottom - lines);
    // Immersive lyrics grow only downwards, keeping the thumbnail and song details clear.
    UIEdgeInsets safe = host.window.safeAreaInsets;
    CGFloat roomTop = CGRectGetMinY(l.stage);
    CGFloat roomBottom = MAX(host.bounds.size.height - safe.bottom, CGRectGetMaxY(l.stage));
    l.room = CGRectMake(CGRectGetMinX(area), roomTop, area.size.width, roomBottom - roomTop);
    l.ok = l.stage.size.height > kLivingHeight / 2 && l.lift < 0;
    return l;
}

// The lines' part of the stage: the band between the title row and the progress bar while the
// controls are there, all of it while they are away.
static UIEdgeInsets bandOf(SGRLyricsLayout l, BOOL alone) {
    if (alone) return UIEdgeInsetsZero;
    return UIEdgeInsetsMake(CGRectGetMinY(l.stage) - CGRectGetMinY(l.room), 0, CGRectGetMaxY(l.room) - CGRectGetMaxY(l.stage), 0);
}

#pragma mark - the title row

// Where the row's trailing controls start, in the unit's coordinates: the nearest arranged view on the
// trailing side of the title that is still there to be seen. The title may not reach it.
static CGFloat trailingEdgeIn(UIView *info) {
    UIView *title = sg_titleElement, *row = title.superview;
    if (!title || !row) return CGFLOAT_MAX;
    CGFloat titleLeft = CGRectGetMinX(untransformed(title, info));
    CGFloat limit = CGRectGetMaxX(SGFrameIn(row, info));
    for (UIView *view in row.subviews) {
        if (view == title || view.hidden || view.alpha < 0.01 || view.bounds.size.width < 1) continue;
        CGFloat x = CGRectGetMinX(SGFrameIn(view, info));
        if (x > titleLeft && x < limit) limit = x;
    }
    return limit;
}

// The title moved right by the thumbnail would run into the add button beside it, and it cannot simply
// be narrowed: Spotify lays its marquee labels out with constraints, which put the width back the next
// time anything in the row lays out -- and a long title, being a marquee, lays out often. A mask on the
// element takes no part in that, so it holds between passes, and it fades the title out where Spotify's
// own fade would have been rather than cutting it.
static void clipTitle(UIView *element, CGFloat width) {
    CGRect bounds = element.bounds;
    if (width >= bounds.size.width - 0.5 || bounds.size.height < 1) {
        element.layer.mask = nil;
        return;
    }
    CAGradientLayer *mask = [element.layer.mask isKindOfClass:CAGradientLayer.class] ? (CAGradientLayer *)element.layer.mask : nil;
    if (!mask) {
        mask = [CAGradientLayer layer];
        mask.colors = @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor];
        mask.startPoint = CGPointMake(0, 0.5);
        mask.endPoint = CGPointMake(1, 0.5);
        element.layer.mask = mask;
    }
    CGFloat fade = MIN(kTitleFade, width);
    CGRect frame = CGRectMake(0, 0, MAX(0, width), bounds.size.height);
    if (CGRectEqualToRect(frame, mask.frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = frame;
    mask.locations = @[@0, @(width > 0 ? (width - fade) / width : 0), @1];
    [CATransaction commit];
}

// The unit's row lays its arranged views out after the unit's own pass, so the transforms go on after it.
static void placeTitleRow(SGRLyricsLayout l) {
    UIView *info = sg_info.viewIfLoaded;
    if (!info) return;
    [SGRowIn(info) layoutIfNeeded];
    CGFloat lift = sg_open ? l.lift : 0, shift = sg_open ? l.shift : 0;
    CGAffineTransform rise = CGAffineTransformMakeTranslation(0, round(lift));
    if (!CGAffineTransformEqualToTransform(info.transform, rise)) info.transform = rise;
    UIView *title = sg_titleElement;
    if (!title) return;
    CGAffineTransform slide = CGAffineTransformMakeTranslation(round(shift), 0);
    if (!CGAffineTransformEqualToTransform(title.transform, slide)) title.transform = slide;
    // Closed it reaches as far as Spotify meant it to; moved, only as far as the controls it moved towards.
    CGFloat room = CGFLOAT_MAX;
    if (sg_open) room = trailingEdgeIn(info) - kTitleGap - (CGRectGetMinX(untransformed(title, info)) + shift);
    clipTitle(title, room);
}

#pragma mark - the lines alone

// The information row belongs to the bottom stack even after moving up beside the thumbnail. Fade
// only its siblings, never the parent: the title, artist and add button must remain visible and usable.
// Alpha, never hidden, since changing visibility inside Spotify's stacks can crash their layout.
static void showControls(CGFloat alpha) {
    UIView *info = sg_info.viewIfLoaded;
    UIStackView *stack = (UIStackView *)info.superview;
    if ([stack isKindOfClass:UIStackView.class]) {
        for (UIView *unit in stack.subviews) if (unit != info && unit != sg_floating.viewIfLoaded) unit.alpha = alpha;
    }
}

static void stopAloneTimer(void) {
    [sg_aloneTimer invalidate];
    sg_aloneTimer = nil;
}

static void scheduleAlone(void);

// Sing's microphone in the corner of the band the lines have now. Held, it keeps the controls from going
// and lets the count start over once it lets go.
static void placeSing(SGRPlayerLyricsOverlay *overlay, SGRLyricsLayout l) {
    CGRect band = [overlay convertRect:sg_alone ? l.room : l.stage fromView:sg_host];
    sg_sing = SGRSingControlForPage(overlay, band, sg_alone, ^(BOOL held) {
        sg_singHeld = held;
        if (held) stopAloneTimer();
        else scheduleAlone();
    });
}

static void setAlone(BOOL alone, BOOL animated) {
    if (alone == sg_alone) return;
    UIView *host = sg_host;
    SGRPlayerLyricsOverlay *overlay = host ? objc_getAssociatedObject(host, &kOverlayKey) : nil;
    SGRLyricsLayout l = layoutIn(host);
    if (alone && (!l.ok || !overlay.superview)) return;
    sg_alone = alone;
    stopAloneTimer();
    NSTimeInterval duration = animated ? (alone ? kAloneOut : kAloneBack) : 0;
    // Without a measurement the band is put back by the next layout pass (replace).
    if (l.ok && overlay.superview) [overlay.lyrics setLineInsets:bandOf(l, alone) duration:duration];
    void (^fade)(void) = ^{
        showControls(alone ? 0 : 1);
        if (l.ok && overlay.superview) {
            placeSing(overlay, l);
            [sg_sing layoutIfNeeded];
        }
    };
    if (duration > 0) {
        [UIView animateWithDuration:duration delay:0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:fade completion:nil];
    } else {
        fade();
    }
    SGLog(@"redesign player: the controls %@, the lines from %.0f to %.0f", alone ? @"away" : @"back",
          alone ? CGRectGetMinY(l.room) : CGRectGetMinY(l.stage), alone ? CGRectGetMaxY(l.room) : CGRectGetMaxY(l.stage));
}

// The lines on the player and the song playing, with nothing over the player and no one listening to
// its controls with VoiceOver.
static BOOL mayGoAlone(void) {
    UIView *host = sg_host;
    SGRPlayerLyricsOverlay *overlay = host ? objc_getAssociatedObject(host, &kOverlayKey) : nil;
    if (!sg_open || sg_moving || sg_singHeld || !host.window || !overlay.superview || overlay.lyrics.hidden) return NO;
    SPTPlayerState *state = SGPlayerState();
    if (!state || state.isPaused) return NO;
    // A sheet the player opens (the queue, the devices, the menu) is presented by its topmost controller.
    UIViewController *top = sg_player;
    while (top.parentViewController) top = top.parentViewController;
    if (top.presentedViewController) return NO;
    return !SGRPlayerIsTransitioning() && !UIAccessibilityIsVoiceOverRunning()
        && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

// Counts the time untouched from now. A timer that finds the lines not in (a track still bringing its
// own) or a sheet over the player starts over. One that finds the song paused or the app away lets it
// be, so a locked phone playing on is not woken for it: playing again starts it (SGRPlayerLyricsWatcher),
// and so does the app coming back (the %ctor).
static void scheduleAlone(void) {
    stopAloneTimer();
    if (!sg_open || sg_alone) return;
    sg_aloneTimer = [NSTimer scheduledTimerWithTimeInterval:kAloneAfter repeats:NO block:^(NSTimer *timer) {
        sg_aloneTimer = nil;
        if (mayGoAlone()) setAlone(YES, YES);
        else if (sg_open && !SGPlayerState().isPaused && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) scheduleAlone();
    }];
}

// A completed tap somewhere on the player, on `view`.
static void touched(UIView *view) {
    if (sg_alone && sg_sing && [view isDescendantOfView:sg_sing]) {
        sg_tapBroughtBack = NO;
        return;
    }
    sg_tapBroughtBack |= sg_alone;
    if (sg_alone) setAlone(NO, YES);
    scheduleAlone();
}

// Observe a tap without taking it from another recognizer. A drag fails before it can restore the
// controls, so browsing the lyrics does not change their room or bring the bottom bar back.
@interface SGRPlayerTouchWatcher : UIGestureRecognizer
@end

@implementation SGRPlayerTouchWatcher {
    CGPoint _start;
    NSTimeInterval _began;
    __weak UIView *_touchedView;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    UITouch *touch = touches.anyObject;
    sg_tapBroughtBack = NO;
    _start = [touch locationInView:self.view];
    _began = touch.timestamp;
    _touchedView = touch.view;
    if (!sg_alone) scheduleAlone();
    if (touches.count != 1) self.state = UIGestureRecognizerStateFailed;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    CGPoint point = [touches.anyObject locationInView:self.view];
    if (hypot(point.x - _start.x, point.y - _start.y) > 10) self.state = UIGestureRecognizerStateFailed;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (self.state == UIGestureRecognizerStatePossible && touches.anyObject.timestamp - _began < 0.35)
        touched(_touchedView);
    self.state = UIGestureRecognizerStateFailed;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    self.state = UIGestureRecognizerStateFailed;
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other { return NO; }

@end

static void watchTouches(UIView *host) {
    if (objc_getAssociatedObject(host, &kWatcherKey)) return;
    SGRPlayerTouchWatcher *watcher = [[SGRPlayerTouchWatcher alloc] initWithTarget:nil action:NULL];
    watcher.cancelsTouchesInView = NO;
    watcher.delaysTouchesEnded = NO;
    [host addGestureRecognizer:watcher];
    objc_setAssociatedObject(host, &kWatcherKey, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - opening and closing

BOOL SGRPlayerLyricsAvailable(void) {
    NSString *track = SGKaraokePlayingTrack();
    return track != nil && (SGKaraokeLinesForTrack(track) != nil || SGSingAvailable());
}

BOOL SGRPlayerLyricsOpen(void) {
    return sg_open;
}

// Puts the overlay's own views where the measurements say, without animating. The thumbnail is laid out
// at the size and place Spotify draws its cover at and moved by its transform alone, so a pass that
// runs while it is up leaves it exactly where the eye has it: the two are worked out from one
// measurement. Bounds and a centre, not a frame, since both views can be under a transform.
static void place(SGRPlayerLyricsOverlay *overlay, UIView *host, SGRLyricsLayout l) {
    overlay.frame = CGRectUnion(l.cover, CGRectUnion(l.thumb, l.room));
    CGRect cover = [overlay convertRect:l.cover fromView:host], stage = [overlay convertRect:l.room fromView:host];
    overlay.thumb.bounds = (CGRect){CGPointZero, cover.size};
    overlay.thumb.center = CGPointMake(CGRectGetMidX(cover), CGRectGetMidY(cover));
    UIView *face = overlay.thumb.face;
    CGPoint middle = CGPointMake(CGRectGetMidX(overlay.thumb.bounds), CGRectGetMidY(overlay.thumb.bounds));
    face.bounds = overlay.thumb.bounds;
    face.center = middle;
    overlay.cover.frame = face.bounds;
    SGRShadowPlate *plate = SGRShadowPlateIn(face, &kPlateKey);
    plate.bounds = face.bounds;
    plate.center = middle;
    overlay.stage.bounds = (CGRect){CGPointZero, stage.size};
    overlay.stage.center = CGPointMake(CGRectGetMidX(stage), CGRectGetMidY(stage));
    overlay.empty.frame = UIEdgeInsetsInsetRect(overlay.stage.bounds, bandOf(l, NO));
}

// Where the thumbnail's view has to go to land on `l.thumb`, as a transform about its own centre: the
// shadow and the corners travel with it that way, instead of a shadow redrawn on every frame.
static CGAffineTransform thumbTransform(SGRLyricsLayout l) {
    CGFloat scale = l.cover.size.width > 0 ? l.thumb.size.width / l.cover.size.width : 1;
    CGAffineTransform move = CGAffineTransformMakeTranslation(round(CGRectGetMidX(l.thumb) - CGRectGetMidX(l.cover)),
                                                             round(CGRectGetMidY(l.thumb) - CGRectGetMidY(l.cover)));
    return CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale), move);
}

// The corners as they will be drawn: a radius under a scale is drawn scaled, so the thumbnail asks for
// the radius it wants divided by the shrink, and the two ends of the animation are 12pt and 8pt corners.
static CGFloat thumbRadius(SGRLyricsLayout l, BOOL open) {
    if (!open) return SGRRadiusArtwork;
    CGFloat scale = l.cover.size.width > 0 ? l.thumb.size.width / l.cover.size.width : 1;
    return scale > 0 ? SGRRadiusCover / scale : SGRRadiusArtwork;
}

static void setOpen(BOOL open, BOOL animated) {
    UIView *host = sg_host;
    if (open == sg_open) return;
    if (!host) {
        SGLog(@"redesign player: the lyrics were asked for before the player laid out");
        return;
    }
    SGRLyricsLayout l = layoutIn(host);
    if (open && !l.ok) {
        SGLog(@"redesign player: the lyrics have nowhere to go (stage %.0fx%.0f, lift %.0f)", l.stage.size.width, l.stage.size.height, l.lift);
        return;
    }
    // The thumbnail is the Kit's picture drawn again, and Spotify's cover goes as it appears: without a
    // picture there would be a hole where the cover was, so the cover stays and the lyrics wait.
    UIImage *picture = SGRNowPlayingArtwork(NULL, NULL);
    if (open && !picture) {
        SGLog(@"redesign player: no artwork read yet, the lyrics stay down");
        return;
    }
    // The controls come back first: the thumbnail flying back to the cover is one of them.
    if (!open) {
        setAlone(NO, animated);
        stopAloneTimer();
    }
    BOOL clipWasShowing = SGRPlayerAnimatedShowing(NULL, NULL);
    sg_open = open;
    SGRPlayerLyricsChanged();
    SGRPlayerAnimatedFollowLyrics(open, animated);

    SGRPlayerLyricsOverlay *overlay = overlayIn(host);
    if (!open) SGRSingControlDismiss(overlay);
    place(overlay, host, l);
    CGAffineTransform away = thumbTransform(l);
    BOOL inPlace = open ? clipWasShowing : SGRPlayerAnimatedShowing(NULL, NULL);
    CGAffineTransform small = CGAffineTransformConcat(CGAffineTransformMakeScale(kThumbAppearScale, kThumbAppearScale), away);
    CGAffineTransform full = inPlace ? small : CGAffineTransformIdentity;
    // The state it starts from, so the animation has both ends of every value and nothing jumps into it.
    overlay.thumb.transform = open ? full : away;
    overlay.cover.layer.cornerRadius = thumbRadius(l, inPlace || !open);
    if (open) {
        overlay.thumb.alpha = inPlace ? 0 : 1;
        overlay.cover.image = SGRNowPlayingArtwork(NULL, NULL);
        overlay.stage.alpha = 0;
        overlay.stage.transform = CGAffineTransformMakeScale(kLyricsEnterScale, kLyricsEnterScale);
        [overlay.lyrics setLineInsets:bandOf(l, NO) duration:0];
        placeSing(overlay, l);
        sg_sing.alpha = 0;
        // Spotify's cover goes the moment the redesign's own takes its place: the same picture at the
        // same size with the same corners, so there is nothing to see in the swap. Coming back it waits
        // for the thumbnail to land on it, or the two would be on screen at once, one of them half size.
        SGRPlayerCoverList().alpha = 0;
    }

    void (^move)(void) = ^{
        overlay.thumb.transform = open ? away : full;
        if (inPlace) overlay.thumb.alpha = open ? 1 : 0;
        overlay.cover.layer.cornerRadius = thumbRadius(l, inPlace || open);
        placeTitleRow(l);
        sg_floating.viewIfLoaded.alpha = open ? 0 : 1;
    };
    void (^show)(void) = ^{
        overlay.stage.alpha = open ? 1 : 0;
        overlay.stage.transform = open ? CGAffineTransformIdentity
                                       : CGAffineTransformMakeScale(kLyricsEnterScale, kLyricsEnterScale);
        sg_sing.alpha = open ? 1 : 0;
    };
    void (^settled)(BOOL) = ^(BOOL finished) {
        sg_moving = NO;
        if (sg_open) return;   // opened again while it was going away
        SGRPlayerCoverList().alpha = 1;
        [overlay removeFromSuperview];
    };

    if (!animated) {
        move();
        show();
        settled(YES);
    } else {
        sg_moving = YES;
        SGRAnimate(SGRMotionLayout, move, settled);
        // The lines come in behind the cover leaving, and go before it comes back.
        [UIView animateWithDuration:open ? kLyricsIn : kLyricsOut delay:open ? kLyricsInDelay : 0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:show completion:nil];
    }
    if (open) scheduleAlone();
    SGLog(@"redesign player: lyrics %@%@, thumbnail %.0fx%.0f at %.0f,%.0f, title row up %.0f and right %.0f, lines %.0fx%.0f",
          open ? @"up" : @"away", inPlace ? @" in place over a clip" : @"", l.thumb.size.width, l.thumb.size.height, l.thumb.origin.x, l.thumb.origin.y,
          -l.lift, l.shift, l.stage.size.width, l.stage.size.height);
}

void SGRPlayerToggleLyrics(void) {
    if (!sg_open && !SGRPlayerLyricsAvailable()) return;
    setOpen(!sg_open, YES);
}

// A layout pass, a new track or a turn of the phone: the state is put back where it belongs without
// animating, since the frames it is measured from have just changed.
static void replace(void) {
    UIView *host = sg_host;
    if (!host || sg_moving) return;   // a pass in the middle of the transition would cut it short
    SGRLyricsLayout l = layoutIn(host);
    if (sg_open && !l.ok) return;
    placeTitleRow(l);
    sg_floating.viewIfLoaded.alpha = sg_open ? 0 : 1;
    if (!sg_open) return;
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    if (!overlay.superview) return;
    place(overlay, host, l);
    overlay.thumb.transform = thumbTransform(l);
    overlay.cover.layer.cornerRadius = thumbRadius(l, YES);
    overlay.lyrics.frame = overlay.stage.bounds;
    [overlay.lyrics setLineInsets:bandOf(l, sg_alone) duration:0];
    if (sg_alone) showControls(0);
    placeSing(overlay, l);
    SGRPlayerCoverList().alpha = 0;
}

#pragma mark - the units

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host || host.bounds.size.height < kLivingHeight) return;
    if (sg_host != host) {
        sg_host = host;
        SGLog(@"redesign player: the lyrics have the player's view %.0fx%.0f", host.bounds.size.width, host.bounds.size.height);
    }
    sg_player = (UIViewController *)self;
    watchTouches(host);
    replace();
}

// The bar morphs back out of a full size cover as the player closes, so the thumbnail is put away first.
- (void)viewWillDisappear:(BOOL)animated {
    if (sg_open) setOpen(NO, NO);
    %orig;
}
%end

static void infoLaidOut(UIViewController *unit) {
    sg_info = unit;
    UIView *host = unit.viewIfLoaded;
    // The title and the artist are two labels of one arranged element view, which is what moves.
    UIView *label = SGRFindByIdentifier(host, @"now-playing-title-label", &kTitleKey);
    UIView *element = nil;
    for (UIView *v = label; v && v != host; v = v.superview) {
        if ([v.superview isKindOfClass:UIStackView.class]) { element = v; break; }
    }
    if (element && sg_titleElement != element) {
        sg_titleElement = element;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign player: the title rides on %@ %@", NSStringFromClass(element.class), NSStringFromCGRect(element.frame)); });
    }
    replace();
}

static void durationLaidOut(UIViewController *unit) {
    sg_duration = unit;
    replace();
}

%hook _TtC20NowPlaying_ModesImpl23InformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    infoLaidOut((UIViewController *)self);
}
%end

%hook _TtC20NowPlaying_ModesImpl19DurationElementUnit
- (void)viewDidLayoutSubviews {
    %orig;
    durationLaidOut((UIViewController *)self);
}
%end

// Spotify Free's player builds the same elements into units of its own (Player.h); its floating unit
// is the shared one below.
%hook _TtC32ReinventFree_ReinventFreeNpvImpl35ReinventFreeInformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    infoLaidOut((UIViewController *)self);
}
%end

%hook _TtC32ReinventFree_ReinventFreeNpvImpl20DurationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    durationLaidOut((UIViewController *)self);
}
%end

// The chips over the title (Switch to video and whatever else a track brings) sit in the middle of the
// room the lines take, so they go while the lines are up. The row keeps its height: the rest of the
// bottom stack stays where it was, which is the whole point of lifting only the title out of it.
%hook _TtC20NowPlaying_ModesImpl20FloatingElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_floating = (UIViewController *)self;
    replace();
}
%end

#pragma mark - the track changing under them

// Lyrics arrive a moment after the track does: the glyph is asked again while they would be coming, and
// the lines already up wait out the same grace before they go. Not in the background, where Spotify may
// not ask for lyrics until the app is back, so coming back starts it over.
static void awaitLyrics(void) {
    for (NSNumber *delay in @[@1, @(kLyricsGrace)]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            SGRPlayerLyricsChanged();
            if (sg_open && delay.doubleValue >= kLyricsGrace && !SGRPlayerLyricsAvailable()) {
                SGLog(@"redesign player: no lyrics for the track that came on, the cover is back");
                setOpen(NO, YES);
            }
        });
    }
}

// Sing switched on or off in Mod Settings > Karaoke, or its voice model arriving or going: the lyrics' glyph and
// the microphone follow at once, and lyrics that were open only for Sing put the cover back.
static void singAvailabilityChanged(void) {
    static BOOL available;
    if (SGSingAvailable() == available) return;
    available = !available;
    SGRPlayerLyricsChanged();
    if (!sg_open) return;
    if (!SGRPlayerLyricsAvailable()) setOpen(NO, YES);
    else replace();
}

@interface SGRPlayerLyricsWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerLyricsWatcher {
    NSString *_track;
    BOOL _paused;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    // Paused, the controls come back for the play button and stay; playing again, the wait starts over.
    if (state.isPaused != _paused) {
        _paused = state.isPaused;
        if (_paused) {
            setAlone(NO, YES);
            stopAloneTimer();
        } else {
            scheduleAlone();
        }
    }
    NSString *track = SGURIString(state.track.URI);
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    awaitLyrics();
}

@end

static SGRPlayerLyricsWatcher *sg_watcher;

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    sg_watcher = [SGRPlayerLyricsWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        SGRPlayerLyricsChanged();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGSingDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        singAvailabilityChanged();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        // Spotify's own request may have been answered with nothing while the app was away.
        SGKaraokeRequestLyrics(SGKaraokePlayingTrack());
        SGRPlayerLyricsChanged();
        awaitLyrics();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (!sg_aloneTimer) scheduleAlone();   // the wait gave up while the app was away
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (!sg_open) return;
        SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
        overlay.cover.image = SGRNowPlayingArtwork(NULL, NULL);
    }];
    SGRequireClasses(@[
        @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController",
        @"_TtC20NowPlaying_ModesImpl23InformationElementsUnit",
        @"_TtC20NowPlaying_ModesImpl19DurationElementUnit",
        @"_TtC20NowPlaying_ModesImpl20FloatingElementsUnit",
        @"_TtC32ReinventFree_ReinventFreeNpvImpl35ReinventFreeInformationElementsUnit",
        @"_TtC32ReinventFree_ReinventFreeNpvImpl20DurationElementsUnit",
    ]);
}
