// ListeningStats.h says what is kept and why.
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"
#import "ListeningStats.h"

// A play is a listen of 30 seconds or more; anything under 5 is not kept at all.
static const double kPlaySeconds = 30, kKeepSeconds = 5;
// How often the listen going on is written down, so a Spotify killed mid-song loses at most this much.
static const NSTimeInterval kFlushInterval = 30;

@implementation SGListeningEntry
@end

@implementation SGListeningSummary
@end

@interface SGListeningLog : NSObject <SGPlayerStateObserver>
@property (nonatomic) BOOL recording;
@end

@implementation SGListeningLog {
    NSMutableArray<NSMutableArray *> *_events;   // [unix seconds, uri, seconds listened]
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *_tracks;   // uri: [title, artist, artist uri]
    BOOL _loaded, _dirty;
    NSString *_uri;                 // the track being listened to
    CFAbsoluteTime _playingSince;   // 0 while not playing
    double _listened;               // seconds of this listen before _playingSince
    NSTimeInterval _startedAt;      // unix seconds the listen began
    NSInteger _eventIndex;          // where the listen is in _events once kept, -1 before
    NSTimer *_timer;
}

+ (instancetype)shared {
    static SGListeningLog *log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = [SGListeningLog new]; });
    return log;
}

+ (NSURL *)fileURL {
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [base URLByAppendingPathComponent:@"spoti.pw/Stats/listening.json"];
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _events = [NSMutableArray array];
    _tracks = [NSMutableDictionary dictionary];
    _eventIndex = -1;
    return self;
}

- (void)load {
    if (_loaded) return;
    _loaded = YES;
    NSData *data = [NSData dataWithContentsOfURL:SGListeningLog.fileURL];
    NSDictionary *saved = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![saved isKindOfClass:NSDictionary.class]) return;
    for (id event in saved[@"events"]) {
        if ([event isKindOfClass:NSArray.class] && [event count] == 3 && [event[1] isKindOfClass:NSString.class]
            && [event[0] isKindOfClass:NSNumber.class] && [event[2] isKindOfClass:NSNumber.class]) {
            [_events addObject:[event mutableCopy]];
        }
    }
    NSDictionary *tracks = saved[@"tracks"];
    if ([tracks isKindOfClass:NSDictionary.class]) {
        [tracks enumerateKeysAndObjectsUsingBlock:^(NSString *uri, NSArray *info, BOOL *stop) {
            if ([uri isKindOfClass:NSString.class] && [info isKindOfClass:NSArray.class] && info.count == 3) self->_tracks[uri] = info;
        }];
    }
    SGLog(@"listening stats: %lu listens of %lu tracks", (unsigned long)_events.count, (unsigned long)_tracks.count);
}

- (void)save {
    if (!_dirty) return;
    _dirty = NO;
    // A snapshot, since the events of the listen going on are changed in place; the JSON is made off the main thread.
    NSDictionary *saved = @{@"v": @1, @"events": [[NSArray alloc] initWithArray:_events copyItems:YES], @"tracks": [_tracks copy]};
    NSURL *url = SGListeningLog.fileURL;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:saved options:0 error:NULL];
        if (!data) return;
        [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        if (![data writeToURL:url options:NSDataWritingAtomic error:NULL]) SGLog(@"listening stats: could not write the log");
    });
}

// The listen so far into the log: added once it is worth keeping, then updated in place.
- (void)note {
    if (!_uri) return;
    double listened = _listened + (_playingSince > 0 ? CFAbsoluteTimeGetCurrent() - _playingSince : 0);
    if (listened < kKeepSeconds) return;
    NSNumber *seconds = @(round(listened));
    if (_eventIndex < 0) {
        [_events addObject:[@[@((long long)_startedAt), _uri, seconds] mutableCopy]];
        _eventIndex = (NSInteger)_events.count - 1;
    } else if (_eventIndex < (NSInteger)_events.count) {
        _events[(NSUInteger)_eventIndex][2] = seconds;
    }
    _dirty = YES;
}

- (void)flush {
    [self note];
    [self save];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!_recording) return;
    [self load];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (_playingSince > 0) {
        _listened += now - _playingSince;
        _playingSince = 0;
    }
    SPTPlayerTrack *track = [state respondsToSelector:@selector(track)] ? state.track : nil;
    NSString *uri = SGURIString(track.URI);
    if (![uri isEqualToString:_uri]) {
        [self note];
        if (_dirty) [self save];
        _uri = uri.length ? [uri copy] : nil;
        _listened = 0;
        _startedAt = NSDate.date.timeIntervalSince1970;
        _eventIndex = -1;
        if (_uri) {
            NSString *title = [track respondsToSelector:@selector(trackTitle)] ? track.trackTitle : nil;
            NSString *artist = [track respondsToSelector:@selector(artistName)] ? track.artistName : nil;
            NSString *artistURI = [track respondsToSelector:@selector(artistURI)] ? SGURIString(track.artistURI) : nil;
            if (title.length) _tracks[_uri] = @[title, artist ?: @"", artistURI ?: @""];
        }
    }
    BOOL loading = [state respondsToSelector:@selector(isLoading)] && state.isLoading;
    if (_uri && state.isPlaying && !state.isPaused && !loading) _playingSince = now;
}

- (void)setRecording:(BOOL)recording {
    if (recording == _recording) return;
    _recording = recording;
    if (recording) {
        [self load];
        SGAddPlayerStateObserver(self);
        _timer = [NSTimer scheduledTimerWithTimeInterval:kFlushInterval repeats:YES block:^(NSTimer *timer) {
            [SGListeningLog.shared flush];
        }];
        _timer.tolerance = 5;
        SPTPlayerState *state = SGPlayerState();
        if (state) [self playerStateDidChange:state];
    } else {
        // The listen going on ends here, written down while the recorder still takes it.
        _recording = YES;
        [self playerStateDidChange:nil];
        _recording = NO;
        [_timer invalidate];
        _timer = nil;
        [self flush];
    }
}

- (void)clear {
    [self load];
    [_events removeAllObjects];
    [_tracks removeAllObjects];
    _eventIndex = -1;
    _listened = 0;
    _playingSince = _playingSince > 0 ? CFAbsoluteTimeGetCurrent() : 0;
    _startedAt = NSDate.date.timeIntervalSince1970;
    if (_uri && _recording) {
        // The track playing keeps its name for when its listen is written down.
        SPTPlayerTrack *track = SGPlayerState().track;
        NSString *title = [track respondsToSelector:@selector(trackTitle)] ? track.trackTitle : nil;
        if (title.length) _tracks[_uri] = @[title, track.artistName ?: @"", SGURIString(track.artistURI) ?: @""];
    }
    _dirty = YES;
    [self save];
}

// Listens from Spotify's history, [unix seconds, uri, seconds] each, with the names of their tracks.
- (NSUInteger)importEvents:(NSArray<NSArray *> *)events tracks:(NSDictionary<NSString *, NSArray<NSString *> *> *)tracks {
    [self load];
    NSMutableSet<NSString *> *known = [NSMutableSet setWithCapacity:_events.count];
    for (NSArray *event in _events) [known addObject:[NSString stringWithFormat:@"%lld|%@", [event[0] longLongValue], event[1]]];
    NSUInteger added = 0;
    for (NSArray *event in events) {
        NSString *key = [NSString stringWithFormat:@"%lld|%@", [event[0] longLongValue], event[1]];
        if ([known containsObject:key]) continue;
        [known addObject:key];
        [_events addObject:[event mutableCopy]];
        added++;
    }
    [tracks enumerateKeysAndObjectsUsingBlock:^(NSString *uri, NSArray<NSString *> *info, BOOL *stop) {
        if (!self->_tracks[uri]) self->_tracks[uri] = info;
    }];
    if (added) {
        // Kept in time order, the playing listen's place moving with it.
        NSArray *playing = _eventIndex >= 0 && _eventIndex < (NSInteger)_events.count ? _events[(NSUInteger)_eventIndex] : nil;
        [_events sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
        if (playing) _eventIndex = (NSInteger)[_events indexOfObjectIdenticalTo:(NSMutableArray *)playing];
        _dirty = YES;
        [self save];
    }
    return added;
}

static NSArray<SGListeningEntry *> *top(NSDictionary<NSString *, SGListeningEntry *> *entries, NSUInteger count) {
    NSArray *sorted = [entries.allValues sortedArrayUsingComparator:^NSComparisonResult(SGListeningEntry *a, SGListeningEntry *b) {
        if (a.plays != b.plays) return a.plays > b.plays ? NSOrderedAscending : NSOrderedDescending;
        if (a.seconds != b.seconds) return a.seconds > b.seconds ? NSOrderedAscending : NSOrderedDescending;
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    return [sorted subarrayWithRange:NSMakeRange(0, MIN(count, sorted.count))];
}

- (SGListeningSummary *)summarize:(SGListeningPeriod)period count:(NSUInteger)count {
    [self load];
    [self note];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval from = period == SGListeningPeriodMonth ? now - 28 * 86400 : period == SGListeningPeriodHalfYear ? now - 182 * 86400 : 0;
    NSMutableDictionary<NSString *, SGListeningEntry *> *tracks = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, SGListeningEntry *> *artists = [NSMutableDictionary dictionary];
    SGListeningSummary *summary = [SGListeningSummary new];
    NSTimeInterval first = now;
    for (NSArray *event in _events) {
        NSTimeInterval at = [event[0] doubleValue];
        if (at < from) continue;
        first = MIN(first, at);
        NSString *uri = event[1];
        double seconds = [event[2] doubleValue];
        BOOL play = seconds >= kPlaySeconds;
        summary.seconds += seconds;
        if (play) summary.plays++;
        NSArray<NSString *> *info = _tracks[uri];
        SGListeningEntry *track = tracks[uri];
        if (!track) {
            track = [SGListeningEntry new];
            track.uri = uri;
            track.title = info.count ? info[0] : uri;
            track.subtitle = info.count > 1 && info[1].length ? info[1] : nil;
            tracks[uri] = track;
        }
        track.seconds += seconds;
        if (play) track.plays++;
        NSString *artistName = info.count > 1 ? info[1] : nil;
        if (artistName.length) {
            NSString *artistURI = info.count > 2 && info[2].length ? info[2] : nil;
            NSString *key = artistURI ?: artistName;
            SGListeningEntry *artist = artists[key];
            if (!artist) {
                artist = [SGListeningEntry new];
                artist.uri = artistURI;
                artist.title = artistName;
                artists[key] = artist;
            }
            artist.seconds += seconds;
            if (play) artist.plays++;
        }
    }
    summary.tracks = (NSInteger)tracks.count;
    summary.artists = (NSInteger)artists.count;
    summary.days = summary.seconds > 0 ? MAX(1, (NSInteger)ceil((now - first) / 86400)) : 0;
    summary.topTracks = top(tracks, count);
    summary.topArtists = top(artists, count);
    return summary;
}

@end

void SGListeningStatsApply(void) {
    SGListeningLog.shared.recording = SGEnabled(SGKeyListeningStats);
}

SGListeningSummary *SGListeningSummarize(SGListeningPeriod period, NSUInteger count) {
    return [SGListeningLog.shared summarize:period count:count];
}

// One file's listens: its records turned into events, the names into `tracks`.
static NSUInteger readHistory(NSURL *file, NSMutableArray<NSArray *> *events, NSMutableDictionary *tracks) {
    BOOL scoped = [file startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:file];
    if (scoped) [file stopAccessingSecurityScopedResource];
    NSArray *records = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![records isKindOfClass:NSArray.class]) return 0;
    NSDateFormatter *minutes = [NSDateFormatter new];
    minutes.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    minutes.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    minutes.dateFormat = @"yyyy-MM-dd HH:mm";
    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    NSUInteger read = 0;
    for (NSDictionary *record in records) {
        if (![record isKindOfClass:NSDictionary.class]) continue;
        NSString *title, *artist, *uri, *ended;
        double played;
        NSDate *end;
        if (record[@"ts"]) {   // the extended history
            title = record[@"master_metadata_track_name"];
            artist = record[@"master_metadata_album_artist_name"];
            uri = record[@"spotify_track_uri"];
            ended = record[@"ts"];
            played = [record[@"ms_played"] doubleValue] / 1000;
            end = [ended isKindOfClass:NSString.class] ? [iso dateFromString:ended] : nil;
        } else {               // the account data
            title = record[@"trackName"];
            artist = record[@"artistName"];
            ended = record[@"endTime"];
            played = [record[@"msPlayed"] doubleValue] / 1000;
            end = [ended isKindOfClass:NSString.class] ? [minutes dateFromString:ended] : nil;
        }
        // Podcasts and records without a track carry no track name.
        if (![title isKindOfClass:NSString.class] || !title.length || !end || played < 5) continue;
        if (![artist isKindOfClass:NSString.class]) artist = @"";
        if (![uri isKindOfClass:NSString.class] || ![uri hasPrefix:@"spotify:track:"]) {
            uri = [NSString stringWithFormat:@"imported:%@|%@", artist, title];
        }
        [events addObject:@[@((long long)(end.timeIntervalSince1970 - played)), uri, @(round(played))]];
        if (!tracks[uri]) tracks[uri] = @[title, artist, @""];
        read++;
    }
    return read;
}

void SGListeningImport(NSArray<NSURL *> *files, void (^done)(NSUInteger added, NSString *problem)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSArray *> *events = [NSMutableArray array];
        NSMutableDictionary *tracks = [NSMutableDictionary dictionary];
        NSUInteger read = 0;
        for (NSURL *file in files) read += readHistory(file, events, tracks);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!read) {
                done(0, @"No listens in that. Pick the StreamingHistory_music or Streaming_History_Audio files from Spotify's data download.");
                return;
            }
            NSUInteger added = [SGListeningLog.shared importEvents:events tracks:tracks];
            SGLog(@"listening stats: %lu listens read, %lu new", (unsigned long)read, (unsigned long)added);
            done(added, nil);
        });
    });
}

void SGListeningClear(void) {
    [SGListeningLog.shared clear];
}

void SGListeningStatsFlush(void) {
    [SGListeningLog.shared flush];
}
