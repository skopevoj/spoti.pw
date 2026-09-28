// QQ Music's public musicu search and line-timed LRC. QRC uses QQ's own nonstandard cipher;
// request the unencrypted LRC variant so this source can run inside the tweak without a decoder.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kMusicu = @"https://u.y.qq.com/cgi-bin/musicu.fcg";

static NSDictionary<NSString *, NSString *> *headers(void) {
    return @{@"Referer": @"https://y.qq.com/", @"User-Agent": @"Mozilla/5.0", @"Accept": @"application/json"};
}

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

static BOOL matches(NSDictionary *song, SGLyricsQuery *query) {
    NSString *title = [song[@"title"] isKindOfClass:NSString.class] ? song[@"title"] : song[@"songname"];
    if (![normalized(title) isEqualToString:normalized(query.title)]) return NO;
    if (query.seconds > 0 && [song[@"interval"] respondsToSelector:@selector(integerValue)] &&
        labs([song[@"interval"] integerValue] - query.seconds) > 6) return NO;
    NSString *wanted = normalized([query.artist componentsSeparatedByString:@" feat"].firstObject);
    for (NSDictionary *singer in [song[@"singer"] isKindOfClass:NSArray.class] ? song[@"singer"] : @[]) {
        NSString *name = normalized([singer isKindOfClass:NSDictionary.class] ? singer[@"name"] : nil);
        if (name.length && wanted.length && ([name containsString:wanted] || [wanted containsString:name])) return YES;
    }
    return NO;
}

static void lyricsForSong(NSNumber *songID, void (^done)(SGLyricsResult *)) {
    NSDictionary *request = @{@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo": @{
        @"method": @"GetPlayLyricInfo", @"module": @"music.musichallSong.PlayLyricInfo",
        @"param": @{@"crypt": @0, @"qrc": @0, @"songID": songID}}};
    SGLyricsPostJSON([NSURL URLWithString:kMusicu], headers(), request, ^(id root) {
        id value = [root isKindOfClass:NSDictionary.class]
            ? root[@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo"] : nil;
        NSDictionary *reply = [value isKindOfClass:NSDictionary.class] ? value : nil;
        NSDictionary *data = [reply[@"data"] isKindOfClass:NSDictionary.class] ? reply[@"data"] : nil;
        NSString *encoded = [data[@"lyric"] isKindOfClass:NSString.class] ? data[@"lyric"] : nil;
        NSData *bytes = encoded.length ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
        NSString *lrc = bytes ? [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding] : nil;
        NSArray<SGKaraokeLine *> *lines = lrc ? SGLyricsLinesFromLRC(lrc) : nil;
        if (!lines.count) { done(nil); return; }
        SGLyricsResult *result = [SGLyricsResult new];
        result.synced = YES;
        result.karaokeLines = lines;
        NSArray<NSNumber *> *starts;
        NSArray<NSString *> *texts;
        SGLyricsPageLines(lines, &starts, &texts);
        result.starts = starts;
        result.texts = texts;
        done(result);
    });
}

SGLyricsAsk SGQQMusicAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
    if (!query.title.length || !query.artist.length) { done(nil); return; }
    NSDictionary *request = @{
        @"comm": @{@"ct": @"19", @"cv": @"1859", @"uin": @"0"},
        @"req": @{@"method": @"DoSearchForQQMusicDesktop", @"module": @"music.search.SearchCgiService",
                  @"param": @{@"grp": @1, @"num_per_page": @8, @"page_num": @1,
                               @"query": [NSString stringWithFormat:@"%@ %@", query.title, query.artist], @"search_type": @0}}
    };
    SGLyricsPostJSON([NSURL URLWithString:kMusicu], headers(), request, ^(id root) {
        id value = [root isKindOfClass:NSDictionary.class] ? root[@"req"] : nil;
        NSDictionary *requestReply = [value isKindOfClass:NSDictionary.class] ? value : nil;
        NSDictionary *data = [requestReply[@"data"] isKindOfClass:NSDictionary.class] ? requestReply[@"data"] : nil;
        NSDictionary *body = [data[@"body"] isKindOfClass:NSDictionary.class] ? data[@"body"] : nil;
        NSDictionary *song = [body[@"song"] isKindOfClass:NSDictionary.class] ? body[@"song"] : nil;
        NSArray *list = [song[@"list"] isKindOfClass:NSArray.class] ? song[@"list"] : @[];
        for (NSDictionary *candidate in list) {
            if (![candidate isKindOfClass:NSDictionary.class] || !matches(candidate, query)) continue;
            NSNumber *songID = [candidate[@"id"] isKindOfClass:NSNumber.class] ? candidate[@"id"] : nil;
            if (songID) { lyricsForSong(songID, done); return; }
        }
        SGLog(@"qqmusic: no matching recording for %@ by %@", query.title, query.artist);
        done(nil);
    });
};
