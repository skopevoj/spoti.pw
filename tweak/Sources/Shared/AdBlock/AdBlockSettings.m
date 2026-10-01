#import "Settings/SGModPage.h"
#import "AdBlock.h"
#import "Shared/Privacy/Privacy.h"

NSString *const SGFakePremiumWarning = @"This is the part of EeveeSpotify Spotify's takedown went after, and it has not been tested here. It can end in a forced logout or worse for the account. A Premium account gains nothing from it.";

// Every switch here forces a flag Spotify ships on to off, so the titles name the blocking: on stops
// the thing, off is Spotify's own value. Hide ads and Hide upsells already force the first two
// sections off, which locks those rows.
static UIViewController *adFlagsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Ad and upsell flags" intro:SGRestartNote sections:@[
        SGNotedSection(@"Ads", @[
            SGKillRow(@"Block the ad when the app opens", @"ios-feature-adonappopen.enabled"),
            SGKillRow(@"Block its CTA card", @"ios-feature-adonappopen.cta_card_enabled"),
        ], @"Locked while Hide ads is on."),
        SGNotedSection(@"Upsells", @[
            SGKillRow(@"Hide the shuffle toggle upsell", @"ios-feature-shuffletoggleupsell.is_enabled_pt2"),
            SGKillRow(@"Hide the shuffle upsell in the video player", @"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled"),
        ], @"Locked while Hide upsells is on."),
        SGSection(@"Reduce interventions", @[
            SGFlagRow(@"Reduce interventions", @"ios-messaging-reduceinterventions-impl.enabled"),
        ]),
        SGSection(@"Tooltips", @[
            SGKillRow(@"Hide the smart shuffle helper", @"ios-messaging-reduceinterventions-impl.enable_message_smart_shuffle_helper_tooltip"),
            SGKillRow(@"Hide the data saver tip", @"ios-feature-nowplayingbar.data_saver_tooltip"),
            SGKillRow(@"Hide the player suggestions upsell", @"ios-messaging-reduceinterventions-impl.enable_message_reinvent_free_n_p_v_suggestions_upsell"),
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

// The switches first and what they have stopped last, so the counters bury no setting.
UIViewController *SGAdsSettingsPage(void) {
    NSMutableArray<SGModRow *> *counts = [NSMutableArray array];
    for (NSString *label in SGAdBlockLabels()) {
        [counts addObject:SGStatRow(label, ^NSString *{
            return @(SGAdBlockCount(label)).stringValue;
        })];
    }
    [counts addObject:SGStatRow(@"Total", ^NSString *{
        return @(SGAdBlockCount(nil)).stringValue;
    })];
    [counts addObject:SGActionRow(@"Reset the counters", nil, ^{ SGResetAdBlock(); })];

    SGModRow *fakePremium = SGOptionRow(@"Spoof Premium", nil, SGKeyFakePremium);
    fakePremium.warning = SGFakePremiumWarning;

    return [[SGModPage alloc] initWithTitle:@"Premium, ads & privacy" intro:SGRestartNote sections:@[
        SGNotedSection(@"Ads", @[
            SGWithSymbol(SGOptionRow(@"Hide ads", nil, SGKeyHideAds), @"speaker.slash"),
            SGWithSymbol(SGOptionRow(@"Hide upsells", nil, SGKeyHideUpsells), @"hand.raised"),
            SGWithSymbol(SGOptionRow(@"Hide the video carousel in Search", nil, SGKeyHideSearchVideos), @"play.rectangle.on.rectangle"),
            SGWithSymbol(SGOptionRow(@"Hide social proof in Search", nil, SGKeyHideSocialProof), @"person.2"),
            SGWithSymbol(SGPageRow(@"Ad and upsell flags", ^UIViewController *{ return adFlagsPage(); }), @"flag"),
        ], @"Audio ads between songs need Spoof Premium."),
        SGNotedSection(@"Premium", @[
            SGWithSymbol(fakePremium, @"crown"),
        ], @"Free accounts only."),
        SGPrivacySection(),
        SGSection(@"Ads blocked so far", counts),
        SGPrivacyCountersSection(),
    ] footer:nil];
}
