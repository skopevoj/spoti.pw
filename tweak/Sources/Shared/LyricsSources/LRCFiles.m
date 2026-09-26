#import "LRCFiles.h"
#import "Shared/Lyrics/Lyrics.h"

static NSString *libraryPath(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documents stringByAppendingPathComponent:@"spoti.pw/Lyrics"];
}

NSArray<NSString *> *SGLRCFiles(void) {
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:libraryPath() error:nil];
    NSPredicate *lrc = [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
        return [name.pathExtension.lowercaseString isEqualToString:@"lrc"];
    }];
    return [[names filteredArrayUsingPredicate:lrc] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

NSString *SGLRCImport(NSURL *url, NSError **error) {
    if (![url.pathExtension.lowercaseString isEqualToString:@"lrc"]) {
        if (error) *error = [NSError errorWithDomain:@"spoti.pw.LRC" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Choose an .lrc file."}];
        return nil;
    }
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!data || data.length == 0 || data.length > 1024 * 1024) {
        if (error && !*error) *error = [NSError errorWithDomain:@"spoti.pw.LRC" code:2 userInfo:@{NSLocalizedDescriptionKey: @"The file is empty or larger than 1 MB."}];
        return nil;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
    if (!text || ![text containsString:@"]"]) {
        if (error) *error = [NSError errorWithDomain:@"spoti.pw.LRC" code:3 userInfo:@{NSLocalizedDescriptionKey: @"This file could not be read as LRC text."}];
        return nil;
    }
    NSString *directory = libraryPath();
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *base = url.lastPathComponent.stringByDeletingPathExtension;
    base = [[base stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!base.length) base = @"Lyrics";
    NSString *name = [base stringByAppendingPathExtension:@"lrc"];
    NSUInteger suffix = 2;
    while ([[NSFileManager defaultManager] fileExistsAtPath:[directory stringByAppendingPathComponent:name]])
        name = [[NSString stringWithFormat:@"%@ (%lu)", base, (unsigned long)suffix++] stringByAppendingPathExtension:@"lrc"];
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (![utf8 writeToFile:[directory stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:error]) return nil;
    NSMutableArray<NSString *> *order = [SGLyricsOrder() mutableCopy];
    if (![order containsObject:@"importedlrc"]) [order insertObject:@"importedlrc" atIndex:0];
    SGLyricsSetOrder(order);
    SGLyricsInvalidateCache();
    NSString *playing = SGKaraokePlayingTrack();
    if (playing) SGLyricsPrefetch(playing);
    return name;
}

BOOL SGLRCDelete(NSString *name) {
    if (![name.pathExtension.lowercaseString isEqualToString:@"lrc"] || ![name.lastPathComponent isEqualToString:name]) return NO;
    NSString *path = [libraryPath() stringByAppendingPathComponent:name];
    return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

static NSString *fold(NSString *text) {
    NSString *clean = [[text ?: @"" stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en"]] lowercaseString];
    NSMutableString *result = [NSMutableString string];
    NSCharacterSet *letters = NSCharacterSet.alphanumericCharacterSet;
    for (NSUInteger i = 0; i < clean.length; i++) {
        unichar c = [clean characterAtIndex:i];
        if ([letters characterIsMember:c]) [result appendFormat:@"%C", c];
    }
    return result;
}

static SGLyricsResult *parseLRC(NSString *content, SGLyricsQuery *query, NSString *filename) {
    NSString *tagTitle = nil, *tagArtist = nil;
    NSInteger offset = 0;
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSRegularExpression *timestamp = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]" options:0 error:nil];
    for (NSString *raw in [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([line hasPrefix:@"[ti:"] && [line hasSuffix:@"]"]) tagTitle = [line substringWithRange:NSMakeRange(4, line.length - 5)];
        else if ([line hasPrefix:@"[ar:"] && [line hasSuffix:@"]"]) tagArtist = [line substringWithRange:NSMakeRange(4, line.length - 5)];
        else if ([line hasPrefix:@"[offset:"] && [line hasSuffix:@"]"]) offset = [[line substringWithRange:NSMakeRange(8, line.length - 9)] integerValue];
        NSArray<NSTextCheckingResult *> *matches = [timestamp matchesInString:line options:0 range:NSMakeRange(0, line.length)];
        NSString *lyric = [timestamp stringByReplacingMatchesInString:line options:0 range:NSMakeRange(0, line.length) withTemplate:@""];
        lyric = [lyric stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!lyric.length) continue;
        for (NSTextCheckingResult *match in matches) {
            NSInteger minutes = [[line substringWithRange:[match rangeAtIndex:1]] integerValue];
            NSInteger seconds = [[line substringWithRange:[match rangeAtIndex:2]] integerValue];
            NSString *fraction = [match rangeAtIndex:3].location == NSNotFound ? @"0" : [line substringWithRange:[match rangeAtIndex:3]];
            NSInteger millis = fraction.length == 1 ? fraction.integerValue * 100 : fraction.length == 2 ? fraction.integerValue * 10 : fraction.integerValue;
            NSInteger at = MAX(0, minutes * 60000 + seconds * 1000 + millis + offset);
            [entries addObject:@{@"start": @(at), @"text": lyric}];
        }
    }
    NSString *fileTitle = filename.stringByDeletingPathExtension;
    NSString *title = tagTitle.length ? tagTitle : fileTitle;
    NSString *artist = tagArtist;
    // Also recognize common "Artist - Title.lrc" / "Title - Artist.lrc" naming styles, including
    // files whose tags expose a title but omit the artist, and Unicode dash separators.
    if (!tagTitle.length && query.title.length && ![fold(query.title) isEqualToString:fold(title)]) {
        for (NSString *separator in @[@" - ", @" – ", @" — "]) {
            NSArray<NSString *> *parts = [fileTitle componentsSeparatedByString:separator];
            if (parts.count != 2) continue;
            NSString *left = [parts[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSString *right = [parts[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSString *leftFold = fold(left), *rightFold = fold(right), *queryTitle = fold(query.title);
            NSString *queryArtist = fold(query.artist);
            if ([leftFold isEqualToString:queryArtist] && [rightFold isEqualToString:queryTitle]) {
                artist = left; title = right;
                break;
            } else if ([rightFold isEqualToString:queryArtist] && [leftFold isEqualToString:queryTitle]) {
                artist = right; title = left;
                break;
            } else if (!query.artist.length && [rightFold isEqualToString:queryTitle]) {
                artist = left; title = right;
                break;
            } else if (!query.artist.length && [leftFold isEqualToString:queryTitle]) {
                artist = right; title = left;
                break;
            }
        }
    }
    if (query.title.length && ![fold(query.title) isEqualToString:fold(title)]) return nil;
    if (query.artist.length && artist.length && ![fold(query.artist) isEqualToString:fold(artist)]) return nil;
    if (!query.title.length) return nil;
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"start"] compare:b[@"start"]]; }];
    NSMutableArray *starts = [NSMutableArray array], *texts = [NSMutableArray array];
    for (NSDictionary *entry in entries) { [starts addObject:entry[@"start"]]; [texts addObject:entry[@"text"]]; }
    SGLyricsResult *result = [SGLyricsResult new];
    result.title = title;
    result.artist = artist ?: @"";
    if (entries.count) {
        result.synced = YES;
        result.starts = starts;
        result.texts = texts;
        result.karaokeLines = SGKaraokeEstimatedLines(starts, texts);
    } else {
        NSMutableArray *plain = [NSMutableArray array];
        for (NSString *raw in [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (line.length && ![line hasPrefix:@"["]) [plain addObject:line];
        }
        if (!plain.count) return nil;
        result.texts = plain;
        result.karaokeLines = SGKaraokeStaticLines(plain);
    }
    return result;
}

SGLyricsAsk SGImportedLRCAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        SGLyricsResult *found = nil;
        for (NSString *name in SGLRCFiles()) {
            NSString *path = [libraryPath() stringByAppendingPathComponent:name];
            NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (!content) continue;
            found = parseLRC(content, query, name);
            if (found) break;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(found); });
    });
};
