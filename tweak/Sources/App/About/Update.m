// The repo's GitHub Releases, so a build that is already on someone's phone can tell them a newer one
// exists and show what changed in it. Release Please cuts every release from the commits, so the
// release body is the changelog itself: a "### Features" or "### Fixes" heading over a line per
// commit, each ending in a link to it. One request brings the last twenty releases rather than only
// the newest, which is what lets the Updates page show every version between this build and the
// newest one. Asked a few seconds after Spotify comes up (UpdateNotice.m) and when Mod Settings
// opens, at most once every six hours either way, and on demand from the page. spoti.pw is asked
// first and hands on GitHub's list; the request carries Usage.m's body. GitHub itself is the fallback.
#import "Core/SGCore.h"
#import "About.h"

NSString *const SGUpdateURL = @"https://spoti.pw/api/update";
static NSString *const kGitHubURL = @"https://api.github.com/repos/skopevoj/spoti.pw/releases?per_page=100";
NSString *const SGUpdateCheckedNotification = @"spotifyglass.update.checked.notification";

static NSString *const kChecked = @"spotifyglass.update.checked";
static NSString *const kReleases = @"spotifyglass.update.releases";
static const NSTimeInterval kInterval = 6 * 60 * 60;
static const NSUInteger kKept = 20;

static NSString *sg_failure;
static BOOL sg_running;

@implementation SGUpdateChange
@end

@implementation SGUpdateRelease
@end

// "0.14.1" against "0.15": the numbers position by position, a missing one counting zero. A beta
// ("0.23.0-beta.2") is newer than the release before it and older than its own.
static BOOL isNewer(NSString *candidate, NSString *current) {
    NSArray<NSString *> *candidateParts = [candidate componentsSeparatedByString:@"-"];
    NSArray<NSString *> *currentParts = [current componentsSeparatedByString:@"-"];
    NSArray<NSString *> *left = [candidateParts.firstObject componentsSeparatedByString:@"."];
    NSArray<NSString *> *right = [currentParts.firstObject componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(left.count, right.count); i++) {
        NSInteger a = i < left.count ? left[i].integerValue : 0;
        NSInteger b = i < right.count ? right[i].integerValue : 0;
        if (a != b) return a > b;
    }
    if (candidateParts.count == 1 || currentParts.count == 1) return candidateParts.count < currentParts.count;
    return [candidateParts[1] compare:currentParts[1] options:NSNumericSearch] == NSOrderedDescending;
}

// A beta build is told about betas as well as releases; a release build only ever about releases.
static BOOL isBetaBuild(void) {
    return strchr(SG_VERSION, '-') != NULL;
}

static NSString *stringOr(id value, NSString *fallback) {
    return [value isKindOfClass:NSString.class] ? value : fallback;
}

#pragma mark - the changelog out of the release's markdown

// "[the text](https://…)" is left as its text, and what release-please writes around a scope --
// "**player:** …" -- loses its stars. Nothing else in a body of its is markup.
static NSString *plainText(NSString *markdown) {
    static NSRegularExpression *link;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        link = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]*)\\]\\([^)]*\\)" options:0 error:NULL];
    });
    NSString *text = [link stringByReplacingMatchesInString:markdown options:0
                                                      range:NSMakeRange(0, markdown.length) withTemplate:@"$1"];
    text = [text stringByReplacingOccurrencesOfString:@"**" withString:@""];
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// The commit a line ends with -- " ([4b63f35](https://github.com/…/commit/4b63f35…))" -- taken off the
// text and kept as the line's link. A line written by hand has none and keeps all of itself.
static NSString *takeCommitURL(NSString **line) {
    static NSRegularExpression *trailer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        trailer = [NSRegularExpression regularExpressionWithPattern:@"\\s*\\(\\[[0-9a-f]{6,}\\]\\(([^)]+)\\)\\)\\s*$" options:0 error:NULL];
    });
    NSString *text = *line;
    NSTextCheckingResult *match = [trailer firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) return nil;
    *line = [text substringToIndex:match.range.location];
    return [text substringWithRange:[match rangeAtIndex:1]];
}

// A release body into its lines: "### Features" names what follows, "* …" is a line of it, and a
// line that wraps onto the next one is joined back together. Anything else -- the "## [0.19.0](…)"
// heading release-please leads with, blank lines -- is dropped, the version being known already.
static NSArray<SGUpdateChange *> *changesIn(NSString *body) {
    NSMutableArray<SGUpdateChange *> *changes = [NSMutableArray array];
    NSString *kind = @"Changes";
    SGUpdateChange *open = nil;
    for (NSString *raw in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([line hasPrefix:@"###"]) {
            kind = plainText([line stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# "]]);
            open = nil;
        } else if ([line hasPrefix:@"* "] || [line hasPrefix:@"- "]) {
            NSString *text = [line substringFromIndex:2];
            NSString *url = takeCommitURL(&text);
            text = plainText(text);
            if (!text.length) { open = nil; continue; }
            open = [SGUpdateChange new];
            open.kind = kind;
            open.text = text;
            open.url = url;
            [changes addObject:open];
        } else if (line.length && ![line hasPrefix:@"#"] && open) {
            // A line too long for one, wrapped by whoever edited the release by hand.
            NSString *text = line;
            NSString *url = takeCommitURL(&text);
            open.text = [open.text stringByAppendingFormat:@" %@", plainText(text)];
            if (url) open.url = url;
        } else {
            open = nil;
        }
    }
    return changes;
}

#pragma mark - what the last check left

NSArray<SGUpdateRelease *> *SGUpdateReleases(void) {
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:kReleases];
    NSMutableArray<SGUpdateRelease *> *releases = [NSMutableArray array];
    for (id entry in stored) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *version = stringOr(entry[@"version"], nil);
        if (!version.length) continue;
        // A list a beta build left behind, read by the release installed over it.
        if ([entry[@"prerelease"] boolValue] && !isBetaBuild()) continue;
        SGUpdateRelease *release = [SGUpdateRelease new];
        release.version = version;
        release.date = stringOr(entry[@"date"], @"");
        release.url = stringOr(entry[@"url"], nil);
        release.changes = changesIn(stringOr(entry[@"notes"], @""));
        [releases addObject:release];
    }
    return releases;
}

SGUpdateRelease *SGUpdateNewestRelease(void) {
    return SGUpdateReleases().firstObject;
}

BOOL SGUpdateIsNewer(NSString *version) {
    return version.length && isNewer(version, @(SG_VERSION));
}

NSString *SGUpdateVersion(void) {
    NSString *newest = SGUpdateNewestRelease().version;
    return SGUpdateIsNewer(newest) ? newest : nil;
}

// What the Updates row shows on the right; the page's own ticker reads it while the page is open,
// so the async check lands in the cell without anything having to be told about it.
NSString *SGUpdateStatus(void) {
    if (sg_running) return @"checking…";
    if (sg_failure) return sg_failure;
    NSString *latest = SGUpdateVersion();
    if (latest) return [latest stringByAppendingString:@" is out"];
    if ([NSUserDefaults.standardUserDefaults doubleForKey:kChecked] > 0) return @"up to date";
    return @"not checked";
}

#pragma mark - the check

// Drafts are not builds anyone is meant to be sent to, and pre-releases (the betas) only beta builds
// are, so otherwise they count for neither the newest version nor the changelog. GitHub answers newest
// first; the sort keeps that true whatever order a hand-made release lands in.
static NSArray<NSDictionary *> *releasesFrom(NSData *data) {
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![json isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (id item in (NSArray *)json) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *release = item;
        BOOL prerelease = [release[@"prerelease"] boolValue];
        if ([release[@"draft"] boolValue] || (prerelease && !isBetaBuild())) continue;
        NSString *tag = stringOr(release[@"tag_name"], nil);
        if (!tag.length) continue;
        [entries addObject:@{
            @"version": [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag,
            @"notes": stringOr(release[@"body"], @""),
            @"date": stringOr(release[@"published_at"], @""),
            @"url": stringOr(release[@"html_url"], @""),
            @"prerelease": @(prerelease),
        }];
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return isNewer(a[@"version"], b[@"version"]) ? NSOrderedAscending : NSOrderedDescending;
    }];
    if (entries.count > kKept) [entries removeObjectsInRange:NSMakeRange(kKept, entries.count - kKept)];
    return entries.count ? entries : nil;
}

static void ask(NSString *url, NSData *body, void (^done)(NSArray<NSDictionary *> *releases, NSInteger status, NSError *error)) {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 10;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    if (body) {
        request.HTTPMethod = @"POST";
        request.HTTPBody = body;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    NSURLSessionDataTask *task = [[NSURLSession sessionWithConfiguration:configuration]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        done(status == 200 ? releasesFrom(data) : nil, status, error);
    }];
    [task resume];
}

void SGCheckForUpdate(BOOL force) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSTimeInterval last = [store doubleForKey:kChecked];
    if (sg_running) return;
    // The day's count goes out with the first check of the day, whatever the six hours say.
    BOOL owed = SGUsageOwed();
    if (!force && !owed && last > 0 && NSDate.date.timeIntervalSince1970 - last < kInterval) return;

    sg_running = YES;
    sg_failure = nil;
    void (^finish)(NSArray<NSDictionary *> *, NSInteger, NSError *) = ^(NSArray<NSDictionary *> *releases, NSInteger status, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_running = NO;
            if (!releases) {
                // Unauthenticated GitHub allows sixty requests an hour per address; a phone behind a
                // carrier NAT can be told to wait, and that is worth reading apart from a dead network.
                sg_failure = status == 403 || status == 429 ? @"asked too often" : @"check failed";
                SGLog(@"update check failed: HTTP %ld, %@", (long)status,
                      error.localizedDescription ?: @"no release in the reply");
            } else {
                [store setObject:releases forKey:kReleases];
                [store setDouble:NSDate.date.timeIntervalSince1970 forKey:kChecked];
                SGLog(@"update check: the newest is %@, this build is %s", releases.firstObject[@"version"], SG_VERSION);
            }
            [NSNotificationCenter.defaultCenter postNotificationName:SGUpdateCheckedNotification object:nil];
        });
    };
    NSData *body = SGUsageBody();
    if (body) SGUsageNoteAsked();
    SGLog(@"update check: asking spoti.pw %@", body ? @"with the usage body" : @"without the usage body");
    ask(SGUpdateURL, body, ^(NSArray<NSDictionary *> *releases, NSInteger status, NSError *error) {
        if (releases) return finish(releases, status, error);
        SGLog(@"update check: spoti.pw answered HTTP %ld, asking GitHub", (long)status);
        ask(kGitHubURL, nil, finish);
    });
}
