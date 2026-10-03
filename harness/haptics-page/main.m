// Mod Settings > Player's Vibrations cards (Shared/Haptics/HapticsSettings.m) on an SGModPage laid out like the
// Player page in the redesign, with the real Settings/ framework and SGFeedback.m behind them and stubs.m for
// Music Haptics' engine. The launch line sets the switches up and then plays actions, one every 0.7 s from 1 s
// in; screenshot after.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/HapticsPageHarness.app
//     xcrun simctl launch <udid> com.vojta.hapticspageharness [setup...] [action...]
//
// Setup: keep (the stored settings stay; otherwise every spotifyglass.redesign.haptics key is cleared first),
// system (native mode available), native (native selected), controls-off, music (generated selected),
// follows=<n>, slow (animations at a twentieth
// of their speed).
// Actions: toggle=<section>.<row> (that row's switch flipped the way a tap does), slide=<section>.<row>:<value>
// menu=<section>.<row>:<index> (choose a dropdown's actual UIAction), check=none|native|generated,
// (that slider dragged there and let go), swipe=<section>.<row>:<n> (VoiceOver's swipe up on it, n times, down
// for a negative n), info=<section>.<row> (a tap on its ⓘ), select=<section>.<row> (a tap on a row of the page
// on top), pop, bottom (scrolled to the end), dump (the stored haptics keys, what the hooks would read, and the
// rows each section shows, to the log).
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Haptics/SystemMusicHaptics.h"

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

@interface AppDelegate : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation AppDelegate

// The Player page as App/Pages.m builds it in the redesign, its links standing in for the pages they open.
- (UIViewController *)playerPage {
    UIViewController *(^none)(void) = ^UIViewController *{ return nil; };
    SGModRow *blocked = SGPageRow(@"Blocked artists", none);
    blocked.value = ^NSString *{ return @"Off"; };
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithArray:@[
        SGSection(nil, @[SGWithSymbol(SGPageRow(@"Gestures", none), @"hand.tap"), SGWithSymbol(SGPageRow(@"Lyrics", none), @"quote.bubble"),
                         SGWithSymbol(blocked, @"person.crop.circle.badge.xmark")]),
        SGSection(nil, @[SGWithSymbol(SGPageRow(@"Now playing", none), @"rectangle.bottomthird.inset.filled"),
                         SGWithSymbol(SGPageRow(@"Lock screen widget", none), @"lock")]),
    ]];
    [sections addObjectsFromArray:SGVibrationsSections()];
    return [[SGModPage alloc] initWithTitle:@"Player" intro:@"Changes apply after you restart Spotify. Gestures, Blocked artists and Vibrations apply straight away."
                                   sections:sections footer:nil];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    return YES;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (![args containsObject:@"keep"]) {
        for (NSString *key in store.dictionaryRepresentation.allKeys) {
            if ([key hasPrefix:@"spotifyglass.redesign.haptics"] || [key hasPrefix:@"spotifyglass.haptics"]) [store removeObjectForKey:key];
        }
    }
    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (NSString *arg in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        if ([arg isEqualToString:@"controls-off"]) SGSetEnabled(SGKeyControlHaptics, NO);
        else if ([arg isEqualToString:@"music"]) SGSetEnabled(SGKeyMusicHaptics, YES);
        else if ([arg isEqualToString:@"native"]) SGSetEnabled(SGKeySystemMusicHaptics, YES);
        else if ([arg hasPrefix:@"follows="]) SGSetInt(SGKeyMusicFollows, [arg substringFromIndex:8].integerValue);
        else if (![@[@"keep", @"slow", @"system"] containsObject:arg]) [actions addObject:arg];
    }

    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.nav = [[UINavigationController alloc] initWithRootViewController:[self playerPage]];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    if ([args containsObject:@"slow"]) self.window.layer.speed = 0.05;

    [actions enumerateObjectsUsingBlock:^(NSString *action, NSUInteger i, BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 0.7 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@", action);
            [self run:action];
        });
    }];
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
    if ([verb isEqualToString:@"toggle"]) {
        UITableViewCell *cell = [table cellForRowAtIndexPath:[self pathFrom:value]];
        NSMutableArray<UISwitch *> *switches = [NSMutableArray array];
        findViews(cell, UISwitch.class, switches);
        UISwitch *toggle = switches.firstObject;
        [toggle setOn:!toggle.on animated:YES];
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    } else if ([verb isEqualToString:@"menu"] || [verb isEqualToString:@"openmenu"]) {
        NSArray<NSString *> *at = [value componentsSeparatedByString:@":"];
        UITableViewCell *cell = [table cellForRowAtIndexPath:[self pathFrom:at[0]]];
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        findViews(cell, UIButton.class, buttons);
        UIButton *menu = nil;
        for (UIButton *button in buttons) if (button.menu) menu = button;
        NSCAssert(menu, @"Dropdown must exist");
        if ([verb isEqualToString:@"openmenu"]) {
            if (@available(iOS 17.4, *)) [menu performPrimaryAction];
            return;
        }
        UIAction *choice = (UIAction *)menu.menu.children[at[1].integerValue];
        [menu sendAction:choice];
    } else if ([verb isEqualToString:@"check"]) {
        BOOL native = [value isEqualToString:@"native"], generated = [value isEqualToString:@"generated"];
        NSCAssert(SGFlag(SGKeySystemMusicHaptics, NO) == native, @"Native preference must match selected mode");
        NSCAssert(SGFlag(SGKeyMusicHaptics, NO) == generated, @"Generated preference must match selected mode");
        NSCAssert([table numberOfRowsInSection:3] == (native ? 2 : generated ? 3 : 1), @"Only selected mode's settings must be visible");
        NSLog(@"[harness] PASS: %@ preferences and visible rows", value);
    } else if ([verb isEqualToString:@"slide"] || [verb isEqualToString:@"swipe"]) {
        NSArray<NSString *> *at = [value componentsSeparatedByString:@":"];
        UITableViewCell *cell = [table cellForRowAtIndexPath:[self pathFrom:at[0]]];
        NSMutableArray<UISlider *> *sliders = [NSMutableArray array];
        findViews(cell, UISlider.class, sliders);
        UISlider *slider = sliders.firstObject;
        if ([verb isEqualToString:@"swipe"]) {
            NSInteger n = at[1].integerValue;
            for (NSInteger i = 0; i < labs(n); i++) {
                if (n > 0) [slider accessibilityIncrement];
                else [slider accessibilityDecrement];
            }
        } else {
            // A drag: a few values on the way, off the steps, then let go.
            float from = slider.value, to = at[1].floatValue;
            for (int step = 1; step <= 4; step++) {
                slider.value = from + (to - from) * step / 4 + (step < 4 ? 1.3f : 0);
                [slider sendActionsForControlEvents:UIControlEventValueChanged];
            }
            [slider sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        NSLog(@"[harness] slider %@ reads %@ (thumb at %.1f)", slider.accessibilityLabel, slider.accessibilityValue, slider.value);
    } else if ([verb isEqualToString:@"info"]) {
        UITableViewCell *cell = [table cellForRowAtIndexPath:[self pathFrom:value]];
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        findViews(cell, UIButton.class, buttons);
        [buttons.firstObject sendActionsForControlEvents:UIControlEventTouchUpInside];
        UIAlertController *alert = (UIAlertController *)self.nav.topViewController.presentedViewController;
        NSLog(@"[harness] the ⓘ shows \"%@\": %@", alert.title, [alert.message substringToIndex:MIN(60, alert.message.length)]);
    } else if ([verb isEqualToString:@"select"]) {
        [table.delegate tableView:table didSelectRowAtIndexPath:[self pathFrom:value]];
    } else if ([verb isEqualToString:@"pop"]) {
        [self.nav popViewControllerAnimated:YES];
    } else if ([verb isEqualToString:@"bottom"]) {
        CGFloat max = MAX(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom);
        [table setContentOffset:CGPointMake(0, max) animated:NO];
    } else if ([verb isEqualToString:@"dump"]) {
        NSDictionary *all = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
        for (NSString *key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if ([key hasPrefix:@"spotifyglass.redesign.haptics"] || [key hasPrefix:@"spotifyglass.haptics"]) NSLog(@"[harness] stored %@ = %@", key, all[key]);
        }
        NSLog(@"[harness] the hooks read: Controls %@ at %.0f%%, Music Haptics %@ at %.0f%% following %ld", SGEnabled(SGKeyControlHaptics) ? @"on" : @"off",
              SGHapticsStrength(SGKeyControlStrength) * 100, SGFlag(SGKeyMusicHaptics, NO) ? @"on" : @"off",
              SGHapticsStrength(SGKeyMusicStrength) * 100, (long)SGMusicHapticsFollows());
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
                NSString *title = [(UIListContentConfiguration *)cell.contentConfiguration text];
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                if (!title) findViews(cell.contentView, UILabel.class, labels);
                [rows addObject:[NSString stringWithFormat:@"%@ (%.0fpt)", title ?: labels.firstObject.text ?: @"?", [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]].size.height]];
            }
            NSLog(@"[harness] section %ld: %@", (long)section, [rows componentsJoinedByString:@", "]);
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // The redesign's look: black, the redesign's own accent.
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeyRedesign];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
