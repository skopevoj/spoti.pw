// The one thing the mod says for itself, unasked: a release newer than this build is out. Nobody
// opens Mod Settings to look, so the check runs on its own a few seconds after Spotify comes up and
// a release nobody has been told about brings a sheet -- once per release, and never over the
// welcome tour, the signing fix or anything else holding the screen, which it waits out. Tell me
// when one is out on the Updates page switches it off; the page and the row are still there.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"

static NSString *const kTold = @"spotifyglass.update.told";
static const NSTimeInterval kSettle = 6;   // after the app comes up, for its own screens to land
static const NSTimeInterval kRetry = 4;
static const NSInteger kTries = 15;        // a minute of waiting for the screen, then not this run

static BOOL sg_offered;   // once a run, whatever else happens

BOOL SGUpdateNoticeShown(void) {
    return sg_offered;
}

// Everything that has changed since this build, newest release first, which is what the sheet counts
// and reads the first lines of.
static NSArray<SGUpdateChange *> *changesSinceThisBuild(void) {
    NSMutableArray<SGUpdateChange *> *changes = [NSMutableArray array];
    for (SGUpdateRelease *release in SGUpdateReleases()) {
        if (!SGUpdateIsNewer(release.version)) break;
        [changes addObjectsFromArray:release.changes];
    }
    return changes;
}

// Three lines and a count: enough to know whether to care, with the whole changelog a tap away.
static NSString *noticeBody(NSString *version) {
    NSArray<SGUpdateChange *> *changes = changesSinceThisBuild();
    NSMutableString *body = [NSMutableString stringWithFormat:@"This build is %s.", SG_VERSION];
    NSUInteger shown = MIN(changes.count, (NSUInteger)3);
    for (NSUInteger i = 0; i < shown; i++) [body appendFormat:@"\n\n• %@", changes[i].text];
    if (changes.count > shown) [body appendFormat:@"\n\nand %lu more in %@.", (unsigned long)(changes.count - shown), version];
    return body;
}

static void offerWhenClear(NSInteger tries) {
    if (sg_offered) return;
    NSString *version = SGUpdateVersion();
    if (!version || !SGEnabled(SGKeyUpdateNotice)) return;
    if ([[NSUserDefaults.standardUserDefaults stringForKey:kTold] isEqualToString:version]) return;
    UIViewController *top = SGTopController();
    // The tour, the signing sheet and Spotify's own alerts own the screen first; a sheet presented
    // from one of them lands nowhere, so this one waits its turn and gives up rather than nagging.
    if (!top || SGOnboardingShowing() || [top isKindOfClass:UIAlertController.class]) {
        if (tries <= 0) {
            SGLog(@"update notice: the screen stayed busy, %@ waits for Mod Settings", version);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            offerWhenClear(tries - 1);
        });
        return;
    }

    sg_offered = YES;
    // Told before it is read, not after: a sheet dismissed by a tap outside it, or by Spotify going
    // away under it, is still a sheet this release has had.
    [NSUserDefaults.standardUserDefaults setObject:version forKey:kTold];
    SGUpdateRelease *release = SGUpdateNewestRelease();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ is out", version]
                                                                  message:noticeBody(version)
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"What's new" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // The sheet is still going as this runs, so the page waits for the screen it is pushed onto.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGShowPage(SGTopController(), SGUpdatePage());
        });
    }]];
    if (release.url.length)
        [sheet addAction:[UIAlertAction actionWithTitle:@"Get it" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            SGOpenURL(release.url);
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Not now" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:sheet animated:YES completion:nil];
    SGLog(@"update notice: offered %@ over %@", version, NSStringFromClass(top.class));
}

void SGWatchForUpdates(void) {
    // Every time Spotify comes to the front, not only the first: it lives for days behind other apps,
    // and the day's usage count has to go out on a day it was merely brought back. The sheet is still
    // once per launch.
    static BOOL launched;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        BOOL first = !launched;
        launched = YES;
        if (!first && !SGUsageOwed()) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BOOL tell = first && SGEnabled(SGKeyUpdateNotice);
            if (tell && SGUpdateVersion()) {   // the last check knows one already
                offerWhenClear(kTries);
            } else if (tell) {
                __block id landed = [NSNotificationCenter.defaultCenter addObserverForName:SGUpdateCheckedNotification
                                                                                    object:nil
                                                                                     queue:NSOperationQueue.mainQueue
                                                                                usingBlock:^(NSNotification *n) {
                    [NSNotificationCenter.defaultCenter removeObserver:landed];
                    offerWhenClear(kTries);
                }];
            }
            // Inside the six hours this does nothing and no check lands, which is the point: the
            // sheet is for a release that turned up, not for every launch. The day's usage count is
            // the exception, and it goes out whether or not the sheet is wanted.
            if (tell || SGUsageOwed()) SGCheckForUpdate(NO);
        });
    }];
}
