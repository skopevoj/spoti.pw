// What the player harness does not compile: the Kit's hooks (SGRAccent.x, SGRRepaint.x), the rest of
// the player's hooks, the lyrics store and the haptics. Everything here answers the way the phone would
// for one track with lyrics, so the redesign's own code is what is being looked at. The player itself
// is a mock the harness drives: SGRHarnessSetTrack reports a track change to every observer.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"
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
CFTimeInterval SGPlayerTransitionEnds(void) { return 0; }

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
// a track whose metadata names none.
void SGRHarnessSetTrack(NSString *uri, NSString *imageURI, BOOL paused) {
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
    [track setValue:metadata forKey:@"metadata"];
    SPTPlayerState *state = [SPTPlayerState new];
    [state setValue:track forKey:@"track"];
    [state setValue:@(paused) forKey:@"isPaused"];
    [state setValue:@(!paused) forKey:@"isPlaying"];
    sg_state = state;
    for (id<SGPlayerStateObserver> observer in sg_observers.allObjects) [observer playerStateDidChange:state];
}

#pragma mark - Redesigned/Player/PlayerControls.x

void SGRPlayerVanish(UIView *view) {
    view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

#pragma mark - Shared/Haptics

void SGPlayFeedback(NSInteger feedback) {}
void SGPrepareFeedback(NSInteger feedback) {}

#pragma mark - Shared/LyricsSources

NSString *SGLyricsCreditFor(NSString *trackID) { return @"the harness"; }

#pragma mark - Shared/Lyrics/KaraokeSource.x

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
void SGKaraokeSeek(NSInteger ms) {
    sg_position = ms;
    sg_started = CACurrentMediaTime();
}
void SGRHarnessPlayFrom(NSInteger ms) { SGKaraokeSeek(ms); }

#pragma mark - Lyrics meanings (no network in the layout harness)
#import "Shared/LyricsMeanings/Meanings.h"
void SGLyricsMeaningsFor(NSString *trackID, NSArray<SGKaraokeLine *> *lines,
                        void (^reply)(NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *)) {
    reply(@{});
}
void SGRShowMeanings(NSString *lineText, NSArray<SGLyricsMeaning *> *meanings) {}

// Shared menu decoration is outside the player geometry harness.
void SGPlayerMenuWatchMoreButton(UIView *button) {}
