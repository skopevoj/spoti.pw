// Ad components taken out of the Hub JSON Home, Browse and Search pages are built from, before
// the builder renders them (EeveeSpotify's HubsAdBlocker). A component is an ad when its
// namespace, name, id, type or the keys of its metadata, logging or custom dictionaries say so;
// its title never counts, "Billboard Hot 100" is a playlist. The plain ad words go with the ads
// switch, a promotion word next to a surface word with the upsells one.
#import "Core/SGCore.h"
#import "AdBlock.h"

// Bare "ad" and "ads" are absent on purpose: as substrings they hit made-for-you and release-radar.
static NSString *const adWords[] = {
    @"sponsored", @"upsell", @"campaign", @"promoted", @"premium-upsell", @"billboard", @"interstitial", @"marquee",
    @"leavebehind", @"leave-behind", @"displayad", @"display-ad", @"fullbleed", @"full-bleed", @"leaderboard",
    @"advertisement", @"sponsor", @"native-ad", @"mobile-ads", @"on-surface", @"onsurface", @"search-ad", @"home-ad",
    @"sponsored-content", @"sponsored-ad", @"ad-card", @"native-ad-home-shelf", @"sponsored-shelf", @"sponsored-row",
    @"ad-shelf", @"ad-row", @"sponsored-item", @"ad-item", @"upgrade-component", @"mobile-display-ad-card",
    @"mobile-ads-display-ad-element",
};
static NSString *const intentWords[] = {@"premium", @"upgrade", @"offer", @"marketing", @"promo", @"promotion", @"subscribe", @"subscription"};
static NSString *const surfaceWords[] = {@"banner", @"card", @"popup", @"pop-up", @"sheet", @"overlay", @"component", @"message"};

#define COUNT(list) (sizeof(list) / sizeof(list[0]))

static BOOL ads, upsells;

static BOOL containsAny(NSString *text, NSString *const words[], size_t count) {
    for (size_t i = 0; i < count; i++) {
        if ([text containsString:words[i]]) return YES;
    }
    return NO;
}

static BOOL adWord(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return NO;
    text = text.lowercaseString;
    if (ads && containsAny(text, adWords, COUNT(adWords))) return YES;
    return upsells && containsAny(text, intentWords, COUNT(intentWords)) && containsAny(text, surfaceWords, COUNT(surfaceWords));
}

static BOOL anyKey(NSDictionary *dictionary) {
    if (![dictionary isKindOfClass:NSDictionary.class]) return NO;
    for (NSString *key in dictionary) {
        if (adWord(key)) return YES;
    }
    return NO;
}

static BOOL isAd(NSDictionary *component) {
    id kind = component[@"component"];
    if ([kind isKindOfClass:NSDictionary.class]) {
        NSString *ns = kind[@"namespace"], *name = kind[@"name"];
        if (adWord(ns) || adWord(name) || adWord([NSString stringWithFormat:@"%@:%@", ns, name])) return YES;
    } else if (adWord(kind)) {
        return YES;
    }
    if (adWord(component[@"id"]) || adWord(component[@"type"])) return YES;
    NSDictionary *metadata = component[@"metadata"];
    if ([metadata isKindOfClass:NSDictionary.class]) {
        for (NSString *key in @[@"ad", @"is_ad", @"is_sponsored"]) {
            if ([metadata[key] respondsToSelector:@selector(boolValue)] && [metadata[key] boolValue]) return YES;
        }
    }
    if (anyKey(metadata) || anyKey(component[@"custom"])) return YES;
    NSDictionary *logging = component[@"logging"];
    return [logging isKindOfClass:NSDictionary.class] && (adWord(logging[@"type"]) || anyKey(logging));
}

static NSArray *filtered(NSArray *components) {
    if (![components isKindOfClass:NSArray.class]) return components;
    NSMutableArray *kept = [NSMutableArray array];
    for (NSDictionary *component in components) {
        if (![component isKindOfClass:NSDictionary.class]) {
            [kept addObject:component];
            continue;
        }
        if (isAd(component)) {
            SGAdBlockCountOne(@"Page components");
            SGLog(@"dropped page component %@", component[@"id"] ?: component[@"component"]);
            continue;
        }
        NSMutableDictionary *copy = [component mutableCopy];
        for (NSString *key in @[@"children", @"rows", @"body"]) {
            if (copy[key]) copy[key] = filtered(copy[key]);
        }
        [kept addObject:copy];
    }
    return kept;
}

%hook HUBViewModelBuilderImplementation
- (void)addJSONDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        %orig;
        return;
    }
    NSMutableDictionary *copy = [dictionary mutableCopy];
    for (NSString *key in @[@"body", @"overlays", @"sections"]) {
        if (copy[key]) copy[key] = filtered(copy[key]);
    }
    NSDictionary *header = copy[@"header"];
    if ([header isKindOfClass:NSDictionary.class]) {
        if (isAd(header)) {
            SGAdBlockCountOne(@"Page components");
            [copy removeObjectForKey:@"header"];
        } else if (header[@"children"]) {
            NSMutableDictionary *headerCopy = [header mutableCopy];
            headerCopy[@"children"] = filtered(header[@"children"]);
            copy[@"header"] = headerCopy;
        }
    }
    %orig(copy);
}
%end

%ctor {
    ads = SGHidden(SGKeyHideAds);
    upsells = SGHidden(SGKeyHideUpsells);
    if (!ads && !upsells) return;
    %init;
    SGRequireClasses(@[@"HUBViewModelBuilderImplementation"]);
}
