// What SGRKaraokeView.m links against, answering the way the phone would for one track playing on a
// clock of the harness's own: the lines are whatever main.m keeps, the position runs from the launch
// line's -at at -rate, and holds at -pauseAt for -holdFor seconds before it runs on.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

UIColor *SGRAccentColor(void) { return nil; }

NSString *const SGPlayerTransitionNotification = @"spotifyglass.playerTransition";
NSString *const SGPlayerTransitionEndedNotification = @"spotifyglass.playerTransitionEnded";
CFTimeInterval SGPlayerTransitionEnds(void) { return 0; }

void SGRPlayFeedback(NSInteger feedback) {}
void SGPlayFeedback(NSInteger feedback) {}   // the name it has had since Haptics moved to Shared
NSString *SGLyricsCreditFor(NSString *trackID) { return @"the harness"; }
// -translateTo es: the language the Lyrics page would ask translations for.
NSString *SGLyricsTranslationLanguage(void) { return [NSUserDefaults.standardUserDefaults stringForKey:@"translateTo"]; }

// Line meanings: -title and -artist name the track Genius is searched for, and the setting's key
// (-spotifyglass.lyricsMeanings 3) turns them on.
@interface SGHarnessTrack : NSObject
@property (nonatomic, copy) NSString *trackTitle, *artistName;
@end
@implementation SGHarnessTrack
@end
id SGKaraokeTrackFor(NSString *trackID) {
    SGHarnessTrack *track = [SGHarnessTrack new];
    track.trackTitle = [NSUserDefaults.standardUserDefaults stringForKey:@"title"];
    track.artistName = [NSUserDefaults.standardUserDefaults stringForKey:@"artist"];
    return track;
}
id SGChoiceRow(NSString *title, NSString *subtitle, NSString *key, NSArray *choices, NSInteger fallback) { return nil; }
UIViewController *SGTopController(void) {
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIViewController *top = scene.windows.firstObject.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

static NSArray<SGKaraokeLine *> *sg_lines;
static double sg_from = -1, sg_rate = 1, sg_pauseAt = -1, sg_holdFor = 0;
static CFTimeInterval sg_since, sg_heldAt;

void SGHarnessStartClock(double at, double rate, double pauseAt, double holdFor) {
    sg_from = at;
    sg_rate = rate;
    sg_pauseAt = pauseAt;
    sg_holdFor = holdFor;
    sg_since = CACurrentMediaTime();
    sg_heldAt = 0;
}

NSString *SGKaraokePlayingTrack(void) { return @"harness"; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) { return sg_lines; }
void SGKaraokeKeepLines(NSString *trackID, NSArray<SGKaraokeLine *> *lines) { sg_lines = lines; }

NSInteger SGKaraokePositionMs(void) {
    if (sg_from < 0) return -1;
    CFTimeInterval now = CACurrentMediaTime();
    double at = sg_from + (now - sg_since) * 1000 * sg_rate;
    if (sg_pauseAt >= 0 && at >= sg_pauseAt) {
        // Held where it was asked to stop, then on from there as if never stopped.
        if (!sg_heldAt) sg_heldAt = now;
        if (sg_holdFor <= 0 || now - sg_heldAt < sg_holdFor) return (NSInteger)sg_pauseAt;
        SGHarnessStartClock(sg_pauseAt, sg_rate, -1, 0);
        return (NSInteger)sg_pauseAt;
    }
    return (NSInteger)at;
}

static NSUInteger sg_seekCount;
NSUInteger SGHarnessSeekCount(void) { return sg_seekCount; }
void SGKaraokeSeek(NSInteger ms) { sg_seekCount++; SGHarnessStartClock(ms, sg_rate, -1, 0); }
