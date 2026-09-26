#import "Core/SGCore.h"
#import "SGRLyricsImmersive.h"
#import "SGRKaraokeView.h"
#import "Redesigned/Kit/SGRTokens.h"
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <AVFoundation/AVFoundation.h>

// Observes touch-down without delaying ordinary controls. Only a gesture that starts in immersive
// mode is recognized/cancelled, so its first tap cannot reach a lyric's seek recognizer underneath.
@interface SGRLyricsTouch : UIGestureRecognizer <UIGestureRecognizerDelegate>
@property (nonatomic, weak) SGRLyricsImmersiveController *owner;
@end
@implementation SGRLyricsTouch {
    NSMutableSet<UITouch *> *_touches;
    BOOL _consumes;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    // A deliberately visible control handles its own first gesture. Revealing the player on
    // touch-down would move Sing's microphone away before its button or pan can act.
    if (self.owner.immersive) {
        for (UIView *view = touch.view; view && view != self.view; view = view.superview) {
            if ([view isKindOfClass:UIControl.class]) return NO;
        }
    }
    return YES;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_touches.count) {
        _consumes = self.owner.immersive;
        [self.owner hold:SGRImmersiveTouch active:YES];
        _touches = [NSMutableSet set];
    }
    [_touches unionSet:touches];
    if (_consumes) self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateBegan : UIGestureRecognizerStateChanged;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_consumes) self.state = UIGestureRecognizerStateChanged;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [_touches minusSet:touches];
    if (!_touches.count) {
        [self.owner hold:SGRImmersiveTouch active:NO];
        self.state = _consumes ? UIGestureRecognizerStateEnded : UIGestureRecognizerStateFailed;
    }
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [_touches removeAllObjects];
    [self.owner hold:SGRImmersiveTouch active:NO];
    self.state = UIGestureRecognizerStateCancelled;
}
- (void)reset {
    [super reset];
    if (_touches.count) [self.owner hold:SGRImmersiveTouch active:NO];
    [_touches removeAllObjects];
    _consumes = NO;
}
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other { return _consumes; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
@end

@interface SGRLyricsChrome : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) BOOL accessibilityHidden;
@end
@implementation SGRLyricsChrome
@end

static char kImmersiveOwnerKey;

SGRLyricsImmersiveController *SGRLyricsImmersiveOwner(UIView *view) {
    for (UIView *parent = view; parent; parent = parent.superview) {
        if ([parent isKindOfClass:SGRKaraokeView.class]) return nil;
        id owner = objc_getAssociatedObject(parent, &kImmersiveOwnerKey);
        if (owner) return owner;
    }
    return nil;
}

@implementation SGRLyricsImmersiveController {
    __weak UIView *_page;
    __weak SGRKaraokeView *_karaoke;
    NSArray<SGRLyricsChrome *> *_chrome;
    SGRLyricsTouch *_touch;
    NSTimer *_timer;
    SGRImmersiveState _state;
    BOOL _drawnImmersive, _presented, _interrupted;
    NSUInteger _animation;
}
- (instancetype)initWithPage:(UIView *)page lyrics:(SGRKaraokeView *)lyrics chrome:(NSArray<UIView *> *)chrome {
    if (!(self = [super init])) return nil;
    _page = page;
    _karaoke = lyrics;
    objc_setAssociatedObject(page, &kImmersiveOwnerKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak typeof(self) weak = self;
    lyrics.interactionChanged = ^(NSUInteger reason, BOOL held) {
        [weak hold:reason == 1 ? SGRImmersiveBrowse : SGRImmersiveMenu active:held];
    };
    NSMutableArray *saved = [NSMutableArray array];
    for (UIView *view in chrome) {
        SGRLyricsChrome *item = [SGRLyricsChrome new];
        item.view = view;
        [saved addObject:item];
    }
    _chrome = saved;
    _touch = [[SGRLyricsTouch alloc] initWithTarget:nil action:nil];
    _touch.owner = self;
    _touch.delegate = _touch;
    _touch.delaysTouchesBegan = NO;
    _touch.delaysTouchesEnded = NO;
    [page addGestureRecognizer:_touch];
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(lifecycle:) name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(lifecycle:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:nil];
    [nc addObserver:self selector:@selector(activity:) name:AVAudioSessionRouteChangeNotification object:nil];
    [nc addObserver:self selector:@selector(focus:) name:UIAccessibilityElementFocusedNotification object:nil];
    [nc addObserver:self selector:@selector(voiceOver:) name:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];
    return self;
}
- (void)dealloc {
    [_timer invalidate];
    [_page removeGestureRecognizer:_touch];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)addChromeView:(UIView *)view {
    if (!view) return;
    for (SGRLyricsChrome *item in _chrome) if (item.view == view) return;
    SGRLyricsChrome *item = [SGRLyricsChrome new];
    item.view = view; item.alpha = view.alpha;
    item.accessibilityHidden = view.accessibilityElementsHidden;
    _chrome = [_chrome arrayByAddingObject:item];
    if (_drawnImmersive) { view.alpha = 0; view.accessibilityElementsHidden = YES; }
}
- (BOOL)immersive { return _state.immersive; }
- (void)setPresented:(BOOL)presented {
    _presented = presented;
    [_timer invalidate];
    _timer = nil;
    BOOL active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive && !_interrupted;
    SGRImmersiveSetVisible(&_state, presented, active, CACurrentMediaTime());
    [self draw:NO];
    if (!presented || !active) return;
    // VoiceOver starts conservatively; a focus notification in the lyric surface releases the hold.
    if (UIAccessibilityIsVoiceOverRunning()) _state.holds |= SGRImmersiveAccessibility;
    __weak typeof(self) weak = self;
    _timer = [NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) { [weak checkIdle]; }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)lifecycle:(NSNotification *)note {
    if ([note.name isEqualToString:UIApplicationWillResignActiveNotification]) {
        SGRImmersiveSetVisible(&_state, _presented, NO, CACurrentMediaTime());
        [_timer invalidate]; _timer = nil;
        [self draw:NO];
    } else [self setPresented:_presented];
}
- (void)interruption:(NSNotification *)note {
    // AVAudioSession may post off-main.
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_interrupted = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan;
        [self setPresented:self->_presented];
    });
}
- (void)activity:(NSNotification *)note { dispatch_async(dispatch_get_main_queue(), ^{ [self interact]; }); }
- (void)voiceOver:(NSNotification *)note { [self hold:SGRImmersiveAccessibility active:UIAccessibilityIsVoiceOverRunning()]; }
- (void)focus:(NSNotification *)note {
    if (!_presented) return;
    id focused = note.userInfo[UIAccessibilityFocusedElementKey];
    UIView *view = [focused isKindOfClass:UIView.class] ? focused : nil;
    // Non-view accessibility elements are kept visible too; never hide a focused control.
    BOOL lyric = view && _karaoke && [view isDescendantOfView:_karaoke] && !(view.accessibilityTraits & UIAccessibilityTraitButton);
    [self hold:SGRImmersiveAccessibility active:UIAccessibilityIsVoiceOverRunning() && !lyric];
}
- (void)interact {
    SGRImmersiveInteract(&_state, CACurrentMediaTime());
    [self draw:YES];
}
- (void)hold:(uint32_t)reason active:(BOOL)active {
    SGRImmersiveHold(&_state, reason, active, CACurrentMediaTime());
    [self draw:YES];
}
- (BOOL)busy:(UIView *)view {
    if (!view || view.hidden || view.alpha < 0.01) return NO;
    if (view == _karaoke) return NO; // its browsing/menu callbacks already hold the deadline
    if ([view isKindOfClass:UIControl.class] && ((UIControl *)view).tracking) return YES;
    if ([view isKindOfClass:UIScrollView.class]) {
        UIScrollView *scroll = (UIScrollView *)view;
        if (scroll.dragging || scroll.decelerating || scroll.tracking) return YES;
    }
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        if (gesture == _touch) continue;
        if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) return YES;
    }
    for (UIView *child in view.subviews) if ([self busy:child]) return YES;
    return NO;
}
- (void)checkIdle {
    if (!_page.window || !_presented) { [self setPresented:NO]; return; }
    // A menu or route picker owned by the page suspends hiding until its dismissal.
    UIViewController *vc = nil;
    for (UIResponder *r = _page; r; r = r.nextResponder) if ([r isKindOfClass:UIViewController.class]) { vc = (id)r; break; }
    // Persistent controls handle their gesture before revealing the player. Polling their
    // tracking state while immersive would move them away from the finger mid-tap.
    BOOL busy = (!_state.immersive && [self busy:_page]) || vc.presentedViewController != nil;
    if (busy || (_state.holds & SGRImmersiveControl)) [self hold:SGRImmersiveControl active:busy];
    SGRImmersiveAdvance(&_state, CACurrentMediaTime());
    [self draw:YES];
}
- (void)draw:(BOOL)animated {
    BOOL immersive = _state.immersive;
    if (immersive == _drawnImmersive) return;
    if (immersive) {
        for (SGRLyricsChrome *item in _chrome) {
            item.alpha = item.view.alpha;
            item.accessibilityHidden = item.view.accessibilityElementsHidden;
        }
    }
    _drawnImmersive = immersive;
    NSUInteger generation = ++_animation;
    void (^changes)(void) = ^{
        for (SGRLyricsChrome *item in self->_chrome) {
            UIView *view = item.view;
            view.alpha = immersive ? 0 : item.alpha;
            view.accessibilityElementsHidden = immersive ? YES : item.accessibilityHidden;
        }
        self->_karaoke.chromeHidden = immersive;
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        if (generation == self->_animation && self.layoutChanged) self.layoutChanged(immersive);
    };
    if (animated) [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut animations:changes completion:completion];
    else { changes(); completion(YES); }
    // Revealing controls also restores their touch targets immediately.
    if (!immersive && self.layoutChanged) self.layoutChanged(NO);
}
@end
