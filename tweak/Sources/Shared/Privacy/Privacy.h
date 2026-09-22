// Privacy: telemetry blocking (Privacy.x), an NSURLProtocol that answers the analytics endpoints
// itself and counts what it stopped. On unless switched off.
#import <UIKit/UIKit.h>

#define SGKeyBlockTelemetry @"spotifyglass.blockTelemetry"
// Search clutter (Clutter.m); on forces its flags off.
#define SGKeyHideSearchVideos @"spotifyglass.adblock.searchVideos"
#define SGKeyHideSocialProof @"spotifyglass.adblock.socialProof"

// The destinations it knows in the order it lists them, and how many requests to one of them it
// has answered instead of letting out (nil label for all of them).
NSArray<NSString *> *SGBlockedLabels(void);
NSUInteger SGBlockedCount(NSString *label);
void SGResetBlocked(void);

// The telemetry switch and counters, reused by the Premium, ads & privacy page.
@class SGModSection;
SGModSection *SGPrivacySection(void);
SGModSection *SGPrivacyCountersSection(void);

// The Privacy & clutter page: telemetry, the Search switches, the tips, what telemetry blocking stopped.
UIViewController *SGPrivacySettingsPage(void);
