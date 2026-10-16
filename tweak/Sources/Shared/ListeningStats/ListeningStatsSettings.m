// Mod Settings > Listening stats: the recorder's switch, the period, and for it the minutes, plays, top
// tracks and top artists, every period's rows made at once and shown as the period is picked. A track or
// an artist opens in Spotify when tapped.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Navigation/Links.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "ListeningStats.h"

static const NSUInteger kTop = 10;

static NSString *duration(double seconds) {
    long minutes = lround(seconds / 60);
    if (minutes < 60) return [NSString stringWithFormat:@"%ld min", minutes];
    return minutes % 60 ? [NSString stringWithFormat:@"%ld h %ld min", minutes / 60, minutes % 60]
                        : [NSString stringWithFormat:@"%ld h", minutes / 60];
}

static NSString *plays(NSInteger count) {
    return count == 1 ? @"1 play" : [NSString stringWithFormat:@"%ld plays", (long)count];
}

static NSString *number(NSInteger value) {
    return [NSNumberFormatter localizedStringFromNumber:@(value) numberStyle:NSNumberFormatterDecimalStyle];
}

static void openURI(NSString *uri) {
    NSURL *url = uri.length ? [NSURL URLWithString:uri] : nil;
    if (!url || !SGOpenSpotifyURI(url)) SGLog(@"listening stats: could not open %@", uri);
}

static SGModRow *entryRow(SGListeningEntry *entry, NSUInteger rank, BOOL track) {
    NSString *title = [NSString stringWithFormat:@"%lu. %@", (unsigned long)rank, entry.title];
    NSString *value = track ? plays(entry.plays) : duration(entry.seconds);
    NSString *uri = entry.uri;
    return SGStatActionRow(title, track ? entry.subtitle : plays(entry.plays), ^NSString *{ return value; }, ^{ openURI(uri); });
}

static NSArray<SGModSection *> *periodSections(SGListeningPeriod period) {
    SGListeningSummary *summary = SGListeningSummarize(period, kTop);
    BOOL (^shown)(void) = ^BOOL {
        return SGInt(SGKeyListeningStatsPeriod, SGListeningPeriodMonth) == period;
    };
    NSMutableArray<SGModRow *> *overview = [NSMutableArray array];
    double perDay = summary.days ? summary.seconds / summary.days : 0;
    NSArray *facts = @[
        @[@"Listening time", duration(summary.seconds)],
        @[@"Plays", number(summary.plays)],
        @[@"Tracks", number(summary.tracks)],
        @[@"Artists", number(summary.artists)],
        @[@"A day, on average", duration(perDay)],
    ];
    for (NSArray<NSString *> *fact in facts) {
        NSString *value = fact[1];
        SGModRow *row = SGStatRow(fact[0], ^NSString *{ return value; });
        row.visible = shown;
        [overview addObject:row];
    }

    NSMutableArray<SGModRow *> *tracks = [NSMutableArray array], *artists = [NSMutableArray array];
    [summary.topTracks enumerateObjectsUsingBlock:^(SGListeningEntry *entry, NSUInteger index, BOOL *stop) {
        [tracks addObject:entryRow(entry, index + 1, YES)];
    }];
    [summary.topArtists enumerateObjectsUsingBlock:^(SGListeningEntry *entry, NSUInteger index, BOOL *stop) {
        [artists addObject:entryRow(entry, index + 1, NO)];
    }];
    if (!tracks.count) [tracks addObject:SGStatRow(@"Nothing yet", ^NSString *{ return @""; })];
    for (SGModRow *row in [tracks arrayByAddingObjectsFromArray:artists]) row.visible = shown;
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObjects:
        SGSection(@"Overview", overview), SGSection(@"Top tracks", tracks), nil];
    if (artists.count) [sections addObject:SGSection(@"Top artists", artists)];
    return sections;
}

static void confirmClear(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear listening stats?"
        message:@"Everything recorded so far is removed from this iPhone." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGListeningClear();
        UINavigationController *navigation = SGTopController().navigationController;
        [navigation popViewControllerAnimated:YES];
    }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// The picker's delegate, kept for as long as the picker is up.
@interface SGListeningImporter : NSObject <UIDocumentPickerDelegate>
@end

static SGListeningImporter *sg_importer;

static void say(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

@implementation SGListeningImporter
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    sg_importer = nil;
    SGListeningImport(urls, ^(NSUInteger added, NSString *problem) {
        if (problem) say(@"Nothing imported", problem);
        else say(@"Imported", added ? [NSString stringWithFormat:@"%lu listens added. Open Listening stats again to see them.", (unsigned long)added]
                                     : @"Every listen in that was already here.");
    });
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker {
    sg_importer = nil;
}
@end

static void pickHistory(void) {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    sg_importer = [SGListeningImporter new];
    picker.delegate = sg_importer;
    picker.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

UIViewController *SGListeningStatsPage(void) {
    SGModRow *record = SGSwitchRow(@"Record listening", @"Kept only on this iPhone", SGKeyListeningStats);
    record.changed = ^(BOOL on) { SGListeningStatsApply(); };
    NSArray<SGModRow *> *periods = SGChoiceListRows(SGKeyListeningStatsPeriod, @[@"Last 4 weeks", @"Last 6 months", @"All time"],
                                                    nil, SGListeningPeriodMonth, nil);
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObjects:
        SGNotedSection(nil, @[record], @"A track counts as played once it has run 30 seconds. Nothing leaves this iPhone."),
        SGSection(@"Period", periods), nil];
    for (SGListeningPeriod period = SGListeningPeriodMonth; period <= SGListeningPeriodAllTime; period++) {
        [sections addObjectsFromArray:periodSections(period)];
    }
    SGModRow *import = SGActionRow(@"Import Spotify's history", @"The JSON files from your data download", ^{ pickHistory(); });
    SGModSection *importing = SGNotedSection(nil, @[import],
        @"Ask Spotify for your data on its account page under Privacy, then pick the StreamingHistory_music or "
         "Streaming_History_Audio files. Listens already here are not counted twice.");
    importing.footerLink = @"https://www.spotify.com/account/privacy/";
    [sections addObject:importing];
    SGModRow *clear = SGActionRow(@"Clear listening stats", nil, ^{ confirmClear(); });
    clear.color = SGRed();
    [sections addObject:SGSection(nil, @[clear])];
    return [[SGModPage alloc] initWithTitle:@"Listening stats" intro:nil sections:sections footer:nil];
}

NSString *SGListeningStatsSummary(void) {
    if (!SGEnabled(SGKeyListeningStats)) return @"Off";
    return duration(SGListeningSummarize(SGListeningPeriodMonth, 0).seconds);
}
