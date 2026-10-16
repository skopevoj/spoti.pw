// The tweak's side of Siri and Shortcuts (SpeedPitchIntents.swift, SpeedPitchPresets.h): the notifications an
// intent posts become presets used, speed and pitch set or put back, and Siri is told the presets' names
// again when they change, so "Use <name> in Spotify" knows them.
//
// The observers are put up as the tweak loads, since an intent can run while Spotify is not open: the system
// then starts it in the background, and the intent posts as soon as it is let run.
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "SpeedPitch.h"
#import "SpeedPitchPresets.h"

// Spotify's App Intents metadata lists the intents, and Siri looks the presets up through the Swift query,
// so there is nothing for Siri to learn unless the Swift side is in this build.
static void tellSiri(void) {
    Class bridge = NSClassFromString(@"SGSpeedPitchShortcutsBridge");
    SEL refresh = NSSelectorFromString(@"refresh");
    if ([bridge respondsToSelector:refresh]) ((void (*)(id, SEL))objc_msgSend)(bridge, refresh);
}

// Several changes in a moment (a slider dragged on a preset's page) are one telling.
static void tellSiriSoon(void) {
    static NSUInteger asked;
    NSUInteger mine = ++asked;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (mine == asked) tellSiri();
    });
}

static double number(NSDictionary *info, NSString *key, double fallback) {
    id value = info[key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

%ctor {
    if (SGOff("intents")) return;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSOperationQueue *main = NSOperationQueue.mainQueue;
    [center addObserverForName:SGSpeedPitchIntentPresetNotification object:nil queue:main usingBlock:^(NSNotification *note) {
        SGSpeedPitchPreset *preset = SGSpeedPitchPresetWithIdentifier(note.object);
        if (!preset) {
            SGLog(@"speed and pitch: Siri or Shortcuts asked for a preset that is not saved any more");
            return;
        }
        SGSpeedPitchPresetApply(preset);
    }];
    [center addObserverForName:SGSpeedPitchIntentSetNotification object:nil queue:main usingBlock:^(NSNotification *note) {
        NSDictionary *info = note.userInfo;
        SGLog(@"speed and pitch: set from Siri or Shortcuts");
        SGPlayerApplySpeedPitch(number(info, @"speed", 1), (float)number(info, @"pitch", 0), number(info, @"follows", 0) != 0);
    }];
    [center addObserverForName:SGSpeedPitchIntentResetNotification object:nil queue:main usingBlock:^(NSNotification *note) {
        SGLog(@"speed and pitch: put back from Siri or Shortcuts");
        // Pitch keeps following speed or not as it was set.
        SGPlayerApplySpeedPitch(1, 0, SGFlag(SGKeyPitchFollowsSpeed, YES));
    }];
    [center addObserverForName:SGSpeedPitchPresetsChangedNotification object:nil queue:main usingBlock:^(NSNotification *note) {
        tellSiriSoon();
    }];
    // Once the app is up: Siri learns the presets saved so far.
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:main usingBlock:^(NSNotification *note) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ tellSiri(); });
        });
    }];
}
