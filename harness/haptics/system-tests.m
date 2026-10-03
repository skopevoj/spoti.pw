#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "Shared/Haptics/SGHapticTrack.h"
#import "Shared/Lyrics/Protobuf.h"

static int checks;
static void check(BOOL pass, NSString *name) {
    checks++;
    if (!pass) { NSLog(@"FAIL: %@", name); exit(1); }
}

static NSData *response(NSString *uri, NSString *code, NSInteger kind, NSInteger status, NSString *type) {
    NSData *external = SGPBSerialize(@[SGPBString(1, @"isrc"), SGPBString(2, code)]);
    NSData *track = SGPBSerialize(@[SGPBBytes(10, external)]);
    NSData *any = SGPBSerialize(@[SGPBString(1, type), SGPBBytes(2, track)]);
    NSData *header = SGPBSerialize(@[SGPBVarint(1, status)]);
    NSData *entity = SGPBSerialize(@[SGPBBytes(1, header), SGPBString(2, uri), SGPBBytes(3, any)]);
    NSData *provider = SGPBSerialize(@[SGPBVarint(1, 200)]);
    NSData *array = SGPBSerialize(@[SGPBBytes(1, provider), SGPBVarint(2, kind), SGPBBytes(3, entity)]);
    return SGPBSerialize(@[SGPBBytes(2, array)]);
}

int main(void) {
    @autoreleasepool {
        NSString *uri = @"spotify:track:5Sg09MvHqNWPWsYeuY2toY", *other = @"spotify:track:0000000000000000000000";
        NSString *code = @"USUG11904206", *type = @"type.googleapis.com/spotify.metadata.Track";
        check(SGHapticTrackURI(uri), @"Spotify track URI accepted");
        for (id value in @[@"spotify:episode:5Sg09MvHqNWPWsYeuY2toY", @"spotify:local:a:b:c:1", @"spotify:ad:example", @"spotify:track:short", @"spotify:track:5Sg09MvHqNWPWsYeuY2to/", @42])
            check(!SGHapticTrackURI(value), @"Non-track or malformed URI rejected");
        check([SGHapticISRC(@"usug11904206") isEqual:code], @"ISRC normalized");
        for (id value in @[@"USUG1190420", @"1SUG11904206", @"USUG1190420X", @"US-UG1-19-04206", @42, NSNull.null])
            check(!SGHapticISRC(value), @"Invalid recording code rejected");
        check(!SGHapticMetadataRequest(@"spotify:local:a:b:c:1"), @"Local file is never looked up");
        NSArray *request = SGPBParse(SGHapticMetadataRequest(uri));
        NSArray *entity = SGPBParse(SGPBFirst(request, 2).payload);
        check([SGPBText(SGPBFirst(entity, 1)) isEqual:uri], @"Lookup uses exact URI");
        check(SGPBFirst(SGPBParse(SGPBFirst(entity, 2).payload), 1).varint == 10, @"Requests TRACK_V4");
        NSData *body = response(uri, code, 10, 200, type);
        check([SGHapticISRCFromResponse(body, uri) isEqual:code], @"Exact recording resolved");
        NSData *providerFailure = SGPBEdit(body, @[@2, @1], ^NSData *(NSData *header) { return SGPBSerialize(@[SGPBVarint(1, 500)]); });
        check(!SGHapticISRCFromResponse(providerFailure, uri), @"Provider-level error rejected");
        check(!SGHapticISRCFromResponse(body, other), @"Response for another track rejected");
        check(!SGHapticISRCFromResponse(response(uri, code, 9, 200, type), uri), @"Album ISRC cannot masquerade as track");
        check(!SGHapticISRCFromResponse(response(uri, code, 10, 404, type), uri), @"Entity-level errors rejected even on HTTP 200");
        check(!SGHapticISRCFromResponse(response(uri, code, 10, 200, @"type.googleapis.com/spotify.metadata.Album"), uri), @"Wrong protobuf type rejected");
        check(!SGHapticISRCFromResponse(response(uri, @"bad", 10, 200, type), uri), @"Invalid ISRC in valid response rejected");
        check(!SGHapticISRCFromResponse([@"<html>upstream error</html>" dataUsingEncoding:NSUTF8StringEncoding], uri), @"Non-protobuf response rejected");
        for (NSUInteger end = 0; end < body.length; end++)
            check(!SGHapticISRCFromResponse([body subdataWithRange:NSMakeRange(0, end)], uri), @"Every truncated response rejected");
        NSData *albumOnly = SGPBSerialize(@[SGPBBytes(2, SGPBSerialize(@[SGPBVarint(2, 9), SGPBBytes(3, SGPBFirst(SGPBParse(SGPBFirst(SGPBParse(body), 2).payload), 3).payload)]))]);
        NSMutableData *batch = [albumOnly mutableCopy];
        [batch appendData:body];
        check([SGHapticISRCFromResponse(batch, uri) isEqual:code], @"Batched response selects the requested kind");

        NSDictionary *appleSong = @{@"id": @"1440742918", @"type": @"songs", @"attributes":
            @{@"name": @"Runaway (feat. Pusha T)", @"isrc": @"USUM71027402", @"durationInMillis": @547733, @"hasHaptics": @YES}};
        NSData *(^catalog)(id) = ^NSData *(id songs) {
            return [NSJSONSerialization dataWithJSONObject:@{@"data": songs} options:0 error:nil];
        };
        check([SGHapticAppleID(catalog(@[appleSong]), @"USUM71027402", 547.733) isEqual:@1440742918], @"Exact Apple haptic recording selected");
        check(!SGHapticAppleID(catalog(@[appleSong]), @"USUM71027403", 547.733), @"Same song's other recording rejected");
        check(!SGHapticAppleID(catalog(@[appleSong]), @"USUM71027402", 300), @"Different haptic timeline duration rejected");
        for (id value in @[@"0", @"-1", @"1.0", @" 12", @"12x", @"9999999999999999999999", @42, NSNull.null]) {
            NSMutableDictionary *bad = [appleSong mutableCopy]; bad[@"id"] = value;
            check(!SGHapticAppleID(catalog(@[bad]), @"USUM71027402", 547.733), @"Invalid Apple catalog ID rejected");
        }
        for (id value in @[@NO, @"true", NSNull.null]) {
            NSMutableDictionary *bad = [appleSong mutableCopy], *attrs = [appleSong[@"attributes"] mutableCopy];
            attrs[@"hasHaptics"] = value; bad[@"attributes"] = attrs;
            check(!SGHapticAppleID(catalog(@[bad]), @"USUM71027402", 547.733), @"Unsupported catalog haptics rejected");
        }
        check(!SGHapticAppleID(catalog(@{}), @"USUM71027402", 547.733), @"Malformed Apple data shape rejected");
        check(!SGHapticAppleID(catalog(@[NSNull.null]), @"USUM71027402", 547.733), @"Malformed Apple song rejected");
        check(!SGHapticAppleID(catalog(@[appleSong]), @"USUM71027402", NAN), @"Nonfinite expected duration rejected");
        check(!SGHapticAppleID([@"bad json" dataUsingEncoding:NSUTF8StringEncoding], @"USUM71027402", 547.733), @"Invalid JSON rejected");

        NSDictionary *track = @{@"uri": uri, @"title": @"Blinding Lights", @"album": @"After Hours", @"duration": @200};
        NSDictionary *info = @{MPMediaItemPropertyTitle: @"Blinding Lights", MPMediaItemPropertyAlbumTitle: @"After Hours",
            MPMediaItemPropertyPlaybackDuration: @200, MPMediaItemPropertyArtist: @"a line of lyrics",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: @45, MPNowPlayingInfoPropertyPlaybackRate: @1.25, @"artwork-marker": @"keep"};
        check(SGHapticInfoMatches(info, track), @"Exact title album duration survives lock-screen lyrics");
        NSDictionary *withCode = SGHapticInfo(info, track, code);
        check([withCode[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] isEqual:code], @"Recording attached");
        NSMutableDictionary *roundtrip = [withCode mutableCopy];
        [roundtrip removeObjectForKey:MPNowPlayingInfoPropertyInternationalStandardRecordingCode];
        check([roundtrip isEqual:info], @"Artwork, lyric, position and speed fields preserved");
        check([SGHapticInfo(withCode, track, nil) isEqual:info], @"Switching to generated removes native recording");
        check(!SGHapticInfo(nil, track, code), @"Cleared Now Playing remains nil");
        check([SGHapticInfo(withCode, nil, code) isEqual:info], @"Clearing track strips stale recording");
        NSMutableDictionary *next = [info mutableCopy];
        next[MPMediaItemPropertyTitle] = @"Next song";
        check(!SGHapticInfoMatches(next, track), @"Next song cannot inherit stale ISRC");
        next[MPMediaItemPropertyTitle] = @"Blinding Lights";
        next[MPMediaItemPropertyAlbumTitle] = @"Another recording";
        check(!SGHapticInfoMatches(next, track), @"Same title from another album rejected");
        next[MPMediaItemPropertyAlbumTitle] = @"After Hours";
        next[MPMediaItemPropertyPlaybackDuration] = @300;
        check(!SGHapticInfoMatches(next, track), @"Different duration rejected");
        next[MPNowPlayingInfoPropertyExternalContentIdentifier] = uri;
        check(SGHapticInfoMatches(next, track), @"Authoritative Spotify URI identifies exact track");
        next[MPNowPlayingInfoPropertyExternalContentIdentifier] = [uri stringByAppendingString:@"#E565A600-07A0-47FF-8C8D-1E8760BA5C05"];
        check(SGHapticInfoMatches(next, track), @"Device playback UUID fragment does not change the recording");
        check([SGHapticInfo(next, track, code)[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] isEqual:code], @"ISRC reaches Now Playing with Spotify's playback fragment");
        next[MPNowPlayingInfoPropertyExternalContentIdentifier] = [other stringByAppendingString:@"#E565A600-07A0-47FF-8C8D-1E8760BA5C05"];
        check(!SGHapticInfoMatches(next, track), @"Another recording with a playback fragment is rejected");
        next[MPNowPlayingInfoPropertyExternalContentIdentifier] = other;
        check(!SGHapticInfoMatches(next, track), @"Different authoritative URI rejected");
        NSString *appleKey = @"test.catalogID";
        NSDictionary *withApple = SGHapticInfoWithAppleID(info, track, code, appleKey, @1440742918, nil);
        check([withApple[appleKey] isEqual:@1440742918], @"Matched recording publishes catalog ID");
        check(!withApple[MPNowPlayingInfoPropertyInternationalStandardRecordingCode], @"Verified catalog ID replaces ISRC so system playback and warning use the same lookup");
        check([SGHapticInfoWithAppleID(info, track, code, appleKey, nil, nil) isEqual:withCode], @"Unresolved catalog ID retains the public ISRC fallback");
        check([SGHapticInfoWithAppleID(withApple, track, nil, appleKey, nil, @1440742918) isEqual:info], @"Switching mode removes both owned identifiers");
        check([SGHapticInfoWithAppleID(withApple, nil, nil, appleKey, nil, @1440742918) isEqual:info], @"Track change removes previous Apple ID");
        check(!SGHapticInfoWithAppleID(next, track, code, appleKey, @1440742918, nil)[appleKey], @"Mismatched Spotify track cannot inherit Apple ID");
        check(!SGHapticInfoWithAppleID(nil, track, code, appleKey, @1440742918, nil), @"Cleared Now Playing stays cleared with catalog lookup");
        check([SGHapticInfoWithAppleID(info, track, code, nil, @1440742918, nil) isEqual:withCode], @"Missing optional system key preserves ISRC path");
        NSMutableDictionary *foreignID = [info mutableCopy]; foreignID[appleKey] = @99;
        check([SGHapticInfoWithAppleID(foreignID, track, nil, appleKey, nil, @1440742918) isEqual:foreignID], @"Unowned catalog metadata preserved");
        NSDictionary *replacement = SGHapticInfoWithAppleID(withApple, track, code, appleKey, @1440621284, @1440742918);
        check([replacement[appleKey] isEqual:@1440621284], @"New verified recording ID replaces owned ID");
        NSMutableDictionary *rest = [replacement mutableCopy];
        [rest removeObjectForKey:appleKey];
        [rest removeObjectForKey:MPNowPlayingInfoPropertyInternationalStandardRecordingCode];
        check([rest isEqual:info], @"Catalog mapping preserves artwork, lyrics and timing");
        NSLog(@"PASS: %d system Music Haptics data checks", checks);
    }
    return 0;
}
