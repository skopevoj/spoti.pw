#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGRAccent.h"
#import "SGRAppearance.h"

// Going back to Spotify's green is offered only once a colour of the mod's is set, so a stray tap
// cannot wipe it.
static void chooseAccent(void) {
    if (!SGRAccentColor()) {
        SGRPickAccent();
        return;
    }
    UIViewController *top = SGTopController();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Accent colour" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Pick a colour" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRPickAccent(); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Spotify's green" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { SGSetInt(SGRKeyAccent, -1); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = top.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 0, 0);
    sheet.popoverPresentationController.permittedArrowDirections = 0;
    [top presentViewController:sheet animated:YES completion:nil];
}

// The choice page pops itself after its callback, so wait for that navigation transition before
// presenting. Presenting on the outgoing page can silently lose the restart sheet.
static void offerAppearanceRestart(void) {
    UINavigationController *nav = SGTopController().navigationController;
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^show)(void) = ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Apply appearance"
                message:@"Spotify needs to close to apply the complete theme. Open it again after closing. Your music and settings are kept."
                preferredStyle:UIAlertControllerStyleAlert];
            alert.overrideUserInterfaceStyle = SGRedesignAppearanceStyle();
            [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Close Spotify" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
            [SGTopController() presentViewController:alert animated:YES completion:nil];
        };
        id<UIViewControllerTransitionCoordinator> transition = nav.transitionCoordinator;
        if (!transition || ![transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { show(); }]) show();
    });
}

// Change both native stores at launch, before cached colors or redesigned panes are constructed.
NSArray<SGModRow *> *SGRAppearanceRows(void) {
    SGModRow *appearance = SGChoiceRow(@"Color appearance", @"Choose a theme, then close and reopen Spotify", SGRKeyAppearance,
        @[@"Dark", @"Light", @"System (at launch)"], SGRAppearanceSystem);
    appearance.choiceNotes = @[@"Deep black backgrounds and light text.", @"Light backgrounds and dark text.", @"Use the phone's appearance when Spotify starts. System changes take effect next launch."];
    appearance.choiceFooter = @"The app offers to close after a change so Spotify's native screens and the redesign apply the same complete theme. System is the default when no choice has been saved.";
    appearance.chosen = ^(NSInteger index) { if (SGRAppearanceNeedsRestart()) offerAppearanceRestart(); };
    SGModRow *active = SGStatRow(@"Active appearance", ^NSString *{
        NSString *status = SGRAppearanceStatus();
        return SGRAppearanceNeedsRestart() ? [status stringByAppendingString:@" · pending"] : status;
    });
    active.subtitle = @"New choices apply after reopening";
    return @[
        SGWithSymbol(appearance, @"circle.lefthalf.filled"),
        SGWithSymbol(active, @"checkmark.circle"),
        SGWithSymbol(SGStatActionRow(@"Accent colour", nil, ^NSString *{ return SGRAccentLabel(); }, ^{ chooseAccent(); }), @"paintpalette"),
    ];
}
