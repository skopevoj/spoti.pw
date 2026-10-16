// Lyrics.h says what this does. Two passes, one request out at a time:
//
// Listing: the Web API's pages of Liked Songs (/v1/me/tracks), and with playlists asked for, the library's
// playlists (/v1/me/playlists) and each one's songs, followed page by page through their `next`. Every song
// with a Spotify id that is not saved already goes on the list once.
//
// Fetching: each song in turn is named for the sources that search by name, then asked the way a song that
// plays is (KaraokeSource.x): the mod's sources first when one is on, Spotify's own color-lyrics after them
// when what they found is not timed, or Spotify's alone. The best timed lines are written to the phone.
//
// A refused sign-in is waited out (Spotify's next request brings a fresh token), a 429 its Retry-After, and
// a lost connection the app coming back, since iOS stops the requests of an app it has put away.
#import "Core/SGCore.h"
#import "Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"

NSNotificationName const SGLyricsDownloadDidChangeNotification = @"spotifyglass.lyricsDownloadDidChange";

// Between one song and the next, and the most a 429 is waited out for.
static const NSTimeInterval kPace = 0.35, kMostBackoff = 60;
// A refused sign-in or a lost request is tried again this many times in a row before the run stops or
// the song is passed over.
static const NSUInteger kMostTries = 5;
// How long the run waits for Spotify to have signed in at all.
static const NSTimeInterval kSignInWait = 20;

typedef NS_ENUM(NSInteger, SGPageKind) {
    SGPageLiked,       // /v1/me/tracks: items[].track
    SGPagePlaylists,   // /v1/me/playlists: items[] are playlists
    SGPagePlaylist,    // a playlist's songs: items[].track, or items[].item in the newer naming
};

static BOOL sg_running, sg_listing, sg_waitingForApp;
// Bumped by every start and stop, so the answers of a run that is over do nothing.
static NSUInteger sg_run;
static SGLyricsDownloadScope sg_scope;
// Pages still to read, as [kind, address].
static NSMutableArray<NSArray *> *sg_pages;
static NSMutableArray<NSDictionary *> *sg_songs;
static NSMutableSet<NSString *> *sg_listed;
static NSUInteger sg_next, sg_saved, sg_none, sg_already, sg_tries;
static NSString *sg_message;
static void (^sg_resume)(void);

static void changed(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsDownloadDidChangeNotification object:nil];
}

static NSString *formatted(NSUInteger number) {
    return [NSNumberFormatter localizedStringFromNumber:@(number) numberStyle:NSNumberFormatterDecimalStyle];
}

static void finish(NSString *message) {
    sg_running = NO;
    sg_listing = NO;
    sg_waitingForApp = NO;
    sg_resume = nil;
    sg_run++;
    sg_message = message;
    SGLog(@"lyrics download: %@", message);
    changed();
}

static void after(NSTimeInterval seconds, void (^block)(void)) {
    NSUInteger run = sg_run;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_running && run == sg_run) block();
    });
}

// A request that did not get through: with the app put away, it waits for the app to come back; in front,
// it is tried again a few seconds later, `giveUp` once it has failed kMostTries times in a row.
static void lost(void (^again)(void), void (^giveUp)(void)) {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        sg_waitingForApp = YES;
        sg_resume = again;
        changed();
        return;
    }
    if (++sg_tries >= kMostTries) {
        sg_tries = 0;
        giveUp();
        return;
    }
    after(3 * sg_tries, again);
}

static NSTimeInterval retryAfter(NSHTTPURLResponse *response) {
    NSTimeInterval seconds = [[response valueForHTTPHeaderField:@"Retry-After"] doubleValue];
    return MIN(MAX(seconds, 5), kMostBackoff);
}

#pragma mark - the Web API

// GET with the app's sign-in; answers on the main queue of the run that asked, with the JSON and the status.
static void getJSON(NSString *address, void (^done)(id json, NSHTTPURLResponse *response, NSError *error)) {
    NSString *authorization = SGKaraokeSpotifyAuthorization();
    NSURL *url = [NSURL URLWithString:address];
    if (!authorization || !url) {
        done(nil, nil, nil);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:authorization forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    NSUInteger run = sg_run;
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (sg_running && run == sg_run) done(json, http, error);
        });
    }] resume];
}

static id field(id object, NSString *key) {
    return [object isKindOfClass:NSDictionary.class] ? object[key] : nil;
}

// A song as the list keeps it, nil for a local file, an episode or anything without an id.
static NSDictionary *songFrom(id track) {
    NSString *trackID = field(track, @"id");
    id type = field(track, @"type");
    if (![trackID isKindOfClass:NSString.class] || !trackID.length || [field(track, @"is_local") boolValue]) return nil;
    if ([type isKindOfClass:NSString.class] && ![type isEqualToString:@"track"]) return nil;
    NSMutableArray<NSString *> *artists = [NSMutableArray array];
    for (id artist in [field(track, @"artists") isKindOfClass:NSArray.class] ? field(track, @"artists") : @[]) {
        NSString *name = field(artist, @"name");
        if ([name isKindOfClass:NSString.class] && name.length) [artists addObject:name];
    }
    NSString *title = field(track, @"name"), *album = field(field(track, @"album"), @"name");
    NSNumber *length = field(track, @"duration_ms");
    return @{
        @"id": trackID,
        @"title": [title isKindOfClass:NSString.class] ? title : @"",
        @"artist": [artists componentsJoinedByString:@", "],
        @"album": [album isKindOfClass:NSString.class] ? album : @"",
        @"seconds": @([length isKindOfClass:NSNumber.class] ? length.integerValue / 1000 : 0),
    };
}

static void addSong(NSDictionary *song) {
    if (!song || [sg_listed containsObject:song[@"id"]]) return;
    [sg_listed addObject:song[@"id"]];
    if (SGLyricsOfflineHas(song[@"id"])) {
        sg_already++;
        return;
    }
    [sg_songs addObject:song];
}

static void fetchNext(void);

static void listNext(void) {
    if (!sg_pages.count) {
        sg_listing = NO;
        sg_tries = 0;
        SGLog(@"lyrics download: %lu songs to fetch, %lu already saved", (unsigned long)sg_songs.count, (unsigned long)sg_already);
        changed();
        fetchNext();
        return;
    }
    NSArray *page = sg_pages.firstObject;
    SGPageKind kind = [page[0] integerValue];
    NSString *address = page[1];
    getJSON(address, ^(id json, NSHTTPURLResponse *response, NSError *error) {
        NSInteger status = response.statusCode;
        if (status == 429) {
            after(retryAfter(response), ^{ listNext(); });
            return;
        }
        if (status == 401 || !response) {
            lost(^{ listNext(); }, ^{ finish(@"Spotify's sign-in was refused. Play a song and try again."); });
            return;
        }
        // A playlist whose songs the old address no longer gives: the newer one.
        if (kind == SGPagePlaylist && (status == 404 || status == 410) && [address containsString:@"/tracks"]) {
            sg_pages[0] = @[@(SGPagePlaylist), [address stringByReplacingOccurrencesOfString:@"/tracks" withString:@"/items"]];
            listNext();
            return;
        }
        [sg_pages removeObjectAtIndex:0];
        sg_tries = 0;
        if (status < 200 || status >= 300) {
            // A playlist that cannot be read (Spotify's own mixes, a removed one) is passed over.
            SGLog(@"lyrics download: %@ -> HTTP %ld, passed over", address, (long)status);
            listNext();
            return;
        }
        NSArray *items = [field(json, @"items") isKindOfClass:NSArray.class] ? field(json, @"items") : @[];
        for (id item in items) {
            if (kind == SGPagePlaylists) {
                NSString *playlist = field(item, @"id");
                if ([playlist isKindOfClass:NSString.class] && playlist.length) {
                    [sg_pages addObject:@[@(SGPagePlaylist), [NSString stringWithFormat:@"https://api.spotify.com/v1/playlists/%@/tracks?limit=100", playlist]]];
                }
                continue;
            }
            addSong(songFrom(field(item, @"track") ?: field(item, @"item")));
        }
        NSString *next = field(json, @"next");
        if ([next isKindOfClass:NSString.class] && next.length) [sg_pages insertObject:@[@(kind), next] atIndex:0];
        changed();
        listNext();
    });
}

#pragma mark - one song's lyrics

// Spotify's own color-lyrics for the song, asked with the headers of Spotify's own requests.
static void askSpotify(NSString *trackID, void (^done)(NSArray<SGKaraokeLine *> *lines, NSHTTPURLResponse *response, NSError *error)) {
    NSDictionary<NSString *, NSString *> *headers = SGKaraokeSpotifyHeaders();
    if (!headers) {
        done(nil, nil, nil);
        return;
    }
    NSString *address = [NSString stringWithFormat:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/%@?format=json&vocalRemoval=false&market=from_token", trackID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:address]];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:name];
    }];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    // The mod's own, so LyricsHook's request hook leaves it alone.
    [NSURLProtocol setProperty:@YES forKey:SGLyricsOwnRequestKey inRequest:request];
    NSUInteger run = sg_run;
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *body, NSURLResponse *response, NSError *error) {
        NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesFromBody(body);
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (sg_running && run == sg_run) done(http.statusCode >= 200 && http.statusCode < 300 ? lines : nil, http, error);
        });
    }] resume];
}

static void saveSong(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *credit) {
    if (lines.count) {
        SGLyricsOfflineStore(trackID, lines, credit);
        sg_saved++;
    } else {
        sg_none++;
    }
    sg_next++;
    sg_tries = 0;
    changed();
    after(kPace, ^{ fetchNext(); });
}

// Spotify's answer for a song the sources gave `found` for (nil for nothing): its lines are taken only when
// they are timed more finely, as the lyrics view takes them.
static void finishWithSpotify(NSString *trackID, NSArray<SGKaraokeLine *> *found, NSString *credit) {
    askSpotify(trackID, ^(NSArray<SGKaraokeLine *> *lines, NSHTTPURLResponse *response, NSError *error) {
        NSInteger status = response.statusCode;
        if (status == 429) {
            after(retryAfter(response), ^{ finishWithSpotify(trackID, found, credit); });
            return;
        }
        // No headers yet, a refused sign-in or a lost request: tried again, and in the end the song keeps
        // what the sources found.
        if (status == 401 || status == 403 || (!response && SGKaraokeSpotifyHeaders())) {
            lost(^{ finishWithSpotify(trackID, found, credit); }, ^{ saveSong(trackID, found, credit); });
            return;
        }
        if (lines.count && (!found.count || SGKaraokeLinesTiming(lines) < SGKaraokeLinesTiming(found))) {
            saveSong(trackID, lines, @"Spotify");
            return;
        }
        saveSong(trackID, found, credit);
    });
}

static void fetchNext(void) {
    if (sg_next >= sg_songs.count) {
        NSMutableString *message = [NSMutableString stringWithFormat:@"Done · %@ saved", formatted(sg_saved)];
        if (sg_none) [message appendFormat:@", %@ without lyrics", formatted(sg_none)];
        if (sg_already) [message appendFormat:@", %@ already saved", formatted(sg_already)];
        finish(message);
        return;
    }
    NSDictionary *song = sg_songs[sg_next];
    NSString *trackID = song[@"id"];
    // Played meanwhile and saved by the engine.
    if (SGLyricsOfflineHas(trackID)) {
        sg_already++;
        sg_next++;
        changed();
        fetchNext();
        return;
    }
    if (!SGLyricsActive()) {
        finishWithSpotify(trackID, nil, nil);
        return;
    }
    SGLyricsNameTrack(trackID, song[@"title"], song[@"artist"], song[@"album"], [song[@"seconds"] integerValue]);
    NSUInteger run = sg_run;
    SGLyricsFetch(trackID, ^(SGLyricsResult *result) {
        if (!sg_running || run != sg_run) return;
        NSArray<SGKaraokeLine *> *lines = result.karaokeLines;
        NSString *credit = !result ? nil : result.credit.text ?: SGLyricsProviderFor(result.provider).name;
        if (lines.count && SGKaraokeLinesTiming(lines) != SGKaraokeTimingNone) {
            saveSong(trackID, lines, credit);
            return;
        }
        finishWithSpotify(trackID, lines, credit);
    });
}

#pragma mark - starting and stopping

static void begin(NSUInteger waited) {
    if (!SGKaraokeSpotifyAuthorization()) {
        if (waited >= kSignInWait) {
            finish(@"Spotify has not signed in yet. Play a song and try again.");
            return;
        }
        after(1, ^{ begin(waited + 1); });
        return;
    }
    sg_pages = [NSMutableArray arrayWithObject:@[@(SGPageLiked), @"https://api.spotify.com/v1/me/tracks?limit=50"]];
    if (sg_scope == SGLyricsDownloadLikedAndPlaylists) [sg_pages addObject:@[@(SGPagePlaylists), @"https://api.spotify.com/v1/me/playlists?limit=50"]];
    listNext();
}

void SGLyricsDownloadStart(SGLyricsDownloadScope scope) {
    if (sg_running) return;
    if (!SGKaraokeRunning()) {
        sg_message = @"Needs the redesign, lock screen lyrics or a lyrics source on, which read saved lyrics";
        changed();
        return;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                         queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (!sg_running || !sg_waitingForApp) return;
            void (^resume)(void) = sg_resume;
            sg_waitingForApp = NO;
            sg_resume = nil;
            changed();
            if (resume) resume();
        }];
    });
    // Saving is what the download is for.
    if (!SGLyricsOfflineEnabled()) SGSetEnabled(SGKeyLyricsOffline, YES);
    sg_run++;
    sg_running = YES;
    sg_listing = YES;
    sg_waitingForApp = NO;
    sg_resume = nil;
    sg_scope = scope;
    sg_songs = [NSMutableArray array];
    sg_listed = [NSMutableSet set];
    sg_next = sg_saved = sg_none = sg_already = sg_tries = 0;
    sg_message = nil;
    SGLog(@"lyrics download: started (%@)", scope == SGLyricsDownloadLiked ? @"Liked Songs" : @"Liked Songs and playlists");
    changed();
    begin(0);
}

void SGLyricsDownloadStop(void) {
    if (!sg_running) return;
    finish(sg_listing ? @"Stopped" : [NSString stringWithFormat:@"Stopped at %@ of %@", formatted(sg_next), formatted(sg_songs.count)]);
}

BOOL SGLyricsDownloadRunning(void) {
    return sg_running;
}

NSString *SGLyricsDownloadStatus(void) {
    if (!sg_running) return sg_message ?: @"";
    if (sg_waitingForApp) return @"Paused until Spotify is open";
    if (sg_listing) return sg_listed.count ? [NSString stringWithFormat:@"Listing songs… %@", formatted(sg_listed.count)] : @"Listing songs…";
    return [NSString stringWithFormat:@"%@ of %@ · %@ saved", formatted(sg_next), formatted(sg_songs.count), formatted(sg_saved)];
}

double SGLyricsDownloadProgress(void) {
    if (!sg_running) return -1;
    if (sg_listing || !sg_songs.count) return 0;
    return (double)sg_next / sg_songs.count;
}
