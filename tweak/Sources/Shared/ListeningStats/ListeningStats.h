// Listening stats (Mod Settings > Listening stats), under either look: what was listened to, for how
// long and how often, kept only on this iPhone. The player's state (Shared/Player/PlayerState.h) says
// when a track plays and stops; each time a track is listened to is one entry in a log, a play once it
// has run 30 seconds, the way Spotify counts one. The page reads the log for the last four weeks, the
// last six months and all time: minutes, plays, the top tracks and artists.
//
//     SGListeningLog.m          the recorder and the log, Application Support/spoti.pw/Stats/listening.json
//     ListeningStats.x          starts the recorder at launch
//     ListeningStatsSettings.m  the page
#import <UIKit/UIKit.h>

#define SGKeyListeningStats @"spotifyglass.listeningStats"                 // on until switched off
#define SGKeyListeningStatsPeriod @"spotifyglass.listeningStats.period"    // an SGListeningPeriod

typedef NS_ENUM(NSInteger, SGListeningPeriod) {
    SGListeningPeriodMonth = 0,   // the last four weeks
    SGListeningPeriodHalfYear,    // the last six months
    SGListeningPeriodAllTime,
};

@interface SGListeningEntry : NSObject
@property (nonatomic, copy) NSString *uri, *title, *subtitle;
@property (nonatomic) NSInteger plays;
@property (nonatomic) double seconds;
@end

@interface SGListeningSummary : NSObject
@property (nonatomic) double seconds;
@property (nonatomic) NSInteger plays, tracks, artists, days;
@property (nonatomic, copy) NSArray<SGListeningEntry *> *topTracks, *topArtists;
@end

// From the switch and at launch: starts or stops recording. Main thread.
void SGListeningStatsApply(void);
// What the log says for a period, the top `count` of each. Main thread.
SGListeningSummary *SGListeningSummarize(SGListeningPeriod period, NSUInteger count);
// Empties the log.
void SGListeningClear(void);
// Spotify's own history, from its privacy page's data download: the account data's
// StreamingHistory_music_*.json (end time, artist, track, ms played) or the extended history's
// Streaming_History_Audio_*.json (ts, ms_played, the names and spotify_track_uri). Listens already in the
// log are left out, so a file read twice adds nothing. `done` comes back on the main thread.
void SGListeningImport(NSArray<NSURL *> *files, void (^done)(NSUInteger added, NSString *problem));

UIViewController *SGListeningStatsPage(void);
// Beside the row on Mod Settings' main page: the last four weeks' minutes, or Off.
NSString *SGListeningStatsSummary(void);
