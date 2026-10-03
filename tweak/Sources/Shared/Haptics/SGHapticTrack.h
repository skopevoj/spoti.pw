// Spotify's exact recording identifier for Apple's Music Haptics. No title searches: another
// release or remix can have a different haptic timeline. These helpers have no player state.
#import <Foundation/Foundation.h>

NSString *SGHapticISRC(id value);
BOOL SGHapticTrackURI(NSString *uri);
NSData *SGHapticMetadataRequest(NSString *uri);
NSString *SGHapticISRCFromResponse(NSData *data, NSString *uri);
// Only a haptic-enabled Apple catalog song with the same ISRC and duration is accepted.
NSNumber *SGHapticAppleID(NSData *data, NSString *isrc, double duration);
BOOL SGHapticInfoMatches(NSDictionary *info, NSDictionary *track);
NSDictionary *SGHapticInfo(NSDictionary *info, NSDictionary *track, NSString *isrc);
NSDictionary *SGHapticInfoWithAppleID(NSDictionary *info, NSDictionary *track, NSString *isrc,
                                    NSString *key, NSNumber *identifier, NSNumber *previousIdentifier);
