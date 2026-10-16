// Lyrics kept on this iPhone (Lyrics.h): every song's lines, once they load from wherever they came,
// are written to Library/Application Support/spoti.pw/Lyrics/<track>.json in Spotify's container, kept
// out of the iCloud backup, with the source's credit. KaraokeSource.x reads a saved song's lines from
// there before asking anyone, so they show at once and without a connection, and writes a song's lines
// again whenever they change (a translation added, Spotify's better timed ones). Local files keep their
// own (Shared/LyricsSources/LocalLyrics.m). The oldest go once there are more than kMostSongs, enough for a
// whole library downloaded at once (LyricsDownload.m) at a few kilobytes a song.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"

static const NSUInteger kMostSongs = 20000, kKeptAfterPrune = 18000;

static NSURL *folder(void) {
    static NSURL *url;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        url = [base URLByAppendingPathComponent:@"spoti.pw/Lyrics" isDirectory:YES];
    });
    return url;
}

// A base62 id is all a file is named for; anything else (a local file's id) is not saved here.
static NSURL *fileFor(NSString *trackID) {
    if (trackID.length == 0 || trackID.length > 64) return nil;
    static NSCharacterSet *other;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        other = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"].invertedSet;
    });
    if ([trackID rangeOfCharacterFromSet:other].location != NSNotFound) return nil;
    return [folder() URLByAppendingPathComponent:[trackID stringByAppendingPathExtension:@"json"]];
}

static dispatch_queue_t disk(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.lyrics.offline", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

BOOL SGLyricsOfflineEnabled(void) {
    return SGEnabled(SGKeyLyricsOffline);
}

#pragma mark - lines to and from JSON

static NSDictionary *lineToJSON(SGKaraokeLine *line) {
    if (!line) return nil;
    NSMutableArray *words = [NSMutableArray arrayWithCapacity:line.words.count];
    for (SGKaraokeWord *word in line.words) [words addObject:@[word.text ?: @"", @(word.start), @(word.end), @(word.joined)]];
    NSMutableDictionary *json = [@{@"s": @(line.start), @"e": @(line.end), @"t": @(line.timing), @"a": @(line.align), @"w": words} mutableCopy];
    if (line.voice) json[@"v"] = line.voice;
    if (line.translation) json[@"tr"] = line.translation;
    if (line.backing) json[@"b"] = lineToJSON(line.backing);
    if (line.pronunciation) json[@"p"] = lineToJSON(line.pronunciation);
    return json;
}

static NSInteger integer(id value) { return [value isKindOfClass:NSNumber.class] ? [value integerValue] : 0; }

static SGKaraokeLine *lineFromJSON(id json, int depth) {
    if (![json isKindOfClass:NSDictionary.class] || depth > 2) return nil;
    NSDictionary *dict = json;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.start = integer(dict[@"s"]);
    line.end = integer(dict[@"e"]);
    line.timing = (SGKaraokeTiming)MIN(MAX(integer(dict[@"t"]), 0), (NSInteger)SGKaraokeTimingNone);
    line.align = integer(dict[@"a"]) == SGKaraokeAlignTrailing ? SGKaraokeAlignTrailing : SGKaraokeAlignLeading;
    if ([dict[@"v"] isKindOfClass:NSString.class]) line.voice = dict[@"v"];
    if ([dict[@"tr"] isKindOfClass:NSString.class]) line.translation = dict[@"tr"];
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    for (id item in [dict[@"w"] isKindOfClass:NSArray.class] ? dict[@"w"] : @[]) {
        if (![item isKindOfClass:NSArray.class] || [item count] != 4 || ![item[0] isKindOfClass:NSString.class]) return nil;
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = item[0];
        word.start = integer(item[1]);
        word.end = integer(item[2]);
        word.joined = integer(item[3]) != 0;
        [words addObject:word];
    }
    line.words = words;
    line.backing = lineFromJSON(dict[@"b"], depth + 1);
    line.pronunciation = lineFromJSON(dict[@"p"], depth + 1);
    return line;
}

#pragma mark - reading and writing

BOOL SGLyricsOfflineHas(NSString *trackID) {
    if (!SGLyricsOfflineEnabled()) return NO;
    NSURL *file = fileFor(trackID);
    return file && [NSFileManager.defaultManager fileExistsAtPath:file.path];
}

void SGLyricsOfflineRead(NSString *trackID, void (^done)(NSArray<SGKaraokeLine *> *lines)) {
    NSURL *file = fileFor(trackID);
    dispatch_async(disk(), ^{
        NSData *data = file ? [NSData dataWithContentsOfURL:file] : nil;
        NSDictionary *saved = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSMutableArray<SGKaraokeLine *> *lines = nil;
        NSString *credit = nil;
        if ([saved isKindOfClass:NSDictionary.class] && [saved[@"lines"] isKindOfClass:NSArray.class]) {
            lines = [NSMutableArray array];
            for (id json in saved[@"lines"]) {
                SGKaraokeLine *line = lineFromJSON(json, 0);
                if (!line) { lines = nil; break; }
                [lines addObject:line];
            }
            if ([saved[@"credit"] isKindOfClass:NSString.class]) credit = saved[@"credit"];
        }
        // Read again, it counts as used: the oldest unread go first.
        if (lines.count) [file setResourceValue:NSDate.date forKey:NSURLContentModificationDateKey error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (lines.count && credit.length) SGLyricsSetCredit(trackID, SGLyricsCreditNamed(credit));
            done(lines.count ? lines : nil);
        });
    });
}

static void prune(void) {
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder()
        includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    if (files.count <= kMostSongs) return;
    NSArray<NSURL *> *oldestFirst = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *x = nil, *y = nil;
        [a getResourceValue:&x forKey:NSURLContentModificationDateKey error:nil];
        [b getResourceValue:&y forKey:NSURLContentModificationDateKey error:nil];
        NSDate *first = x ?: NSDate.distantPast, *second = y ?: NSDate.distantPast;
        return [first compare:second];
    }];
    for (NSUInteger i = 0; i + kKeptAfterPrune < oldestFirst.count; i++) [NSFileManager.defaultManager removeItemAtURL:oldestFirst[i] error:nil];
}

void SGLyricsOfflineStore(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *credit) {
    NSURL *file = fileFor(trackID);
    if (!file || !lines.count || !SGLyricsOfflineEnabled()) return;
    NSMutableArray *json = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [json addObject:lineToJSON(line)];
    NSMutableDictionary *saved = [@{@"v": @1, @"lines": json} mutableCopy];
    if (credit.length) saved[@"credit"] = credit;
    NSData *data = [NSJSONSerialization dataWithJSONObject:saved options:0 error:NULL];
    if (!data) return;
    dispatch_async(disk(), ^{
        static NSUInteger writes;
        NSURL *base = folder();
        if (![NSFileManager.defaultManager fileExistsAtPath:base.path]) {
            [NSFileManager.defaultManager createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:nil];
            NSURL *excluded = base;
            [excluded setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        }
        [data writeToURL:file options:NSDataWritingAtomic error:nil];
        if (++writes % 50 == 1) prune();
    });
}

// Main queue: the lines are the engine's, and their credit is set just after they are kept.
void SGLyricsOfflineSave(NSString *trackID, NSArray<SGKaraokeLine *> *lines) {
    if (!fileFor(trackID) || !lines.count || !SGLyricsOfflineEnabled()) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Kept again since with other lines: those are saved by their own call.
        if (SGKaraokeLinesForTrack(trackID) != lines) return;
        SGLyricsOfflineStore(trackID, lines, SGLyricsCreditFor(trackID).text);
    });
}

#pragma mark - Mod Settings

static void measure(NSUInteger *songs, unsigned long long *bytes) {
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder()
        includingPropertiesForKeys:@[NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    *songs = files.count;
    *bytes = 0;
    for (NSURL *file in files) {
        NSNumber *size = nil;
        [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        *bytes += size.unsignedLongLongValue;
    }
}

NSArray<SGModRow *> *SGLyricsOfflineRows(void) {
    SGModRow *save = SGOptionRow(@"Save lyrics offline", @"Kept on this iPhone once they load, for when there is no connection",
                                 SGKeyLyricsOffline);
    SGModRow *saved = SGStatActionRow(@"Saved lyrics", nil, ^NSString *{
        NSUInteger songs = 0;
        unsigned long long bytes = 0;
        measure(&songs, &bytes);
        if (!songs) return @"None";
        return [NSString stringWithFormat:@"%lu %@ · %@", (unsigned long)songs, songs == 1 ? @"song" : @"songs",
                [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile]];
    }, ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove saved lyrics?"
            message:@"Songs played again save their lyrics again while the switch is on." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            dispatch_async(disk(), ^{ [NSFileManager.defaultManager removeItemAtURL:folder() error:nil]; });
        }]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    // Every song of the library at once: Liked Songs, or those and the playlists; tapped again, it stops.
    SGModRow *download = SGStatActionRow(@"Download all lyrics", @"Liked Songs and playlists, without playing them", ^NSString *{
        return SGLyricsDownloadStatus();
    }, ^{
        if (SGLyricsDownloadRunning()) {
            SGLyricsDownloadStop();
            return;
        }
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Download all lyrics"
            message:@"Every song's lyrics are saved on this iPhone, one song at a time, while Spotify is open. It can take a while "
                     "for a big library; songs already saved are skipped." preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Liked Songs" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            SGLyricsDownloadStart(SGLyricsDownloadLiked);
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Liked Songs and playlists" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            SGLyricsDownloadStart(SGLyricsDownloadLikedAndPlaylists);
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *top = SGTopController();
        sheet.popoverPresentationController.sourceView = top.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
        [top presentViewController:sheet animated:YES completion:nil];
    });
    download.symbol = @"arrow.down.circle";
    download.progress = ^double { return SGLyricsDownloadProgress(); };
    download.refreshOn = SGLyricsDownloadDidChangeNotification;
    saved.refreshOn = SGLyricsDownloadDidChangeNotification;
    return @[save, download, saved];
}
