// The What's new sheet: the first launch after an update lists what this version brought, read from its
// release on GitHub (Update.m keeps the list), and the Mod page opens it again. A fresh install has the
// welcome tour instead and is only marked as having seen it. A build with no release of its own (one built
// between releases) shows nothing, and is not asked about again.
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"

static NSString *const kSeen = @"spotifyglass.whatsNew.seen";
static const NSUInteger kLines = 6;

static SGUpdateRelease *thisRelease(void) {
    NSString *version = @(SG_VERSION);
    for (SGUpdateRelease *release in SGUpdateReleases()) {
        if ([release.version isEqualToString:version]) return release;
    }
    return nil;
}

static void present(SGUpdateRelease *release) {
    NSMutableString *body = [NSMutableString string];
    NSUInteger shown = MIN(release.changes.count, kLines);
    for (NSUInteger i = 0; i < shown; i++) [body appendFormat:@"%@• %@", i ? @"\n\n" : @"", release.changes[i].text];
    if (release.changes.count > shown) [body appendFormat:@"\n\nand %lu more.", (unsigned long)(release.changes.count - shown)];
    if (!release.changes.count) [body appendString:@"Fixes and polish."];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"What's new in %@", release.version]
                                                                  message:body preferredStyle:UIAlertControllerStyleAlert];
    sheet.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if (release.changes.count > shown) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"See everything" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SGShowPage(SGTopController(), SGUpdatePage());
            });
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:sheet animated:YES completion:nil];
}

void SGShowWhatsNew(void) {
    SGUpdateRelease *release = thisRelease();
    if (release) {
        present(release);
        return;
    }
    __block id landed = [NSNotificationCenter.defaultCenter addObserverForName:SGUpdateCheckedNotification object:nil
                                                                         queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:landed];
        SGUpdateRelease *found = thisRelease();
        if (found) {
            present(found);
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"What's new" message:[NSString stringWithFormat:
            @"There are no release notes for %s, a build made between releases.", SG_VERSION] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    }];
    SGCheckForUpdate(YES);
}

// Once, on the first launch of a version; called a few seconds after Spotify comes up (UpdateNotice.m).
void SGWhatsNewAtLaunch(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSString *seen = [store stringForKey:kSeen], *version = @(SG_VERSION);
    if ([seen isEqualToString:version]) return;
    [store setObject:version forKey:kSeen];
    if (!seen || SGOnboardingShowing()) return;   // a fresh install gets the tour
    void (^show)(void) = ^{
        SGUpdateRelease *release = thisRelease();
        if (release && !SGOnboardingShowing()) present(release);
    };
    if (thisRelease()) {
        show();
        return;
    }
    __block id landed = [NSNotificationCenter.defaultCenter addObserverForName:SGUpdateCheckedNotification object:nil
                                                                         queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:landed];
        show();
    }];
    SGCheckForUpdate(YES);
}
