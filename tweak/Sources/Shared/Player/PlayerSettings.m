// The player's settings that do not depend on the look: the lock screen widget's flags.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "PlayerSettings.h"
#import "SpeedPitch.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"

UIViewController *SGLockScreenWidgetPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Lock screen widget" intro:SGRestartNote sections:@[
        SGSection(@"Controls", @[
            SGFlagRow(@"Like and dislike buttons", @"ios-feature-lockscreen.like_dislike_enabled"),
            SGFlagRow(@"Skip button on podcasts", @"ios-feature-lockscreen.skip_button_on_podcasts"),
            SGFlagRow(@"Chapter skip controls", @"ios-feature-lockscreen.enable_chapter_skip_controls"),
            SGFlagRow(@"Burst skip", @"ios-feature-lockscreen.burst_skip_enabled"),
        ]),
        SGSection(@"Artwork", [SGAnimatedArtworkRows() arrayByAddingObject:
            SGFlagRow(@"Companion content", @"ios-feature-lockscreen.companion_content_enabled")]),
    ] footer:nil];
}

SGModSection *SGSpeedPitchSection(void) {
    SGModRow *follows = SGSwitchRow(@"Pitch follows speed", @"Faster and higher together, like a record", SGKeyPitchFollowsSpeed);
    // The switch stores itself; the sound changes now, and turning it on puts the pitch back to normal.
    follows.changed = ^(BOOL on) { SGSetPlayerPitchFollowsSpeed(on); };
    return SGNotedSection(@"Speed and pitch", @[follows],
                          @"The speed and pitch sliders are in the player's more menu. With this on, the pitch slider goes and a "
                          "faster song is played by resampling, the way a record is, with none of the time stretch's smearing. "
                          "It applies where speed does.");
}
