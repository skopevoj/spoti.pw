// What the update check tells spoti.pw about this install, so installs can be counted: versions,
// device, look, and which big switches are on. Nothing of the account or of what is played.
#import <dlfcn.h>
#import <sys/utsname.h>
#import "Core/SGCore.h"
#import "About.h"
#import "Native/Appearance/Appearance.h"
#import "Native/Player/NowPlaying.h"
#import "Shared/AdBlock/AdBlock.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/JamesDSP/JamesDSP.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/Privacy/Privacy.h"

// Outside "spotifyglass." on purpose: Reset all settings must not mint a second install, and a
// settings backup restored on another phone must not carry this one's id along.
static NSString *const kInstall = @"spotipw.install";
static NSString *const kAsked = @"spotipw.asked";

// Not SGEnabled: after a reset that reads every unset switch as off, and this is not one of them.
static BOOL usageOn(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyUsage];
    return stored ? [stored boolValue] : YES;
}

// Asked on every return to the front, so the formatter is made once.
static NSString *today(void) {
    static NSDateFormatter *format;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        format = [NSDateFormatter new];
        format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        format.dateFormat = @"yyyy-MM-dd";
    });
    return [format stringFromDate:NSDate.date];
}

BOOL SGUsageOwed(void) {
    return usageOn() && ![[NSUserDefaults.standardUserDefaults stringForKey:kAsked] isEqualToString:today()];
}

// Marked when asked, not when answered: a day spoti.pw is down costs that day's count, not a request
// on every launch.
void SGUsageNoteAsked(void) {
    [NSUserDefaults.standardUserDefaults setObject:today() forKey:kAsked];
}

static NSString *installID(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSString *stored = [store stringForKey:kInstall];
    if ([[NSUUID alloc] initWithUUIDString:stored ?: @""]) return stored;
    NSString *made = NSUUID.UUID.UUIDString.lowercaseString;
    [store setObject:made forKey:kInstall];
    return made;
}

static NSString *device(void) {
    struct utsname name;
    return uname(&name) == 0 ? @(name.machine) : nil;
}

// A dylib inside the app's bundle was put into the IPA; one outside it was injected by a jailbreak.
static NSString *installKind(void) {
    NSString *bundle = NSBundle.mainBundle.bundlePath;
    Dl_info info;
    if (dladdr(&installKind, &info) && info.dli_fname && ![@(info.dli_fname) hasPrefix:bundle]) return @"jailbreak";
    NSString *marker = [bundle.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"_TrollStore"];
    return [NSFileManager.defaultManager fileExistsAtPath:marker] ? @"trollstore" : @"sideload";
}

NSData *SGUsageBody(void) {
    if (!usageOn()) return nil;
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"id"] = installID();
    body[@"mod"] = @SG_VERSION;
    body[@"spotify"] = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"];
    body[@"ios"] = UIDevice.currentDevice.systemVersion;
    body[@"device"] = device();
    body[@"ui"] = SGRedesignedUI() ? @"redesigned" : @"native";
    body[@"kind"] = installKind();
    body[@"lang"] = NSLocale.currentLocale.languageCode;
    body[@"region"] = NSLocale.currentLocale.countryCode;
    body[@"features"] = @{
        @"dsp": @(SGHidden(SGKeyDSP)),
        @"liveActivity": @(SGFlag(SGKeyLiveActivity, NO)),
        @"lockScreenLyrics": @(SGFlag(SGKeyLockScreenLyrics, NO)),
        @"musicHaptics": @(SGFlag(SGKeyMusicHaptics, NO)),
        @"controlHaptics": @(SGEnabled(SGKeyControlHaptics)),
        @"artistBlock": @(SGFlag(SGKeyArtistBlock, NO)),
        @"gestures": @(SGFlag(SGKeyGestures, NO)),
        @"blockTelemetry": @(SGEnabled(SGKeyBlockTelemetry)),
        @"hideAds": @(SGHidden(SGKeyHideAds)),
        @"fakePremium": @(SGHidden(SGKeyFakePremium)),
        @"lyricsCard": @(SGFlag(SGKeyLyricsCard, NO)),
        @"amoled": @(SGFlag(SGKeyAmoled, NO)),
    };
    body[@"lyrics"] = SGLyricsOrder();
    return [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
}
