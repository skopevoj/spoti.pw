// Runs Shared/LyricsSources/SpicyLyrics.m against replies of the shapes the developer platform
// documents (fixtures/, placeholder words), and against the statuses it documents: the key refused,
// no lyrics, the rate limit.
#import "Core/SGCore.h"
#import "LyricsSources.h"

extern NSURL *sg_sentTo;
extern NSDictionary<NSString *, NSString *> *sg_sentHeaders;
extern NSUInteger sg_sentCount;
extern id sg_replyBody;
extern NSInteger sg_replyStatus;
extern NSDictionary<NSString *, NSString *> *sg_replyHeaders;
extern NSInteger sg_notedFailures;
extern NSString *sg_language;

SGLyricsResult *SGSpicyLyricsResultFrom(NSDictionary *body);

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("  %s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

static void checkEqual(id got, id want, NSString *what) {
    check(got == want || [got isEqual:want], [NSString stringWithFormat:@"%@ (got %@, want %@)", what, got, want]);
}

// build.sh runs it from fixtures/.
static NSDictionary *fixture(NSString *name) {
    NSData *data = [NSData dataWithContentsOfFile:[name stringByAppendingString:@".json"]];
    if (!data) {
        fprintf(stderr, "no fixtures/%s.json here; run ./build.sh\n", name.UTF8String);
        exit(2);
    }
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static NSDictionary *error(NSInteger status, NSString *code) {
    return @{@"Body": @{@"error": code, @"message": @"placeholder"}, @"Status": @(status), @"Type": @"object"};
}

static void reply(NSInteger status, id body, NSDictionary<NSString *, NSString *> *headers) {
    sg_replyStatus = status;
    sg_replyBody = body;
    sg_replyHeaders = headers;
}

static SGLyricsResult *ask(NSString *trackID) {
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = trackID;
    __block SGLyricsResult *answer = nil;
    __block BOOL called = NO;
    SGSpicyLyricsAsk(query, ^(SGLyricsResult *result) {
        answer = result;
        called = YES;
    });
    check(called, [NSString stringWithFormat:@"the source answered for %@", trackID]);
    return answer;
}

static NSString *words(SGKaraokeLine *line) {
    return SGKaraokeLineText(line);
}

int main(void) {
    @autoreleasepool {
        __block NSUInteger announced = 0;
        [NSNotificationCenter.defaultCenter addObserverForName:SGSpicyLyricsKeyDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { announced++; }];

        printf("with no key\n");
        reply(200, fixture(@"syllable-community"), nil);
        check(ask(@"HarnessTrack0000000001") == nil, @"nothing is answered");
        checkEqual(@(sg_sentCount), @0, @"and nothing is sent");
        checkEqual(SGSpicyLyricsProblem(), @"Needs a key", @"the row says it needs one");
        check(SGSpicyLyricsKeyShown() == nil, @"no key to show");

        printf("the key\n");
        check([SGSpicyLyricsSetKey(@"sl_sk_0123456789abcdef") containsString:@"secret"], @"a secret key is refused, saying why");
        check(SGSpicyLyricsSetKey(@"hello") != nil, @"something that is not a key is refused");
        check(SGSpicyLyricsSetKey(@"sl_pk_0123 456789abcdef") != nil, @"a key with a space inside is refused");
        checkEqual(@(announced), @0, @"nothing refused is announced");
        check(SGSpicyLyricsSetKey(@"  sl_pk_0123456789abcdef\n") == nil, @"a publishable key is stored, pasted with whitespace");
        checkEqual(@(announced), @1, @"and announced");
        checkEqual(SGSpicyLyricsKeyShown(), @"sl_pk_…cdef", @"only its ends are shown");
        check(SGSpicyLyricsProblem() == nil, @"no problem once it is set");

        printf("a community sync, timed by the syllable\n");
        NSInteger failuresBefore = sg_notedFailures;
        SGLyricsResult *result = ask(@"HarnessTrack0000000001");
        checkEqual(sg_sentTo.absoluteString, @"https://api.spicylyrics.org/v1/lyrics/HarnessTrack0000000001", @"the address");
        checkEqual(sg_sentHeaders[@"Authorization"], @"Bearer sl_pk_0123456789abcdef", @"the key as a bearer");
        check(!sg_sentHeaders[@"Origin"] && !sg_sentHeaders[@"Referer"], @"no origin, which the key's No origin header entry allows");
        checkEqual(@(sg_sentHeaders.count), @3, @"nothing else of the account: Authorization, Accept, User-Agent");
        check(result.synced && result.wordTimed, @"synced and word timed");
        checkEqual(@(result.karaokeLines.count), @3, @"three lines");
        SGKaraokeLine *first = result.karaokeLines.firstObject;
        checkEqual(@(first.start), @1500, @"the line starts at its own StartTime, in ms");
        checkEqual(@(first.end), @4250, @"and ends at its EndTime");
        checkEqual(words(first), @"alpha bravo", @"syllables of one word run together, words apart");
        checkEqual(@(first.words.count), @3, @"a word per syllable");
        check(first.words[1].joined && !first.words[2].joined, @"IsPartOfWord joins the next syllable to it");
        checkEqual(@(first.words[1].end), @2401, @"a fractional second lands on the right ms");
        checkEqual(words(first.backing), @"(echo foxtrot)", @"the backing vocals hang off the line");
        checkEqual(@(first.backing.start), @3000, @"timed by their own syllables");
        checkEqual(words(first.pronunciation), @"arfa burabo", @"the pronunciation from each syllable's romanisation");
        checkEqual(@(first.pronunciation.words[1].start), @1900, @"on the syllables' times");
        checkEqual(first.translation, @"charlie delta", @"the translation, with the Lyrics page on Any");
        SGKaraokeLine *second = result.karaokeLines[1], *third = result.karaokeLines[2];
        checkEqual(@(second.align), @(SGKaraokeAlignTrailing), @"OppositeAligned puts the line on the far side");
        checkEqual(@(first.align), @(SGKaraokeAlignLeading), @"the first voice leads");
        check(second.backing == nil && second.pronunciation == nil && second.translation == nil, @"a bare line has nothing added");
        check(third.start < second.end, @"a line sung over another keeps its own times");
        checkEqual(@(result.texts.count), @3, @"the page gets a line for each");
        checkEqual(result.texts.firstObject, @"alpha bravo (echo foxtrot)", @"with the backing on the same row");
        SGLyricsCredit *credit = result.credit;
        checkEqual(credit.text, @"Spicy Lyrics, uploaded by uploader-one, made by maker-two", @"credited to both");
        checkEqual(credit.links, (@[[NSURL URLWithString:@"https://spicylyrics.org/uid/1"], [NSURL URLWithString:@"https://spicylyrics.org/uid/2"]]), @"each linked to their url");
        checkEqual(credit.linkTitles, (@[@"Uploader: uploader-one", @"Maker: maker-two"]), @"the links named");
        check(credit.required, @"and shown whatever Show source says");
        checkEqual(@(sg_notedFailures), @(failuresBefore), @"a 200 is no failure");
        NSUInteger sent = sg_sentCount;
        check(ask(@"HarnessTrack0000000001") == result, @"asked again, the kept answer");
        checkEqual(@(sg_sentCount), @(sent), @"without a request");

        printf("a translation in another language than the one asked for\n");
        sg_language = @"cs";
        SGLyricsResult *strict = SGSpicyLyricsResultFrom(fixture(@"syllable-community")[@"Body"]);
        check(strict.karaokeLines.firstObject.translation == nil, @"is left out: the API does not name its language");
        sg_language = nil;

        printf("Apple Music's, passed on\n");
        result = SGSpicyLyricsResultFrom(fixture(@"syllable-apple")[@"Body"]);
        checkEqual(result.credit.text, @"Apple Music via Spicy Lyrics", @"the catalogue named");
        checkEqual(@(result.credit.links.count), @0, @"no one to link");
        check(result.credit.required, @"still shown");

        printf("Spotify's, timed by the line\n");
        result = SGSpicyLyricsResultFrom(fixture(@"line-spotify")[@"Body"]);
        check(result.synced && !result.wordTimed, @"synced but not word timed");
        checkEqual(@(result.karaokeLines.count), @2, @"two lines");
        SGKaraokeLine *line = result.karaokeLines.firstObject;
        checkEqual(@(line.start), @2000, @"each line at its own start");
        checkEqual(@(line.end), @4500, @"and its own end");
        checkEqual(@(line.timing), @(SGKaraokeTimingLine), @"its words estimated");
        checkEqual(words(line), @"juliett kilo", @"the text");
        checkEqual(line.translation, @"lima", @"its translation");
        checkEqual(@(result.karaokeLines[1].align), @(SGKaraokeAlignTrailing), @"OppositeAligned here too");
        checkEqual(words(result.karaokeLines[1]), @"mike november (oscar)", @"the backing already in the text");
        checkEqual(result.credit.text, @"Spotify via Spicy Lyrics", @"the catalogue named");

        printf("a community sync with no distinct maker\n");
        result = SGSpicyLyricsResultFrom(fixture(@"line-community-uploader")[@"Body"]);
        checkEqual(result.credit.text, @"Spicy Lyrics, uploaded by uploader-three", @"the uploader alone, no empty maker");
        checkEqual(@(result.credit.links.count), @1, @"one link");

        printf("plain text from a source it does not name\n");
        result = SGSpicyLyricsResultFrom(fixture(@"static-unknown")[@"Body"]);
        check(!result.synced, @"not synced");
        checkEqual(result.texts, (@[@"papa", @"♪", @"quebec"]), @"the words, a break for the empty line");
        checkEqual(result.starts, (@[@0, @0, @0]), @"every start zero");
        checkEqual(@(result.karaokeLines.count), @2, @"two lines to show");
        checkEqual(@(SGKaraokeLinesTiming(result.karaokeLines)), @(SGKaraokeTimingNone), @"untimed");
        checkEqual(result.karaokeLines[1].translation, @"romeo", @"a translation stays with its line past the break");
        checkEqual(result.credit.text, @"Spicy Lyrics, source unknown", @"the source said to be unknown");

        printf("replies that are no lyrics\n");
        check(SGSpicyLyricsResultFrom(@{@"Type": @"Syllable", @"Content": @[]}) == nil, @"no lines");
        check(SGSpicyLyricsResultFrom(@{@"Type": @"Karaoke"}) == nil, @"a shape it does not know");
        check(SGSpicyLyricsResultFrom(@{@"Type": @"Line", @"Content": @[@"not a line", @{@"Text": @7}]}) == nil, @"lines of the wrong types");
        reply(200, @[@"not", @"an", @"envelope"], nil);
        check(ask(@"HarnessTrack0000000006") == nil, @"a body that is not the envelope");

        printf("a track id that is not Spotify's\n");
        sent = sg_sentCount;
        check(ask(@"local:track") == nil, @"nothing");
        checkEqual(@(sg_sentCount), @(sent), @"and nothing sent");

        printf("no lyrics for the track\n");
        failuresBefore = sg_notedFailures;
        reply(404, error(404, @"lyrics_not_found"), nil);
        check(ask(@"HarnessTrack0000000007") == nil, @"nothing");
        checkEqual(@(sg_notedFailures), @(failuresBefore), @"which is an answer, not a failure");
        sent = sg_sentCount;
        ask(@"HarnessTrack0000000007");
        checkEqual(@(sg_sentCount), @(sent), @"and kept");

        printf("the key refused\n");
        announced = 0;
        reply(403, error(403, @"origin_not_allowed"), nil);
        check(ask(@"HarnessTrack0000000008") == nil, @"nothing");
        checkEqual(SGSpicyLyricsProblem(), @"Key rejected: allow No origin header", @"the row says what to change");
        checkEqual(@(announced), @1, @"and the page is told");
        sent = sg_sentCount;
        reply(200, fixture(@"syllable-apple"), nil);
        check(ask(@"HarnessTrack0000000009") == nil, @"the next track is not asked for with it");
        checkEqual(@(sg_sentCount), @(sent), @"nothing sent");
        check(SGSpicyLyricsSetKey(@"sl_pk_fedcba9876543210") == nil, @"a new key");
        check(SGSpicyLyricsProblem() == nil, @"clears the refusal");
        check(ask(@"HarnessTrack0000000009") != nil, @"and is asked with at once");
        reply(401, error(401, @"key_revoked"), nil);
        ask(@"HarnessTrack0000000010");
        checkEqual(SGSpicyLyricsProblem(), @"Key rejected: revoked", @"a revoked key");
        SGSpicyLyricsSetKey(@"sl_pk_0123456789abcdef");
        reply(401, error(401, @"key_not_found"), nil);
        ask(@"HarnessTrack0000000011");
        checkEqual(SGSpicyLyricsProblem(), @"Key rejected: not found", @"an unknown key");
        SGSpicyLyricsSetKey(@"sl_pk_0123456789abcdef");

        printf("the rate limit\n");
        failuresBefore = sg_notedFailures;
        reply(429, error(429, @"rate_limited"), @{@"Retry-After": @"1", @"RateLimit-Limit": @"60", @"RateLimit-Remaining": @"0", @"RateLimit-Reset": @"1"});
        check(ask(@"HarnessTrack0000000012") == nil, @"a 429 is nothing");
        checkEqual(@(sg_notedFailures), @(failuresBefore + 1), @"and a failure, so the walk asks again later");
        sent = sg_sentCount;
        reply(200, fixture(@"syllable-apple"), nil);
        check(ask(@"HarnessTrack0000000013") == nil, @"within Retry-After nothing is asked");
        checkEqual(@(sg_sentCount), @(sent), @"nothing sent");
        checkEqual(@(sg_notedFailures), @(failuresBefore + 2), @"which counts as lost too");
        [NSThread sleepForTimeInterval:1.1];
        check(ask(@"HarnessTrack0000000013") != nil, @"after it, asked again");
        reply(200, fixture(@"syllable-apple"), @{@"RateLimit-Remaining": @"0", @"RateLimit-Reset": @"1"});
        check(ask(@"HarnessTrack0000000014") != nil, @"the window's last request answers");
        sent = sg_sentCount;
        check(ask(@"HarnessTrack0000000015") == nil, @"and the next waits for the window to reset");
        checkEqual(@(sg_sentCount), @(sent), @"nothing sent");
        [NSThread sleepForTimeInterval:1.1];

        printf("busy\n");
        reply(503, error(503, @"server_busy"), nil);
        check(ask(@"HarnessTrack0000000016") == nil, @"a 503 is nothing");
        sent = sg_sentCount;
        reply(200, fixture(@"syllable-apple"), nil);
        check(ask(@"HarnessTrack0000000017") == nil, @"without a Retry-After it still waits");
        checkEqual(@(sg_sentCount), @(sent), @"nothing sent");

        printf("the key removed\n");
        check(SGSpicyLyricsSetKey(@"") == nil, @"an empty key removes it");
        checkEqual(SGSpicyLyricsProblem(), @"Needs a key", @"and the row says so");

        printf("\n%s\n", failures ? [NSString stringWithFormat:@"%d failed", failures].UTF8String : "all passed");
        return failures ? 1 : 0;
    }
}
