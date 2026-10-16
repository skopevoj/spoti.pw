// A local file's lyrics (LyricsSources.h): Spotify has none for it and no source knows it by Spotify's
// id, so they come from what the user typed in for it (Documents/rokis.pw/Local lyrics/<id>.lrc, LRC or
// plain lines), and failing that from LRCLIB by the title, the artist and the length the file's
// spotify:local:artist:album:title:seconds URI carries. Either way they are kept as any track's are, so
// the redesign's lyrics, the lock screen and the Live Activity show them.
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"
#import "LyricsSources.h"

static NSMutableSet<NSString *> *sg_asked;

static NSURL *fileFor(NSString *localID) {
    return [[[NSURL fileURLWithPath:SGDocumentsFolder() isDirectory:YES] URLByAppendingPathComponent:@"Local lyrics" isDirectory:YES]
            URLByAppendingPathComponent:[localID stringByAppendingPathExtension:@"lrc"]];
}

// spotify:local:Artist:Album:Title:215, each part percent encoded with + for a space.
static NSArray<NSString *> *partsOf(NSString *uri) {
    if (![uri hasPrefix:@"spotify:local:"]) return nil;
    NSArray<NSString *> *raw = [[uri substringFromIndex:@"spotify:local:".length] componentsSeparatedByString:@":"];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in raw) {
        NSString *spaced = [part stringByReplacingOccurrencesOfString:@"+" withString:@" "];
        [parts addObject:spaced.stringByRemovingPercentEncoding ?: spaced];
    }
    return parts.count >= 4 ? parts : nil;
}

static NSArray<SGKaraokeLine *> *linesFromText(NSString *text) {
    NSArray<SGKaraokeLine *> *lines = SGLyricsLinesFromLRC(text);
    if (lines.count) return lines;
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    for (NSString *row in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [row stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        [rows addObject:trimmed];
    }
    lines = SGKaraokeStaticLines(rows);
    return lines.count ? lines : nil;
}

NSString *SGLocalLyricsSaved(NSString *localID) {
    if (!SGKaraokeIsLocalTrack(localID)) return nil;
    NSString *text = [NSString stringWithContentsOfURL:fileFor(localID) encoding:NSUTF8StringEncoding error:NULL];
    return text.length ? text : nil;
}

static SGLyricsQuery *queryFor(NSString *localID) {
    SPTPlayerTrack *track = SGKaraokeTrackFor(localID);
    if (!track) {
        SPTPlayerTrack *playing = SGPlayerState().track;
        if ([SGKaraokeLocalTrackID(SGURIString(playing.URI)) isEqualToString:localID]) track = playing;
    }
    NSArray<NSString *> *parts = partsOf(SGURIString(track.URI));
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = localID;
    query.title = track.trackTitle.length ? track.trackTitle : parts[2];
    query.artist = track.artistName.length ? track.artistName : parts[0];
    query.album = parts[1].length ? parts[1] : nil;
    query.seconds = parts[3].integerValue;
    return query;
}

void SGLocalLyricsFetch(NSString *localID) {
    if (!SGKaraokeIsLocalTrack(localID)) return;
    // The player's state hook that notices a new track can run off the main queue.
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGLocalLyricsFetch(localID); });
        return;
    }
    if (!sg_asked) sg_asked = [NSMutableSet set];
    if ([sg_asked containsObject:localID] || SGKaraokeLinesForTrack(localID)) return;
    [sg_asked addObject:localID];
    NSString *saved = SGLocalLyricsSaved(localID);
    NSArray<SGKaraokeLine *> *typed = saved ? linesFromText(saved) : nil;
    if (typed) {
        SGLog(@"local lyrics: %lu typed in lines for %@", (unsigned long)typed.count, localID);
        SGKaraokeKeepLines(localID, typed);
        return;
    }
    SGLyricsQuery *query = queryFor(localID);
    if (!query.title.length || !query.artist.length) {
        SGLog(@"local lyrics: no name for %@", localID);
        [sg_asked removeObject:localID];
        return;
    }
    SGLrcLibAsk(query, ^(SGLyricsResult *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!result.karaokeLines.count) {
                SGLog(@"local lyrics: LRCLIB has none for %@ by %@", query.title, query.artist);
                return;   // stays asked: the editor is where they come from now
            }
            SGLyricsSetCredit(localID, SGLyricsCreditNamed(@"LRCLIB"));
            SGKaraokeKeepLines(localID, result.karaokeLines);
        });
    });
}

NSString *SGLocalLyricsSave(NSString *localID, NSString *text) {
    if (!SGKaraokeIsLocalTrack(localID)) return @"Lyrics can be typed in only for a local file.";
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSURL *url = fileFor(localID);
    if (!trimmed.length) {
        [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
        [sg_asked removeObject:localID];
        SGLocalLyricsFetch(localID);
        return nil;
    }
    NSArray<SGKaraokeLine *> *lines = linesFromText(trimmed);
    if (!lines) return @"There are no lines in that.";
    [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *error;
    if (![trimmed writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        return [@"They could not be saved: " stringByAppendingString:error.localizedDescription ?: @"unknown error"];
    }
    SGLyricsSetCredit(localID, SGLyricsCreditNamed(@"Your lyrics"));
    SGKaraokeKeepLines(localID, lines);
    SGLog(@"local lyrics: %lu lines typed in for %@", (unsigned long)lines.count, localID);
    return nil;
}

BOOL SGLocalLyricsPlaying(NSString **localID, NSString **name) {
    SPTPlayerTrack *track = SGPlayerState().track;
    NSString *found = SGKaraokeLocalTrackID(SGURIString(track.URI));
    if (!found) return NO;
    if (localID) *localID = found;
    if (name) {
        NSString *title = track.trackTitle, *artist = track.artistName;
        *name = title.length ? (artist.length ? [NSString stringWithFormat:@"%@ · %@", title, artist] : title) : @"This local file";
    }
    return YES;
}
