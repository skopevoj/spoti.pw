// The redesign's rows on the Player page (Redesigned/NowPlayingBar/NowPlayingBarSettings.m), the Fluid artwork page
// and Animated artwork's Sources page they open (Redesigned/Player/PlayerBackgroundSettings.m), with the preview
// drawn by the Kit's renderer. The launch line sets things up and then plays actions, one every 1.2 s from 1 s in;
// screenshot between them.
//
//     ./build.sh && xcrun simctl install <udid> build/KawarpHarness.app
//     SIMCTL_CHILD_HARNESS_COVER=<picture> xcrun simctl launch <udid> com.vojta.kawarpharness [setup...] [action...]
//
// Setup: keep (the stored player keys stay; otherwise every spotifyglass.redesign.player key is cleared first),
// old-off (the Moving background switch stored off, as an older build left it), old=<n> (the Background an older
// build stored: 0 Still artwork, 1 Colour flow, 2 Fluid artwork), style=<n> (0 Fluid artwork, 1 Animated artwork).
// Actions: select=<section>.<row> (a tap on a row of the page on top), slide=<section>.<row>:<value> (that slider
// dragged there and let go), pop, dump (the stored keys, what the player would read, and each section's rows).
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Player/Player.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (![args containsObject:@"keep"]) {
        for (NSString *key in store.dictionaryRepresentation.allKeys) {
            if ([key hasPrefix:@"spotifyglass.redesign.player"]) [store removeObjectForKey:key];
        }
    }
    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (NSString *arg in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        if ([arg isEqualToString:@"old-off"]) [store setBool:NO forKey:SGRKeyPlayerMotionWas];
        else if ([arg hasPrefix:@"old="]) [store setInteger:[arg substringFromIndex:4].integerValue forKey:SGRKeyPlayerBackgroundWas];
        else if ([arg hasPrefix:@"style="]) SGSetInt(SGRKeyPlayerBackground, [arg substringFromIndex:6].integerValue);
        else if (![arg isEqualToString:@"keep"]) [actions addObject:arg];
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIViewController *page = [[SGModPage alloc] initWithTitle:@"Player" intro:SGRestartNote sections:SGRNowPlayingSections() footer:nil];
    self.nav = [[UINavigationController alloc] initWithRootViewController:page];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];

    [actions enumerateObjectsUsingBlock:^(NSString *action, NSUInteger i, BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 1.2 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@", action);
            [self run:action];
        });
    }];
    return YES;
}

- (UITableView *)table {
    return ((UITableViewController *)self.nav.topViewController).tableView;
}

- (NSIndexPath *)pathFrom:(NSString *)text {
    NSArray<NSString *> *at = [text componentsSeparatedByString:@"."];
    return [NSIndexPath indexPathForRow:at[1].integerValue inSection:at[0].integerValue];
}

- (void)run:(NSString *)action {
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@"="];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    UITableView *table = self.table;
    if ([verb isEqualToString:@"select"]) {
        [table.delegate tableView:table didSelectRowAtIndexPath:[self pathFrom:value]];
    } else if ([verb isEqualToString:@"slide"]) {
        NSArray<NSString *> *at = [value componentsSeparatedByString:@":"];
        NSIndexPath *path = [self pathFrom:at[0]];
        [table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionNone animated:NO];
        UITableViewCell *cell = [table cellForRowAtIndexPath:path];
        NSMutableArray<UISlider *> *sliders = [NSMutableArray array];
        findViews(cell, UISlider.class, sliders);
        UISlider *slider = sliders.firstObject;
        float from = slider.value, to = at[1].floatValue;
        for (int step = 1; step <= 4; step++) {
            slider.value = from + (to - from) * step / 4;
            [slider sendActionsForControlEvents:UIControlEventValueChanged];
        }
        [slider sendActionsForControlEvents:UIControlEventTouchUpInside];
        NSLog(@"[harness] slider %@ reads %@", slider.accessibilityLabel, slider.accessibilityValue);
    } else if ([verb isEqualToString:@"pop"]) {
        [self.nav popViewControllerAnimated:YES];
    } else if ([verb isEqualToString:@"dump"]) {
        NSDictionary *all = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
        for (NSString *key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if ([key hasPrefix:@"spotifyglass.redesign.player"]) NSLog(@"[harness] stored %@ = %@", key, all[key]);
        }
        SGRWarpLook look = SGRPlayerFluidLook();
        NSLog(@"[harness] the player reads: background %ld, speed %.2f warp %.2f blur %.0f saturation %.2f brightness %.2f, sources %@ "
              "(the lock screen's %@)", (long)SGRPlayerBackgroundStyle(), look.speed, look.warp, look.blur, look.saturation, look.brightness,
              [SGArtworkOrderFor(SGRKeyPlayerArtworkSources) componentsJoinedByString:@", "],
              [SGArtworkOrderFor(SGKeyLockScreenArtworkSources) componentsJoinedByString:@", "]);
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
                NSString *title = [(UIListContentConfiguration *)cell.contentConfiguration text];
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                findViews(cell.accessoryView ?: cell.contentView, UILabel.class, labels);
                [rows addObject:[NSString stringWithFormat:@"%@ [%@]", title ?: @"?", labels.firstObject.text ?: @""]];
            }
            NSLog(@"[harness] section %ld: %@", (long)section, [rows componentsJoinedByString:@", "]);
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeyRedesign];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
