// The Animated lock screen rows, put on the Lock screen widget page by Shared/Player/PlayerSettings.m, and
// the Sources row for an order of these sources (the redesigned player keeps one of its own).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGOrderPage.h"
#import "Settings/SGPageStyle.h"
#import "LockScreenArtwork.h"

static void sayWhatIsMissing(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Animated lock screen"
        message:[NSString stringWithFormat:@"Animated artwork is the lock screen's own, and iOS takes one only from 26 on. This phone runs iOS %@, where the cover stays still.", UIDevice.currentDevice.systemVersion]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static NSArray<SGOrderItem *> *sources(void) {
    return @[
        SGOrderItemMake(SGArtworkSourceSpotify, @"Spotify Canvas", @"The track's own clip"),
        SGOrderItemMake(SGArtworkSourceApple, @"Apple Music", @"The album's animated cover"),
    ];
}

SGModRow *SGArtworkSourcesRow(NSString *key, NSString *note) {
    SGModRow *row = SGPageRow(@"Sources", ^UIViewController *{
        return SGOrderPage(@"Artwork sources", sources(), ^NSArray<NSString *> *{ return SGArtworkOrderFor(key); },
                           ^(NSArray<NSString *> *keys) { SGArtworkSetOrderFor(key, keys); }, note);
    });
    row.value = ^NSString *{
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *source in SGArtworkOrderFor(key)) {
            for (SGOrderItem *item in sources()) {
                if ([item.key isEqualToString:source]) [names addObject:item.name];
            }
        }
        return names.count ? [names componentsJoinedByString:@", "] : @"None";
    };
    return row;
}

NSArray<SGModRow *> *SGAnimatedArtworkRows(void) {
    if (!SGAnimatedArtworkAvailable())
        return @[SGStatActionRow(@"Animated lock screen", nil, ^NSString *{ return @"Needs iOS 26"; }, ^{ sayWhatIsMissing(); })];
    SGModRow *order = SGArtworkSourcesRow(SGKeyLockScreenArtworkSources,
        @"Asked top to bottom until one has a clip. Apple Music gets only the artist and album name.");
    order.visible = ^BOOL { return SGFlag(SGKeyLockScreenArtwork, YES); };
    return @[
        SGSwitchRow(@"Animated lock screen", @"A moving cover behind the lock screen's controls", SGKeyLockScreenArtwork),
        order,
    ];
}
