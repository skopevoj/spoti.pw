// Ad sections taken out of the feeds Home, Search and the page under the player are built from
// (EeveeSpotify's BrowsitaSectionStripper). A feed is one container field of sections, each a
// field 1 message; a section goes when its bytes name an ad, or a promotion and a surface for it.
#import "Core/SGCore.h"
#import "AdBlock.h"
#import "Protobuf.h"

static const char *const hardMarkers[] = {
    "spotify:ad:", "ad-formats", "advertisement", "brand-ad", "sponsored", "marquee", "promoted", "home-ads",
    "adsproduct", "leavebehind", "leave-behind", "premium-upsell", "premium_upsell", "premiumupsell",
    "referralsupsellcard",
};
static const char *const intentMarkers[] = {
    "upsell", "upgrade", "subscribe", "premium", "promo", "promotion", "marketing", "offer",
};
static const char *const surfaceMarkers[] = {
    "banner", "card", "popup", "pop-up", "sheet", "interstitial", "promotion", "promo",
};
// The filter chips of Search carry "browse" and "chip" in their ids and are never the ad.
static const char *const keepMarkers[] = {"filter", "chip", "pillar", "browse:chips"};

#define COUNT(list) (sizeof(list) / sizeof(list[0]))

// ASCII, case-insensitive; the markers are lower case.
static BOOL contains(NSData *data, const char *needle) {
    const uint8_t *bytes = data.bytes;
    size_t length = data.length, n = strlen(needle);
    for (size_t i = 0; i + n <= length; i++) {
        size_t k = 0;
        while (k < n && tolower(bytes[i + k]) == needle[k]) k++;
        if (k == n) return YES;
    }
    return NO;
}

static BOOL containsAny(NSData *data, const char *const markers[], size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (contains(data, markers[i])) return YES;
    }
    return NO;
}

static BOOL adSection(NSData *section) {
    if (containsAny(section, hardMarkers, COUNT(hardMarkers))) return YES;
    if (containsAny(section, keepMarkers, COUNT(keepMarkers))) return NO;
    return containsAny(section, intentMarkers, COUNT(intentMarkers)) && containsAny(section, surfaceMarkers, COUNT(surfaceMarkers));
}

NSData *SGStripFeed(NSData *body) {
    NSMutableArray<SGPBField *> *fields = SGPBParse(body);
    SGPBField *container = fields.firstObject;
    if (container.number != 1 || container.wire != 2) return nil;
    NSMutableArray<SGPBField *> *sections = SGPBParse(container.payload);
    if (!sections) return nil;
    NSMutableArray<SGPBField *> *kept = [NSMutableArray array];
    for (SGPBField *section in sections) {
        if (section.number != 1 || section.wire != 2) return nil;
        if (adSection(section.payload)) SGAdBlockCountOne(@"Feed sections");
        else [kept addObject:section];
    }
    if (kept.count == sections.count) return nil;
    SGLog(@"dropped %lu of %lu feed sections", (unsigned long)(sections.count - kept.count), (unsigned long)sections.count);
    container.payload = SGPBSerialize(kept);
    return SGPBSerialize(fields);
}
