// The Visualizer page in the redesign (Player.h): the switch that rings the cover with bars and the spin, over
// the ring's own settings (Shared/Visualizer), all applying at once.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Visualizer/Visualizer.h"
#import "Player.h"

NSArray<SGModSection *> *SGRPlayerVisualizerSections(void) {
    void (^tell)(BOOL) = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGVisualizerSettingsDidChangeNotification object:nil];
    };
    SGModRow *on = SGWithSymbol(SGOptionRow(@"Visualizer", @"Bars round the cover, moving with the music", SGRKeyPlayerVisualizer),
                                @"circle.dotted.circle");
    on.changed = tell;
    SGModRow *spin = SGWaitsOn(SGSwitchRow(@"Spin the cover", @"Slowly, while the song plays", SGRKeyPlayerVisualizerSpin),
                               SGRKeyPlayerVisualizer, NO);
    spin.changed = tell;
    return @[SGNotedSection(nil, @[on, spin],
        @"The cover becomes a circle with the bars round it, like an NCS video. It listens to what you hear, after speed, "
         "pitch and audio effects, only while the player is on screen.")];
}

UIViewController *SGRPlayerVisualizerPage(void) {
    return SGVisualizerSettingsPage(SGRPlayerVisualizerSections(), SGRKeyPlayerVisualizer, nil);
}
