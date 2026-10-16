// Mod Settings > AirPods gestures: the switch and what a nod and a shake do, all applying at once.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGHeadGestureDetector.h"
#import "Shared/HeadMotion/SGHeadMotion.h"
#import "HeadGestures.h"

static NSArray<NSString *> *actions(void) {
    return @[@"Nothing", @"Play or pause", @"Next track", @"Previous track", @"Start the track over", @"Like the song"];
}

static void tell(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// One gesture measured while an alert says what to do; `done` gets the fastest swing, nil without AirPods.
static void measure(NSString *title, NSString *message, BOOL nod, void (^done)(NSNumber *speed)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
    SGHeadGesturesMeasure(3.5, ^(NSNumber *nodSpeed, NSNumber *shakeSpeed) {
        [alert dismissViewControllerAnimated:YES completion:^{ done(nod ? nodSpeed : shakeSpeed); }];
    });
}

// A comfortable gesture's fastest swing sits well over where a swing starts counting, so the scale puts that
// start at about half of what was measured.
static NSInteger scaleFor(NSNumber *speed, float defaultStart) {
    return MAX(30, MIN(200, lround(speed.floatValue * 0.5f / defaultStart * 100)));
}

static void learn(void) {
    measure(@"Nod twice", @"Nod twice now, the way you would to like a song, then hold still.", YES, ^(NSNumber *nod) {
        if (!nod) {
            tell(@"No head tracking", @"Put in AirPods Pro, AirPods Max, AirPods (3rd generation) or later, or Beats with head tracking, and try again.");
            return;
        }
        measure(@"Shake your head", @"Now shake your head, the way you would to skip a song, then hold still.", NO, ^(NSNumber *shake) {
            NSInteger nodScale = scaleFor(nod, SGHeadGestureNodSpeed()), shakeScale = scaleFor(shake, SGHeadGestureShakeSpeed());
            SGSetInt(SGKeyHeadGestureNodScale, nodScale);
            SGSetInt(SGKeyHeadGestureShakeScale, shakeScale);
            // Following again starts the detector with what was learned.
            SGSetEnabled(SGKeyHeadGestures, NO);
            SGHeadGesturesApply();
            SGSetEnabled(SGKeyHeadGestures, YES);
            SGHeadGesturesApply();
            tell(@"Learned", [NSString stringWithFormat:@"Nods now count at %ld %% and shakes at %ld %% of the usual effort.", (long)nodScale, (long)shakeScale]);
        });
    });
}

UIViewController *SGHeadGesturesSettingsPage(void) {
    SGModRow *on = SGOptionRow(@"AirPods gestures", @"Nod or shake your head to control playback", SGKeyHeadGestures);
    on.changed = ^(BOOL value) { SGHeadGesturesApply(); };
    SGModRow *nod = SGWaitsOn(SGChoiceRow(@"Nod twice", nil, SGKeyHeadGestureNod, actions(), SGHeadGestureActionLike), SGKeyHeadGestures, NO);
    SGModRow *shake = SGWaitsOn(SGChoiceRow(@"Shake your head", nil, SGKeyHeadGestureShake, actions(), SGHeadGestureActionNext),
                                SGKeyHeadGestures, NO);
    NSString *footer = SGHeadMotionSupported()
        ? @"Works with AirPods Pro, AirPods Max, AirPods (3rd generation) or later, and Beats with head tracking. "
          "Nod twice, or shake your head, quickly and then hold still; nodding along to a song is left alone. "
          "Skips only happen while something plays. Head tracking asks for Motion & Fitness access the first time."
        : @"Needs head tracking, from iOS 14.";
    SGModRow *teach = SGStatActionRow(@"Learn my nod and shake", nil, ^NSString *{
        return SGInt(SGKeyHeadGestureNodScale, 100) == 100 && SGInt(SGKeyHeadGestureShakeScale, 100) == 100 ? @"Default" : @"Learned";
    }, ^{ learn(); });
    SGWaitsOn(teach, SGKeyHeadGestures, NO);
    SGModSection *section = SGNotedSection(nil, @[on, nod, shake, teach], footer);
    return [[SGModPage alloc] initWithTitle:@"AirPods gestures" intro:nil sections:@[section] footer:nil];
}
