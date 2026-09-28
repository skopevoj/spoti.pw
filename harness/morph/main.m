// Morph harness: PlayerMorph.x run for real against a mock of Spotify's
// SPTBarOverlayPresentationTransition, which sets the player's frame, its alpha and the bar stand-in's
// frame and alpha from -setProgress: the way 9.1.78 does (0x109815464), driven by a display link on a
// spring. The page opens the player one second after launch, closes it two seconds later, and repeats.
// Stubbed: the bar's card and artwork (NowPlayingBar.x), the player's cover (PlayerArtwork.x), the
// artwork, the field and the log.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static const CGFloat kW = 402, kH = 874;

#pragma mark - stubs for what PlayerMorph.x reads

static __weak UIView *sg_card, *sg_barArt, *sg_cover;
static UIImage *sg_art;

CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius) {
    if (!sg_card.window) return CGRectNull;
    if (radius) *radius = 24;
    return [host convertRect:sg_card.bounds fromView:sg_card];
}
CGRect SGRNowPlayingArtworkFrameIn(UIView *host) {
    return sg_barArt.window ? [host convertRect:sg_barArt.bounds fromView:sg_barArt] : CGRectNull;
}
CGRect SGRPlayerCoverFrameIn(UIView *host) {
    return sg_cover.window ? [host convertRect:sg_cover.bounds fromView:sg_cover] : CGRectNull;
}
void SGRPlayerSetCoverHidden(BOOL hidden) { sg_cover.alpha = hidden ? 0 : 1; }
id SGRPlayerField(void) { return nil; }
BOOL SGRPlayerAnimatedShowing(CGFloat *shown, NSTimeInterval *left) {
    if (shown) *shown = 0;
    if (left) *left = 0;
    return NO;
}
UIImage *SGRNowPlayingArtwork(NSString **uri, NSString **identity) { return sg_art; }
const CGFloat SGRRadiusArtwork = 12;
BOOL SGRReduceMotion(void) { return NO; }
BOOL SGRedesignedUI(void) { return YES; }
void SGRequireClasses(NSArray *names) {}

#pragma mark - Spotify's transition, as 9.1.78 runs it

@interface SGHarnessContext : NSObject
@property (nonatomic, strong) UIView *containerView;
@end
@implementation SGHarnessContext
@end

@interface SPTBarOverlayPresentationTransition : NSObject
@property (nonatomic, strong) SGHarnessContext *transitioningContext;
@property (nonatomic, strong) UIView *overlayView, *barSnapshotView, *bottomBarView;
@property (nonatomic) CGRect barFrame;
@property (nonatomic) double progress;
@property (nonatomic) BOOL presenting;
@end

@implementation SPTBarOverlayPresentationTransition {
    CADisplayLink *_link;
    CFTimeInterval _start;
    void (^_done)(void);
}

- (void)setProgress:(double)progress {
    _progress = MIN(1, MAX(0, progress));
    UIView *container = self.transitioningContext.containerView;
    CGFloat maxY = CGRectGetMaxY(self.barFrame);
    self.overlayView.frame = CGRectOffset(container.bounds, 0, maxY - maxY * _progress);
    CGRect bar = self.barSnapshotView.frame;
    bar.origin.y = self.barFrame.origin.y - (self.barFrame.origin.y) * _progress * 0.2;
    self.barSnapshotView.frame = bar;
    self.barSnapshotView.alpha = 1 - MIN(_progress, 0.5) * 2;
    self.overlayView.alpha = MIN(1, _progress * 2);
}

- (void)runFrom:(UIView *)container done:(void (^)(void))done {
    self.transitioningContext = [SGHarnessContext new];
    self.transitioningContext.containerView = container;
    self.barFrame = [container convertRect:self.bottomBarView.bounds fromView:self.bottomBarView];
    [container addSubview:self.overlayView];
    if (self.presenting) {
        self.barSnapshotView = [self.bottomBarView snapshotViewAfterScreenUpdates:NO];
    } else {
        // Closing, the bar is hidden: Spotify shows it, renders it into an image and hides it again.
        self.bottomBarView.hidden = NO;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:self.bottomBarView.bounds];
        UIView *bar = self.bottomBarView;
        self.barSnapshotView = [[UIImageView alloc] initWithImage:[renderer imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [bar.layer renderInContext:c.CGContext];
        }]];
    }
    self.barSnapshotView.frame = self.barFrame;
    [container addSubview:self.barSnapshotView];
    self.bottomBarView.hidden = YES;
    [self setProgress:self.presenting ? 0 : 1];
    _done = done;
    _start = CACurrentMediaTime();
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(update)];
    _link.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)holdFrom:(UIView *)container at:(double)progress {
    self.transitioningContext = [SGHarnessContext new];
    self.transitioningContext.containerView = container;
    self.barFrame = [container convertRect:self.bottomBarView.bounds fromView:self.bottomBarView];
    [container addSubview:self.overlayView];
    self.barSnapshotView = [self.bottomBarView snapshotViewAfterScreenUpdates:NO];
    self.barSnapshotView.frame = self.barFrame;
    [container addSubview:self.barSnapshotView];
    self.bottomBarView.hidden = YES;
    [self setProgress:0];
    [self setProgress:progress];
}

- (void)update {
    double t = CACurrentMediaTime() - _start, w = 13;
    double x = 1 - (1 + w * t) * exp(-w * t);
    BOOL settled = x > 0.999;
    [self setProgress:self.presenting ? x : 1 - x];
    if (!settled) return;
    [_link invalidate];
    _link = nil;
    [self setProgress:self.presenting ? 1 : 0];
    [self destroyTransitioningContext];
    [self.barSnapshotView removeFromSuperview];
    if (!self.presenting) [self.overlayView removeFromSuperview];
    self.bottomBarView.hidden = self.presenting;
    if (_done) _done();
}

- (void)destroyTransitioningContext {
    self.transitioningContext = nil;
}
@end

#pragma mark - the page

static UIImage *artworkImage(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *c) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[(id)UIColor.systemOrangeColor.CGColor, (id)UIColor.systemPurpleColor.CGColor];
        CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
        CGContextDrawLinearGradient(c.CGContext, g, CGPointZero, CGPointMake(300, 300), 0);
        CGGradientRelease(g);
        CGColorSpaceRelease(space);
        [@"♫" drawAtPoint:CGPointMake(110, 90) withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:100], NSForegroundColorAttributeName: UIColor.whiteColor}];
    }];
}

static UILabel *label(NSString *text, CGRect frame, CGFloat size, UIColor *color) {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    l.textColor = color;
    return l;
}

@interface VC : UIViewController
@end

@implementation VC {
    UIView *_bar, *_player, *_container;
}

- (UIView *)makeBar {
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, kH - 83 - 64, kW, 56)];
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:[NSClassFromString(@"UIGlassEffect") effectWithStyle:0]];
    glass.frame = CGRectMake(8, 0, 386, 56);
    glass.layer.cornerRadius = 24;
    glass.clipsToBounds = YES;
    [bar addSubview:glass];
    sg_card = glass;
    UIImageView *art = [[UIImageView alloc] initWithImage:sg_art];
    art.frame = CGRectMake(16, 8, 40, 40);
    art.layer.cornerRadius = 20;
    art.clipsToBounds = YES;
    [bar addSubview:art];
    sg_barArt = art;
    [bar addSubview:label(@"Song Title", CGRectMake(66, 9, 200, 18), 15, UIColor.whiteColor)];
    [bar addSubview:label(@"Artist", CGRectMake(66, 28, 200, 16), 13, [UIColor colorWithWhite:1 alpha:0.6])];
    [bar addSubview:label(@"▶︎", CGRectMake(340, 14, 30, 28), 22, UIColor.whiteColor)];
    return bar;
}

- (UIView *)makePlayer {
    UIView *player = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kW, kH)];
    // Spotify paints the player in a plane inside its list (PlayerField.x); a black base of its own.
    player.backgroundColor = UIColor.blackColor;
    UIView *field = [[UIView alloc] initWithFrame:player.bounds];
    field.backgroundColor = [UIColor colorWithRed:0.35 green:0.16 blue:0.3 alpha:1];
    [player addSubview:field];
    [player addSubview:label(@"⌄", CGRectMake(24, 60, 40, 30), 28, UIColor.whiteColor)];
    UIImageView *cover = [[UIImageView alloc] initWithImage:sg_art];
    cover.frame = CGRectMake(24, 118, 354, 354);
    cover.layer.cornerRadius = 12;
    cover.clipsToBounds = YES;
    [player addSubview:cover];
    sg_cover = cover;
    [player addSubview:label(@"Song Title", CGRectMake(24, 520, 300, 28), 24, UIColor.whiteColor)];
    [player addSubview:label(@"Artist", CGRectMake(24, 552, 300, 22), 18, [UIColor colorWithWhite:1 alpha:0.6])];
    UIView *slider = [[UIView alloc] initWithFrame:CGRectMake(24, 600, 354, 4)];
    slider.backgroundColor = [UIColor colorWithWhite:1 alpha:0.4];
    [player addSubview:slider];
    [player addSubview:label(@"⏮     ⏸     ⏭", CGRectMake(90, 650, 260, 50), 40, UIColor.whiteColor)];
    return player;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    sg_art = artworkImage();
    self.view.backgroundColor = UIColor.blackColor;
    for (int i = 0; i < 8; i++) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(16, 70 + i * 90, kW - 32, 80)];
        row.backgroundColor = [UIColor colorWithHue:i / 8.0 saturation:0.5 brightness:0.5 alpha:1];
        row.layer.cornerRadius = 12;
        [self.view addSubview:row];
    }
    UIVisualEffectView *tabs = [[UIVisualEffectView alloc] initWithEffect:[NSClassFromString(@"UIGlassEffect") effectWithStyle:0]];
    tabs.frame = CGRectMake(21, kH - 83, 280, 62);
    tabs.layer.cornerRadius = 31;
    tabs.clipsToBounds = YES;
    [self.view addSubview:tabs];
    _bar = [self makeBar];
    [self.view addSubview:_bar];
    _player = [self makePlayer];
    _container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kW, kH)];
    _container.userInteractionEnabled = NO;
    [self.view addSubview:_container];
    // SIMCTL_CHILD_MORPH_T=0.4 holds the open at that progress, for a screenshot.
    NSString *hold = NSProcessInfo.processInfo.environment[@"MORPH_T"];
    if (hold) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{ [self holdAt:hold.doubleValue]; });
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self cycle]; });
}

- (void)transition:(BOOL)presenting done:(void (^)(void))done {
    SPTBarOverlayPresentationTransition *t = [SPTBarOverlayPresentationTransition new];
    t.presenting = presenting;
    t.overlayView = _player;
    t.bottomBarView = _bar;
    static SPTBarOverlayPresentationTransition *running;
    running = t;
    [t runFrom:_container done:done];
}

- (void)holdAt:(double)progress {
    static SPTBarOverlayPresentationTransition *held;
    held = [SPTBarOverlayPresentationTransition new];
    held.presenting = YES;
    held.overlayView = _player;
    held.bottomBarView = _bar;
    [held holdFrom:_container at:progress];
    UIView *player = _player, *container = _container, *cover = sg_cover;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        NSLog(@"MORPH overlay frame %@ alpha %.2f", NSStringFromCGRect(player.frame), player.alpha);
        NSLog(@"MORPH mask %@ sublayer %@", NSStringFromCGRect(player.layer.mask.frame), [NSValue valueWithCATransform3D:player.layer.sublayerTransform]);
        CALayer *shown = container.layer.presentationLayer ?: container.layer;
        NSLog(@"MORPH cover model %@ presented top-left %@", NSStringFromCGRect([container convertRect:cover.bounds fromView:cover]),
              NSStringFromCGPoint([cover.layer.presentationLayer convertPoint:CGPointZero toLayer:shown]));
        for (UIView *v in container.subviews) NSLog(@"MORPH sub %@ %@", v.class, NSStringFromCGRect(v.frame));
    });
}

- (void)cycle {
    [self transition:YES done:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self transition:NO done:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self cycle]; });
            }];
        });
    }];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [VC new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); }
}
