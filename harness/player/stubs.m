// What the player harness does not compile: the Kit's hooks (SGRAccent.x, SGRRepaint.x), the rest of
// the player's hooks, the lyrics store, Genius's meanings, the haptics, and where Animated artwork's clips
// come from. Everything here answers the way the phone would for one track with lyrics, so the
// redesign's own code is what is being looked at. The player itself is a mock the harness drives:
// SGRHarnessSetTrack reports a track change to every observer.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Shared/LockScreenArtwork/SGCanvas.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"

#pragma mark - SGRAccent.x, SGRRepaint.x

UIColor *SGRAccentColor(void) { return nil; }
__weak UIView *sgr_nowPlayingRoot = nil;
__weak UIView *sgr_nowPlayingCard = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;

#pragma mark - Shared/Player/PlayerEvents.x

NSString *const SGPlayerTransitionNotification = @"spotifyglass.playerTransition";
NSString *const SGPlayerTransitionEndedNotification = @"spotifyglass.playerTransitionEnded";
CFTimeInterval sg_harnessTransitionEnds;
CFTimeInterval SGPlayerTransitionEnds(void) { return sg_harnessTransitionEnds > CACurrentMediaTime() ? sg_harnessTransitionEnds : 0; }

#pragma mark - Shared/Player/PlayerState.x

NSString *SGURIString(id uri) {
    if ([uri isKindOfClass:NSString.class]) return uri;
    if ([uri isKindOfClass:NSURL.class]) return ((NSURL *)uri).absoluteString;
    return nil;
}

// A player that plays what the harness tells it to, reporting on the main thread the way
// Shared/Player/PlayerState.x moves Spotify's reports onto it.
@implementation SPTPlayerTrack
@end
@implementation SPTPlayerOptions
@end
@implementation SPTPlayerState
@end

static NSHashTable *sg_observers;
static SPTPlayerState *sg_state;

void SGAddPlayerStateObserver(id observer) {
    if (!sg_observers) sg_observers = [NSHashTable weakObjectsHashTable];
    [sg_observers addObject:observer];
}
SPTPlayerState *SGPlayerState(void) { return sg_state; }

// `imageURI` is the xlarge picture as Spotify's metadata has it, spotify:image:<40 hex digits>, or nil for
// a track whose metadata names none; `extra` goes into the metadata as well.
static SPTPlayerTrack *trackWith(NSString *uri, NSString *imageURI, NSDictionary *extra) {
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    [track setValue:uri forKey:@"URI"];
    NSMutableDictionary *metadata = [@{@"title": uri} mutableCopy];
    if (imageURI) {
        // The four sizes share the picture's last 24 digits (out/karaoke-diag.log:174-177 on the phone).
        NSString *hash = [imageURI substringFromIndex:imageURI.length - 24];
        metadata[@"image_xlarge_url"] = imageURI;
        metadata[@"image_large_url"] = imageURI;
        metadata[@"image_url"] = [@"spotify:image:ab67616d00001e02" stringByAppendingString:hash];
        metadata[@"image_small_url"] = [@"spotify:image:ab67616d00004851" stringByAppendingString:hash];
    }
    [metadata addEntriesFromDictionary:extra ?: @{}];
    [track setValue:metadata forKey:@"metadata"];
    return track;
}

// `future` is the tracks up next, each {uri, metadata}.
void SGRHarnessSetTrackWith(NSString *uri, NSString *imageURI, BOOL paused, NSDictionary *extra, NSArray<NSDictionary *> *future) {
    SPTPlayerTrack *track = trackWith(uri, imageURI, extra);
    NSMutableArray<SPTPlayerTrack *> *next = [NSMutableArray array];
    for (NSDictionary *entry in future) [next addObject:trackWith(entry[@"uri"], nil, entry[@"metadata"])];
    SPTPlayerState *state = [SPTPlayerState new];
    [state setValue:next forKey:@"future"];
    [state setValue:track forKey:@"track"];
    [state setValue:@(paused) forKey:@"isPaused"];
    [state setValue:@(!paused) forKey:@"isPlaying"];
    sg_state = state;
    for (id<SGPlayerStateObserver> observer in sg_observers.allObjects) [observer playerStateDidChange:state];
}

void SGRHarnessSetTrack(NSString *uri, NSString *imageURI, BOOL paused) {
    SGRHarnessSetTrackWith(uri, imageURI, paused, nil, nil);
}

#pragma mark - Shared/LockScreenArtwork: the sources and the download

// Local clips instead of Spotify's and Apple's: a Canvas is the file the track's metadata names (canvas.url),
// Apple Music's cover the one SGRHarnessAppleClips gives the album, and each file lands after the delay
// SGRHarnessClipDelays gives its name, as a download would; without one it is already on disk.
NSMutableDictionary<NSString *, NSURL *> *SGRHarnessAppleClips;
NSMutableDictionary<NSString *, NSNumber *> *SGRHarnessClipDelays;

void SGArtworkAsk(NSString *source, SPTPlayerTrack *track, SGCanvas *fromMetadata, BOOL tall, void (^done)(SGCanvas *canvas, NSString *note)) {
    if ([source isEqualToString:SGArtworkSourceSpotify]) {
        done(fromMetadata, fromMetadata ? @"track metadata" : @"no canvas in the metadata, and canvaz has none");
        return;
    }
    NSString *album = track.metadata[@"album_title"];
    NSURL *file = album ? SGRHarnessAppleClips[album] : nil;
    if (!file) {
        done(nil, @"no animated cover");
        return;
    }
    SGCanvas *canvas = [SGCanvas new];
    canvas.identifier = [@"am-" stringByAppendingString:file.lastPathComponent.stringByDeletingPathExtension];
    canvas.address = file.absoluteString;
    canvas.video = YES;
    // Apple Music is asked over the network: its answer comes a moment later.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        done(canvas, tall ? @"the 3:4 cover" : @"the square cover");
    });
}

NSURLSessionTask *SGArtworkFetchAside(NSString *identifier, NSString *address, void (^done)(NSURL *file, NSString *note)) {
    NSURL *file = [NSURL URLWithString:address];
    double delay = SGRHarnessClipDelays[file.lastPathComponent].doubleValue;
    NSLog(@"[harness] fetch %@: %@", file.lastPathComponent, delay > 0 ? [NSString stringWithFormat:@"lands in %.1f s", delay] : @"on disk");
    if (delay <= 0) {
        done(file, @"cached");
        return nil;
    }
    // Once fetched it is on disk.
    SGRHarnessClipDelays[file.lastPathComponent] = nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
        done(file, [NSString stringWithFormat:@"downloaded after %.1f s", delay]);
    });
    return nil;
}

#pragma mark - Shared/Haptics

static NSUInteger sg_skipTaps;
void SGPlayFeedback(NSInteger feedback) {
    if (feedback == 2) sg_skipTaps++;   // SGFeedbackSkip: a lyric line, or a tap on the bar
}
NSUInteger SGRHarnessSkipTaps(void) { return sg_skipTaps; }
void SGPrepareFeedback(NSInteger feedback) {}

#pragma mark - Shared/LyricsSources, Shared/LyricsMeanings, Redesigned/Lyrics/MeaningSheet.m

@implementation SGLyricsCredit
@end
SGLyricsCredit *SGLyricsCreditFor(NSString *trackID) {
    SGLyricsCredit *credit = [SGLyricsCredit new];
    credit.text = @"the harness";
    return credit;
}
void SGLyricsOpenCredit(SGLyricsCredit *credit) {}
BOOL SGLyricsActive(void) { return NO; }
void SGLyricsMeaningsFor(NSString *trackID, NSArray *lines, void (^done)(NSDictionary *byLine)) {}
void SGRShowMeanings(NSString *lineText, NSArray *meanings) {}

#pragma mark - Shared/Lyrics/KaraokeSource.x

NSNotificationName const SGKaraokeLinesDidChangeNotification = @"spotifyglass.karaokeLinesChanged";
static NSArray<SGKaraokeLine *> *sg_lines;
static NSString *sg_track = @"harness";
static NSInteger sg_position;
static CFTimeInterval sg_started;

NSString *SGKaraokePlayingTrack(void) { return sg_track; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) { return sg_lines; }
void SGKaraokeKeepLines(NSString *trackID, NSArray<SGKaraokeLine *> *lines) { sg_lines = lines; }
void SGKaraokeRequestLyrics(NSString *trackID) {}
id SGKaraokePlayer(void) { return nil; }
SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID) { return nil; }
void SGKaraokeRememberTrack(SPTPlayerTrack *track) {}

// The song runs on from the moment the harness started it, so the sweep is alive in a screenshot.
NSInteger SGKaraokePositionMs(void) {
    if (!sg_started) return sg_position;
    return sg_position + (NSInteger)((CACurrentMediaTime() - sg_started) * 1000);
}
static NSUInteger sg_lineSeeks;
void SGRHarnessPlayFrom(NSInteger ms) {
    sg_position = ms;
    sg_started = CACurrentMediaTime();
}
// Only the lyrics seek through here; the progress bar's unit plays from the harness's own call.
void SGKaraokeSeek(NSInteger ms) {
    sg_lineSeeks++;
    NSLog(@"[harness] a line seeks to %ld ms", (long)ms);
    SGRHarnessPlayFrom(ms);
}
NSUInteger SGRHarnessLineSeeks(void) { return sg_lineSeeks; }
