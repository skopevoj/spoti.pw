#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Headers/SPTPlayer.h"
#import "Meanings.h"

static NSString *const kSearch = @"https://genius.com/api/search/song";
static NSString *const kReferents = @"https://genius.com/api/referents";
static const NSUInteger kMostPages = 5, kPerPage = 50;
// Shorter than this, a fragment found inside a line is more likely a common phrase than the line.
static const NSUInteger kLeastContained = 10;
static const double kLeastShared = 0.75;

@implementation SGLyricsMeaning
@end

SGLyricsMeaningsLevel SGLyricsMeaningsShown(void) {
    NSInteger level = SGInt(SGKeyLyricsMeanings, SGLyricsMeaningsOff);
    return level >= SGLyricsMeaningsOff && level <= SGLyricsMeaningsAll ? level : SGLyricsMeaningsOff;
}

SGModRow *SGLyricsMeaningsRow(void) {
    SGModRow *row = SGChoiceRow(@"Line meanings", nil, SGKeyLyricsMeanings,
                                @[@"Off", @"From the artist", @"Artist and editors", @"Everyone"], SGLyricsMeaningsOff);
    row.choiceFooter = @"Explanations from Genius. Tap the bubble after a line, or hold the line.";
    return row;
}

#pragma mark - text

// Letters and digits only, lowercase, accents gone and apostrophes closed up, so "Don’t" and "dont"
// read alike across sources.
static NSString *folded(NSString *text) {
    static NSCharacterSet *kept;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ kept = NSCharacterSet.alphanumericCharacterSet; });
    NSString *plain = [text stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
                                                locale:nil];
    NSMutableString *out = [NSMutableString stringWithCapacity:plain.length];
    BOOL space = NO;
    for (NSUInteger i = 0; i < plain.length; i++) {
        unichar c = [plain characterAtIndex:i];
        if (c == '\'' || c == 0x2019 || c == 0x2018 || c == '`') continue;
        if ([kept characterIsMember:c]) {
            if (space && out.length) [out appendString:@" "];
            space = NO;
            [out appendFormat:@"%C", c];
        } else {
            space = YES;
        }
    }
    return out;
}

// "Song (feat. X) - Remastered 2011" as Genius titles it: "Song".
static NSString *bareTitle(NSString *title) {
    NSString *bare = title ?: @"";
    NSRange dash = [bare rangeOfString:@" - "];
    if (dash.location != NSNotFound) bare = [bare substringToIndex:dash.location];
    static NSRegularExpression *brackets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ brackets = [NSRegularExpression regularExpressionWithPattern:@"\\s*[\\(\\[][^\\)\\]]*[\\)\\]]" options:0 error:nil]; });
    bare = [brackets stringByReplacingMatchesInString:bare options:0 range:NSMakeRange(0, bare.length) withTemplate:@""];
    return [bare stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static BOOL sameLine(NSString *a, NSString *b) {
    if (!a.length || !b.length) return NO;
    if ([a isEqualToString:b]) return YES;
    if (MIN(a.length, b.length) >= kLeastContained && ([a containsString:b] || [b containsString:a])) return YES;
    NSArray<NSString *> *wordsA = [a componentsSeparatedByString:@" "], *wordsB = [b componentsSeparatedByString:@" "];
    if (MIN(wordsA.count, wordsB.count) < 4) return NO;
    NSCountedSet *left = [[NSCountedSet alloc] initWithArray:wordsA];
    NSUInteger shared = 0;
    for (NSString *word in wordsB) {
        if (![left countForObject:word]) continue;
        [left removeObject:word];
        shared++;
    }
    return (double)shared / MAX(wordsA.count, wordsB.count) >= kLeastShared;
}

// A fragment's lines as they can be matched, the [Chorus] headings left out.
static NSArray<NSString *> *fragmentLines(NSString *fragment) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *row in [fragment componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [row stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) continue;
        NSString *text = folded(trimmed);
        if (text.length) [lines addObject:text];
    }
    return lines;
}

#pragma mark - Genius

static NSDictionary<NSString *, NSString *> *headers(void) {
    return @{@"User-Agent": @"Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
             @"Accept": @"application/json"};
}

static void getJSON(NSString *base, NSDictionary<NSString *, NSString *> *query, void (^done)(NSDictionary *response)) {
    NSURLComponents *url = [NSURLComponents componentsWithString:base];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10];
    [headers() enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:name];
    }];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *reply, NSError *error) {
        NSInteger status = [reply isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)reply).statusCode : 0;
        id root = !error && status < 400 && data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        id response = [root isKindOfClass:NSDictionary.class] ? root[@"response"] : nil;
        if (![response isKindOfClass:NSDictionary.class]) {
            SGLog(@"meanings: %@ answered %ld, error %@", url.path, (long)status, error);
            response = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(response); });
    }] resume];
}

static NSString *stringIn(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

// The hit whose title and artist both agree with the track's; a song only near it would explain
// lines it does not have.
static NSNumber *songIn(NSDictionary *response, NSString *title, NSString *artist) {
    NSString *wantTitle = folded(bareTitle(title));
    NSString *wantArtist = folded([artist componentsSeparatedByString:@", "].firstObject);
    id sections = response[@"sections"];
    for (NSDictionary *section in [sections isKindOfClass:NSArray.class] ? sections : @[]) {
        id hits = [section isKindOfClass:NSDictionary.class] ? section[@"hits"] : nil;
        for (NSDictionary *hit in [hits isKindOfClass:NSArray.class] ? hits : @[]) {
            NSDictionary *song = [hit isKindOfClass:NSDictionary.class] ? hit[@"result"] : nil;
            if (![song isKindOfClass:NSDictionary.class] || ![song[@"id"] isKindOfClass:NSNumber.class]) continue;
            NSString *hitTitle = folded(bareTitle(stringIn(song[@"title"])));
            NSString *hitArtists = folded(stringIn(song[@"artist_names"]) ?: @"");
            BOOL titled = [hitTitle isEqualToString:wantTitle];
            BOOL byArtist = wantArtist.length && hitArtists.length
                && ([hitArtists containsString:wantArtist] || [wantArtist containsString:hitArtists]);
            if (titled && byArtist) return song[@"id"];
        }
    }
    return nil;
}

// By the annotation, not the referent: a referent the artist spoke to is "verified" as a whole, the
// editors' annotations under it too.
static SGLyricsMeaningAuthor authorOf(NSDictionary *annotation) {
    NSString *state = stringIn(annotation[@"state"]);
    if ([annotation[@"verified"] boolValue] || [state isEqualToString:@"verified"]) return SGLyricsMeaningByArtist;
    if ([state isEqualToString:@"accepted"]) return SGLyricsMeaningByEditors;
    return SGLyricsMeaningByCommunity;
}

static void addMeanings(NSDictionary *response, NSMutableArray<SGLyricsMeaning *> *into) {
    id referents = response[@"referents"];
    for (NSDictionary *referent in [referents isKindOfClass:NSArray.class] ? referents : @[]) {
        if (![referent isKindOfClass:NSDictionary.class] || [referent[@"is_description"] boolValue]) continue;
        NSString *fragment = stringIn(referent[@"fragment"]);
        id annotations = referent[@"annotations"];
        if (!fragment.length || ![annotations isKindOfClass:NSArray.class]) continue;
        for (NSDictionary *annotation in annotations) {
            if (![annotation isKindOfClass:NSDictionary.class] || [annotation[@"deleted"] boolValue]) continue;
            if ([stringIn(annotation[@"state"]) isEqualToString:@"rejected"]) continue;
            id body = annotation[@"body"];
            NSString *text = [stringIn([body isKindOfClass:NSDictionary.class] ? body[@"plain"] : nil)
                              stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!text.length) continue;
            SGLyricsMeaning *meaning = [SGLyricsMeaning new];
            meaning.fragment = fragment;
            meaning.body = text;
            meaning.author = authorOf(annotation);
            meaning.url = stringIn(annotation[@"share_url"]) ?: stringIn(referent[@"url"]);
            [into addObject:meaning];
        }
    }
}

static void fetchReferents(NSNumber *song, NSUInteger page, NSMutableArray<SGLyricsMeaning *> *into, void (^done)(void)) {
    getJSON(kReferents, @{@"song_id": song.stringValue, @"text_format": @"plain",
                          @"per_page": @(kPerPage).stringValue, @"page": @(page).stringValue}, ^(NSDictionary *response) {
        addMeanings(response, into);
        id next = response[@"next_page"];
        if ([next isKindOfClass:NSNumber.class] && page < kMostPages) fetchReferents(song, page + 1, into, done);
        else done();
    });
}

#pragma mark - asking once per track

// Main queue only: every meaning Genius has for a track, empty for none.
static NSMutableDictionary<NSString *, NSArray<SGLyricsMeaning *> *> *sg_meanings;
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_waiting;

static void answer(NSString *trackID, NSArray<SGLyricsMeaning *> *meanings, BOOL keep) {
    if (keep) sg_meanings[trackID] = meanings;
    NSArray *waiting = sg_waiting[trackID];
    [sg_waiting removeObjectForKey:trackID];
    for (void (^each)(NSArray<SGLyricsMeaning *> *) in waiting) each(meanings);
}

static void meaningsOf(NSString *trackID, void (^done)(NSArray<SGLyricsMeaning *> *meanings)) {
    if (!sg_meanings) {
        sg_meanings = [NSMutableDictionary dictionary];
        sg_waiting = [NSMutableDictionary dictionary];
    }
    NSArray<SGLyricsMeaning *> *known = sg_meanings[trackID];
    if (known) {
        done(known);
        return;
    }
    if (sg_waiting[trackID]) {
        [sg_waiting[trackID] addObject:[done copy]];
        return;
    }
    sg_waiting[trackID] = [NSMutableArray arrayWithObject:[done copy]];

    SPTPlayerTrack *track = SGKaraokeTrackFor(trackID);
    NSString *title = track.trackTitle, *artist = track.artistName;
    // Not kept: the player may name the track later.
    if (!title.length || !artist.length) {
        answer(trackID, @[], NO);
        return;
    }
    NSString *q = [NSString stringWithFormat:@"%@ %@", bareTitle(title), artist];
    getJSON(kSearch, @{@"q": q, @"per_page": @"10"}, ^(NSDictionary *response) {
        NSNumber *song = songIn(response, title, artist);
        if (!song) {
            SGLog(@"meanings: no Genius song for %@ by %@", title, artist);
            answer(trackID, @[], response != nil);   // a failed search is asked again next time
            return;
        }
        NSMutableArray<SGLyricsMeaning *> *meanings = [NSMutableArray array];
        fetchReferents(song, 1, meanings, ^{
            SGLog(@"meanings: Genius song %@ for %@ has %lu annotations", song, title, (unsigned long)meanings.count);
            answer(trackID, meanings, YES);
        });
    });
}

// Each meaning goes to every line its fragment's first matchable line matches, so a chorus explained
// once is explained wherever it is sung.
static NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *matched(NSArray<SGLyricsMeaning *> *meanings,
                                                                        NSArray<SGKaraokeLine *> *lines,
                                                                        SGLyricsMeaningsLevel level) {
    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [texts addObject:folded(SGKaraokeLineText(line))];
    SGLyricsMeaningAuthor furthest = level == SGLyricsMeaningsArtist ? SGLyricsMeaningByArtist
                                   : level == SGLyricsMeaningsEditors ? SGLyricsMeaningByEditors : SGLyricsMeaningByCommunity;
    NSMutableDictionary<NSNumber *, NSMutableArray<SGLyricsMeaning *> *> *byLine = [NSMutableDictionary dictionary];
    for (SGLyricsMeaning *meaning in meanings) {
        if (meaning.author > furthest) continue;
        for (NSString *wanted in fragmentLines(meaning.fragment)) {
            BOOL found = NO;
            for (NSUInteger i = 0; i < texts.count; i++) {
                if (!sameLine(wanted, texts[i])) continue;
                found = YES;
                NSMutableArray<SGLyricsMeaning *> *list = byLine[@(i)] ?: (byLine[@(i)] = [NSMutableArray array]);
                // A chorus annotated at each of its places carries the same words at every one.
                if (![[list valueForKey:@"body"] containsObject:meaning.body]) [list addObject:meaning];
            }
            if (found) break;
        }
    }
    for (NSMutableArray<SGLyricsMeaning *> *list in byLine.allValues) {
        [list sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(SGLyricsMeaning *a, SGLyricsMeaning *b) {
            return a.author < b.author ? NSOrderedAscending : a.author > b.author ? NSOrderedDescending : NSOrderedSame;
        }];
    }
    return byLine;
}

void SGLyricsMeaningsFor(NSString *trackID, NSArray<SGKaraokeLine *> *lines,
                         void (^done)(NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *byLine)) {
    SGLyricsMeaningsLevel level = SGLyricsMeaningsShown();
    if (level == SGLyricsMeaningsOff || !trackID.length || !lines.count) return;
    meaningsOf(trackID, ^(NSArray<SGLyricsMeaning *> *meanings) {
        NSDictionary *byLine = meanings.count ? matched(meanings, lines, level) : @{};
        if (meanings.count) SGLog(@"meanings: %lu of %lu lines of %@ explained", (unsigned long)byLine.count, (unsigned long)lines.count, trackID);
        done(byLine);
    });
}
