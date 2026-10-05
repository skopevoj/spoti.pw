// The donate sheet and the Ko-fi button over a stand-in Home: `sheet` brings the sheet up a second in,
// `tour` shows the button alone, as the welcome tour has it, and `certificate` brings up the certificate
// offer with spoti.pw's copy (the logo from the file in HARNESS_LOGO, the glyph without one).
#import <UIKit/UIKit.h>
#import "App/Donate/Donate.h"
#import "App/About/About.h"
#import "App/Sheet/SGCardSheet.h"

BOOL SGOnboardingShowing(void) { return NO; }
BOOL SGUpdateNoticeShown(void) { return NO; }

@interface Delegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation Delegate

static UIViewController *home(void) {
    UIViewController *screen = [UIViewController new];
    screen.view.backgroundColor = UIColor.blackColor;
    NSArray *colors = @[UIColor.systemPinkColor, UIColor.systemTealColor, UIColor.systemOrangeColor, UIColor.systemIndigoColor, UIColor.systemGreenColor, UIColor.systemPurpleColor];
    CGFloat side = (402 - 16 * 3) / 2.0;
    for (NSInteger i = 0; i < 8; i++) {
        UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(16 + (i % 2) * (side + 16), 90 + (i / 2) * (side + 16), side, side)];
        tile.backgroundColor = colors[i % colors.count];
        tile.layer.cornerRadius = 10;
        [screen.view addSubview:tile];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"tour"]) {
        UIView *dim = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
        [screen.view addSubview:dim];
        SGGlowButton *button = [[SGGlowButton alloc] initWithTitle:@"Buy a student a coffee" symbol:@"cup.and.saucer.fill" color:SGKofiColor() prominent:NO];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [screen.view addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.centerXAnchor constraintEqualToAnchor:screen.view.centerXAnchor],
            [button.centerYAnchor constraintEqualToAnchor:screen.view.centerYAnchor],
        ]];
    }
    return screen;
}

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = home();
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self.window makeKeyAndVisible];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"sheet"])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGShowDonateSheet(); });
    if ([NSProcessInfo.processInfo.arguments containsObject:@"certificate"]) {
        NSString *path = NSProcessInfo.processInfo.environment[@"HARNESS_LOGO"];
        UIImage *logo = path ? [UIImage imageWithData:[NSData dataWithContentsOfFile:path] scale:3] : nil;
        NSDictionary *offer = @{
            @"show": @YES,
            @"title": @"Re-signing every week?",
            @"message": @"Your signature runs out on {date}. A certificate lasts a year, with no 3-app limit.",
            @"note": @"From $8.89 at Arctic Sign. spoti.pw gets a share.",
            @"action": @"Get a certificate",
            @"dismiss": @"Not now",
            @"url": @"https://spoti.pw/go/cert",
            @"color": @"#257BFE",
        };
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGShowCertificateSheet(offer, logo); });
    }
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(Delegate.class));
    }
}
