// LandscapeLyrics.h says what this is.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"
#import "SGRKaraokeView.h"
#import "LandscapeLyrics.h"

// How long the phone has to stay on its side, or upright again, before the screen comes or goes.
static const NSTimeInterval kSettle = 0.35;

static void dismissLandscape(BOOL held);

@interface SGRLandscapeLyricsController : UIViewController
@property (nonatomic) UIDeviceOrientation orientation;
@end

@implementation SGRLandscapeLyricsController {
    UIView *_turned;
    UIView *_host;
    SGRKaraokeView *_lyrics;
    UILabel *_title;
    UIButton *_close;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _turned = [UIView new];
    _turned.backgroundColor = UIColor.blackColor;
    [self.view addSubview:_turned];
    // The lyrics take the whole of what they are put in, so they get a view of their own.
    _host = [UIView new];
    [_turned addSubview:_host];
    _lyrics = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    _lyrics.landscape = YES;
    _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_host addSubview:_lyrics];
    _title = [UILabel new];
    _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _title.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    [_turned addSubview:_title];
    _close = [UIButton buttonWithType:UIButtonTypeSystem];
    [_close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold]]
            forState:UIControlStateNormal];
    _close.tintColor = [UIColor colorWithWhite:1 alpha:0.7];
    _close.accessibilityLabel = @"Close";
    [_close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_turned addSubview:_close];
    [self refreshTitle];
}

- (void)refreshTitle {
    SPTPlayerTrack *track = SGPlayerState().track;
    NSString *title = [track respondsToSelector:@selector(trackTitle)] ? track.trackTitle : nil;
    NSString *artist = [track respondsToSelector:@selector(artistName)] ? track.artistName : nil;
    _title.text = title.length ? (artist.length ? [NSString stringWithFormat:@"%@ · %@", title, artist] : title) : nil;
}

- (void)closeTapped {
    dismissLandscape(YES);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    CGFloat angle = self.orientation == UIDeviceOrientationLandscapeRight ? -M_PI_2 : M_PI_2;
    _turned.transform = CGAffineTransformIdentity;
    _turned.bounds = CGRectMake(0, 0, size.height, size.width);
    _turned.center = CGPointMake(size.width / 2, size.height / 2);
    _turned.transform = CGAffineTransformMakeRotation(angle);
    // The notch and the rounded corners sit on the short sides once turned.
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat side = MAX(MAX(safe.top, safe.bottom), 24), width = size.height, height = size.width;
    _close.frame = CGRectMake(width - side - 36, 14, 36, 36);
    _title.frame = CGRectMake(side, 14, width - 2 * side - 48, 36);
    _host.frame = CGRectMake(side, 54, width - 2 * side, height - 54 - 12);
    _lyrics.frame = _host.bounds;
}

@end

static UIWindow *sg_window;
static SGRLandscapeLyricsController *sg_controller;
static NSUInteger sg_turns;
// Closed by hand: stays closed until the phone has been upright again.
static BOOL sg_held;

static void dismissLandscape(BOOL held) {
    if (held) sg_held = YES;
    if (!sg_window) return;
    UIWindow *window = sg_window;
    sg_window = nil;
    sg_controller = nil;
    [UIView animateWithDuration:0.25 animations:^{ window.alpha = 0; } completion:^(BOOL finished) {
        window.hidden = YES;
    }];
    SGLog(@"landscape lyrics: closed");
}

static void present(UIDeviceOrientation orientation) {
    if (sg_window) {
        if (sg_controller.orientation != orientation) {
            sg_controller.orientation = orientation;
            [UIView animateWithDuration:0.3 animations:^{ [sg_controller.view setNeedsLayout]; [sg_controller.view layoutIfNeeded]; }];
        }
        return;
    }
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    if (!scene) return;
    sg_controller = [SGRLandscapeLyricsController new];
    sg_controller.orientation = orientation;
    sg_window = [[UIWindow alloc] initWithWindowScene:scene];
    sg_window.windowLevel = UIWindowLevelStatusBar + 1;
    sg_window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    sg_window.rootViewController = sg_controller;
    sg_window.alpha = 0;
    sg_window.hidden = NO;
    [UIView animateWithDuration:0.3 animations:^{ sg_window.alpha = 1; }];
    SGLog(@"landscape lyrics: opened");
}

static void settle(UIDeviceOrientation orientation) {
    BOOL sideways = orientation == UIDeviceOrientationLandscapeLeft || orientation == UIDeviceOrientationLandscapeRight;
    if (orientation == UIDeviceOrientationPortrait) sg_held = NO;
    if (sideways) {
        if (sg_held || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        if (sg_window || [SGRKaraokeView lyricsOnScreen]) present(orientation);
    } else if (orientation == UIDeviceOrientationPortrait || orientation == UIDeviceOrientationPortraitUpsideDown) {
        dismissLandscape(NO);
    }
}

static void orientationChanged(void) {
    UIDeviceOrientation orientation = UIDevice.currentDevice.orientation;
    // Face up and face down say nothing about which way the screen is read.
    if (orientation == UIDeviceOrientationFaceUp || orientation == UIDeviceOrientationFaceDown || orientation == UIDeviceOrientationUnknown) return;
    NSUInteger turn = ++sg_turns;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (turn == sg_turns) settle(orientation);
    });
}

SGModRow *SGRLandscapeLyricsRow(void) {
    return SGSwitchRow(@"Landscape lyrics", @"Turn the phone on its side with the lyrics open", SGRKeyLandscapeLyrics);
}

%ctor {
    // The screen turns the lyrics by 90 degrees on its own, which only an iPhone held on its side wants.
    if (!SGRedesignedUI() || !SGEnabled(SGRKeyLandscapeLyrics) || UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
        [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) { orientationChanged(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) { dismissLandscape(NO); }];
    });
}
