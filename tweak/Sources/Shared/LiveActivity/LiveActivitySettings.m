// The Live Activity page (App/ModSettings.x links it from the root, under either look).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "LiveActivity.h"

static NSArray<NSString *> *viewNames(void) {
    return @[@"Lyrics", @"Queue", @"Control menu", @"Player"];
}

UIViewController *SGLiveActivitySettingsPage(void) {
    SGModRow *on = SGOptionRow(@"Live Activity", nil, SGKeyLiveActivity);
    on.changed = ^(BOOL value) { SGSetLiveActivityEnabled(value); };
    SGModRow *view = SGChoiceRow(@"Shows", nil, SGKeyLiveActivityView, viewNames(), SGLiveActivityLyrics);
    SGModRow *translation = SGSwitchRow(@"Translation", @"Under the line, where the lyrics have one", SGKeyLiveActivityTranslation);
    translation.visible = ^BOOL { return SGInt(SGKeyLiveActivityView, SGLiveActivityLyrics) == SGLiveActivityLyrics; };
    view.choiceNotes = @[@"The line being sung, and the next one", @"The tracks up next, a tap playing one",
                         @"Tabs of controls, the queue and a sleep timer", @"The cover in a ring of bars, the controls and a bar to seek on"];
    BOOL (^isPlayer)(void) = ^BOOL { return SGInt(SGKeyLiveActivityView, SGLiveActivityLyrics) == SGLiveActivityPlayer; };
    SGModRow *bars = SGSwitchRow(@"Visualizer", @"Bars round the cover, in the cover's colours", SGKeyLiveActivityBars);
    bars.visible = isPlayer;
    SGModRow *rate = SGChoiceRow(@"Bars move", nil, SGKeyLiveActivityBarsRate, @[@"Once a second", @"Twice a second", @"Four times a second"], 1);
    rate.choiceNotes = @[@"Lightest on the battery", @"Gliding from one to the next", @"The most lively, and the most battery"];
    rate.choiceFooter = @"iOS draws a Live Activity again only when Spotify sends it something, and may hold back updates that come too fast, "
                         "so the bars glide between steps rather than move with every beat as the ring in the player does.";
    rate.visible = isPlayer;
    SGWaitsOn(rate, SGKeyLiveActivityBars, YES);
    return [[SGModPage alloc] initWithTitle:@"Live Activity" intro:nil sections:@[
        SGNotedSection(nil, @[on, view, translation, bars, rate],
                       @"The card takes the cover's colour and shows how far into the song you are; in Player, a tap along the bar "
                        "jumps there. It also appears on Apple Watch, in CarPlay and in StandBy, where iOS shows it."),
    ] footer:nil];
}

NSString *SGLiveActivitySummary(void) {
    if (!SGFlag(SGKeyLiveActivity, NO)) return @"Off";
    NSInteger index = SGInt(SGKeyLiveActivityView, SGLiveActivityLyrics);
    NSArray<NSString *> *names = viewNames();
    return index >= 0 && index < (NSInteger)names.count ? names[index] : names.firstObject;
}
