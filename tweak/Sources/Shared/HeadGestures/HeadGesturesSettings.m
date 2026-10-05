// Mod Settings > Player > Head gestures: the switch with what the feature is doing, what a nod and a shake do,
// how far the head has to move for each, and a learning run for each that takes the size of the person's own swing.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "HeadGestures.h"

static const NSTimeInterval kLearnSeconds = 6;

static void tell(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// A learning run: the alert says what to do while the sensors are read, then what was found.
static void learn(NSInteger axis) {
    NSString *gesture = axis == 0 ? @"nod" : @"shake";
    UIAlertController *waiting = [UIAlertController alertControllerWithTitle:@"Learning…"
        message:[NSString stringWithFormat:@"With your AirPods in, %@ about five times, the way you would to answer. "
                 "This takes %d seconds.", axis == 0 ? @"nod" : @"shake your head", (int)kLearnSeconds]
        preferredStyle:UIAlertControllerStyleAlert];
    [SGTopController() presentViewController:waiting animated:YES completion:nil];
    SGHeadGesturesCalibrate(axis, kLearnSeconds, ^(BOOL found, NSInteger degrees) {
        [waiting dismissViewControllerAnimated:YES completion:^{
            if (found) {
                tell(@"Learned", [NSString stringWithFormat:@"A %@ now counts from about %ld°. The slider shows it.", gesture, (long)degrees]);
            } else {
                tell(@"Nothing seen", @"Your head's movement did not come through. Put in AirPods that report head movement "
                     "(AirPods Pro, AirPods Max or the 3rd generation and later), allow motion access when asked, and try again.");
            }
        }];
    });
}

static SGModRow *sizeRow(NSString *title, NSString *key, NSInteger fallback) {
    return SGSliderRow(title, @"How far the head has to move from where it rests", SGHeadDegreesMin, SGHeadDegreesMax, 1,
                       ^double { return (double)MAX(SGHeadDegreesMin, MIN(SGHeadDegreesMax, SGInt(key, fallback))); },
                       ^(double value) {
                           SGSetInt(key, (NSInteger)llround(value));
                           SGHeadGesturesApply();
                       },
                       ^NSString *(double value) { return [NSString stringWithFormat:@"%ld°", (long)llround(value)]; });
}

UIViewController *SGHeadGesturesSettingsPage(void) {
    SGModRow *on = SGOptionRow(@"Head gestures", @"Nod and shake with AirPods", SGKeyHeadGestures);
    on.changed = ^(BOOL enabled) { SGHeadGesturesApply(); };
    on.info = @"Reads the head movement of AirPods that report it (AirPods Pro, AirPods Max, AirPods 3rd generation and later) "
              "while a song plays, and for a minute after it pauses. The sensors use a little of their battery.";
    SGModRow *status = SGStatRow(@"Status", ^NSString *{ return SGHeadGesturesStatus(); });

    // The choice rows store the action's index into the names the double tap's zones use.
    SGModRow *nod = SGChoiceRow(@"Nod twice", @"A double nod", SGKeyHeadNodAction, SGGestureActionNames(), SGGesturePlayPause);
    SGModRow *shake = SGChoiceRow(@"Shake", @"Shaking the head side to side", SGKeyHeadShakeAction, SGGestureActionNames(), SGGestureNextTrack);

    SGModRow *nodSize = sizeRow(@"Nod size", SGKeyHeadNodDegrees, SGHeadNodDegreesDefault);
    SGModRow *shakeSize = sizeRow(@"Shake size", SGKeyHeadShakeDegrees, SGHeadShakeDegreesDefault);
    SGModRow *learnNod = SGActionRow(@"Learn my nod", @"Nod a few times and the size follows", ^{ learn(0); });
    SGModRow *learnShake = SGActionRow(@"Learn my shake", @"Shake your head a few times and the size follows", ^{ learn(1); });
    SGModRow *reset = SGActionRow(@"Reset sizes", nil, ^{
        SGSetInt(SGKeyHeadNodDegrees, SGHeadNodDegreesDefault);
        SGSetInt(SGKeyHeadShakeDegrees, SGHeadShakeDegreesDefault);
        SGHeadGesturesApply();
        tell(@"Sizes reset", @"The nod and the shake are back at the sizes they started with. Reopen the page to see the sliders.");
    });

    NSArray<SGModSection *> *sections = @[
        SGNotedSection(nil, @[on, status],
                       @"A nod is two quick tips of the head, a shake three turns side to side. Turning to look at something "
                       "or nodding along to the music in small movements does not count, and one gesture rests the detector "
                       "for two seconds. Everything applies at once."),
        SGSection(@"Actions", @[nod, shake]),
        SGNotedSection(@"Sensitivity", @[nodSize, shakeSize, learnNod, learnShake, reset],
                       @"A smaller size reacts to a smaller movement and to more by accident. Learning takes the size of your own "
                       "movement from a short run."),
    ];
    return [[SGModPage alloc] initWithTitle:@"Head gestures" intro:nil sections:sections footer:nil];
}
