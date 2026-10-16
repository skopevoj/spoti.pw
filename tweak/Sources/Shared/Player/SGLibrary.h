// Liked Songs from the mod's own controls (the Live Activity, AirPods gestures): a track saved to or taken
// out of it through Spotify's Web API, with the Authorization of Spotify's own requests (Shared/Lyrics),
// which goes nowhere but Spotify. Main thread; `done` comes back on it.
#import <Foundation/Foundation.h>

// `trackID` is the base62 id. NO at once, without asking, for a local file or before Spotify has sent a
// request of its own to borrow the token from.
BOOL SGLibrarySaveTrack(NSString *trackID, BOOL save, void (^done)(BOOL saved));
// Whether the mod saved the track this session, for controls that show it.
BOOL SGLibrarySavedThisSession(NSString *trackID);
