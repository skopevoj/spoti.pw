// The Vibrations sections of the Player page, under either look. Controls keeps its switch and strength;
// the music dropdown selects none, native iOS, or generated haptics and shows that mode's settings.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Haptics.h"
#import "SystemMusicHaptics.h"

static NSString *const kMusicHapticsInfo = @"None\nNo music vibrations in Spotify. The separate Controls setting still governs taps on playback buttons.\n\nNative iOS\nUses Apple's haptic tracks for supported songs. Works on the Home Screen and while locked, and follows Music Haptics in Control Center and Settings > Accessibility. Requires iOS 18 or later and Music Haptics enabled in iOS. Not every song is supported.\n\nspoti.pw Generated\nCreates taps and bass rumble from Spotify's sound in real time, without needing an Apple haptic track. Works only while Spotify is open and playing on this iPhone, not through Spotify Connect. Strength and Follows apply to this mode only.";

typedef NS_ENUM(NSInteger, SGMusicHapticsChoice) {
    SGMusicHapticsNone, SGMusicHapticsNative, SGMusicHapticsGenerated,
};

static NSInteger musicChoice(void) {
    // Keep existing settings, including native taking precedence over a saved generated preference.
    if (SGSystemMusicHapticsSelected()) return SGMusicHapticsNative;
    return SGFlag(SGKeyMusicHaptics, NO) ? SGMusicHapticsGenerated : SGMusicHapticsNone;
}

static void chooseMusic(NSInteger choice) {
    if (choice < SGMusicHapticsNone || choice > SGMusicHapticsGenerated ||
        (choice == SGMusicHapticsNative && !SGSystemMusicHapticsAvailable())) return;
    SGSetEnabled(SGKeyMusicHaptics, choice == SGMusicHapticsGenerated);
    SGSetEnabled(SGKeySystemMusicHaptics, choice == SGMusicHapticsNative);
    // Stops the old engine, clears native metadata, then starts only the newly selected engine.
    SGSystemMusicHapticsSettingsChanged();
}

static NSArray<NSString *> *followsNames(void) {
    return @[@"Everything", @"Beat", @"Bass"];
}

static NSArray<NSString *> *followsNotes(void) {
    return @[@"A tap on each kick and snare, and a rumble under the bass",
             @"A tap on each kick and snare, no rumble",
             @"A tap on each kick, and a rumble under the bass"];
}

static void strengthRange(NSString *key, NSInteger *minimum, NSInteger *maximum) {
    BOOL music = [key isEqualToString:SGKeyMusicStrength];
    *minimum = music ? SGMusicStrengthMin : SGControlStrengthMin;
    *maximum = music ? SGMusicStrengthMax : SGControlStrengthMax;
}

double SGHapticsStrength(NSString *key) {
    NSInteger minimum, maximum;
    strengthRange(key, &minimum, &maximum);
    return MAX(minimum, MIN(maximum, SGInt(key, 100))) / 100.0;
}

SGMusicFollows SGMusicHapticsFollows(void) {
    NSInteger follows = SGInt(SGKeyMusicFollows, SGMusicFollowsEverything);
    return follows >= SGMusicFollowsEverything && follows <= SGMusicFollowsBass ? (SGMusicFollows)follows : SGMusicFollowsEverything;
}

// A percentage slider over a strength key, telling `changed` each step it stores.
static SGModRow *strengthRow(NSString *key, void (^changed)(void)) {
    NSInteger minimum, maximum;
    strengthRange(key, &minimum, &maximum);
    return SGSliderRow(@"Strength", nil, minimum, maximum, SGStrengthStep,
        ^double { return SGHapticsStrength(key) * 100; },
        ^(double value) {
            SGSetInt(key, lround(value));
            if (changed) changed();
        },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%ld%%", lround(value)]; });
}

NSArray<SGModSection *> *SGVibrationsSections(void) {
    SGModRow *controls = SGSwitchRow(@"Controls", nil, SGKeyControlHaptics);
    SGModRow *controlStrength = strengthRow(SGKeyControlStrength, ^{
        // Felt as it is set: a tap at the new strength with each step.
        SGPlayFeedback(SGFeedbackAdd);
    });
    controlStrength.visible = ^BOOL { return SGEnabled(SGKeyControlHaptics); };

    SGModRow *music = SGDropdownRow(@"Music Haptics", @[@"None", @"Native iOS", @"spoti.pw Generated"],
                                  ^NSInteger { return musicChoice(); }, ^(NSInteger choice) { chooseMusic(choice); });
    music.info = kMusicHapticsInfo;
    music.choiceEnabled = ^BOOL(NSInteger choice) { return choice != SGMusicHapticsNative || SGSystemMusicHapticsAvailable(); };
    BOOL (^musicOn)(void) = ^BOOL { return musicChoice() == SGMusicHapticsGenerated; };
    SGModRow *musicStrength = strengthRow(SGKeyMusicStrength, ^{ SGMusicHapticsSettingsChanged(); });
    musicStrength.visible = musicOn;
    SGModRow *follows = SGChoiceRow(@"Follows", nil, SGKeyMusicFollows, followsNames(), SGMusicFollowsEverything);
    follows.choiceNotes = followsNotes();
    follows.chosen = ^(NSInteger index) { SGMusicHapticsSettingsChanged(); };
    follows.visible = musicOn;

    NSMutableArray *musicRows = [NSMutableArray arrayWithObject:SGWithSymbol(music, @"waveform")];
    if (SGSystemMusicHapticsAvailable()) {
        SGModRow *status = SGStatRow(@"iOS status", ^NSString *{ return SGSystemMusicHapticsStatus(); });
        status.subtitle = @"Turn on or pause from Control Center or iOS Accessibility settings.";
        status.visible = ^BOOL { return SGSystemMusicHapticsSelected(); };
        status.refreshOn = SGSystemMusicHapticsDidChangeNotification;
        [musicRows addObject:status];
    }
    [musicRows addObjectsFromArray:@[musicStrength, follows]];
    return @[
        SGSection(@"Vibrations", @[SGWithSymbol(controls, @"hand.tap"), controlStrength]),
        SGSection(nil, musicRows),
    ];
}
