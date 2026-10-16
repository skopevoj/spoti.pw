// LyricsLook.h says what is set here.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsLook.h"

NSNotificationName const SGRLyricsLookDidChangeNotification = @"spotifyglass.redesign.lyricsLookChanged";

static NSArray<NSString *> *weightNames(void) { return @[@"Regular", @"Medium", @"Semibold", @"Bold", @"Heavy"]; }
static const UIFontWeight *weights(void) {
    static UIFontWeight values[5];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        values[0] = UIFontWeightRegular; values[1] = UIFontWeightMedium; values[2] = UIFontWeightSemibold;
        values[3] = UIFontWeightBold; values[4] = UIFontWeightHeavy;
    });
    return values;
}
static const NSInteger kBold = 3;

// Read on every line laid out, so kept until a setting changes.
static CGFloat sg_scale = -1, sg_blur, sg_dim;
static NSInteger sg_weight;

static void load(void) {
    if (sg_scale >= 0) return;
    sg_scale = MAX(50, MIN(160, SGInt(SGRKeyLyricsLookSize, 100))) / 100.0;
    sg_blur = MAX(0, MIN(300, SGInt(SGRKeyLyricsLookBlur, 100))) / 100.0;
    sg_dim = MAX(5, MIN(80, SGInt(SGRKeyLyricsLookDim, 30))) / 100.0;
    sg_weight = MAX(0, MIN(4, SGInt(SGRKeyLyricsLookWeight, kBold)));
}

static void changed(void) {
    sg_scale = -1;
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:nil];
}

CGFloat SGRLyricsLookScale(void) { load(); return sg_scale; }
UIFontWeight SGRLyricsLookWeight(void) { load(); return weights()[sg_weight]; }
UIFontWeight SGRLyricsLookLightWeight(void) { load(); return weights()[MAX(0, sg_weight - 1)]; }
CGFloat SGRLyricsLookBlurScale(void) { load(); return sg_blur; }
CGFloat SGRLyricsLookDim(void) { load(); return sg_dim; }

static SGModRow *percentRow(NSString *title, NSString *key, double minimum, double maximum, double step, NSInteger fallback) {
    return SGSliderRow(title, nil, minimum, maximum, step,
        ^double { return SGInt(key, fallback); },
        ^(double value) { SGSetInt(key, (NSInteger)lround(value)); changed(); },
        ^NSString *(double value) { return value == 0 ? @"Off" : [NSString stringWithFormat:@"%ld %%", lround(value)]; });
}

// A look in one tap: size, weight index, blur and unlit brightness, in the keys' own units.
typedef struct { const char *name; const char *note; NSInteger size, weight, blur, dim; } SGRLyricsPreset;
static const SGRLyricsPreset kPresets[] = {
    {"Apple Music", "As the Music app has them", 100, 3, 100, 30},
    {"Big and bold", "Larger and heavier, for across the room", 125, 4, 100, 25},
    {"Clean", "No blur, every line sharp", 100, 3, 0, 35},
    {"Soft", "Lighter, with more of the lines around showing", 92, 2, 60, 45},
    {"Focus", "Only the sung line stands out", 105, 3, 180, 18},
};

static void applyPreset(const SGRLyricsPreset *preset) {
    SGSetInt(SGRKeyLyricsLookSize, preset->size);
    SGSetInt(SGRKeyLyricsLookWeight, preset->weight);
    SGSetInt(SGRKeyLyricsLookBlur, preset->blur);
    SGSetInt(SGRKeyLyricsLookDim, preset->dim);
    changed();
}

static BOOL isPreset(const SGRLyricsPreset *preset) {
    return SGInt(SGRKeyLyricsLookSize, 100) == preset->size && SGInt(SGRKeyLyricsLookWeight, kBold) == preset->weight
        && SGInt(SGRKeyLyricsLookBlur, 100) == preset->blur && SGInt(SGRKeyLyricsLookDim, 30) == preset->dim;
}

static UIViewController *lookPage(void) {
    SGModRow *weight = SGChoiceRow(@"Weight", nil, SGRKeyLyricsLookWeight, weightNames(), kBold);
    weight.chosen = ^(NSInteger index) { changed(); };
    SGModRow *reset = SGActionRow(@"Reset to Apple Music's", nil, ^{
        for (NSString *key in @[SGRKeyLyricsLookSize, SGRKeyLyricsLookWeight, SGRKeyLyricsLookBlur, SGRKeyLyricsLookDim]) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        }
        changed();
        [SGTopController().navigationController popViewControllerAnimated:YES];
    });
    NSMutableArray<SGModRow *> *presets = [NSMutableArray array];
    for (size_t i = 0; i < sizeof kPresets / sizeof *kPresets; i++) {
        const SGRLyricsPreset *preset = &kPresets[i];
        SGModRow *row = SGActionRow(@(preset->name), @(preset->note), ^{ applyPreset(preset); });
        row.checked = ^BOOL { return isPreset(preset); };
        [presets addObject:row];
    }
    NSArray<SGModSection *> *sections = @[
        SGNotedSection(@"Presets", presets, @"A preset sets everything below; move a slider to make it your own."),
        SGNotedSection(@"Text", @[percentRow(@"Size", SGRKeyLyricsLookSize, 60, 150, 5, 100), weight],
                       @"The size is a share of Apple Music's, which is 100 %. Pronunciations and translations follow the lyrics."),
        SGNotedSection(@"Lines", @[percentRow(@"Blur", SGRKeyLyricsLookBlur, 0, 200, 10, 100),
                                   percentRow(@"Lines not sung", SGRKeyLyricsLookDim, 10, 70, 5, 30)],
                       @"How much the lines away from the one being sung blur, and how bright the lines not lit are. Applies straight away."),
        SGSection(nil, @[reset]),
    ];
    return [[SGModPage alloc] initWithTitle:@"Lyrics look" intro:nil sections:sections footer:nil];
}

SGModRow *SGRLyricsLookRow(void) {
    SGModRow *row = SGPageRow(@"Lyrics look", ^UIViewController *{ return lookPage(); });
    row.value = ^NSString *{
        for (size_t i = 0; i < sizeof kPresets / sizeof *kPresets; i++) {
            if (isPreset(&kPresets[i])) return @(kPresets[i].name);
        }
        return @"Custom";
    };
    return row;
}
