// Speed and pitch presets: a name for a speed, a pitch and whether pitch follows speed, saved on the phone
// and applied in one tap from the Speed and pitch panel (SpeedPitchMenu.x), from Mod Settings > Player >
// Speed and pitch presets (SpeedPitchPresetsPage.m), by Siri, and from the Shortcuts app.
//
// Siri and Shortcuts are App Intents (SpeedPitchIntents.swift, listed in Spotify's own App Intents metadata
// by scripts/build-extension.sh and scripts/merge-appintents.py). An intent runs in Spotify's process, in the
// background when Spotify is not open, and tells this file by a notification (SpeedPitchIntents.x); the
// presets it offers to choose from are the ones stored here, under the key below as plain property lists so
// the Swift side reads them without any bridge.
//
// Presets are applied through SGPlayerApplySpeedPitch (SpeedPitch.h), which keeps them until Spotify's output
// starts when they come in before a song plays.
#import <UIKit/UIKit.h>

// An array of dictionaries: id (a UUID string), name, speed (0.5...2), pitch (semitones, -12...12),
// follows (pitch follows speed). Read by SpeedPitchIntents.swift: change the two together.
#define SGKeySpeedPitchPresets @"spotifyglass.speedPitch.presets"

@interface SGSpeedPitchPreset : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) float speed, pitch;
@property (nonatomic) BOOL follows;
@end

// In the order they were made.
NSArray<SGSpeedPitchPreset *> *SGSpeedPitchPresets(void);
SGSpeedPitchPreset *SGSpeedPitchPresetWithIdentifier(NSString *identifier);
// The preset a spoken or typed name means: the same name ignoring case and spaces at the ends, else the one
// the name starts or ends the other's with; nil for none.
SGSpeedPitchPreset *SGSpeedPitchPresetNamed(NSString *name);
// A new preset with a name nobody has yet (a number is added to one taken); values are clamped to the
// sliders' ranges. Stored at once.
SGSpeedPitchPreset *SGSpeedPitchPresetCreate(NSString *name, float speed, float pitch, BOOL follows);
// Stores `preset`'s changes (its name kept unique too).
void SGSpeedPitchPresetSave(SGSpeedPitchPreset *preset);
void SGSpeedPitchPresetDelete(SGSpeedPitchPreset *preset);
// Plays at its speed and pitch.
void SGSpeedPitchPresetApply(SGSpeedPitchPreset *preset);
// Whether the speed and pitch playing now are this preset's.
BOOL SGSpeedPitchPresetIsCurrent(SGSpeedPitchPreset *preset);
// "1.25×  +2 st", "0.80×  pitch follows" and so on.
NSString *SGSpeedPitchPresetSummary(SGSpeedPitchPreset *preset);

// An alert asking for a name, `current` already in the field; Save hands `done` the name typed (not empty).
// From the controller on top.
void SGSpeedPitchPresetPromptName(NSString *title, NSString *message, NSString *current, void (^done)(NSString *name));
// The same for a new preset made of the speed and pitch playing now; `done` gets it once saved, or is not called.
void SGSpeedPitchPresetPromptSave(void (^done)(SGSpeedPitchPreset *preset));

// Posted on the main queue when the list or a preset changes.
extern NSNotificationName const SGSpeedPitchPresetsChangedNotification;

// What Siri and Shortcuts send (SpeedPitchIntents.swift posts them, SpeedPitchIntents.x acts on them):
// object is a preset's identifier, or userInfo has speed (NSNumber), pitch (NSNumber) and follows (NSNumber).
#define SGSpeedPitchIntentPresetNotification @"SGSpeedPitchIntentPreset"
#define SGSpeedPitchIntentSetNotification @"SGSpeedPitchIntentSet"
#define SGSpeedPitchIntentResetNotification @"SGSpeedPitchIntentReset"

// Mod Settings' page of presets (SpeedPitchPresetsPage.m), and what its row reads out.
UIViewController *SGSpeedPitchPresetsPage(void);
NSString *SGSpeedPitchPresetsCountText(void);
