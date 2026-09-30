#import "Settings/SGModPage.h"
#import "Privacy.h"

// Every switch here forces a flag Spotify ships on to off, so the titles name the hiding: on hides
// the thing, off is Spotify's own value.
static UIViewController *tipsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Tips" intro:SGRestartNote sections:@[
        SGSection(@"Reduce interventions", @[
            SGFlagRow(@"Reduce interventions", @"ios-messaging-reduceinterventions-impl.enabled"),
        ]),
        SGSection(@"Tooltips", @[
            SGKillRow(@"Hide the smart shuffle helper", @"ios-messaging-reduceinterventions-impl.enable_message_smart_shuffle_helper_tooltip"),
            SGKillRow(@"Hide the data saver tip", @"ios-feature-nowplayingbar.data_saver_tooltip"),
            SGKillRow(@"Hide the AI playlist creation tip", @"ios-messaging-reduceinterventions-impl.enable_message_your_library_ai_playlist_creation_tooltip"),
            SGKillRow(@"Hide the watch feed explorer tip", @"ios-messaging-reduceinterventions-impl.enable_message_watch_feed_entity_explorer_tooltip"),
            SGKillRow(@"Hide the account switching tip", @"ios-messaging-reduceinterventions-impl.enable_message_account_switching_tooltip"),
            SGKillRow(@"Hide the concert notifications tip", @"ios-messaging-reduceinterventions-impl.enable_message_live_events_concert_notifications_tooltip"),
            SGKillRow(@"Hide the live event tip", @"ios-messaging-reduceinterventions-impl.enable_message_live_events_event_entity_safe_tooltip"),
            SGKillRow(@"Hide the live event venue tip", @"ios-messaging-reduceinterventions-impl.enable_message_live_events_event_entity_venuename_header_tooltip"),
            SGKillRow(@"Hide the Puffin nudge", @"ios-messaging-reduceinterventions-impl.enable_message_puffin_nudge_end_optimization"),
        ]),
    ] footer:nil];
}

static SGModSection *countersSection(void) {
    NSMutableArray<SGModRow *> *counts = [NSMutableArray array];
    for (NSString *label in SGBlockedLabels()) {
        [counts addObject:SGStatRow(label, ^NSString *{
            return @(SGBlockedCount(label)).stringValue;
        })];
    }
    [counts addObject:SGStatRow(@"Total", ^NSString *{
        return @(SGBlockedCount(nil)).stringValue;
    })];
    [counts addObject:SGActionRow(@"Reset the telemetry counters", nil, ^{ SGResetBlocked(); })];
    return SGSection(@"Telemetry blocked so far", counts);
}

// The switches first and what they have stopped last, so the counters bury no setting.
UIViewController *SGPrivacySettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Privacy & clutter" intro:SGRestartNote sections:@[
        SGSection(@"Privacy", @[
            SGWithSymbol(SGSwitchRow(@"Block telemetry", @"Spotify's own events still go out, since Recents is built from them", SGKeyBlockTelemetry), @"antenna.radiowaves.left.and.right.slash"),
            SGWithSymbol(SGSwitchRow(@"Clean shared links", @"Strips tracking parameters (si, utm) when copying or sharing links", SGKeyCleanSharedURLs), @"link"),
        ]),
        SGSection(@"Clutter", @[
            SGWithSymbol(SGOptionRow(@"Hide the video carousel in Search", nil, SGKeyHideSearchVideos), @"play.rectangle.on.rectangle"),
            SGWithSymbol(SGOptionRow(@"Hide social proof in Search", nil, SGKeyHideSocialProof), @"person.2"),
            SGWithSymbol(SGPageRow(@"Tips", ^UIViewController *{ return tipsPage(); }), @"lightbulb"),
        ]),
        countersSection(),
    ] footer:nil];
}
