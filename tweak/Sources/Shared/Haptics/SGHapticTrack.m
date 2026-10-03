#import "SGHapticTrack.h"
#import "Shared/Lyrics/Protobuf.h"
#import <MediaPlayer/MediaPlayer.h>

NSString *SGHapticISRC(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *code = [value uppercaseString];
    if (code.length != 12) return nil;
    for (NSUInteger i = 0; i < code.length; i++) {
        unichar c = [code characterAtIndex:i];
        BOOL letter = c >= 'A' && c <= 'Z', digit = c >= '0' && c <= '9';
        if (!(i < 2 ? letter : i < 5 ? letter || digit : digit)) return nil;
    }
    return code;
}

BOOL SGHapticTrackURI(NSString *uri) {
    if (![uri isKindOfClass:NSString.class] || ![uri hasPrefix:@"spotify:track:"] || uri.length != 36) return NO;
    return [[uri substringFromIndex:14] rangeOfCharacterFromSet:
        [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"] invertedSet]].location == NSNotFound;
}

// spotify.extendedmetadata.BatchedEntityRequest, TRACK_V4 = 10. Schema and endpoint:
// github.com/librespot-org/librespot (protocol/proto/extended_metadata.proto,
// entity_extension_data.proto, extension_kind.proto, metadata.proto; core/src/spclient.rs).
NSData *SGHapticMetadataRequest(NSString *uri) {
    if (!SGHapticTrackURI(uri)) return nil;
    NSData *query = SGPBSerialize(@[SGPBVarint(1, 10)]);
    NSData *entity = SGPBSerialize(@[SGPBString(1, uri), SGPBBytes(2, query)]);
    return SGPBSerialize(@[SGPBBytes(2, entity)]);
}

static NSArray<SGPBField *> *message(SGPBField *field) {
    return field.wire == 2 && field.payload.length ? SGPBParse(field.payload) : nil;
}

NSString *SGHapticISRCFromResponse(NSData *data, NSString *uri) {
    if (!SGHapticTrackURI(uri) || !data.length || data.length > 1024 * 1024) return nil;
    for (SGPBField *arrayField in SGPBParse(data)) {
        if (arrayField.number != 2) continue;
        NSArray *array = message(arrayField);
        if (SGPBFirst(array, 2).varint != 10) continue;
        uint64_t providerStatus = SGPBFirst(message(SGPBFirst(array, 1)), 1).varint;
        // Spotify 9.1.78's service sends HTTP-style 200 in both headers. An omitted provider
        // status is also allowed by the proto3 schema, but an explicit failure is not.
        if (providerStatus != 0 && providerStatus != 200) continue;
        for (SGPBField *entityField in array) {
            if (entityField.number != 3) continue;
            NSArray *entity = message(entityField);
            if (![SGPBText(SGPBFirst(entity, 2)) isEqualToString:uri]) continue;
            uint64_t status = SGPBFirst(message(SGPBFirst(entity, 1)), 1).varint;
            if (status != 200) continue;
            NSArray *any = message(SGPBFirst(entity, 3));
            NSString *type = SGPBText(SGPBFirst(any, 1));
            if (![type isEqualToString:@"type.googleapis.com/spotify.metadata.Track"]) continue;
            NSArray *track = message(SGPBFirst(any, 2));
            for (SGPBField *externalField in track) {
                if (externalField.number != 10) continue;
                NSArray *external = message(externalField);
                if (![SGPBText(SGPBFirst(external, 1)) isEqualToString:@"isrc"]) continue;
                NSString *code = SGHapticISRC(SGPBText(SGPBFirst(external, 2)));
                if (code) return code;
            }
        }
    }
    return nil;
}

NSNumber *SGHapticAppleID(NSData *data, NSString *isrc, double duration) {
    NSString *code = SGHapticISRC(isrc);
    if (!code || !data.length || data.length > 1024 * 1024 || !isfinite(duration) || duration <= 0) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    id songs = [root isKindOfClass:NSDictionary.class] ? ((NSDictionary *)root)[@"data"] : nil;
    if (![songs isKindOfClass:NSArray.class]) return nil;
    for (id entry in songs) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *song = entry;
        if (![song[@"type"] isEqual:@"songs"]) continue;
        NSDictionary *attributes = song[@"attributes"];
        id identifier = song[@"id"];
        if (![attributes isKindOfClass:NSDictionary.class] || ![identifier isKindOfClass:NSString.class] ||
            ![SGHapticISRC(attributes[@"isrc"]) isEqual:code]) continue;
        id length = attributes[@"durationInMillis"], haptics = attributes[@"hasHaptics"];
        if (![length isKindOfClass:NSNumber.class] || ![haptics isKindOfClass:NSNumber.class] ||
            ![haptics isEqual:@YES] || !isfinite([length doubleValue]) ||
            fabs([length doubleValue] / 1000.0 - duration) >= 2) continue;
        if (![identifier length] || [identifier length] > 18 || [identifier rangeOfCharacterFromSet:
            [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) continue;
        long long number = [identifier longLongValue];
        if (number > 0) return @(number);
    }
    return nil;
}

// Some Spotify builds supply an external URI; otherwise require title, album and duration.
// Never compare the artist: lock-screen lyrics deliberately replace that field with a lyric.
BOOL SGHapticInfoMatches(NSDictionary *info, NSDictionary *track) {
    if (!info.count || !track.count) return NO;
    id identifier = info[MPNowPlayingInfoPropertyExternalContentIdentifier];
    if ([identifier isKindOfClass:NSString.class] && [identifier hasPrefix:@"spotify:"]) {
        // Spotify 9.1.78 appends a per-playback UUID fragment in Now Playing. The recording is
        // the URI before that fragment; the fragment changes even while the same song plays.
        NSString *uri = [identifier componentsSeparatedByString:@"#"].firstObject;
        return SGHapticTrackURI(uri) && [uri isEqualToString:track[@"uri"]];
    }
    NSString *title = track[@"title"], *album = track[@"album"];
    id duration = info[MPMediaItemPropertyPlaybackDuration];
    return title.length && album.length && [info[MPMediaItemPropertyTitle] isEqual:title] &&
        [info[MPMediaItemPropertyAlbumTitle] isEqual:album] && [duration isKindOfClass:NSNumber.class] &&
        [track[@"duration"] doubleValue] > 0 && fabs([duration doubleValue] - [track[@"duration"] doubleValue]) < 2;
}

NSDictionary *SGHapticInfo(NSDictionary *info, NSDictionary *track, NSString *isrc) {
    if (!info) return nil;
    if (@available(iOS 18.0, macOS 15.0, *)) {
        NSString *code = SGHapticInfoMatches(info, track) ? SGHapticISRC(isrc) : nil;
        NSString *key = MPNowPlayingInfoPropertyInternationalStandardRecordingCode;
        if ((!code && !info[key]) || [info[key] isEqual:code]) return info;
        NSMutableDictionary *result = [info mutableCopy];
        if (code) result[key] = code;
        else [result removeObjectForKey:key];
        return result;
    }
    return info;
}

NSDictionary *SGHapticInfoWithAppleID(NSDictionary *info, NSDictionary *track, NSString *isrc,
                                    NSString *key, NSNumber *identifier, NSNumber *previousIdentifier) {
    NSDictionary *result = SGHapticInfo(info, track, isrc);
    if (!result || !key.length) return result;
    BOOL removePrevious = previousIdentifier && [result[key] isEqual:previousIdentifier];
    BOOL add = identifier.longLongValue > 0 && SGHapticISRC(isrc) && SGHapticInfoMatches(info, track);
    if (!removePrevious && !add) return result;
    NSMutableDictionary *updated = [result mutableCopy];
    if (removePrevious) [updated removeObjectForKey:key];
    if (add) {
        updated[key] = identifier;
        // The system player accepts the catalog ID, but MediaRemoteUI prefers an ISRC
        // when both are present. A failed ISRC lookup then shows Unavailable while the
        // matching catalog track is playing. Publish one verified identifier to both.
        if (@available(iOS 18.0, macOS 15.0, *))
            [updated removeObjectForKey:MPNowPlayingInfoPropertyInternationalStandardRecordingCode];
    }
    return updated;
}
