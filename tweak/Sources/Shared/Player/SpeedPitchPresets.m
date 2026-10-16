// SpeedPitchPresets.h says what this is for.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "SpeedPitch.h"
#import "SpeedPitchPresets.h"

NSNotificationName const SGSpeedPitchPresetsChangedNotification = @"spotifyglass.speedPitchPresetsChanged";

static const float kMinSpeed = 0.5f, kMaxSpeed = 2, kMaxPitch = 12;
static const NSUInteger kMostPresets = 50;
static float clampSpeedValue(float value);

@interface SGSpeedPitchPreset ()
- (instancetype)initWithIdentifier:(NSString *)identifier;
- (instancetype)initWithValues:(double)speed pitch:(float)pitch follows:(BOOL)follows;
@end

@implementation SGSpeedPitchPreset {
    NSString *_identifier;
}

- (instancetype)initWithIdentifier:(NSString *)identifier {
    if (!(self = [super init])) return nil;
    _identifier = [identifier copy];
    return self;
}

- (NSString *)identifier {
    return _identifier;
}

// A preset that is not stored, to read a summary of values off.
- (instancetype)initWithValues:(double)speed pitch:(float)pitch follows:(BOOL)follows {
    if (!(self = [self initWithIdentifier:@""])) return nil;
    _speed = clampSpeedValue((float)speed);
    _pitch = pitch;
    _follows = follows;
    return self;
}
@end

static float clampSpeedValue(float value) { return isfinite(value) ? MAX(kMinSpeed, MIN(kMaxSpeed, value)) : 1; }
static float clampSpeed(float value) { return isfinite(value) ? MAX(kMinSpeed, MIN(kMaxSpeed, roundf(value * 20) / 20)) : 1; }
static float clampPitch(float value) { return isfinite(value) ? MAX(-kMaxPitch, MIN(kMaxPitch, roundf(value))) : 0; }

static NSArray<NSDictionary *> *storedList(void) {
    id stored = [NSUserDefaults.standardUserDefaults arrayForKey:SGKeySpeedPitchPresets];
    return [stored isKindOfClass:NSArray.class] ? stored : @[];
}

static SGSpeedPitchPreset *presetFrom(NSDictionary *entry) {
    if (![entry isKindOfClass:NSDictionary.class]) return nil;
    NSString *identifier = entry[@"id"], *name = entry[@"name"];
    if (![identifier isKindOfClass:NSString.class] || ![name isKindOfClass:NSString.class] || !identifier.length || !name.length) return nil;
    SGSpeedPitchPreset *preset = [[SGSpeedPitchPreset alloc] initWithIdentifier:identifier];
    preset.name = name;
    preset.speed = clampSpeed([entry[@"speed"] respondsToSelector:@selector(floatValue)] ? [entry[@"speed"] floatValue] : 1);
    preset.pitch = clampPitch([entry[@"pitch"] respondsToSelector:@selector(floatValue)] ? [entry[@"pitch"] floatValue] : 0);
    preset.follows = [entry[@"follows"] respondsToSelector:@selector(boolValue)] ? [entry[@"follows"] boolValue] : NO;
    return preset;
}

static NSDictionary *entryFrom(SGSpeedPitchPreset *preset) {
    return @{@"id": preset.identifier, @"name": preset.name, @"speed": @(preset.speed), @"pitch": @(preset.pitch), @"follows": @(preset.follows)};
}

NSArray<SGSpeedPitchPreset *> *SGSpeedPitchPresets(void) {
    NSMutableArray<SGSpeedPitchPreset *> *presets = [NSMutableArray array];
    for (NSDictionary *entry in storedList()) {
        SGSpeedPitchPreset *preset = presetFrom(entry);
        if (preset) [presets addObject:preset];
    }
    return presets;
}

static void store(NSArray<SGSpeedPitchPreset *> *presets) {
    NSMutableArray *entries = [NSMutableArray arrayWithCapacity:presets.count];
    for (SGSpeedPitchPreset *preset in presets) [entries addObject:entryFrom(preset)];
    [NSUserDefaults.standardUserDefaults setObject:entries forKey:SGKeySpeedPitchPresets];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGSpeedPitchPresetsChangedNotification object:nil];
    });
}

SGSpeedPitchPreset *SGSpeedPitchPresetWithIdentifier(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class]) return nil;
    for (SGSpeedPitchPreset *preset in SGSpeedPitchPresets()) if ([preset.identifier isEqualToString:identifier]) return preset;
    return nil;
}

static NSString *plain(NSString *name) {
    return [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
}

SGSpeedPitchPreset *SGSpeedPitchPresetNamed(NSString *name) {
    NSString *wanted = plain(name ?: @"");
    if (!wanted.length) return nil;
    NSArray<SGSpeedPitchPreset *> *presets = SGSpeedPitchPresets();
    for (SGSpeedPitchPreset *preset in presets) if ([plain(preset.name) isEqualToString:wanted]) return preset;
    for (SGSpeedPitchPreset *preset in presets) {
        NSString *have = plain(preset.name);
        if ([have hasPrefix:wanted] || [wanted hasPrefix:have] || [have hasSuffix:wanted]) return preset;
    }
    return nil;
}

// `name` as it will be kept: trimmed, and with a number after it while another preset has it.
static NSString *uniqueName(NSString *name, NSString *ownIdentifier, NSArray<SGSpeedPitchPreset *> *others) {
    NSString *base = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!base.length) base = @"Preset";
    if (base.length > 40) base = [base substringToIndex:40];
    NSString *candidate = base;
    for (NSInteger n = 2; n < 1000; n++) {
        BOOL taken = NO;
        for (SGSpeedPitchPreset *preset in others) {
            if (![preset.identifier isEqualToString:ownIdentifier] && [plain(preset.name) isEqualToString:plain(candidate)]) taken = YES;
        }
        if (!taken) break;
        candidate = [NSString stringWithFormat:@"%@ %ld", base, (long)n];
    }
    return candidate;
}

SGSpeedPitchPreset *SGSpeedPitchPresetCreate(NSString *name, float speed, float pitch, BOOL follows) {
    NSMutableArray<SGSpeedPitchPreset *> *presets = [SGSpeedPitchPresets() mutableCopy];
    if (presets.count >= kMostPresets) return nil;
    SGSpeedPitchPreset *preset = [[SGSpeedPitchPreset alloc] initWithIdentifier:NSUUID.UUID.UUIDString];
    preset.name = uniqueName(name, preset.identifier, presets);
    preset.speed = clampSpeed(speed);
    preset.pitch = follows ? 0 : clampPitch(pitch);
    preset.follows = follows;
    [presets addObject:preset];
    store(presets);
    return preset;
}

void SGSpeedPitchPresetSave(SGSpeedPitchPreset *preset) {
    NSMutableArray<SGSpeedPitchPreset *> *presets = [SGSpeedPitchPresets() mutableCopy];
    for (NSUInteger i = 0; i < presets.count; i++) {
        if (![presets[i].identifier isEqualToString:preset.identifier]) continue;
        SGSpeedPitchPreset *kept = presets[i];
        kept.name = uniqueName(preset.name, preset.identifier, presets);
        kept.speed = clampSpeed(preset.speed);
        kept.follows = preset.follows;
        kept.pitch = preset.follows ? 0 : clampPitch(preset.pitch);
        preset.name = kept.name;
        store(presets);
        return;
    }
}

void SGSpeedPitchPresetDelete(SGSpeedPitchPreset *preset) {
    NSMutableArray<SGSpeedPitchPreset *> *presets = [SGSpeedPitchPresets() mutableCopy];
    NSUInteger before = presets.count;
    for (NSInteger i = (NSInteger)presets.count - 1; i >= 0; i--) {
        if ([presets[(NSUInteger)i].identifier isEqualToString:preset.identifier]) [presets removeObjectAtIndex:(NSUInteger)i];
    }
    if (presets.count != before) store(presets);
}

void SGSpeedPitchPresetApply(SGSpeedPitchPreset *preset) {
    if (!preset) return;
    SGLog(@"speed and pitch: preset \"%@\" %.2fx %@", preset.name, preset.speed, preset.follows ? @"pitch following" : [NSString stringWithFormat:@"%+.0f st", preset.pitch]);
    SGPlayerApplySpeedPitch(preset.speed, preset.pitch, preset.follows);
}

BOOL SGSpeedPitchPresetIsCurrent(SGSpeedPitchPreset *preset) {
    if (!preset) return NO;
    BOOL speedMatches = fabsf((float)SGPlayerSpeed() - preset.speed) < 0.01f;
    BOOL pitchMatches = preset.follows ? SGPlayerPitchFollowsSpeed() : (!SGPlayerPitchFollowsSpeed() && fabsf(SGPlayerPitch() - preset.pitch) < 0.5f);
    return speedMatches && pitchMatches;
}

NSString *SGSpeedPitchPresetSummary(SGSpeedPitchPreset *preset) {
    NSString *speed = [NSString stringWithFormat:@"%.2f×", preset.speed];
    if (preset.follows) return preset.speed == 1 ? @"Normal" : [speed stringByAppendingString:@"  pitch follows"];
    NSString *pitch = preset.pitch == 0 ? nil : [NSString stringWithFormat:@"%@%.0f st", preset.pitch > 0 ? @"+" : @"−", fabsf(preset.pitch)];
    if (preset.speed == 1 && !pitch) return @"Normal";
    return pitch ? [NSString stringWithFormat:@"%@  %@", speed, pitch] : speed;
}

#pragma mark - asking for a name

void SGSpeedPitchPresetPromptName(NSString *title, NSString *message, NSString *current, void (^done)(NSString *name)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Name";
        field.text = current;
        field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.returnKeyType = UIReturnKeyDone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length && done) done(name);
    }];
    [alert addAction:save];
    alert.preferredAction = save;
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

void SGSpeedPitchPresetPromptSave(void (^done)(SGSpeedPitchPreset *preset)) {
    NSString *message = [NSString stringWithFormat:@"%@. Siri and Shortcuts find it by this name.", SGSpeedPitchPresetSummary(
        [[SGSpeedPitchPreset alloc] initWithValues:SGPlayerSpeed() pitch:SGPlayerPitch() follows:SGPlayerPitchFollowsSpeed()])];
    SGSpeedPitchPresetPromptName(@"Save as a preset", message, nil, ^(NSString *name) {
        SGSpeedPitchPreset *preset = SGSpeedPitchPresetCreate(name, (float)SGPlayerSpeed(), SGPlayerPitch(), SGPlayerPitchFollowsSpeed());
        if (!preset) {
            UIAlertController *full = [UIAlertController alertControllerWithTitle:@"Too many presets" message:@"Delete one to save another."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [full addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [SGTopController() presentViewController:full animated:YES completion:nil];
            return;
        }
        if (done) done(preset);
    });
}
