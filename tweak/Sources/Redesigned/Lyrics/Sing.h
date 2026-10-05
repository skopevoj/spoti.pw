// Sing in the redesign: its switch and the Karaoke page of Mod Settings. The work itself is
// Shared/Sing's; its microphone in the player's lyrics is SGRSingControl.h's.
#import <UIKit/UIKit.h>

#define SGRKeySing @"spotifyglass.redesign.sing"   // off until switched on
#define SGRKeySingVocalsOnly @"spotifyglass.redesign.sing.vocalsonly"   // off until switched on

// Hands the switch to Shared/Sing while the redesign runs (Sing.x), at launch and as it is turned:
// the microphone comes and goes at once, no restart.
void SGRSingApplySwitch(void);
// The vocals only switch, handed over the same way, at launch and as it is turned.
void SGRSingApplyVocalsOnly(void);

// SingSettings.m: Mod Settings > Karaoke, with the switch and the voice model's download, and what its row on
// the main page says beside the chevron (Off, On, No model, the download's percentage).
UIViewController *SGRKaraokeSettingsPage(void);
NSString *SGRKaraokeSummary(void);
