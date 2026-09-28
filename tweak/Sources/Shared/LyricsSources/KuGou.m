// KuGou's KRC lyrics: search by recording, XOR the downloaded payload and inflate it.
#import "Core/SGCore.h"
#import "LyricsSources.h"
#import <string.h>
#import <zlib.h>

static NSString *normalized(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSMutableString *out = [NSMutableString string];
    NSCharacterSet *skip = [NSCharacterSet characterSetWithCharactersInString:@" -_.,:;!?()[]{}'\"·，。！？（）【】—　\t\n"];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (![skip characterIsMember:c]) [out appendFormat:@"%C", c];
    }
    return out.lowercaseString;
}

static BOOL matches(NSDictionary *candidate, SGLyricsQuery *query) {
    if (![candidate[@"id"] isKindOfClass:NSString.class] || ![candidate[@"accesskey"] isKindOfClass:NSString.class] ||
        [candidate[@"product_from"] isEqual:@"ugc"] ||
        ![normalized(candidate[@"song"]) isEqualToString:normalized(query.title)]) return NO;
    NSString *artist = normalized([query.artist componentsSeparatedByString:@" feat"].firstObject);
    NSString *singer = normalized(candidate[@"singer"]);
    if (!artist.length || !singer.length || !([artist containsString:singer] || [singer containsString:artist])) return NO;
    NSInteger duration = [candidate[@"duration"] respondsToSelector:@selector(integerValue)]
        ? [candidate[@"duration"] integerValue] : 0;
    return query.seconds <= 0 || duration <= 0 || labs(duration / 1000 - query.seconds) <= 8;
}

static NSString *decodeKRC(NSString *encoded) {
    if (![encoded isKindOfClass:NSString.class] || encoded.length > 2 * 1024 * 1024) return nil;
    NSData *bytes = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    if (bytes.length <= 4 || bytes.length > 1024 * 1024 || memcmp(bytes.bytes, "krc1", 4)) return nil;
    static const uint8_t key[] = {64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105};
    NSMutableData *compressed = [[bytes subdataWithRange:NSMakeRange(4, bytes.length - 4)] mutableCopy];
    uint8_t *body = compressed.mutableBytes;
    for (NSUInteger i = 0; i < compressed.length; i++) body[i] ^= key[i % sizeof(key)];
    NSMutableData *inflated = [NSMutableData dataWithLength:1024 * 1024];
    uLongf length = (uLongf)inflated.length;
    if (uncompress(inflated.mutableBytes, &length, compressed.bytes, (uLong)compressed.length) != Z_OK) return nil;
    return [[NSString alloc] initWithBytes:inflated.bytes length:(NSUInteger)length encoding:NSUTF8StringEncoding];
}

static NSArray<SGKaraokeLine *> *linesFromKRC(NSString *krc) {
    static NSRegularExpression *header, *part;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        header = [NSRegularExpression regularExpressionWithPattern:@"^\\[(\\d+),(\\d+)\\]" options:0 error:nil];
        part = [NSRegularExpression regularExpressionWithPattern:@"<(\\d+),(\\d+),-?\\d+>" options:0 error:nil];
    });
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    for (NSString *row in [krc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSTextCheckingResult *head = [header firstMatchInString:row options:0 range:NSMakeRange(0, row.length)];
        if (!head) continue;
        NSInteger lineStart = [row substringWithRange:[head rangeAtIndex:1]].integerValue;
        NSInteger lineEnd = lineStart + [row substringWithRange:[head rangeAtIndex:2]].integerValue;
        NSArray<NSTextCheckingResult *> *parts = [part matchesInString:row options:0 range:NSMakeRange(NSMaxRange(head.range), row.length - NSMaxRange(head.range))];
        NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
        SGKaraokeWord *open = nil;
        BOOL spaced = YES;
        for (NSUInteger i = 0; i < parts.count; i++) {
            NSTextCheckingResult *match = parts[i];
            NSUInteger from = NSMaxRange(match.range);
            NSUInteger to = i + 1 < parts.count ? parts[i + 1].range.location : row.length;
            NSString *raw = [row substringWithRange:NSMakeRange(from, to - from)];
            NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSInteger start = lineStart + [row substringWithRange:[match rangeAtIndex:1]].integerValue;
            NSInteger end = start + [row substringWithRange:[match rangeAtIndex:2]].integerValue;
            // KRC sometimes gives a sung syllable zero duration; keep its text visible.
            if (end <= start) end = start + 1;
            BOOL unspaced = SGKaraokeUnspacedScript(text);
            if (text.length && open && !unspaced) {
                open.text = [open.text stringByAppendingString:text];
                open.end = MAX(open.end, end);
            } else if (text.length) {
                SGKaraokeWord *word = [SGKaraokeWord new];
                word.text = text;
                word.start = start;
                word.end = end;
                word.joined = !spaced;
                [words addObject:word];
                open = unspaced ? nil : word;
                spaced = NO;
            }
            if (raw.length > text.length || !text.length) { open = nil; spaced = YES; }
        }
        if (!words.count) continue;
        SGKaraokeLine *line = [SGKaraokeLine new];
        line.words = words;
        line.start = lineStart;
        line.end = MAX(lineEnd, words.lastObject.end);
        line.timing = SGKaraokeTimingWords;
        [lines addObject:line];
    }
    return lines.count ? lines : nil;
}

static void tryCandidates(NSArray<NSDictionary *> *songs, NSUInteger index, void (^done)(SGLyricsResult *)) {
    if (index >= MIN(songs.count, 3)) { done(nil); return; }
    NSDictionary *song = songs[index];
    NSURL *url = SGLyricsURL(@"https://lyrics.kugou.com/download", @{
        @"ver": @"1", @"client": @"pc", @"id": song[@"id"], @"accesskey": song[@"accesskey"],
        @"fmt": @"krc", @"charset": @"utf8"});
    SGLyricsGetJSON(url, @{@"User-Agent": @"Mozilla/5.0"}, ^(id root) {
        NSDictionary *reply = [root isKindOfClass:NSDictionary.class] ? root : nil;
        NSString *krc = [reply[@"status"] integerValue] == 200 ? decodeKRC(reply[@"content"]) : nil;
        NSArray<SGKaraokeLine *> *lines = krc ? linesFromKRC(krc) : nil;
        if (!lines.count) { tryCandidates(songs, index + 1, done); return; }
        SGLyricsResult *result = [SGLyricsResult new];
        result.synced = result.wordTimed = YES;
        result.karaokeLines = lines;
        NSArray<NSNumber *> *starts;
        NSArray<NSString *> *texts;
        SGLyricsPageLines(lines, &starts, &texts);
        result.starts = starts;
        result.texts = texts;
        done(result);
    });
}

SGLyricsAsk SGKuGouAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
    if (!query.title.length || !query.artist.length) { done(nil); return; }
    NSURL *url = SGLyricsURL(@"https://krcs.kugou.com/search", @{
        @"ver": @"1", @"man": @"yes", @"client": @"mobi", @"hash": @"", @"album_audio_id": @"",
        @"keyword": [NSString stringWithFormat:@"%@ - %@", query.artist, query.title],
        @"duration": [NSString stringWithFormat:@"%ld", (long)MAX(query.seconds, 0) * 1000]});
    SGLyricsGetJSON(url, @{@"User-Agent": @"Mozilla/5.0"}, ^(id root) {
        NSDictionary *reply = [root isKindOfClass:NSDictionary.class] ? root : nil;
        NSArray *candidates = [reply[@"candidates"] isKindOfClass:NSArray.class] && [reply[@"status"] integerValue] == 200
            ? reply[@"candidates"] : @[];
        NSMutableArray<NSDictionary *> *fitting = [NSMutableArray array];
        for (id song in candidates) if ([song isKindOfClass:NSDictionary.class] && matches(song, query)) [fitting addObject:song];
        [fitting sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSInteger x = labs([a[@"duration"] integerValue] / 1000 - query.seconds);
            NSInteger y = labs([b[@"duration"] integerValue] / 1000 - query.seconds);
            return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
        }];
        SGLog(@"kugou: %@ by %@ has %lu matching recordings", query.title, query.artist, (unsigned long)fitting.count);
        tryCandidates(fitting, 0, done);
    });
};
