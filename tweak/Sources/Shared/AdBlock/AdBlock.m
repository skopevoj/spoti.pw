#import "Core/SGCore.h"
#import "AdBlock.h"

#pragma mark - flags

// Both lists are EeveeSpotify's, kept to the flags this Spotify has.
static NSString *const adFlags[] = {
    @"ios-feature-adonappopen.enabled",
    @"ios-feature-adonappopen.cta_card_enabled",
    @"ios-nowplaying-scroll-impl.unified_leavebehind_npv_scroll_music_enabled",
    @"ios-nowplaying-scroll-impl.unified_leavebehind_npv_scroll_podcast_enabled",
    @"ios-feature-embeddedplaylist.use_unified_leavebehind_fetch",
    @"ios-adsnowplaying-embeddednpv-impl.foreground_enabled",
    @"ios-adsnowplaying-embeddednpv-impl.music_track_change_enabled",
    @"ios-adsnowplaying-embeddednpv-impl.enable_ads_on_podcast",
    @"ios-feature-adsbase.enable_ads_connect_state_observer",
    @"ios-feature-adsbase.enable_minimal_preroll_management",
    @"ios-feature-adsnowplayingui.embedded_npv_video_show_with_canvas",
    @"ios-feature-adssponsoredcontext.sponsored_playlist_v2_enabled",
    @"ios-feature-adssponsoredcontext.sponsored_context_mismatch_aderror_enabled",
    @"ios-feature-adssponsoredcontextnpbattachment.sponsored_npb_slot_fetch_enabled",
};

static NSString *const upsellFlags[] = {
    @"ios-feature-shuffletoggleupsell.is_enabled_pt2",
    @"ios-feature-shuffletoggleupsell.linear_upsell_new_style_experiment_enabled",
    @"ios-feature-shuffletoggleupsell.play_modes_upsell_new_style_experiment_enabled",
    @"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled",
    @"ios-jam-freeusershuffleupsellsheetpage-impl.free_user_shuffle_upsell_sheet_enabled",
    @"ios-jam-freeuserskipupsellpage-impl.free_user_skip_upsell_sheet_enabled",
    @"ios-jam-freehostedjamsupsell-impl.free_hosted_jams_upsell_enabled",
    @"ios-reinventfree-contextualupsellpremiumpromo-impl.is_promo_cta_enabled",
    @"ios-reinventfree-contextualupsellpremiumpromo-impl.show_time_cap_upsell_with_premium_badge",
    @"ios-reinventfree-controllerui-impl.enable_video_time_cap_upsell",
    @"ios-reinventfree-controllerui-impl.enable_video_time_cap_upsell_on_search",
    @"ios-reinventfree-timecappivot-impl.music_video_upsell_enabled",
    @"ios-settings-mediaqualitypageplugin-impl.is_gbb_upsell_enabled",
    @"ios-settings-mediaqualitypageplugin-impl.should_show_pigeon_upsell",
    @"ios-system-listeningparties.preview_ended_upsell_enabled",
};

static NSString *const socialProofFlags[] = {
    @"ios-feature-search.social_proof_playlist_enabled",
    @"ios-feature-search.social_proof_plays_in_search_enabled",
};

static BOOL listed(NSString *key, NSString *const list[], size_t count) {
    for (size_t i = 0; i < count; i++) {
        if ([key isEqualToString:list[i]]) return YES;
    }
    return NO;
}

BOOL SGAdBlockForcesFlagOff(NSString *key) {
    if (SGHidden(SGKeyHideAds) && listed(key, adFlags, sizeof(adFlags) / sizeof(adFlags[0]))) return YES;
    if (SGHidden(SGKeyHideSearchVideos) && [key isEqualToString:@"ios-feature-search.video_carousel_section_enabled"]) return YES;
    if (SGHidden(SGKeyHideSocialProof) && listed(key, socialProofFlags, sizeof(socialProofFlags) / sizeof(socialProofFlags[0]))) return YES;
    return SGHidden(SGKeyHideUpsells) && listed(key, upsellFlags, sizeof(upsellFlags) / sizeof(upsellFlags[0]));
}

// After an override from the All flags page, and locking the rows that would turn the same flag off.
__attribute__((constructor)) static void registerForcer(void) {
    SGFlagForcer off = ^id(NSString *key) { return SGAdBlockForcesFlagOff(key) ? @NO : nil; };
    SGRegisterFlagForcer(NO, off, off);
}

#pragma mark - counters

static NSString *const kCounts = @"spotifyglass.adblock.counts";
static NSString *const labels[] = {
    @"Ad services", @"Upsell services", @"Popups", @"Page components", @"Feed sections", @"Requests", @"Config rewrites",
};
static NSMutableDictionary<NSString *, NSNumber *> *sg_counts;

// Counting happens on whichever thread the hook ran on, the page reads on the main one.
static NSMutableDictionary<NSString *, NSNumber *> *countsLocked(void) {
    if (!sg_counts) {
        sg_counts = [[NSUserDefaults.standardUserDefaults dictionaryForKey:kCounts] mutableCopy] ?: [NSMutableDictionary dictionary];
    }
    return sg_counts;
}

void SGAdBlockCountOne(NSString *label) {
    @synchronized (kCounts) {
        NSMutableDictionary<NSString *, NSNumber *> *counts = countsLocked();
        counts[label] = @(counts[label].unsignedIntegerValue + 1);
        [NSUserDefaults.standardUserDefaults setObject:counts forKey:kCounts];
    }
}

NSArray<NSString *> *SGAdBlockLabels(void) {
    return [NSArray arrayWithObjects:labels count:sizeof(labels) / sizeof(labels[0])];
}

NSUInteger SGAdBlockCount(NSString *label) {
    @synchronized (kCounts) {
        NSDictionary<NSString *, NSNumber *> *counts = countsLocked();
        if (label) return counts[label].unsignedIntegerValue;
        NSUInteger total = 0;
        for (NSNumber *count in counts.allValues) total += count.unsignedIntegerValue;
        return total;
    }
}

void SGResetAdBlock(void) {
    @synchronized (kCounts) {
        sg_counts = [NSMutableDictionary dictionary];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kCounts];
    }
}
