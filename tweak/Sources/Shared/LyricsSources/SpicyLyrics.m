// Spicy Lyrics' developer platform, matched by Spotify's track id: a community sync first, else Apple
// Music's or Spotify's. Each user asks with a publishable key of their own, and its terms make the credit
// a condition: the catalogue that answered, or a community sync's uploader and maker, linked.
#import "Core/SGCore.h"
#import "LyricsSources.h"
#import "Shared/Lyrics/Lyrics.h"

static NSString *const kAPI = @"https://api.spicylyrics.org/v1/lyrics/";
// Outside "spotifyglass.", so no settings backup, diagnostics dump or reset carries the key.
static NSString *const kKeyKey = @"spotipw.spicylyrics.key";
static NSString *const kRefusedKey = @"spotipw.spicylyrics.refused";   // the error code of the last 401 or 403
static const NSUInteger kKeptTracks = 100;
// A refused key is tried again after this long, in case its application was only paused.
static const NSTimeInterval kRefusedPause = 600;
// A 429 or 503 naming no wait of its own is waited out this long; one naming hours, at most an hour.
static const NSTimeInterval kDefaultWait = 60, kLongestWait = 3600;

NSNotificationName const SGSpicyLyricsKeyDidChangeNotification = @"spotifyglass.spicyLyricsKeyDidChange";

// Main queue only. NSNull for a track it has nothing for; kept in memory alone, far inside the
// 30 days the terms allow a stored answer.
static NSMutableDictionary<NSString *, id> *sg_kept;
static NSDate *sg_notBefore;
static NSDate *sg_refusedAt;

#pragma mark - the key

static NSString *storedKey(void) {
    NSString *key = [NSUserDefaults.standardUserDefaults stringForKey:kKeyKey];
    return key.length ? key : nil;
}

static void announce(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGSpicyLyricsKeyDidChangeNotification object:nil];
}

NSString *SGSpicyLyricsKeyShown(void) {
    NSString *key = storedKey();
    if (key.length <= 12) return key;
    return [NSString stringWithFormat:@"%@…%@", [key substringToIndex:6], [key substringFromIndex:key.length - 4]];
}

// Printable ASCII only: the key goes into a header as it is.
static BOOL plainASCII(NSString *text) {
    NSCharacterSet *printable = [NSCharacterSet characterSetWithRange:NSMakeRange(0x21, 0x5E)];
    return [text rangeOfCharacterFromSet:printable.invertedSet].location == NSNotFound;
}

NSString *SGSpicyLyricsSetKey(NSString *text) {
    NSString *key = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if ([key hasPrefix:@"sl_sk_"]) {
        return @"That is a secret key, which belongs on a server. Use the application's publishable key, which starts with sl_pk_.";
    }
    if (key.length && (![key hasPrefix:@"sl_pk_"] || key.length < 12 || !plainASCII(key))) {
        return @"A publishable key starts with sl_pk_.";
    }
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (key.length) [store setObject:key forKey:kKeyKey];
    else [store removeObjectForKey:kKeyKey];
    [store removeObjectForKey:kRefusedKey];
    sg_refusedAt = nil;
    SGLog(@"spicy: key %@", key.length ? @"stored" : @"removed");
    announce();
    return nil;
}

static NSString *refusal(NSString *code) {
    if ([@[@"origin_not_allowed", @"origins_not_configured"] containsObject:code]) return @"Key rejected: allow No origin header";
    if ([code isEqualToString:@"application_paused"]) return @"Key rejected: application paused";
    if ([code isEqualToString:@"key_revoked"]) return @"Key rejected: revoked";
    if ([@[@"key_not_found", @"key_malformed", @"malformed_authorization"] containsObject:code]) return @"Key rejected: not found";
    if ([@[@"application_suspended", @"user_suspended", @"key_disabled_by_admin", @"application_deleted"] containsObject:code]) {
        return @"Key rejected: disabled";
    }
    return @"Key rejected";
}

NSString *SGSpicyLyricsProblem(void) {
    if (!storedKey()) return @"Needs a key";
    NSString *code = [NSUserDefaults.standardUserDefaults stringForKey:kRefusedKey];
    return code ? refusal(code) : nil;
}

static void noteRefused(NSString *code) {
    sg_refusedAt = NSDate.date;
    NSString *stored = code.length ? code : @"refused";
    if ([[NSUserDefaults.standardUserDefaults stringForKey:kRefusedKey] isEqualToString:stored]) return;
    [NSUserDefaults.standardUserDefaults setObject:stored forKey:kRefusedKey];
    announce();
}

static void noteAccepted(void) {
    sg_refusedAt = nil;
    if (![NSUserDefaults.standardUserDefaults objectForKey:kRefusedKey]) return;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kRefusedKey];
    announce();
}

#pragma mark - the reply as lines

// The API times in seconds, the mod in milliseconds.
static NSInteger msIn(id seconds) {
    return [seconds isKindOfClass:NSNumber.class] ? (NSInteger)llround([seconds doubleValue] * 1000.0) : 0;
}

static NSDictionary *dictionaryIn(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *arrayIn(id value) {
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSString *stringIn(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

// IsPartOfWord marks a syllable the next one runs on from, which is a word joined to the one before
// it read from the other end. `spelt` takes each syllable's romanisation where it has one.
static NSArray<SGKaraokeWord *> *wordsFrom(NSArray *syllables, BOOL spelt) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    BOOL joinToPrevious = NO;
    for (id raw in syllables ?: @[]) {
        NSDictionary *syllable = dictionaryIn(raw);
        if (!syllable) continue;
        BOOL runsOn = [syllable[@"IsPartOfWord"] boolValue];
        NSString *text = spelt ? stringIn(syllable[@"TransliteratedText"]) ?: stringIn(syllable[@"Text"]) : stringIn(syllable[@"Text"]);
        NSString *said = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (said.length) {
            SGKaraokeWord *word = [SGKaraokeWord new];
            word.text = said;
            word.start = msIn(syllable[@"StartTime"]);
            word.end = MAX(msIn(syllable[@"EndTime"]), word.start);
            word.joined = joinToPrevious && words.count > 0;
            [words addObject:word];
        }
        joinToPrevious = runsOn;
    }
    return words;
}

static SGKaraokeLine *lineFrom(NSArray<SGKaraokeWord *> *words, id start, id end) {
    if (!words.count) return nil;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = start ? msIn(start) : words.firstObject.start;
    line.end = MAX(end ? msIn(end) : words.lastObject.end, line.start);
    return line;
}

// Only while the Lyrics page takes any language: the API does not say which one it translated into.
static NSString *translationIn(NSDictionary *part) {
    return SGLyricsTranslationLanguage() ? nil : stringIn(part[@"TranslatedText"]);
}

// The line spelt out: timed by its syllables where they carry one, else the group's text estimated
// across the line; nil where it reads the same as the line.
static SGKaraokeLine *spokenFrom(NSArray *syllables, NSString *plain, SGKaraokeLine *of) {
    BOOL timed = NO;
    for (id raw in syllables ?: @[]) timed = timed || stringIn(dictionaryIn(raw)[@"TransliteratedText"]).length > 0;
    SGKaraokeLine *line = timed ? lineFrom(wordsFrom(syllables, YES), nil, nil) : nil;
    if (!line && plain.length) line = [SGKaraokeEstimatedLines(@[@(of.start), @(of.end)], @[plain, @""]) firstObject];
    if (!line || SGLyricsReadsSame(SGKaraokeLineText(line), SGKaraokeLineText(of))) return nil;
    line.start = of.start;
    line.end = MAX(of.end, line.words.lastObject.end);
    line.align = of.align;
    return line;
}

static void addTranslation(SGKaraokeLine *line, NSArray<NSString *> *parts) {
    NSMutableArray<NSString *> *said = [NSMutableArray array];
    for (NSString *part in parts) if (part.length) [said addObject:part];
    NSString *translation = [said componentsJoinedByString:@" "];
    NSString *text = SGKaraokeLineText(line);
    if (line.backing) text = [text stringByAppendingFormat:@" %@", SGKaraokeLineText(line.backing)];
    if (translation.length && !SGLyricsReadsSame(translation, text)) line.translation = translation;
}

// Content: [{ Type: "Vocal", OppositeAligned, Lead: { Syllables, StartTime, EndTime }, Background: [...] }]
static NSArray<SGKaraokeLine *> *linesFromSyllables(NSArray *content) {
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    for (id raw in content ?: @[]) {
        NSDictionary *vocal = dictionaryIn(raw);
        NSDictionary *lead = dictionaryIn(vocal[@"Lead"]);
        SGKaraokeLine *line = lineFrom(wordsFrom(arrayIn(lead[@"Syllables"]), NO), lead[@"StartTime"], lead[@"EndTime"]);
        if (!line) continue;
        if ([vocal[@"OppositeAligned"] boolValue]) line.align = SGKaraokeAlignTrailing;
        // The page has one backing line under each line, so the API's runs of it read on as one.
        NSMutableArray *backingSyllables = [NSMutableArray array];
        NSMutableArray<NSString *> *backingSpelt = [NSMutableArray array];
        NSMutableArray<NSString *> *translations = [NSMutableArray arrayWithObject:translationIn(lead) ?: @""];
        for (id rawGroup in arrayIn(vocal[@"Background"]) ?: @[]) {
            NSDictionary *group = dictionaryIn(rawGroup);
            [backingSyllables addObjectsFromArray:arrayIn(group[@"Syllables"]) ?: @[]];
            if (stringIn(group[@"TransliteratedText"]).length) [backingSpelt addObject:group[@"TransliteratedText"]];
            [translations addObject:translationIn(group) ?: @""];
        }
        line.backing = lineFrom(wordsFrom(backingSyllables, NO), nil, nil);
        line.backing.align = line.align;
        line.pronunciation = spokenFrom(arrayIn(lead[@"Syllables"]), stringIn(lead[@"TransliteratedText"]), line);
        if (line.backing) line.backing.pronunciation = spokenFrom(backingSyllables, [backingSpelt componentsJoinedByString:@" "], line.backing);
        addTranslation(line, translations);
        [lines addObject:line];
    }
    return lines.count ? lines : nil;
}

// Content: [{ Type: "Vocal", OppositeAligned, Text, StartTime, EndTime }], the backing already in the
// text in parentheses; the words are estimated inside each line's own times.
static NSArray<SGKaraokeLine *> *linesFromLines(NSArray *content) {
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    for (id raw in content ?: @[]) {
        NSDictionary *vocal = dictionaryIn(raw);
        NSString *text = [stringIn(vocal[@"Text"]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length) continue;
        NSInteger start = msIn(vocal[@"StartTime"]), end = MAX(msIn(vocal[@"EndTime"]), start);
        SGKaraokeLine *line = [SGKaraokeEstimatedLines(@[@(start), @(end)], @[text, @""]) firstObject];
        if (!line) continue;
        line.start = start;
        line.end = MAX(end, line.start);
        if ([vocal[@"OppositeAligned"] boolValue]) line.align = SGKaraokeAlignTrailing;
        line.pronunciation = spokenFrom(nil, stringIn(vocal[@"TransliteratedText"]), line);
        addTranslation(line, @[translationIn(vocal) ?: @""]);
        [lines addObject:line];
    }
    return lines.count ? lines : nil;
}

static NSString *catalogueName(NSString *source) {
    if ([source isEqualToString:@"apple_music"]) return @"Apple Music";
    if ([source isEqualToString:@"spotify"]) return @"Spotify";
    return nil;
}

// "Apple Music via Spicy Lyrics", "Spicy Lyrics, uploaded by A, made by B" with both linked, or the
// source named unknown where the reply names none it knows.
static SGLyricsCredit *creditFor(NSDictionary *body) {
    SGLyricsCredit *credit = [SGLyricsCredit new];
    credit.required = YES;
    NSString *source = stringIn(body[@"source"]);
    if (![source isEqualToString:@"spicy_lyrics"]) {
        NSString *catalogue = catalogueName(source);
        credit.text = catalogue ? [catalogue stringByAppendingString:@" via Spicy Lyrics"] : @"Spicy Lyrics, source unknown";
        return credit;
    }
    NSDictionary *made = dictionaryIn(body[@"UploadAttribution"]);
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:@"Spicy Lyrics"];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSURL *> *links = [NSMutableArray array];
    for (NSArray<NSString *> *person in @[@[@"Uploader", @"uploaded"], @[@"Maker", @"made"]]) {
        NSDictionary *who = dictionaryIn(made[person[0]]);
        NSString *name = [stringIn(who[@"username"]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length) continue;
        [parts addObject:[NSString stringWithFormat:@"%@ by %@", person[1], name]];
        NSURL *url = [NSURL URLWithString:stringIn(who[@"url"]) ?: @""];
        if (![@[@"https", @"http"] containsObject:url.scheme.lowercaseString ?: @""] || !url.host.length) continue;
        [titles addObject:[NSString stringWithFormat:@"%@: %@", person[0], name]];
        [links addObject:url];
    }
    credit.text = [parts componentsJoinedByString:@", "];
    credit.linkTitles = titles;
    credit.links = links;
    return credit;
}

// Names the reply's shape and never its words.
static NSString *shapeOf(NSDictionary *body) {
    return [NSString stringWithFormat:@"Type=%@ source=%@ Content=%lu Lines=%lu", stringIn(body[@"Type"]) ?: @"-",
            stringIn(body[@"source"]) ?: @"-", (unsigned long)arrayIn(body[@"Content"]).count,
            (unsigned long)arrayIn(body[@"Lines"]).count];
}

// Not static, so harness/spicylyrics can feed it the documented shapes.
SGLyricsResult *SGSpicyLyricsResultFrom(NSDictionary *body);
SGLyricsResult *SGSpicyLyricsResultFrom(NSDictionary *body) {
    NSString *type = stringIn(body[@"Type"]);
    BOOL wordTimed = [type isEqualToString:@"Syllable"];
    NSArray<SGKaraokeLine *> *lines = wordTimed ? linesFromSyllables(arrayIn(body[@"Content"]))
        : [type isEqualToString:@"Line"] ? linesFromLines(arrayIn(body[@"Content"])) : nil;
    SGLyricsResult *result = [SGLyricsResult new];
    if (lines) {
        result.synced = YES;
        result.wordTimed = wordTimed;
        result.karaokeLines = lines;
        NSArray<NSNumber *> *starts;
        NSArray<NSString *> *texts;
        SGLyricsPageLines(lines, &starts, &texts);
        result.starts = starts;
        result.texts = texts;
    } else if ([type isEqualToString:@"Static"]) {
        NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        NSMutableArray<NSString *> *translations = [NSMutableArray array];
        for (id raw in arrayIn(body[@"Lines"]) ?: @[]) {
            NSDictionary *row = dictionaryIn(raw);
            NSString *text = stringIn(row[@"Text"]);
            if (!text) continue;
            [starts addObject:@0];
            [texts addObject:text.length ? text : @"♪"];
            if (text.length) [translations addObject:translationIn(row) ?: @""];
        }
        result.starts = starts;
        result.texts = texts;
        result.karaokeLines = SGKaraokeStaticLines(texts);
        // Static lines leave the breaks out, as the translations above do, so the two still pair up.
        if (result.karaokeLines.count == translations.count) {
            [result.karaokeLines enumerateObjectsUsingBlock:^(SGKaraokeLine *line, NSUInteger i, BOOL *stop) {
                addTranslation(line, @[translations[i]]);
            }];
        }
    }
    if (!result.texts.count) return nil;
    result.credit = creditFor(body);
    return result;
}

#pragma mark - the source

static void keep(NSString *trackID, SGLyricsResult *result) {
    if (sg_kept.count >= kKeptTracks) [sg_kept removeAllObjects];
    sg_kept[trackID] = result ?: (id)NSNull.null;
}

static BOOL isTrackID(NSString *trackID) {
    static NSCharacterSet *base62;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        base62 = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"];
    });
    return trackID.length == 22 && [trackID rangeOfCharacterFromSet:base62.invertedSet].location == NSNotFound;
}

// Waits out what a 429 or 503 says, and the rest of a window whose last request this was.
static void holdOffAsTold(NSHTTPURLResponse *response) {
    NSInteger status = response.statusCode;
    double retry = [[response valueForHTTPHeaderField:@"Retry-After"] doubleValue];
    double reset = [[response valueForHTTPHeaderField:@"RateLimit-Reset"] doubleValue];
    NSString *remaining = [response valueForHTTPHeaderField:@"RateLimit-Remaining"];
    NSTimeInterval wait = 0;
    if (status == 429 || status == 503) wait = retry > 0 ? retry : reset > 0 ? reset : kDefaultWait;
    else if (remaining.length && remaining.integerValue <= 0 && reset > 0) wait = reset;
    if (wait <= 0) return;
    wait = MIN(wait, kLongestWait);
    sg_notBefore = [NSDate dateWithTimeIntervalSinceNow:wait];
    SGLog(@"spicy: holding off for %.0fs after a %ld", wait, (long)status);
}

// A request not sent counts as one lost, so the walk does not keep the track as having no lyrics.
static void noteNotAsked(NSURL *url) {
    SGLyricsNoteReply([[NSHTTPURLResponse alloc] initWithURL:url statusCode:429 HTTPVersion:nil headerFields:nil], nil);
}

static SGLyricsResult *answer(NSString *trackID, NSString *key, id root, NSHTTPURLResponse *response) {
    NSInteger status = response.statusCode;
    if (response) holdOffAsTold(response);
    NSDictionary *body = dictionaryIn(dictionaryIn(root)[@"Body"]);
    NSString *code = stringIn(body[@"error"]);
    if (status == 401 || status == 403) {
        SGLog(@"spicy: the key was refused, %ld %@", (long)status, code ?: @"with no code");
        if ([key isEqualToString:storedKey()]) noteRefused(code);
        return nil;
    }
    if (status == 404 || status == 400) {
        noteAccepted();
        keep(trackID, nil);
        SGLog(@"spicy: nothing for %@", trackID);
        return nil;
    }
    if (status != 200) {
        SGLog(@"spicy: %@ answered %ld %@", trackID, (long)status, code ?: @"");
        return nil;
    }
    noteAccepted();
    SGLyricsResult *result = SGSpicyLyricsResultFrom(body);
    keep(trackID, result);
    SGLog(@"spicy: %@ came back as %@, %@", trackID, shapeOf(body), !result ? @"nothing the page could show"
          : [NSString stringWithFormat:@"%lu %@ lines", (unsigned long)result.texts.count,
             result.wordTimed ? @"word timed" : result.synced ? @"line timed" : @"untimed"]);
    return result;
}

SGLyricsAsk SGSpicyLyricsAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sg_kept = [NSMutableDictionary dictionary]; });
    NSString *trackID = query.trackID;
    NSString *key = storedKey();
    if (!key || !isTrackID(trackID)) {
        SGLog(@"spicy: nothing to ask with for %@%@", trackID, key ? @", not a Spotify track id" : @", no key set");
        done(nil);
        return;
    }
    id kept = sg_kept[trackID];
    if (kept) {
        done(kept == NSNull.null ? nil : kept);
        return;
    }
    if (sg_refusedAt && -sg_refusedAt.timeIntervalSinceNow < kRefusedPause) {
        SGLog(@"spicy: the key was refused %.0fs ago, %@ not asked", -sg_refusedAt.timeIntervalSinceNow, trackID);
        done(nil);
        return;
    }
    NSURL *url = [NSURL URLWithString:[kAPI stringByAppendingString:trackID]];
    if (sg_notBefore.timeIntervalSinceNow > 0) {
        SGLog(@"spicy: holding off %.0fs more, %@ not asked", sg_notBefore.timeIntervalSinceNow, trackID);
        noteNotAsked(url);
        done(nil);
        return;
    }
    NSDictionary<NSString *, NSString *> *headers = @{
        @"Authorization": [@"Bearer " stringByAppendingString:key],
        @"Accept": @"application/json",
        @"User-Agent": @"spoti.pw " @SG_VERSION @" (https://github.com/skopevoj/spoti.pw)",
    };
    SGLyricsGetJSONReply(url, headers, ^(id root, NSHTTPURLResponse *response) {
        done(answer(trackID, key, root, response));
    });
};
