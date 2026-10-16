// GeminiTranslate.h says what this is for.
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "GeminiTranslate.h"

NSNotificationName const SGGeminiKeyDidChangeNotification = @"spotifyglass.geminiKeyChanged";

static NSString *const kKeyKey = @"spotipw.gemini.key";
// Google's alias for its current Flash model, so the mod does not need a release when a model retires.
static NSString *const kEndpoint = @"https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent";
static const NSUInteger kMostLines = 400;
// After a refusal (a wrong key, a used up quota) nothing is asked for this long.
static const NSTimeInterval kRefusedWait = 10 * 60;

static NSString *sg_problem;
static NSDate *sg_refusedAt;
static NSCache<NSString *, NSArray<NSString *> *> *sg_answers;
static NSMutableSet<NSString *> *sg_asking;
// The line arrays already given their translations, so keeping them again does not ask again.
static NSHashTable<NSArray *> *sg_applied;

static NSString *storedKey(void) {
    NSString *key = [NSUserDefaults.standardUserDefaults stringForKey:kKeyKey];
    return key.length ? key : nil;
}

NSString *SGGeminiKeyShown(void) {
    NSString *key = storedKey();
    if (key.length <= 12) return key;
    return [NSString stringWithFormat:@"%@…%@", [key substringToIndex:4], [key substringFromIndex:key.length - 4]];
}

NSString *SGGeminiSetKey(NSString *text) {
    NSString *key = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"];
    if (key.length && (key.length < 30 || [key rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound)) {
        return @"That does not look like a Gemini API key. Make one at aistudio.google.com/apikey; it starts with AIza.";
    }
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (key.length) [store setObject:key forKey:kKeyKey];
    else [store removeObjectForKey:kKeyKey];
    sg_problem = nil;
    sg_refusedAt = nil;
    SGLog(@"gemini: key %@", key.length ? @"stored" : @"removed");
    [NSNotificationCenter.defaultCenter postNotificationName:SGGeminiKeyDidChangeNotification object:nil];
    return nil;
}

NSString *SGGeminiProblem(void) { return sg_problem; }

NSString *SGGeminiTargetLanguage(void) {
    NSString *tag = SGLyricsTranslationLanguage();
    if (tag.length) return tag;
    NSString *preferred = NSLocale.preferredLanguages.firstObject ?: @"en";
    NSString *language = [NSLocale localeWithLocaleIdentifier:preferred].languageCode;
    return language.length ? language : @"en";
}

static NSString *languageName(NSString *tag) {
    NSString *name = [[NSLocale localeWithLocaleIdentifier:@"en"] localizedStringForLocaleIdentifier:tag];
    return name.length ? name : tag;
}

// The lines to translate, one string each; nil for a song with nothing to translate.
static NSArray<NSString *> *textsOf(NSArray<SGKaraokeLine *> *lines) {
    if (!lines.count || lines.count > kMostLines) return nil;
    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:lines.count];
    NSUInteger words = 0;
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line) ?: @"";
        [texts addObject:text];
        if (text.length) words++;
    }
    return words ? texts : nil;
}

// Most of the lines have a translation already, from the source.
static BOOL alreadyTranslated(NSArray<SGKaraokeLine *> *lines) {
    NSUInteger have = 0, worded = 0;
    for (SGKaraokeLine *line in lines) {
        if (!SGKaraokeLineText(line).length) continue;
        worded++;
        if (line.translation.length) have++;
    }
    return worded && have * 2 >= worded;
}

static void apply(NSString *track, NSArray<SGKaraokeLine *> *lines, NSArray<NSString *> *translations) {
    if (translations.count != lines.count) return;
    NSUInteger given = 0;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *original = SGKaraokeLineText(lines[i]);
        NSString *translation = [translations[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        // A line already in the language reads the same, and a source shows no translation for it.
        if (!original.length || !translation.length || SGLyricsReadsSame(original, translation)) continue;
        lines[i].translation = translation;
        given++;
    }
    [sg_applied addObject:lines];
    SGLog(@"gemini: %lu of %lu lines of %@ translated", (unsigned long)given, (unsigned long)lines.count, track);
    if (given) SGKaraokeKeepLines(track, lines);
}

static NSString *prompt(NSArray<NSString *> *texts, NSString *language) {
    NSMutableString *list = [NSMutableString string];
    [texts enumerateObjectsUsingBlock:^(NSString *text, NSUInteger i, BOOL *stop) {
        [list appendFormat:@"%lu. %@\n", (unsigned long)i + 1, [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    }];
    return [NSString stringWithFormat:
        @"Translate these %lu numbered song lyric lines into %@. Keep the meaning and the tone of a song, one line "
         "for each line, in the same order. A line that is empty or only sounds (oh, la la) stays as it is, and a "
         "line already in %@ is returned unchanged. Answer with a JSON array of exactly %lu strings, the "
         "translations without their numbers, and nothing else.\n\n%@",
        (unsigned long)texts.count, languageName(language), languageName(language), (unsigned long)texts.count, list];
}

static NSArray<NSString *> *answerIn(NSData *data) {
    NSDictionary *reply = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![reply isKindOfClass:NSDictionary.class]) return nil;
    NSArray *candidates = reply[@"candidates"];
    NSDictionary *content = [candidates isKindOfClass:NSArray.class] && candidates.count ? candidates[0][@"content"] : nil;
    NSArray *parts = [content isKindOfClass:NSDictionary.class] ? content[@"parts"] : nil;
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *part in [parts isKindOfClass:NSArray.class] ? parts : @[]) {
        if ([part isKindOfClass:NSDictionary.class] && [part[@"text"] isKindOfClass:NSString.class]) [text appendString:part[@"text"]];
    }
    // The array alone, should the model wrap it in a code fence after all.
    NSRange open = [text rangeOfString:@"["], close = [text rangeOfString:@"]" options:NSBackwardsSearch];
    if (open.location == NSNotFound || close.location == NSNotFound || close.location < open.location) return nil;
    NSData *json = [[text substringWithRange:NSMakeRange(open.location, close.location - open.location + 1)] dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *array = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
    if (![array isKindOfClass:NSArray.class]) return nil;
    for (id item in array) if (![item isKindOfClass:NSString.class]) return nil;
    return array;
}

static NSString *refusal(NSInteger status, NSData *data) {
    NSDictionary *reply = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSString *message = [reply isKindOfClass:NSDictionary.class] && [reply[@"error"] isKindOfClass:NSDictionary.class]
        ? reply[@"error"][@"status"] : nil;
    if (status == 400 || status == 401 || status == 403) return [NSString stringWithFormat:@"Key rejected%@", message ? [@": " stringByAppendingString:message] : @""];
    if (status == 429) return @"Quota used up, try later";
    return nil;
}

// Main queue.
static void translate(NSString *track) {
    if (!track || !SGFlag(SGKeyLyricsGemini, NO)) return;
    NSString *key = storedKey();
    if (!key) return;
    if (sg_refusedAt && -sg_refusedAt.timeIntervalSinceNow < kRefusedWait) return;
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(track);
    if (!lines || [sg_applied containsObject:lines]) return;
    NSString *language = SGGeminiTargetLanguage();
    // The sources take their translation in the Lyrics page's language where they have one.
    if (alreadyTranslated(lines)) return;
    NSArray<NSString *> *texts = textsOf(lines);
    if (!texts) return;
    NSString *cacheKey = [NSString stringWithFormat:@"%@\n%@", language, [texts componentsJoinedByString:@"\n"]];
    NSArray<NSString *> *cached = [sg_answers objectForKey:cacheKey];
    if (cached) {
        apply(track, lines, cached);
        return;
    }
    if ([sg_asking containsObject:cacheKey]) return;
    [sg_asking addObject:cacheKey];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kEndpoint]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:key forHTTPHeaderField:@"x-goog-api-key"];
    NSDictionary *body = @{
        @"contents": @[@{@"role": @"user", @"parts": @[@{@"text": prompt(texts, language)}]}],
        @"generationConfig": @{@"responseMimeType": @"application/json", @"temperature": @0.2},
    };
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    SGLog(@"gemini: translating %lu lines of %@ into %@", (unsigned long)texts.count, track, language);
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSArray<NSString *> *answer = status == 200 ? answerIn(data) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [sg_asking removeObject:cacheKey];
            if (status != 200) {
                NSString *problem = refusal(status, data);
                if (problem) {
                    sg_problem = problem;
                    sg_refusedAt = NSDate.date;
                    [NSNotificationCenter.defaultCenter postNotificationName:SGGeminiKeyDidChangeNotification object:nil];
                }
                SGLog(@"gemini: HTTP %ld, %@", (long)status, error.localizedDescription ?: problem);
                return;
            }
            if (answer.count != texts.count) {
                SGLog(@"gemini: answered %lu lines for %lu, dropped", (unsigned long)answer.count, (unsigned long)texts.count);
                return;
            }
            sg_problem = nil;
            [sg_answers setObject:answer forKey:cacheKey];
            // The source may have handed over better lines meanwhile; those are asked about on their own.
            if (SGKaraokeLinesForTrack(track) == lines) apply(track, lines, answer);
        });
    }] resume];
}

void SGGeminiStart(void) {
    sg_answers = [NSCache new];
    sg_answers.countLimit = 50;
    sg_asking = [NSMutableSet set];
    sg_applied = [NSHashTable weakObjectsHashTable];
    [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:NSString.class]) translate(note.object);
    }];
    // A key or a switch set while a song plays translates it straight away.
    for (NSNotificationName name in @[SGGeminiKeyDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (!sg_problem) translate(SGKaraokePlayingTrack());
        }];
    }
}
