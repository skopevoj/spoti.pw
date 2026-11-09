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

// The picker persists the key before this callback. One main-queue transaction applies it.
NSArray<SGModRow *> *SGRAppearanceRows(void) {
    SGModRow *appearance = SGChoiceRow(@"Color appearance", @"Change the app appearance immediately", SGRKeyAppearance,
        @[@"Dark", @"Light", @"System"], SGRAppearanceSystem);
    appearance.choiceNotes = @[@"Deep black backgrounds and light text.", @"Light backgrounds and dark text.", @"Follow the phone's appearance, including changes while Spotify is open."];
    appearance.choiceFooter = @"Changes apply without restarting or interrupting playback. System follows the phone and is the default when no choice has been saved.";
    appearance.chosen = ^(NSInteger index) { SGRAppearanceApplyPreference(); };
    SGModRow *active = SGStatRow(@"Active appearance", ^NSString *{
        NSString *status = SGRAppearanceStatus();
        return SGRAppearanceNeedsRestart() ? [status stringByAppendingString:@" · pending"] : status;
    });
    active.subtitle = @"Current applied theme";
    return @[
        SGWithSymbol(appearance, @"circle.lefthalf.filled"),
        SGWithSymbol(active, @"checkmark.circle"),
        SGWithSymbol(SGStatActionRow(@"Accent colour", nil, ^NSString *{ return SGRAccentLabel(); }, ^{ chooseAccent(); }), @"paintpalette"),
    ];
}
