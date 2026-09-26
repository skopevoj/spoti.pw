// SPTPlayerState.position and SPTEsperantoPlayer's commands are verified in Spotify 9.1.78
// (Headers/SPTPlayer.h). The position hook is the one audible clock used by Spotify's progress UI.
#import "Core/SGCore.h"
#import "SGSingController.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import <MediaPlayer/MediaPlayer.h>

static double (*sourcePosition)(id, SEL);
double SGSingSourcePosition(SPTPlayerState *state) {
    if (!state) return 0;
    return state.isPaused ? state.positionAsOfTimestamp : sourcePosition ? sourcePosition(state, @selector(position)) : state.position;
}
%hook SPTPlayerState
- (double)position {
    double position;
    return SGSingPosition(self, &position) ? position : %orig;
}
%end

%hook SPTEsperantoPlayer
- (void)seekTo:(double)seconds {
    SGSingPlaybackWillChange();
    %orig;
    SGSingPlaybackDidSeek(seconds);
}
- (void)skipToNextTrack {
    SGSingPlaybackWillChange();
    %orig;
    SGSingPlaybackDidChange();
}
- (id)skipToNextTrackWithOptions:(id)options {
    SGSingPlaybackWillChange();
    id result = %orig;
    SGSingPlaybackDidChange();
    return result;
}
- (id)skipToPreviousTrackWithOptions:(id)options {
    SGSingPlaybackWillChange();
    id result = %orig;
    SGSingPlaybackDidChange();
    return result;
}
- (id)skipToNextTrackWithOptions:(id)options track:(id)track {
    SGSingPlaybackWillChange();
    id result = %orig;
    SGSingPlaybackDidChange();
    return result;
}
%end

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    // PlayerState is main-thread data. Off-main reports are corrected by the controller's next
    // clock publication; never read its Objective-C ownership from an audio/player callback.
    SPTPlayerState *state = NSThread.isMainThread ? SGPlayerState() : nil;
    double position;
    if (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] &&
        [state.track.trackTitle isEqualToString:info[MPMediaItemPropertyTitle]] && SGSingPosition(state, &position)) {
        NSMutableDictionary *shown = [info mutableCopy];
        shown[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(position);
        shown[MPNowPlayingInfoPropertyPlaybackRate] = @(state.isPaused || !state.isPlaying ? 0 : SGPlayerSpeed());
        %orig(shown);
    } else %orig;
}
%end

%ctor {
    sourcePosition = (void *)class_getMethodImplementation(objc_getClass("SPTPlayerState"), @selector(position));
    %init;
    SGRequireClasses(@[@"SPTPlayerState", @"SPTEsperantoPlayer"]);
}
