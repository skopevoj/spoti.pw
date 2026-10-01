// Spoof Premium: the UCS response, which carries the account's product state and its remote
// config, rewritten as it arrives. The attributes and the flag rules are EeveeSpotify's. Offline,
// audio quality and the social session attributes are left alone: the server still decides those,
// and a spoofed one only shows UI the request behind it will fail.
//
// UcsResponse: 1 ResolveResponse { 1 ResolveConfiguration { 3 repeated AssignedValue } },
//   3 AccountAttributesResponse { 1 repeated entry { 1 key, 2 AccountAttribute { 2 bool, 4 string } } }
// AssignedValue: 1 { 1 scope, 2 name }, 3 BoolValue { 1 }, 4 IntValue { 1 }, 5 EnumValue { 1 }
// A customize body is CustomizeMessage { 1 UcsResponse }; bootstrap wraps that in 2 { 1 { 1 { it } } }.
#import "Core/SGCore.h"
#import "AdBlock.h"
#import "Protobuf.h"

#pragma mark - account attributes

// A string goes in as one, a number as a bool.
static NSDictionary<NSString *, id> *forcedAttributes(void) {
    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    iso.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    NSString *yearOn = [iso stringFromDate:[NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitYear value:1 toDate:NSDate.date options:0]];
    return @{
        @"ads": @NO,
        @"ab-ad-player-targeting": @"0",
        @"allow-advertising-id-transmission": @NO,
        @"restrict-advertising-id-transmission": @YES,
        @"can_use_superbird": @YES,
        @"enable-crossfade-product-state": @"1",
        @"enable-gapless-product-state": @"1",
        @"catalogue": @"premium",
        @"financial-product": @"pr:premium,tc:0",
        @"is-eligible-premium-unboxing": @YES,
        @"name": @"Spotify Premium",
        @"nft-disabled": @"1",
        @"on-demand": @YES,
        @"payments-initial-campaign": @"default",
        @"player-license": @"premium",
        @"player-license-v2": @"premium",
        @"product-expiry": yearOn,
        @"shuffle-eligible": @YES,
        @"streaming-rules": @"",
        @"subscription-enddate": yearOn,
        @"type": @"premium",
        @"unrestricted": @YES,
        @"high-bitrate": @YES,
        @"loudness-levels": @"1:-5.0,0.0,3.0:-2.0",
        @"pick-and-shuffle": @NO,
        @"mixing-tools": @"EDIT",
        @"your-library-tags": @YES,
        @"libspotify": @YES,
        @"mobile": @YES,
    };
}

// Attributes that would have the client validate the state against the server, or offer a trial.
static NSString *const strippedAttributes[] = {
    @"payment-state", @"last-premium-activation-date", @"on-demand-trial", @"on-demand-trial-in-progress",
    @"smart-shuffle", @"at-signal", @"feature-set-id-masked", @"strider-key", @"is-eligible-for-trial",
    @"is-eligible-for-upsell", @"upsell-state", @"ad-session-persistence", @"ad-formats-preroll-video",
};

static BOOL stripped(NSString *key) {
    if ([key hasPrefix:@"is-premium-eligible"]) return YES;
    for (size_t i = 0; i < sizeof(strippedAttributes) / sizeof(strippedAttributes[0]); i++) {
        if ([key isEqualToString:strippedAttributes[i]]) return YES;
    }
    return NO;
}

static SGPBField *attributeEntry(NSString *key, id value) {
    SGPBField *attribute = [value isKindOfClass:NSString.class] ? SGPBString(4, value) : SGPBVarint(2, [value boolValue]);
    return SGPBBytes(1, SGPBSerialize(@[SGPBString(1, key), SGPBBytes(2, SGPBSerialize(@[attribute]))]));
}

static NSData *patchAttributes(NSData *response) {
    NSMutableArray<SGPBField *> *fields = SGPBParse(response);
    if (!fields) return nil;
    NSDictionary<NSString *, id> *forced = forcedAttributes();
    NSMutableArray<SGPBField *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (SGPBField *field in fields) {
        NSString *key = field.number == 1 && field.wire == 2 ? SGPBText(SGPBFirst(SGPBParse(field.payload), 1)) : nil;
        if (!key || (!forced[key] && !stripped(key))) {
            [out addObject:field];
            continue;
        }
        if (!forced[key]) continue;
        [seen addObject:key];
        [out addObject:attributeEntry(key, forced[key])];
    }
    for (NSString *key in forced) {
        if (![seen containsObject:key]) [out addObject:attributeEntry(key, forced[key])];
    }
    return SGPBSerialize(out);
}

#pragma mark - remote config

typedef NS_ENUM(NSInteger, SGRuleKind) { SGRuleRemove, SGRuleSet, SGRuleForce, SGRuleEnum };
// A NULL scope or name matches any. Set changes a value that is there, Force adds it when it is not.
typedef struct { const char *scope, *name; SGRuleKind kind; BOOL on; const char *text; } SGRule;

static const SGRule rules[] = {
    // The ios-feature-settings flags only draw the rows; the player core gates each on its own scope.
    {"ios-feature-settings", "crossfade_enabled", SGRuleForce, YES, NULL},
    {"ios-feature-settings", "automix_enabled", SGRuleForce, YES, NULL},
    {"core-playback-setup", "crossfade_enabled", SGRuleForce, YES, NULL},
    {"core-automix", "automix_enabled", SGRuleForce, YES, NULL},
    {"ios-feature-settings", "use_playback_settings_crossfade", SGRuleForce, NO, NULL},
    {"ios-feature-settings", "use_playback_settings_gapless", SGRuleForce, NO, NULL},
    {NULL, "enable_common_capping", SGRuleRemove, NO, NULL},
    {NULL, "enable_pns_common_capping", SGRuleRemove, NO, NULL},
    {NULL, "enable_pick_and_shuffle_common_capping", SGRuleRemove, NO, NULL},
    {NULL, "enable_pick_and_shuffle_dynamic_cap", SGRuleRemove, NO, NULL},
    {NULL, "pick_and_shuffle_timecap", SGRuleRemove, NO, NULL},
    {"ios-feature-queue", NULL, SGRuleRemove, NO, NULL},
    {NULL, "enable_free_on_demand_experiment", SGRuleRemove, NO, NULL},
    {NULL, "enable_free_on_demand_context_menu_experiment", SGRuleRemove, NO, NULL},
    {NULL, "enable_mft_plus_queue", SGRuleRemove, NO, NULL},
    {NULL, "enable_mft_plus_extended_queue", SGRuleRemove, NO, NULL},
    {NULL, "enable_playback_timeout_service", SGRuleSet, NO, NULL},
    {NULL, "enable_playback_timeout_error_ui", SGRuleSet, NO, NULL},
    {NULL, "playback_timeout_action", SGRuleEnum, NO, "Nothing"},
    {NULL, "is_remove_from_queue_enabled_for_mft_plus", SGRuleRemove, NO, NULL},
    {NULL, "is_reordering_for_mft_plus_allowed", SGRuleRemove, NO, NULL},
    {NULL, "ads", SGRuleSet, NO, NULL},
    {NULL, "ad_metadata", SGRuleRemove, NO, NULL},
    {NULL, "ad_slots", SGRuleRemove, NO, NULL},
    {NULL, "enable_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_audio_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_display_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_video_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_premium_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_upsell", SGRuleSet, NO, NULL},
    {NULL, "show_upsell", SGRuleSet, NO, NULL},
    {NULL, "show_premium_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_campaigns", SGRuleSet, NO, NULL},
    {NULL, "enable_promotions", SGRuleSet, NO, NULL},
    {NULL, "enable_search_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_search_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_search_banner_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_search_banner_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_search_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_search_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_search_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_home_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_home_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_home_banner_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_home_banner_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_home_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_home_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_home_upsell", SGRuleSet, NO, NULL},
    {"ios-feature-shuffletoggleupsell", "is_enabled_pt2", SGRuleForce, NO, NULL},
    {"ios-feature-shuffletoggleupsell", "linear_upsell_new_style_experiment_enabled", SGRuleForce, NO, NULL},
    {"ios-feature-shuffletoggleupsell", "play_modes_upsell_new_style_experiment_enabled", SGRuleForce, NO, NULL},
    {"ios-jam-freeusershuffleupsellsheetpage-impl", "free_user_shuffle_upsell_sheet_enabled", SGRuleForce, NO, NULL},
    {"ios-jam-freeuserskipupsellpage-impl", "free_user_skip_upsell_sheet_enabled", SGRuleForce, NO, NULL},
    {"ios-jam-freehostedjamsupsell-impl", "free_hosted_jams_upsell_enabled", SGRuleForce, NO, NULL},
    {"ios-reinventfree-contextualupsellpremiumpromo-impl", "is_promo_cta_enabled", SGRuleForce, NO, NULL},
    {"ios-reinventfree-contextualupsellpremiumpromo-impl", "show_time_cap_upsell_with_premium_badge", SGRuleForce, NO, NULL},
    {"ios-reinventfree-controllerui-impl", "enable_video_time_cap_upsell", SGRuleForce, NO, NULL},
    {"ios-reinventfree-controllerui-impl", "enable_video_time_cap_upsell_on_search", SGRuleForce, NO, NULL},
    {"ios-reinventfree-timecappivot-impl", "music_video_upsell_enabled", SGRuleForce, NO, NULL},
    {"ios-settings-mediaqualitypageplugin-impl", "is_gbb_upsell_enabled", SGRuleForce, NO, NULL},
    {"ios-settings-mediaqualitypageplugin-impl", "should_show_pigeon_upsell", SGRuleForce, NO, NULL},
    {"ios-system-listeningparties", "preview_ended_upsell_enabled", SGRuleForce, NO, NULL},
    {NULL, "enable_now_playing_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_now_playing_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_now_playing_banner_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_now_playing_banner_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_now_playing_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_now_playing_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_now_playing_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_artist_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_artist_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_artist_banner_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_artist_banner_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_artist_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_artist_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_artist_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_playlist_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_playlist_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_playlist_banner_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_playlist_banner_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_playlist_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_playlist_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_playlist_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_album_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_album_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_album_banner_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_album_banner_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_album_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_album_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_album_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_library_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_library_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_library_banner_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_library_banner_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_library_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_library_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_library_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_audiobook_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_audiobook_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_audiobook_banner_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_audiobook_banner_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_audiobook_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_audiobook_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_audiobook_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_podcast_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_podcast_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_podcast_banner_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_podcast_banner_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_podcast_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_podcast_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_podcast_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_content", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_playlists", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_sessions", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_stories", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_videos", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_artist", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_artists", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_album", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_albums", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_track", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_tracks", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_show", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_shows", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_episode", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_episodes", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_audiobook", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_audiobooks", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_podcast", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_podcasts", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_search", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_search_results", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_search_banner", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_search_banners", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_home", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_home_banner", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_home_banners", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_now_playing", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_now_playing_banner", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_now_playing_banners", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_artist_banner", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_artist_banners", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_playlist_banner", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_playlist_banners", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_album_banner", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_album_banners", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_library_banner", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_library_banners", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_audiobook_banner", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_audiobook_banners", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_podcast_banner", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_podcast_banners", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_search_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_search_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_home_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_home_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_now_playing_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_now_playing_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_artist_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_artist_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_playlist_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_playlist_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_album_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_album_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_library_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_library_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_audiobook_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_audiobook_sponsored_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_podcast_sponsored_ad", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_podcast_sponsored_ads", SGRuleSet, NO, NULL},
    {"ios-ad-on-app-open", NULL, SGRuleRemove, NO, NULL},
    {"ios-feature-adonappopen", NULL, SGRuleRemove, NO, NULL},
    {"ios-feature-adonappopen", "enabled", SGRuleSet, NO, NULL},
    {"ios-feature-adonappopen", "background_refresh_frequency_seconds", SGRuleSet, NO, NULL},
    {NULL, "is_ad_on_app_open_enabled", SGRuleSet, NO, NULL},
    {NULL, "ad_on_app_open_enabled", SGRuleSet, NO, NULL},
    {NULL, "adonappopen_enabled", SGRuleSet, NO, NULL},
    {"marquee", NULL, SGRuleRemove, NO, NULL},
    {"ios-feature-marquee", NULL, SGRuleRemove, NO, NULL},
    {"leavebehindadsbase", NULL, SGRuleRemove, NO, NULL},
    {"ios-feature-leavebehindadsbase", NULL, SGRuleRemove, NO, NULL},
    {"ios-nowplaying-scroll-impl", "unified_leavebehind_npv_scroll_music_enabled", SGRuleForce, NO, NULL},
    {"ios-nowplaying-scroll-impl", "unified_leavebehind_npv_scroll_podcast_enabled", SGRuleForce, NO, NULL},
    {"ios-feature-embeddedplaylist", "use_unified_leavebehind_fetch", SGRuleForce, NO, NULL},
    {"ios-adsnowplaying-embeddednpv-impl", "foreground_enabled", SGRuleForce, NO, NULL},
    {"ios-adsnowplaying-embeddednpv-impl", "music_track_change_enabled", SGRuleForce, NO, NULL},
    {"ios-adsnowplaying-embeddednpv-impl", "enable_ads_on_podcast", SGRuleForce, NO, NULL},
    {"ios-feature-instreamads", NULL, SGRuleRemove, NO, NULL},
    {"ios-adsembedded-embeddedctaelements-impl", NULL, SGRuleRemove, NO, NULL},
    {"ios-adsnowplaying-embeddednpv-impl", NULL, SGRuleRemove, NO, NULL},
    {"ios-adsplatform-elementimpl", NULL, SGRuleRemove, NO, NULL},
    {"ios-system-adssponsoredcontext", NULL, SGRuleRemove, NO, NULL},
    {"ios-feature-adsbase", "enable_ads_connect_state_observer", SGRuleSet, NO, NULL},
    {"ios-feature-adsbase", "enable_minimal_preroll_management", SGRuleSet, NO, NULL},
    {"ios-feature-adsbase", "enable_swift_ads_base_movement_logger", SGRuleSet, NO, NULL},
    {"ios-feature-adsswift", NULL, SGRuleRemove, NO, NULL},
    {"ios-feature-adsnowplayingui", "embedded_npv_video_show_with_canvas", SGRuleForce, NO, NULL},
    {"ios-feature-adssponsoredcontext", "sponsored_context_mismatch_aderror_enabled", SGRuleSet, NO, NULL},
    {"ios-feature-adssponsoredcontext", "sponsored_playlist_v2_enabled", SGRuleSet, NO, NULL},
    {"ios-feature-adssponsoredcontextnpbattachment", "sponsored_npb_slot_fetch_enabled", SGRuleSet, NO, NULL},
    {"ios-feature-adsidentitytracking", NULL, SGRuleRemove, NO, NULL},
    {NULL, "enable_popups", SGRuleSet, NO, NULL},
    {NULL, "enable_leave_behind_ads_card_element", SGRuleSet, NO, NULL},
    {NULL, "music_npv_leavebehinds_enabled", SGRuleSet, NO, NULL},
    {NULL, "enable_ads_on_podcast", SGRuleSet, NO, NULL},
    {NULL, "enable_display_element", SGRuleSet, NO, NULL},
    {NULL, "enable_video_element", SGRuleSet, NO, NULL},
    {NULL, "is_promo_cta_enabled", SGRuleSet, NO, NULL},
    {NULL, "show_time_cap_upsell_with_premium_badge", SGRuleSet, NO, NULL},
    {NULL, "enable_video_time_cap_upsell", SGRuleSet, NO, NULL},
    {NULL, "enable_video_time_cap_upsell_on_search", SGRuleSet, NO, NULL},
    {NULL, "music_video_upsell_enabled", SGRuleSet, NO, NULL},
    {NULL, "is_gbb_upsell_enabled", SGRuleSet, NO, NULL},
    {NULL, "should_show_pigeon_upsell", SGRuleSet, NO, NULL},
    {NULL, "disable_suggested_tracks_upsell", SGRuleSet, YES, NULL},
    {NULL, "is_enabled_pt2", SGRuleSet, NO, NULL},
    {NULL, "show_skip_button_during_skippable_ads", SGRuleSet, YES, NULL},
    {NULL, "sponsored_playlist_v2_header_dismissible", SGRuleSet, YES, NULL},
    {NULL, "use_mock_sponsorship_endpoint", SGRuleSet, NO, NULL},
    {NULL, "enable_popup", SGRuleSet, NO, NULL},
    {NULL, "show_popups", SGRuleSet, NO, NULL},
    {NULL, "show_popup", SGRuleSet, NO, NULL},
    {NULL, "enable_interstitials", SGRuleSet, NO, NULL},
    {NULL, "enable_interstitial", SGRuleSet, NO, NULL},
    {NULL, "enable_overlays", SGRuleSet, NO, NULL},
    {NULL, "enable_overlay", SGRuleSet, NO, NULL},
    {NULL, "enable_promotions_on_home", SGRuleSet, NO, NULL},
    {NULL, "enable_promotions_on_search", SGRuleSet, NO, NULL},
    {NULL, "enable_search_page_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_home_page_ads", SGRuleSet, NO, NULL},
    {NULL, "enable_billboard", SGRuleSet, NO, NULL},
    {NULL, "enable_billboards", SGRuleSet, NO, NULL},
    {NULL, "enable_audio_ads_player", SGRuleSet, NO, NULL},
    {NULL, "enable_display_ads_player", SGRuleSet, NO, NULL},
    {NULL, "enable_video_ads_player", SGRuleSet, NO, NULL},
    {NULL, "enable_audio_ads_player_v2", SGRuleSet, NO, NULL},
    {NULL, "enable_display_ads_player_v2", SGRuleSet, NO, NULL},
    {NULL, "enable_video_ads_player_v2", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_search_results_v2", SGRuleSet, NO, NULL},
    {NULL, "enable_sponsored_home_results_v2", SGRuleSet, NO, NULL},
    {"ios-feature-search", "prompted_playlist_merchandizing_enabled", SGRuleSet, NO, NULL},
    {NULL, "should_nova_scroll_use_scrollsita", SGRuleRemove, NO, NULL},
    {"ios-sociallistening-configuration-impl", "premium_gated_start_jam_buttons_enabled", SGRuleForce, NO, NULL},
};
static const size_t ruleCount = sizeof(rules) / sizeof(rules[0]);

static BOOL ruleMatches(const SGRule *rule, NSString *scope, NSString *name) {
    if (rule->scope && ![scope isEqualToString:@(rule->scope)]) return NO;
    return !rule->name || [name isEqualToString:@(rule->name)];
}

// A false BoolValue is an empty message, as protobuf writes it.
static NSData *boolValue(BOOL on) {
    return on ? SGPBSerialize(@[SGPBVarint(1, 1)]) : [NSData data];
}

static void setValue(NSMutableArray<SGPBField *> *value, SGPBField *replacement) {
    [value filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SGPBField *field, NSDictionary *bindings) {
        return field.number < 3 || field.number > 5;
    }]];
    [value addObject:replacement];
}

static NSData *patchConfiguration(NSData *configuration) {
    NSMutableArray<SGPBField *> *fields = SGPBParse(configuration);
    if (!fields) return nil;
    NSMutableArray<SGPBField *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *present = [NSMutableSet set];
    for (SGPBField *field in fields) {
        NSMutableArray<SGPBField *> *value = field.number == 3 && field.wire == 2 ? SGPBParse(field.payload) : nil;
        SGPBField *identifier = SGPBFirst(value, 1);
        NSArray<SGPBField *> *parts = identifier ? SGPBParse(identifier.payload) : nil;
        if (!parts) {
            [out addObject:field];
            continue;
        }
        NSString *scope = SGPBText(SGPBFirst(parts, 1)) ?: @"", *name = SGPBText(SGPBFirst(parts, 2)) ?: @"";
        BOOL removed = NO;
        for (size_t i = 0; i < ruleCount && !removed; i++) {
            if (!ruleMatches(&rules[i], scope, name)) continue;
            switch (rules[i].kind) {
                case SGRuleRemove: removed = YES; break;
                case SGRuleSet:
                    // Set changes a boolean that is there; a value of another kind (a count of seconds, say)
                    // under the same name is left as the server sent it rather than turned into a false.
                    if (SGPBFirst(value, 3)) setValue(value, SGPBBytes(3, boolValue(rules[i].on)));
                    break;
                case SGRuleForce: setValue(value, SGPBBytes(3, boolValue(rules[i].on))); break;
                case SGRuleEnum: setValue(value, SGPBBytes(5, SGPBSerialize(@[SGPBString(1, @(rules[i].text))]))); break;
            }
        }
        if (removed) continue;
        [present addObject:[NSString stringWithFormat:@"%@.%@", scope, name]];
        field.payload = SGPBSerialize(value);
        [out addObject:field];
    }
    for (size_t i = 0; i < ruleCount; i++) {
        if (rules[i].kind != SGRuleForce || !rules[i].scope || !rules[i].name) continue;
        if ([present containsObject:[NSString stringWithFormat:@"%s.%s", rules[i].scope, rules[i].name]]) continue;
        NSData *identifier = SGPBSerialize(@[SGPBString(1, @(rules[i].scope)), SGPBString(2, @(rules[i].name))]);
        [out addObject:SGPBBytes(3, SGPBSerialize(@[SGPBBytes(1, identifier), SGPBBytes(3, boolValue(rules[i].on))]))];
    }
    return SGPBSerialize(out);
}

#pragma mark - the response

static NSData *patchUcs(NSData *ucs) {
    NSMutableArray<SGPBField *> *fields = SGPBParse(ucs);
    if (!fields) return nil;
    SGPBField *resolve = SGPBFirst(fields, 1);
    if (resolve.wire == 2) {
        NSData *edited = SGPBEdit(resolve.payload, @[@1], ^NSData *(NSData *configuration) {
            return patchConfiguration(configuration);
        });
        if (edited) resolve.payload = edited;
    }
    SGPBField *attributes = SGPBFirst(fields, 3);
    if (!attributes) [fields addObject:(attributes = SGPBBytes(3, nil))];
    if (attributes.wire == 2) attributes.payload = patchAttributes(attributes.payload) ?: attributes.payload;
    return SGPBSerialize(fields);
}

NSData *SGPatchCustomize(NSData *body) {
    return SGPBEdit(body, @[@1], ^NSData *(NSData *ucs) { return patchUcs(ucs); });
}

NSData *SGPatchBootstrap(NSData *body) {
    return SGPBEdit(body, @[@2, @1, @1, @1], ^NSData *(NSData *ucs) { return patchUcs(ucs); });
}
