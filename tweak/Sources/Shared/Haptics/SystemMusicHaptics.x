// iOS's own Music Haptics (iOS 18, Settings > Accessibility > Music Haptics), which keeps playing in the
// background and on the lock screen, where the mod's (MusicHaptics.x) cannot: Apple plays its own haptic
// track for a song it knows by ISRC, for an app that says it takes part (MusicHapticsSupported in the IPA's
// Info.plist, plist/liquid-glass.plist) and puts the song's ISRC in the system's now playing info.
//
// Spotify's player names no ISRC, so it is asked of Spotify's Web API for each track, with the Authorization
// of Spotify's own requests (Shared/Lyrics), which goes nowhere but Spotify, and kept for the session. With
// iOS's on and a haptic track for the song, the mod's own Music Haptics steps aside, so the two never play
// at once; for a song Apple has nothing for, the mod's plays as before, in front.
#import <MediaPlayer/MediaPlayer.h>
#import <MediaAccessibility/MediaAccessibility.h>
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Haptics.h"

static NSMutableDictionary<NSString *, NSString *> *sg_isrcs;   // base62 id: ISRC, "" for none
static NSMutableSet<NSString *> *sg_asking;
static NSString *sg_track;          // the base62 id playing
static NSString *sg_isrc;           // its ISRC once known
static BOOL sg_systemCovers;        // iOS's is on and has a haptic track for it
static BOOL sg_hooked;              // taken part in this launch
static NSInteger sg_lookupStatus;   // the last lookup's HTTP status for the track playing, 0 before one
static BOOL sg_checked;             // iOS has answered whether it has a haptic track for the ISRC
// Spotify's token may not be there yet as a track starts; the lookup is tried again this often, this many times.
static const NSTimeInterval kRetryAfter = 3;
static const NSInteger kMostTries = 10;

BOOL SGSystemMusicHapticsCovers(void) { return sg_systemCovers; }

static void tellHaptics(BOOL covers) {
    if (covers == sg_systemCovers) return;
    sg_systemCovers = covers;
    SGLog(@"music haptics: iOS's own %@", covers ? @"plays this song, the mod's steps aside" : @"does not play this song");
    SGMusicHapticsSettingsChanged();
}

// Whether iOS has a haptic track for the ISRC, and is playing haptics at all.
static void checkSystem(NSString *isrc) API_AVAILABLE(ios(18.0)) {
    MAMusicHapticsManager *manager = MAMusicHapticsManager.sharedManager;
    if (!isrc.length || !manager.isActive) {
        tellHaptics(NO);
        return;
    }
    [manager checkHapticTrackAvailabilityForMediaMatchingCode:isrc completionHandler:^(BOOL available) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![isrc isEqualToString:sg_isrc]) return;
            sg_checked = YES;
            tellHaptics(available);
        });
    }];
}

// Sends Spotify's last now playing info again, for the hook below to add the ISRC to.
static void resend(void) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSDictionary *info = center.nowPlayingInfo;
    if (info) center.nowPlayingInfo = info;
}

static void found(NSString *track, NSString *isrc) {
    sg_isrcs[track] = isrc ?: @"";
    [sg_asking removeObject:track];
    if (![track isEqualToString:sg_track]) return;
    sg_isrc = isrc.length ? isrc : nil;
    resend();
    if (@available(iOS 18.0, *)) checkSystem(sg_isrc);
}

static void askISRC(NSString *track, NSInteger tries);

// Asked again in a moment, while the same track plays: Spotify's token comes with its first requests, which a
// track that starts as Spotify opens can beat, and a lookup can fail on a bad connection.
static void askAgain(NSString *track, NSInteger tries) {
    if (tries >= kMostTries) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetryAfter * (tries + 1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([track isEqualToString:sg_track] && !sg_isrc) askISRC(track, tries + 1);
    });
}

static void askISRC(NSString *track, NSInteger tries) {
    NSString *kept = sg_isrcs[track];
    if (kept) {
        found(track, kept);
        return;
    }
    if ([sg_asking containsObject:track]) return;
    NSString *authorization = SGKaraokeSpotifyAuthorization();
    if (!authorization) {
        askAgain(track, tries);
        return;
    }
    [sg_asking addObject:track];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[@"https://api.spotify.com/v1/tracks/" stringByAppendingString:track]]];
    [request setValue:authorization forHTTPHeaderField:@"Authorization"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *reply = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *ids = [reply isKindOfClass:NSDictionary.class] ? reply[@"external_ids"] : nil;
        NSString *isrc = [ids isKindOfClass:NSDictionary.class] && [ids[@"isrc"] isKindOfClass:NSString.class] ? ids[@"isrc"] : nil;
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([track isEqualToString:sg_track]) sg_lookupStatus = status;
            if (status != 200) {
                [sg_asking removeObject:track];   // not kept as none: asked again in a moment
                SGLog(@"music haptics: no ISRC for %@ (HTTP %ld, try %ld)", track, (long)status, (long)tries + 1);
                if (status != 404) askAgain(track, tries);
                return;
            }
            found(track, isrc);
        });
    }] resume];
}

@interface SGSystemHapticsWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGSystemHapticsWatcher
- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    NSString *track = [uri hasPrefix:@"spotify:track:"] ? [uri substringFromIndex:@"spotify:track:".length] : nil;
    if (track == sg_track || [track isEqualToString:sg_track]) return;
    sg_track = track;
    sg_isrc = nil;
    sg_lookupStatus = 0;
    sg_checked = NO;
    tellHaptics(NO);
    if (track) askISRC(track, 0);
}
@end

static SGSystemHapticsWatcher *sg_watcher;

NSString *SGSystemMusicHapticsStatus(void) {
    if (@available(iOS 18.0, *)) {
        if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) return @"Not on this device";
        if (!SGEnabled(SGKeySystemMusicHaptics)) return @"Off";
        if (!sg_hooked) return @"Restart Spotify";
        if (!MAMusicHapticsManager.sharedManager.isActive) return @"Off in Settings";
        if (!sg_track) return @"Play a song";
        if (sg_systemCovers) return @"Playing for this song";
        if (!sg_isrc) return sg_lookupStatus && sg_lookupStatus != 200 ? [NSString stringWithFormat:@"Song not found (%ld)", (long)sg_lookupStatus]
                                                                      : @"Looking the song up";
        return sg_checked ? @"Apple has none for this song" : @"Asking iOS";
    }
    return @"Needs iOS 18";
}

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    NSString *isrc = sg_isrc;
    if (@available(iOS 18.0, *)) {
        if (isrc && info && ![info[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] isEqual:isrc]) {
            NSMutableDictionary *withCode = [info mutableCopy];
            withCode[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] = isrc;
            %orig(withCode);
            return;
        }
    }
    %orig;
}
%end

%ctor {
    if (@available(iOS 18.0, *)) {
        if (SGOff("syshaptics")) return;
        // An iPad has no Taptic Engine for iOS to play a haptic track on.
        if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone || !SGEnabled(SGKeySystemMusicHaptics)) return;
        sg_hooked = YES;
        sg_isrcs = [NSMutableDictionary dictionary];
        sg_asking = [NSMutableSet set];
        %init;
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_watcher = [SGSystemHapticsWatcher new];
            SGAddPlayerStateObserver(sg_watcher);
            SPTPlayerState *state = SGPlayerState();
            if (state) [sg_watcher playerStateDidChange:state];
            // Turned on or off in Accessibility while Spotify runs.
            [MAMusicHapticsManager.sharedManager addStatusObserver:^(NSString *code, BOOL active) {
                dispatch_async(dispatch_get_main_queue(), ^{ checkSystem(sg_isrc); });
            }];
        });
        SGLog(@"music haptics: iOS's own taken part in");
    }
}
