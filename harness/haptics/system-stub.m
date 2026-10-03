// The existing generator harnesses deliberately exercise generated mode. The page harness can
// show the iOS-mode rows with the `system` launch argument without changing a system preference.
#import "Core/SGPrefs.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Haptics/SystemMusicHaptics.h"
NSNotificationName const SGSystemMusicHapticsDidChangeNotification = @"spotifyglass.systemMusicHapticsChanged";
BOOL SGSystemMusicHapticsAvailable(void) { return [NSProcessInfo.processInfo.arguments containsObject:@"system"]; }
BOOL SGSystemMusicHapticsSelected(void) { return SGSystemMusicHapticsAvailable() && SGFlag(SGKeySystemMusicHaptics, NO); }
BOOL SGSystemMusicHapticsActive(void) { return SGSystemMusicHapticsSelected(); }
NSString *SGSystemMusicHapticsStatus(void) { return @"Unavailable"; }
void SGSystemMusicHapticsSettingsChanged(void) { SGSetMusicHapticsEnabled(SGFlag(SGKeyMusicHaptics, NO)); }
