// What the harness does not compile: the accent hook (SGRAccent.x), the repaint hook (SGRRepaint.x), the
// tab bar's composition (Navbar.x) and Mod Settings. Spotify's order of tabs stays as the mock has it.
#import <UIKit/UIKit.h>

UIColor *SGRAccentColor(void) { return nil; }
__weak UIView *sgr_nowPlayingRoot = nil;
__weak UIView *sgr_nowPlayingCard = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;

void SGRComposeTabBar(UIView *tabBar) {}
void SGRLogTabBarRow(UIView *tabBar) {}
void SGOpenModSettings(UIView *source) {}
UIView *SGRCurrentModTab(void) { return nil; }
void SGRTabPicked(UIView *item) {}

#pragma mark - a player for the mini player (`inline`)

@protocol SGHarnessObserver
- (void)playerStateDidChange:(id)state;
@end

// Shared/Player/PlayerState.x and SGKaraokePlayer (Shared/Lyrics) are not compiled: a player of three
// tracks stands in, skipping as the mini player's swipe tells it and telling its observers.
@interface SGHarnessTrack : NSObject
@property (nonatomic, copy) NSString *trackTitle, *artistName;
@property (nonatomic, copy) id URI;
@end
@implementation SGHarnessTrack
@end

@interface SGHarnessState : NSObject
@property (nonatomic, strong) SGHarnessTrack *track;
@property (nonatomic) BOOL isPaused;
@end
@implementation SGHarnessState
@end

static NSHashTable *sg_observers;
static SGHarnessState *sg_state;
static NSInteger sg_index;

static SGHarnessState *stateAt(NSInteger index) {
    NSArray *titles = @[@"Stay High", @"Espresso", @"Birds of a Feather"], *artists = @[@"Juice WRLD", @"Sabrina Carpenter", @"Billie Eilish"];
    NSInteger i = ((index % 3) + 3) % 3;
    SGHarnessTrack *track = [SGHarnessTrack new];
    track.trackTitle = titles[i];
    track.artistName = artists[i];
    track.URI = [NSString stringWithFormat:@"spotify:track:%ld", (long)i];
    SGHarnessState *state = [SGHarnessState new];
    state.track = track;
    return state;
}

id SGPlayerState(void) {
    if (!sg_state) sg_state = stateAt(0);
    return sg_state;
}

void SGAddPlayerStateObserver(id observer) {
    if (!sg_observers) sg_observers = [NSHashTable weakObjectsHashTable];
    [sg_observers addObject:observer];
}

NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSString.class] ? uri : nil;
}

@interface SGHarnessPlayer : NSObject
@end
@implementation SGHarnessPlayer
- (void)step:(NSInteger)by {
    sg_index += by;
    sg_state = stateAt(sg_index);
    NSLog(@"[harness] player skips %+ld to %@", (long)by, sg_state.track.trackTitle);
    for (id<SGHarnessObserver> observer in sg_observers.allObjects) [observer playerStateDidChange:sg_state];
}
- (void)setPaused:(BOOL)paused {
    SGHarnessState *state = stateAt(sg_index);
    state.isPaused = paused;
    sg_state = state;
    NSLog(@"[harness] player %@", paused ? @"pauses" : @"resumes");
    for (id<SGHarnessObserver> observer in sg_observers.allObjects) [observer playerStateDidChange:sg_state];
}
- (id)pause:(id)options { [self setPaused:YES]; return @"pause"; }
- (id)resume:(id)options { [self setPaused:NO]; return @"resume"; }
- (id)skipToNextTrackWithOptions:(id)options { [self step:1]; return @"next"; }
- (id)skipToPreviousTrackWithOptions:(id)options { [self step:-1]; return @"previous"; }
@end

id SGKaraokePlayer(void) {
    static SGHarnessPlayer *player;
    if (!player) player = [SGHarnessPlayer new];
    return player;
}
