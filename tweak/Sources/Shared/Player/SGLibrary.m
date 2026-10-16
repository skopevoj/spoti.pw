// SGLibrary.h says what this is for.
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "SGLibrary.h"

static NSMutableSet<NSString *> *sg_saved;

BOOL SGLibrarySavedThisSession(NSString *trackID) {
    return trackID && [sg_saved containsObject:trackID];
}

BOOL SGLibrarySaveTrack(NSString *trackID, BOOL save, void (^done)(BOOL saved)) {
    NSString *authorization = SGKaraokeSpotifyAuthorization();
    if (!trackID.length || SGKaraokeIsLocalTrack(trackID) || !authorization) {
        SGLog(@"library: cannot %@ %@ (%@)", save ? @"save" : @"remove", trackID, authorization ? @"no track" : @"no token yet");
        return NO;
    }
    if (!sg_saved) sg_saved = [NSMutableSet set];
    NSURL *url = [NSURL URLWithString:[@"https://api.spotify.com/v1/me/tracks?ids=" stringByAppendingString:trackID]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = save ? @"PUT" : @"DELETE";
    [request setValue:authorization forHTTPHeaderField:@"Authorization"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ok = status >= 200 && status < 300;
            if (ok && save) [sg_saved addObject:trackID];
            else if (ok) [sg_saved removeObject:trackID];
            SGLog(@"library: %@ %@ -> HTTP %ld%@", save ? @"save" : @"remove", trackID, (long)status,
                  error ? [@", " stringByAppendingString:error.localizedDescription] : @"");
            if (done) done(ok ? save : !save);
        });
    }] resume];
    return YES;
}
