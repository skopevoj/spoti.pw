#import <UIKit/UIKit.h>
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Redesigned/Lyrics/SGRSingControl.h"
#import "Redesigned/Lyrics/SGRLyricsImmersive.h"

NSArray<SGKaraokeLine *> *SGTTMLLines(NSString *xml);
void SGHarnessStartClock(double at, double rate, double pauseAt, double holdFor);
NSUInteger SGHarnessSeekCount(void);
static BOOL sg_testTouching;
static CFTimeInterval sg_testTouchStarted, sg_testTouchEnded;
static NSUInteger sg_testHiddenDuringTouch;

@interface HarnessApplication : UIApplication
@end
@implementation HarnessApplication
- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches) {
        BOOL down = NO;
        for (UITouch *touch in event.allTouches) if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) down = YES;
        if (down && !sg_testTouching) sg_testTouchStarted = CACurrentMediaTime();
        if (!down && sg_testTouching) sg_testTouchEnded = CACurrentMediaTime();
        sg_testTouching = down;
    }
    [super sendEvent:event];
}
@end

static void after(double seconds, dispatch_block_t work) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), work);
}
static void check(BOOL success, NSString *description) {
    NSLog(@"immersive %@: %@", success ? @"PASS" : @"FAIL", description);
    if (!success) abort();
}

@interface LyricsController : UIViewController
@end
@interface SGRKaraokeView (HarnessBrowsing)
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
- (void)rebuild;
@end
@implementation LyricsController {
    UIView *_header, *_footer, *_host;
    SGRKaraokeView *_lyrics;
    SGRLyricsImmersiveController *_immersive;
    CGRect _normal;
    BOOL _testsStarted, _expanded;
    UILabel *_probe;
    UILabel *_singProbe;
    CGFloat _maximumCapsuleHeight, _minimumCapsuleOffset, _maximumCapsuleOffset;
    NSTimer *_probeTimer;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithRed:0.18 green:0.07 blue:0.16 alpha:1];
    _header = [UIView new]; _footer = [UIView new]; _host = [UIView new];
    [self.view addSubview:_header]; [self.view addSubview:_footer]; [self.view addSubview:_host];
    UILabel *title = [UILabel new]; title.text = @"Sing along\nImmersive lyrics"; title.numberOfLines = 2;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.textColor = UIColor.whiteColor; title.frame = CGRectMake(22, 8, 250, 65); [_header addSubview:title];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; [close setTitle:@"Close" forState:UIControlStateNormal];
    close.frame = CGRectMake(280, 14, 72, 44); close.tintColor = UIColor.whiteColor; [_header addSubview:close];
    UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
    [play setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    play.tintColor = UIColor.whiteColor; play.frame = CGRectMake(150, 30, 60, 50); [_footer addSubview:play];
    UISlider *progress = [UISlider new]; progress.frame = CGRectMake(24, 0, 320, 32); progress.value = 0.4; [_footer addSubview:progress];
    _lyrics = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    [_host addSubview:_lyrics];
    _immersive = [[SGRLyricsImmersiveController alloc] initWithPage:self.view lyrics:_lyrics chrome:@[_footer]];
    __weak typeof(self) weakLayout = self;
    _immersive.layoutChanged = ^(BOOL expanded) {
        typeof(self) strong = weakLayout;
        if (!strong) return;
        strong->_expanded = expanded;
        [strong.view setNeedsLayout];
        [strong.view layoutIfNeeded];
    };
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    // Reproduce the enclosing player's competing dismissal pan. Sing must keep a drag that
    // starts inside its capsule; a plain UIControl alone gets cancelled by this recognizer.
    if ([prefs boolForKey:@"sing-ui"]) {
        [self.view addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(playerPanned:)]];
    }
    NSString *song = [prefs stringForKey:@"song"] ?: @"both";
    NSString *path = [NSBundle.mainBundle pathForResource:song ofType:@"ttml"];
    NSString *text = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    NSArray *lines = text ? SGTTMLLines(text) : nil;
    if ([song isEqualToString:@"static"]) lines = SGKaraokeStaticLines(@[@"An untimed lyric", @"Still fills the screen", @"Scroll at your own pace"]);
    SGKaraokeKeepLines(@"harness", lines);
    SGHarnessStartClock(42000, 1, 45000, 0);
    if ([prefs boolForKey:@"uitest"]) {
        _probe = [UILabel new];
        _probe.accessibilityIdentifier = @"immersive-test-state";
        _probe.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
        _probe.textColor = UIColor.whiteColor;
        [self.view addSubview:_probe];
        if ([prefs boolForKey:@"sing-ui"]) {
            _singProbe = [UILabel new];
            _singProbe.accessibilityIdentifier = @"sing-test-geometry";
            _singProbe.font = _probe.font; _singProbe.textColor = UIColor.whiteColor;
            [self.view addSubview:_singProbe];
        }
        __weak typeof(self) weak = self;
        _probeTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) { [weak updateProbe]; }];
    }
}
- (void)playerPanned:(UIPanGestureRecognizer *)gesture { }
- (void)dealloc { [_probeTimer invalidate]; }
- (void)updateProbe {
    // Test-only observation; events still go through UIKit and the production recognizers.
    CGPoint target = CGPointMake(CGRectGetMidX(_lyrics.bounds), CGRectGetMidY(_lyrics.bounds));
    CGFloat nearest = CGFLOAT_MAX;
    for (UIView *line in [[_lyrics valueForKey:@"_shown"] allValues]) {
        CGRect rect = [line convertRect:line.bounds toView:_lyrics];
        CGFloat distance = fabs(CGRectGetMidY(rect) - CGRectGetMidY(_lyrics.bounds));
        if (CGRectIntersectsRect(rect, _lyrics.bounds) && distance < nearest) {
            nearest = distance;
            target = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
        }
    }
    target = [_lyrics convertPoint:target toView:self.view];
    if (sg_testTouching && _immersive.immersive) sg_testHiddenDuringTouch++;
    _probe.text = [NSString stringWithFormat:@"%@|%lu|%.1f|%.1f|%lu|%.3f", _immersive.immersive ? @"immersive" : @"visible",
                   (unsigned long)SGHarnessSeekCount(), target.x, target.y, (unsigned long)sg_testHiddenDuringTouch,
                   sg_testTouchEnded > sg_testTouchStarted ? sg_testTouchEnded - sg_testTouchStarted : 0];
    if (_singProbe) {
        for (UIView *view in self.view.subviews) {
            if (![NSStringFromClass(view.class) isEqualToString:@"SGRSingControl"]) continue;
            UIView *panel = [view valueForKey:@"panel"];
            BOOL expanded = [[view valueForKey:@"expanded"] boolValue];
            CGFloat height = panel.bounds.size.height, offset = panel.center.y - 124;
            if (expanded && sg_testTouching) {
                _maximumCapsuleHeight = MAX(_maximumCapsuleHeight, height);
                _minimumCapsuleOffset = MIN(_minimumCapsuleOffset, offset);
                _maximumCapsuleOffset = MAX(_maximumCapsuleOffset, offset);
            }
            _singProbe.text = [NSString stringWithFormat:@"%.1f|%.1f|%.1f|%.1f", height,
                              _maximumCapsuleHeight, _minimumCapsuleOffset, _maximumCapsuleOffset];
        }
    }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    CGFloat top = self.view.safeAreaInsets.top;
    _header.frame = CGRectMake(0, top, size.width, 90);
    _footer.frame = CGRectMake(0, size.height - self.view.safeAreaInsets.bottom - 120, size.width, 120);
    _host.frame = CGRectMake(0, top + 90, size.width, MAX(0, _footer.frame.origin.y - top - 90));
    _normal = _host.frame;
    if (_expanded) _host.frame = CGRectMake(_normal.origin.x, _normal.origin.y, _normal.size.width,
                                            size.height - self.view.safeAreaInsets.bottom - _normal.origin.y);
    _lyrics.frame = _host.bounds;
    __weak SGRLyricsImmersiveController *weak = _immersive;
    SGRSingControlForPage(self.view, _host, _immersive.immersive, ^(BOOL held) { [weak hold:SGRImmersiveSing active:held]; });
    _probe.frame = CGRectMake(8, top, size.width - 16, 14);
    _singProbe.frame = CGRectMake(8, top + 14, size.width - 16, 14);
    if (_probe) [self.view bringSubviewToFront:_probe];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_immersive setPresented:YES];
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"test"] && !_testsStarted) {
        _testsStarted = YES;
        [self runChecks];
    }
}
- (void)viewWillDisappear:(BOOL)animated {
    [_immersive setPresented:NO];
    [super viewWillDisappear:animated];
}
- (void)runChecks {
    check(!_immersive.immersive && _header.alpha == 1, @"visible after presentation");
    after(1.8, ^{ check(!self->_immersive.immersive, @"not hidden early"); });
    after(2.4, ^{
        check(self->_immersive.immersive && self->_header.alpha == 1 && self->_footer.alpha == 0, @"bottom controls hide while compact header stays visible");
        check(self->_lyrics.frame.size.height > self->_normal.size.height, @"lyrics viewport expanded");
        check(self->_host.frame.origin.y == self->_normal.origin.y, @"lyrics expand downward without moving the compact header");
        check(!self->_header.hidden && !self->_footer.hidden, @"Spotify stack children never hidden");
        NSArray *views = [[self->_lyrics valueForKey:@"_shown"] allValues];
        [self->_immersive interact];
        check(!self->_immersive.immersive && CGRectEqualToRect(self->_host.frame, self->_normal), @"reveal restores normal viewport immediately");
        NSArray *afterViews = [[self->_lyrics valueForKey:@"_shown"] allValues];
        check([views isEqualToArray:afterViews], @"height transition retains lyric line views");
        [self->_immersive hold:SGRImmersiveMenu active:YES];
    });
    after(5, ^{
        check(!self->_immersive.immersive && self->_header.alpha == 1, @"open menu prevents auto-hide");
        [self->_immersive hold:SGRImmersiveMenu active:NO];
    });
    after(7.4, ^{
        check(self->_immersive.immersive, @"menu dismissal starts fresh timer");
        [self->_immersive setPresented:NO];
    });
    after(10, ^{
        check(!self->_immersive.immersive && self->_header.alpha == 1, @"disappeared page has no live idle timer");
        [self->_immersive setPresented:YES];
        check(!self->_immersive.immersive, @"reopening starts visible");
    });
    after(10.2, ^{
        [self->_lyrics scrollViewWillBeginDragging:nil];
        [self->_lyrics rebuild];
    });
    after(12.6, ^{
        check(self->_immersive.immersive, @"lyric rebuild releases its browsing hold");
        NSLog(@"immersive ALL CHECKS PASSED");
    });
}
@end

@interface HarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HarnessScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [LyricsController new];
    [self.window makeKeyAndVisible];
}
@end
@interface HarnessDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation HarnessDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Lyrics" sessionRole:session.role];
    config.delegateClass = HarnessScene.class;
    return config;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, NSStringFromClass(HarnessApplication.class), NSStringFromClass(HarnessDelegate.class)); }
}
