#import "Core/SGCore.h"
#import "Privacy.h"

static NSString *const socialProofFlags[] = {
    @"ios-feature-search.social_proof_playlist_enabled",
    @"ios-feature-search.social_proof_plays_in_search_enabled",
};

static BOOL forcedOff(NSString *key, BOOL videos, BOOL socialProof) {
    if (videos && [key isEqualToString:@"ios-feature-search.video_carousel_section_enabled"]) return YES;
    if (!socialProof) return NO;
    for (size_t i = 0; i < sizeof(socialProofFlags) / sizeof(socialProofFlags[0]); i++) {
        if ([key isEqualToString:socialProofFlags[i]]) return YES;
    }
    return NO;
}

// After an override from the All flags page, and locking the rows that would turn the same flag off.
__attribute__((constructor)) static void registerForcer(void) {
    // Read once: Spotify asks for every flag it has through here as it starts.
    SGFlagForcer atLaunch = ^id(NSString *key) {
        static BOOL videos, socialProof;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            videos = SGHidden(SGKeyHideSearchVideos);
            socialProof = SGHidden(SGKeyHideSocialProof);
        });
        return forcedOff(key, videos, socialProof) ? @NO : nil;
    };
    SGFlagForcer locked = ^id(NSString *key) {
        return forcedOff(key, SGHidden(SGKeyHideSearchVideos), SGHidden(SGKeyHideSocialProof)) ? @NO : nil;
    };
    SGRegisterFlagForcer(NO, atLaunch, locked);
}
