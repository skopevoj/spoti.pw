// The Audio effects page (Shared/AudioEffects) in a navigation controller, the way Mod Settings pushes it,
// with the real Settings/ framework and AudioEffectsSettings.m behind it and stubs.m standing in for the engine.
// The launch line sets the page up and then plays actions, one every 0.7 s from 1 s in; screenshot after.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/AudioEffectsPageHarness.app
//     xcrun simctl launch <udid> com.vojta.audioeffectspageharness [setup...] [action...]
//
// Setup: keep (the stored settings stay; otherwise every spotifyglass.dsp key is cleared first), master
// (the effects on), allon (every effect on), broken (Liveprog's script is one that does not compile), slow
// (animations at a twentieth of their speed).
// Actions: scroll=<y>, section=<n> (that card at the top), toggle=<n> (flips card n's switch the way a tap
// does), drag=<band>:<gain> (the equalizer's band mid-drag, the bubble up), release (lets it go),
// preset=<i>, reset=eq, select=<section>.<row> (a tap on a row of the page on top), push=convolver|ddc|
// liveprog|geq, import=<name> (a file of that name picked in the document picker), paste=<text> (the
// GraphicEQ editor's Paste with that on the clipboard), slide=<section>.<row>:<value> (a slider dragged
// there), swipe=<section>.<row>:<n> and band=<band>:<n> (VoiceOver's swipe on a slider or an equalizer band,
// n times), string=<key after spotifyglass.dsp.>:<text> (stored behind the page's back, as the engine's
// errors turn up), pop, delete=<row> (the library's swipe to delete on that file), hit (which band a finger
// takes around each handle, to the log), confirm (the alert's destructive button), dump (the stored dsp keys and the first sections' frames to the log).
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Shared/AudioEffects/AudioEffects.h"
#import "Shared/AudioEffects/AudioEffectsPage.h"
#import "Shared/AudioEffects/SGDSPCurveView.h"
#import "Settings/SGModPage.h"

@interface SGDSPCurveView (Harness)
- (void)setBand:(NSInteger)band to:(double)value;
- (void)showBubbleFor:(NSInteger)band;
- (void)highlight:(NSInteger)band on:(BOOL)on;
- (void)refreshBar;
- (void)setGains:(NSArray<NSNumber *> *)gains animated:(BOOL)animated;
- (void)resetTapped;
- (NSInteger)bandAt:(CGPoint)point;
- (CGFloat)xFor:(double)hz;
- (CGFloat)yFor:(double)value;
@end

static NSArray<NSString *> *effectKeys(void) {
    return @[SGKeyDSPCompander, SGKeyDSPBass, SGKeyDSPEqualizer, SGKeyDSPGraphicEq, SGKeyDSPConvolver, SGKeyDSPDDC,
             SGKeyDSPLiveprog, SGKeyDSPReverb, SGKeyDSPStereoWide, SGKeyDSPCrossfeed, SGKeyDSPTube];
}

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@property (nonatomic) NSInteger draggedBand;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (![args containsObject:@"keep"]) {
        for (NSString *key in store.dictionaryRepresentation.allKeys) {
            if ([key hasPrefix:@"spotifyglass.dsp"]) [store removeObjectForKey:key];
        }
    }
    if ([args containsObject:@"master"]) SGDSPSetSwitch(SGKeyDSP, YES);
    if ([args containsObject:@"allon"]) for (NSString *key in effectKeys()) SGDSPSetSwitch(key, YES);
    if ([args containsObject:@"broken"]) SGDSPSetString(SGKeyDSPLiveprogFile, @"Tape saturation broken.eel");

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.nav = [[UINavigationController alloc] initWithRootViewController:SGDSPSettingsPage()];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    // Animations at a twentieth of their speed, to be caught halfway in a screenshot.
    if ([args containsObject:@"slow"]) self.window.layer.speed = 0.05;
    self.draggedBand = -1;

    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (NSString *arg in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        if (![@[@"keep", @"master", @"allon", @"broken", @"slow"] containsObject:arg]) [actions addObject:arg];
    }
    [actions enumerateObjectsUsingBlock:^(NSString *action, NSUInteger i, BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 0.7 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@", action);
            [self run:action];
        });
    }];
    return YES;
}

- (UITableView *)table {
    return ((UITableViewController *)self.nav.topViewController).tableView;
}

- (SGDSPCurveView *)curve {
    NSMutableArray<SGDSPCurveView *> *curves = [NSMutableArray array];
    findViews(self.table, SGDSPCurveView.class, curves);
    // The equalizer's has the presets, so it has the one more button.
    for (SGDSPCurveView *curve in curves) {
        NSMutableArray *buttons = [NSMutableArray array];
        findViews(curve, UIButton.class, buttons);
        if (buttons.count == 2) return curve;
    }
    return curves.firstObject;
}

// An SGModPage laid out like the Player page, to hold the Audio effects page up against.
- (UIViewController *)referencePage {
    SGModRow *blocked = SGPageRow(@"Blocked artists", ^UIViewController *{ return nil; });
    blocked.value = ^NSString *{ return @"Off"; };
    return [[SGModPage alloc] initWithTitle:@"Player" intro:@"Changes apply after you restart Spotify. Gestures and Blocked artists apply straight away." sections:@[
        SGSection(nil, @[SGWithSymbol(SGPageRow(@"Gestures", ^UIViewController *{ return nil; }), @"hand.tap"), SGWithSymbol(blocked, @"person.crop.circle.badge.xmark")]),
        SGSection(@"Vibrations", @[SGWithSymbol(SGSwitchRow(@"Controls", @"Play, pause, skipping, scrubbing, shuffle, repeat and adding a song", @"spotifyglass.x"), @"hand.tap"),
                                   SGWithSymbol(SGOptionRow(@"Music Haptics", @"Taps and rumbles along with the music", @"spotifyglass.y"), @"waveform")]),
        SGSection(nil, @[SGChoiceRow(@"Shows", nil, @"spotifyglass.z", @[@"Lyrics", @"Queue"], 0)]),
    ] footer:nil];
}

- (void)run:(NSString *)action {
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@"="];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    UITableView *table = self.table;
    if ([verb isEqualToString:@"scroll"]) {
        CGFloat max = MAX(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom);
        [table setContentOffset:CGPointMake(0, MIN(value.doubleValue - table.adjustedContentInset.top, max)) animated:NO];
    } else if ([verb isEqualToString:@"section"]) {
        CGRect rect = [table rectForSection:value.integerValue];
        CGFloat max = table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom;
        [table setContentOffset:CGPointMake(0, MIN(rect.origin.y - table.adjustedContentInset.top, max)) animated:NO];
    } else if ([verb isEqualToString:@"toggle"]) {
        UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:value.integerValue]];
        UISwitch *toggle = (UISwitch *)cell.accessoryView;
        [toggle setOn:!toggle.on animated:YES];
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    } else if ([verb isEqualToString:@"drag"]) {
        NSArray<NSString *> *bandGain = [value componentsSeparatedByString:@":"];
        SGDSPCurveView *curve = [self curve];
        self.draggedBand = bandGain[0].integerValue;
        [curve highlight:self.draggedBand on:YES];
        // A few steps on the way, the way a finger gets there.
        double target = bandGain[1].doubleValue;
        for (int step = 1; step <= 5; step++) [curve setBand:self.draggedBand to:round(target * step / 5 * 10) / 10];
        [curve showBubbleFor:self.draggedBand];
    } else if ([verb isEqualToString:@"release"]) {
        SGDSPCurveView *curve = [self curve];
        [curve highlight:self.draggedBand on:NO];
        [curve refreshBar];
    } else if ([verb isEqualToString:@"preset"]) {
        [[self curve] setGains:SGDSPEqualizerPreset(value.integerValue) animated:YES];
    } else if ([verb isEqualToString:@"reset"]) {
        [[self curve] resetTapped];
    } else if ([verb isEqualToString:@"select"]) {
        NSArray<NSString *> *at = [value componentsSeparatedByString:@"."];
        NSIndexPath *path = [NSIndexPath indexPathForRow:at[1].integerValue inSection:at[0].integerValue];
        [table.delegate tableView:table didSelectRowAtIndexPath:path];
    } else if ([verb isEqualToString:@"push"]) {
        NSDictionary<NSString *, NSNumber *> *kinds = @{@"convolver": @(SGDSPFileImpulseResponse), @"ddc": @(SGDSPFileDDC), @"liveprog": @(SGDSPFileLiveprog)};
        UIViewController *page = kinds[value] ? SGDSPLibraryPage(kinds[value].integerValue)
                               : [value isEqualToString:@"reference"] ? [self referencePage] : SGDSPGraphicEqPage();
        [self.nav pushViewController:page animated:NO];
    } else if ([verb isEqualToString:@"import"]) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:value];
        [@"imported" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        id<UIDocumentPickerDelegate> page = (id<UIDocumentPickerDelegate>)self.nav.topViewController;
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
        [page documentPicker:picker didPickDocumentsAtURLs:@[[NSURL fileURLWithPath:path]]];
    } else if ([verb isEqualToString:@"paste"]) {
        UIPasteboard.generalPasteboard.string = value;
        [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
    } else if ([verb isEqualToString:@"slide"] || [verb isEqualToString:@"swipe"]) {
        // slide=S.R:value drags row R of card S's slider there; swipe=S.R:n is VoiceOver's swipe up, n times.
        NSArray<NSString *> *at = [value componentsSeparatedByString:@":"];
        NSArray<NSString *> *path = [at[0] componentsSeparatedByString:@"."];
        UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:path[1].integerValue inSection:path[0].integerValue]];
        NSMutableArray<UISlider *> *sliders = [NSMutableArray array];
        findViews(cell, UISlider.class, sliders);
        UISlider *slider = sliders.firstObject;
        if ([verb isEqualToString:@"swipe"]) {
            for (NSInteger i = 0; i < at[1].integerValue; i++) [slider accessibilityIncrement];
        } else {
            slider.value = at[1].floatValue;
            [slider sendActionsForControlEvents:UIControlEventValueChanged];
            [slider sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        NSLog(@"[harness] slider %@ reads %@", slider.accessibilityLabel, slider.accessibilityValue);
    } else if ([verb isEqualToString:@"band"]) {
        // band=B:n is VoiceOver's swipe on the equalizer's band B, up n times (down for a negative n).
        NSArray<NSString *> *at = [value componentsSeparatedByString:@":"];
        SGDSPCurveView *curve = [self curve];
        NSArray *elements = curve.accessibilityElements;
        UIAccessibilityElement *band = elements[2 + at[0].integerValue];
        for (NSInteger i = 0; i < labs(at[1].integerValue); i++) {
            if (at[1].integerValue > 0) [band accessibilityIncrement];
            else [band accessibilityDecrement];
        }
        NSLog(@"[harness] band %@ reads %@", band.accessibilityLabel, band.accessibilityValue);
    } else if ([verb isEqualToString:@"string"]) {
        // string=<key suffix>:<text>, stored behind the page's back the way the engine's own changes land.
        NSRange colon = [value rangeOfString:@":"];
        SGDSPSetString([@"spotifyglass.dsp." stringByAppendingString:[value substringToIndex:colon.location]], [value substringFromIndex:colon.location + 1]);
    } else if ([verb isEqualToString:@"confirm"]) {
        // confirm: the destructive button of the alert on screen, pressed.
        UIAlertController *alert = (UIAlertController *)self.nav.topViewController.presentedViewController;
        for (UIAlertAction *action in alert.actions) {
            if (action.style != UIAlertActionStyleDestructive) continue;
            void (^handler)(UIAlertAction *) = [action valueForKey:@"handler"];
            [alert dismissViewControllerAnimated:NO completion:^{ handler(action); }];
        }
    } else if ([verb isEqualToString:@"pop"]) {
        [self.nav popViewControllerAnimated:NO];
    } else if ([verb isEqualToString:@"delete"]) {
        // delete=<row>: the library's swipe action on that file, run as a swipe and a tap on Delete would.
        NSIndexPath *path = [NSIndexPath indexPathForRow:value.integerValue inSection:1];
        UISwipeActionsConfiguration *swipe = [(id<UITableViewDelegate>)table.delegate tableView:table trailingSwipeActionsConfigurationForRowAtIndexPath:path];
        UIContextualAction *action = swipe.actions.firstObject;
        action.handler(action, [table cellForRowAtIndexPath:path], ^(BOOL done) { NSLog(@"[harness] swipe action done %d", done); });
    } else if ([verb isEqualToString:@"hit"]) {
        // hit: which band a finger going down takes, on each handle, beside it, between two and far off.
        SGDSPCurveView *curve = [self curve];
        NSArray<NSNumber *> *gains = SGDSPGains(SGKeyDSPEqualizerGains);
        for (NSInteger band = 0; band < 15; band++) {
            CGFloat x = [curve xFor:SGDSPEqualizerFrequencies[band]], y = [curve yFor:gains[band].doubleValue];
            NSLog(@"[harness] band %ld: on %ld, 20pt above %ld, 40pt above %ld, halfway to the next %ld",
                  (long)band, (long)[curve bandAt:CGPointMake(x, y)], (long)[curve bandAt:CGPointMake(x, y - 20)],
                  (long)[curve bandAt:CGPointMake(x, y - 40)], (long)[curve bandAt:CGPointMake(x + 9, y)]);
        }
    } else if ([verb isEqualToString:@"dump"]) {
        NSDictionary *all = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
        for (NSString *key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if ([key hasPrefix:@"spotifyglass.dsp"]) NSLog(@"[harness] %@ = %@", key, all[key]);
        }
        NSLog(@"[harness] summary: %@; on top %@ with %ld sections", SGDSPSummary(), self.nav.topViewController.class,
              (long)table.numberOfSections);
        for (NSInteger section = 0; section < MIN(3, table.numberOfSections); section++) {
            NSLog(@"[harness] section %ld header %@ rows from %@", (long)section, NSStringFromCGRect([table rectForHeaderInSection:section]),
                  NSStringFromCGRect([table rectForSection:section]));
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
