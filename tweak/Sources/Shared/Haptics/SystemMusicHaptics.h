#import <Foundation/Foundation.h>

#define SGKeySystemMusicHaptics @"spotifyglass.haptics.music.system"
extern NSNotificationName const SGSystemMusicHapticsDidChangeNotification;
BOOL SGSystemMusicHapticsAvailable(void);
BOOL SGSystemMusicHapticsSelected(void);
BOOL SGSystemMusicHapticsActive(void);
NSString *SGSystemMusicHapticsStatus(void);
void SGSystemMusicHapticsSettingsChanged(void);
