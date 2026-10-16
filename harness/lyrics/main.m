// The lyrics harness: SGRKaraokeView playing a song on a clock of its own (stubs.m), for looking at
// what it does with lines sung over each other, instrumental breaks, translations and pronunciations
// without the phone. The songs are TTML read by the real SGTTML.m, or LRC timed by the real estimate.
//
// Launch arguments (the argument domain of NSUserDefaults, so a setting's key works as one too):
//   -song NAME     fixtures/NAME.ttml, .lrc, .json (Spotify's own) or .txt (plain) in the app, or rtl,
//                  built here (default duet)
//   -file PATH     a TTML or LRC file on the Mac instead
//   -at MS         where the clock starts (default 0)
//   -rate X        how fast it runs (default 1)
//   -pauseAt MS    where it stops, for -holdFor seconds (default for good)
//   -sharp 1       no distance blur, so every line can be read in one screenshot
//   -player 1      the view in a stage the size of the player's instead of the whole lyrics page
//   -aloneAt S     with -player 1: the view laid over the player's whole room with the lines in the
//                  stage's band, which grows to all of it S seconds in, as the controls go (the lines
//                  alone, PlayerLyrics.x); -backAt S shrinks it back, as a touch brings them
//   -light 1       the window in light mode, for the glass's appearance
//   -perf LABEL    logs the cost of the view's frames every 240 of them, under LABEL
//   -dump 1        prints the lines as read, with their pronunciations and translations, and quits
//   -openMenu S    opens the pronunciation and translation menu S seconds in, as a tap on its button would
//   -toggleAt S    switches the pronunciation and the translation over S seconds in, as the menu would
// and the lyrics' own settings by their keys: -spotifyglass.lyricsSimulateWords 1 (sweep line timed
// lines on the estimate), -spotifyglass.redesign.lyricsPronunciation 1,
// -spotifyglass.redesign.lyricsTranslation 1, -spotifyglass.redesign.lyricsTextOrder '(translation, lyrics, pronunciation)'.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach_time.h>
#import "Redesigned/Lyrics/SGRKaraokeView.h"
// HEAD's sources (build.sh old) may be from before the lyrics had anything but their words.
#if __has_include("Redesigned/Lyrics/LyricsText.h")
#import "Redesigned/Lyrics/LyricsText.h"
#endif

NSArray<SGKaraokeLine *> *SGTTMLLines(NSString *xml);
void SGHarnessStartClock(double at, double rate, double pauseAt, double holdFor);

static const NSInteger kWordMs = 500;

static SGKaraokeLine *timed(NSInteger start, NSString *text, NSString *voice) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    NSInteger at = start;
    for (NSString *piece in [text componentsSeparatedByString:@" "]) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = piece;
        word.start = at;
        word.end = at + kWordMs - 50;
        at += kWordMs;
        [words addObject:word];
    }
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = start;
    line.end = at;
    line.voice = voice;
    return line;
}

// Issue 28's song: right to left lines among left to right ones, a second voice and a backing row,
// with a break of ten seconds before the last line.
static NSArray<SGKaraokeLine *> *rightToLeftSong(void) {
    SGKaraokeLine *backed = timed(22000, @"قلبي معك دائما", @"v1");
    backed.backing = timed(22500, @"(oh oh)", @"v1");
    NSArray<SGKaraokeLine *> *lines = @[
        timed(1000, @"Hello from the other side", @"v1"),
        timed(4000, @"שלום עולם, אני שר לך הלילה", @"v1"),
        timed(8000, @"يا حبيبي تعال الليلة نرقص حتى الصباح ونغني للقمر", @"v1"),
        timed(14000, @"دوستت دارم تا ابد", @"v1"),
        timed(17000, @"أنا أحب Spotify!", @"v1"),
        timed(19500, @"2 לבבות אחד", @"v1"),
        backed,
        timed(25000, @"وأنا أيضا يا حبيبي", @"v2"),
        timed(28000, @"And me too my love", @"v2"),
        timed(41000, @"שלום", @"v1"),
    ];
    SGKaraokeAlignVoices(lines);
    return lines;
}

// The same with a translation under two lines and a romanization under a third (rtlx), to see the
// texts under a line keep to its edge.
static NSArray<SGKaraokeLine *> *rightToLeftSongWithExtras(void) {
    NSArray<SGKaraokeLine *> *lines = rightToLeftSong();
#ifdef SGRKeyLyricsTextOrder
    lines[1].translation = @"Hello world, I sing to you tonight";
    lines[2].translation = @"My love, come tonight, let us dance until morning and sing to the moon";
    SGKaraokeLine *spoken = timed(lines[3].start, @"dustat daram ta abad", nil);
    spoken.align = lines[3].align;
    lines[3].pronunciation = spoken;
    lines[7].translation = @"And me too, my love";
#endif
    return lines;
}

// [mm:ss.xx] text, as LRCLIB and Spotify's own line-synced lyrics come: timed by the line, the words
// estimated, a ♪ or an empty line a break.
static NSArray<SGKaraokeLine *> *linesOfLRC(NSString *lrc) {
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    NSRegularExpression *stamp = [NSRegularExpression regularExpressionWithPattern:@"^\\[(\\d+):(\\d+(?:\\.\\d+)?)\\]\\s?(.*)$" options:0 error:nil];
    for (NSString *row in [lrc componentsSeparatedByString:@"\n"]) {
        NSTextCheckingResult *match = [stamp firstMatchInString:row options:0 range:NSMakeRange(0, row.length)];
        if (!match) continue;
        double seconds = [row substringWithRange:[match rangeAtIndex:1]].doubleValue * 60 + [row substringWithRange:[match rangeAtIndex:2]].doubleValue;
        [starts addObject:@((NSInteger)llround(seconds * 1000))];
        [texts addObject:[row substringWithRange:[match rangeAtIndex:3]]];
    }
    return SGKaraokeEstimatedLines(starts, texts);
}

static NSArray<SGKaraokeLine *> *songNamed(NSString *name, NSString *file) {
    if (!file && [name isEqualToString:@"rtl"]) return rightToLeftSong();
    if (!file && [name isEqualToString:@"rtlx"]) return rightToLeftSongWithExtras();
    NSString *path = file;
    for (NSString *type in @[@"ttml", @"lrc", @"json", @"txt"]) path = path ?: [NSBundle.mainBundle pathForResource:name ofType:type];
    NSString *text = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!text) NSLog(@"harness: no song at %@", path ?: name);
    NSString *type = path.pathExtension;
    // Spotify's own color-lyrics JSON, read by the real parser, and plain text as the sources hand it on.
    if ([type isEqualToString:@"json"]) return SGKaraokeLinesFromBody([text dataUsingEncoding:NSUTF8StringEncoding]);
#ifdef SGKeyLyricsSimulateWords
    if ([type isEqualToString:@"txt"]) return SGKaraokeStaticLines([text componentsSeparatedByString:@"\n"]);
#endif
    return [type isEqualToString:@"lrc"] ? linesOfLRC(text) : SGTTMLLines(text);
}

static void dump(NSArray<SGKaraokeLine *> *lines) {
    for (SGKaraokeLine *line in lines) {
#ifdef SGKeyLyricsSimulateWords
        const char *timing = line.timing == SGKaraokeTimingWords ? "W" : line.timing == SGKaraokeTimingLine ? "~" : "-";
#else
        const char *timing = "?";
#endif
        printf("%7ld-%7ld %s%s %s\n", (long)line.start, (long)line.end, timing, line.align ? "R" : "L", SGKaraokeLineText(line).UTF8String);
        if (line.backing) printf("                  bg %s\n", SGKaraokeLineText(line.backing).UTF8String);
#ifdef SGRKeyLyricsTextOrder
        // A pronunciation's words with the time each starts, "+" before one joined to the word before.
        for (SGKaraokeLine *spoken in @[line.pronunciation ?: (id)NSNull.null, line.backing.pronunciation ?: (id)NSNull.null]) {
            if (spoken == (id)NSNull.null) continue;
            NSMutableArray<NSString *> *words = [NSMutableArray array];
            for (SGKaraokeWord *word in spoken.words) [words addObject:[NSString stringWithFormat:@"%@%@@%ld", word.joined ? @"+" : @"", word.text, (long)word.start]];
            printf("                  %s %s\n", spoken == line.pronunciation ? "pr" : "bp", [words componentsJoinedByString:@" "].UTF8String);
        }
        if (line.translation) printf("                  tr %s\n", line.translation.UTF8String);
#endif
    }
    fflush(stdout);
}

#pragma mark - the cost of a frame

static IMP sg_tick;
static NSString *sg_perfLabel;
static double sg_samples[240];
static NSUInteger sg_sampleCount;

static int compareDoubles(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

static void timedTick(id self, SEL _cmd) {
    uint64_t begin = mach_absolute_time();
    ((void (*)(id, SEL))sg_tick)(self, _cmd);
    uint64_t took = mach_absolute_time() - begin;
    static mach_timebase_info_data_t base;
    if (!base.denom) mach_timebase_info(&base);
    sg_samples[sg_sampleCount++] = took * base.numer / base.denom / 1000.0;
    if (sg_sampleCount < 240) return;
    double sorted[240];
    memcpy(sorted, sg_samples, sizeof(sorted));
    qsort(sorted, 240, sizeof(double), compareDoubles);
    double sum = 0;
    for (NSUInteger i = 0; i < 240; i++) sum += sorted[i];
    printf("perf %s at %ld ms: tick mean %.1f us, median %.1f, p95 %.1f, max %.1f\n", sg_perfLabel.UTF8String,
           (long)SGKaraokePositionMs(), sum / 240, sorted[120], sorted[228], sorted[239]);
    fflush(stdout);
    sg_sampleCount = 0;
}

#pragma mark - the app

@interface SGHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSUserDefaults *args = NSUserDefaults.standardUserDefaults;
#ifdef SGRKeyLyricsTextOrder
    // Each launch starts from its own arguments, not from what the menu stored on the last one.
    for (NSString *key in @[SGRKeyLyricsPronunciation, SGRKeyLyricsTranslation, SGRKeyLyricsTextOrder]) [args removeObjectForKey:key];
#endif
    NSString *song = [args stringForKey:@"song"] ?: @"duet";
    SGKaraokeKeepLines(@"harness", songNamed(song, [args stringForKey:@"file"]));
    // -dumpTo PATH: the dump into a file on the Mac, for when simctl launch --console shows nothing.
    if ([args stringForKey:@"dumpTo"]) freopen([args stringForKey:@"dumpTo"].fileSystemRepresentation, "w", stdout);
    if ([args boolForKey:@"dump"] || [args stringForKey:@"dumpTo"]) {
        dump(SGKaraokeLinesForTrack(@"harness"));
        exit(0);
    }
    SGHarnessStartClock([args doubleForKey:@"at"], [args objectForKey:@"rate"] ? [args doubleForKey:@"rate"] : 1,
                        [args objectForKey:@"pauseAt"] ? [args doubleForKey:@"pauseAt"] : -1, [args doubleForKey:@"holdFor"]);
    if ((sg_perfLabel = [args stringForKey:@"perf"])) {
        Method tick = class_getInstanceMethod(SGRKaraokeView.class, NSSelectorFromString(@"tick"));
        sg_tick = method_setImplementation(tick, (IMP)timedTick);
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    // -light 1: the system in light mode, as a phone set to it would put the player's panes.
    self.window.overrideUserInterfaceStyle = [args boolForKey:@"light"] ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.blackColor;
    CGRect bounds = root.view.bounds;
    // The full screen page has the header above the lines and the controls below; the player's own
    // lines sit between its title row and its progress bar.
    CGRect stage = [args boolForKey:@"player"] ? CGRectMake(0, 200, bounds.size.width, 440)
                                                : CGRectMake(0, 110, bounds.size.width, bounds.size.height - 300);
    // The player's room with its controls away: from under the status bar to the home indicator.
    BOOL alone = [args boolForKey:@"player"] && [args objectForKey:@"aloneAt"];
    CGRect room = CGRectMake(0, 62, bounds.size.width, bounds.size.height - 62 - 34);
    UIEdgeInsets band = UIEdgeInsetsMake(CGRectGetMinY(stage) - CGRectGetMinY(room), 0, CGRectGetMaxY(room) - CGRectGetMaxY(stage), 0);
    UIView *host = [[UIView alloc] initWithFrame:alone ? room : stage];
    [root.view addSubview:host];
    SGRKaraokeView *karaoke = [[SGRKaraokeView alloc] initWithFrame:host.bounds];
    karaoke.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if ([args boolForKey:@"sharp"]) [karaoke setValue:@0 forKey:@"maxBlur"];
    [host addSubview:karaoke];
    if (alone) {
        [karaoke setLineInsets:band duration:0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([args doubleForKey:@"aloneAt"] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [karaoke setLineInsets:UIEdgeInsetsZero duration:0.6];
        });
        if ([args objectForKey:@"backAt"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([args doubleForKey:@"backAt"] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [karaoke setLineInsets:band duration:0.3];
            });
        }
    }
    UILabel *caption = [[UILabel alloc] initWithFrame:CGRectMake(24, 60, bounds.size.width - 48, 20)];
    caption.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    caption.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    [root.view addSubview:caption];
    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        caption.text = [NSString stringWithFormat:@"%@  %.1f s", song, SGKaraokePositionMs() / 1000.0];
    }];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    if ([args objectForKey:@"openMenu"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([args doubleForKey:@"openMenu"] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            for (UIView *view in karaoke.subviews) {
                if (![view isKindOfClass:UIButton.class]) continue;
                UIContextMenuInteraction *menu = ((UIButton *)view).contextMenuInteraction;
                SEL present = NSSelectorFromString(@"_presentMenuAtLocation:");
                if ([menu respondsToSelector:present]) ((void (*)(id, SEL, CGPoint))objc_msgSend)(menu, present, CGPointMake(22, 22));
            }
        });
    }
#ifdef SGRKeyLyricsTextOrder
    if ([args objectForKey:@"toggleAt"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([args doubleForKey:@"toggleAt"] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGRSetLyricsTextShown(SGRLyricsTextPronunciation, ![args boolForKey:SGRKeyLyricsPronunciation]);
            SGRSetLyricsTextShown(SGRLyricsTextTranslation, ![args boolForKey:SGRKeyLyricsTranslation]);
        });
    }
#endif
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessDelegate.class));
    }
}
