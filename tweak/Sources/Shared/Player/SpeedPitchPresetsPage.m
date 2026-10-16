// Mod Settings > Player > Speed and pitch presets (SpeedPitchPresets.h): the list of presets, swiped to
// delete, a row that saves the speed and pitch playing now as a new one, and a page per preset to set its
// name, speed, pitch and whether pitch follows speed, use it and delete it. Each change is stored as it is
// made, so Siri and Shortcuts see it at once.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "SpeedPitch.h"
#import "SpeedPitchPresets.h"

// The switch of a preset's page is a switch row, which reads and stores a key; this one carries the preset
// being edited. Only one page of a preset is open at a time.
static NSString *const kEditorFollows = @"spotifyglass.speedPitch.editor.follows";

static NSString *appName(void) {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    return [name isKindOfClass:NSString.class] && name.length ? name : @"Spotify";
}

#pragma mark - a preset's page

static UIViewController *presetPage(NSString *identifier) {
    SGSpeedPitchPreset *first = SGSpeedPitchPresetWithIdentifier(identifier);
    if (!first) return nil;
    SGSetEnabled(kEditorFollows, first.follows);
    // Every row reads the preset as it is stored now, and a change is stored before the page redraws.
    SGSpeedPitchPreset *(^current)(void) = ^SGSpeedPitchPreset *{ return SGSpeedPitchPresetWithIdentifier(identifier) ?: first; };

    SGModRow *name = SGStatActionRow(@"Name", nil, ^NSString *{ return current().name; }, ^{
        SGSpeedPitchPresetPromptName(@"Rename", @"Siri and Shortcuts find the preset by its name.", current().name, ^(NSString *text) {
            SGSpeedPitchPreset *preset = current();
            preset.name = text;
            SGSpeedPitchPresetSave(preset);
        });
    });
    SGModRow *speed = SGSliderRow(@"Speed", nil, 0.5, 2, 0.05,
        ^double { return current().speed; },
        ^(double value) {
            SGSpeedPitchPreset *preset = current();
            preset.speed = (float)value;
            SGSpeedPitchPresetSave(preset);
        },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%.2f×", value]; });
    SGModRow *follows = SGOptionRow(@"Pitch follows speed", @"Faster plays higher, as a record does", kEditorFollows);
    follows.changed = ^(BOOL on) {
        SGSpeedPitchPreset *preset = current();
        preset.follows = on;
        SGSpeedPitchPresetSave(preset);
    };
    SGModRow *pitch = SGSliderRow(@"Pitch", nil, -12, 12, 1,
        ^double { return current().pitch; },
        ^(double value) {
            SGSpeedPitchPreset *preset = current();
            preset.pitch = (float)value;
            SGSpeedPitchPresetSave(preset);
        },
        ^NSString *(double value) { return value == 0 ? @"0" : [NSString stringWithFormat:@"%@%.0f st", value > 0 ? @"+" : @"−", fabs(value)]; });
    pitch.visible = ^BOOL { return !current().follows; };

    SGModRow *use = SGActionRow(@"Use it now", @"Plays at this speed and pitch", ^{ SGSpeedPitchPresetApply(current()); });
    use.symbol = @"play.circle";
    SGModRow *remove = SGActionRow(@"Delete preset", nil, ^{
        UIViewController *top = SGTopController();
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete this preset?"
            message:[NSString stringWithFormat:@"“%@” goes, and Siri and Shortcuts stop finding it.", current().name] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            SGSpeedPitchPresetDelete(current());
            UINavigationController *navigation = [top isKindOfClass:UINavigationController.class] ? (UINavigationController *)top : top.navigationController;
            [navigation popViewControllerAnimated:YES];
        }]];
        [top presentViewController:alert animated:YES completion:nil];
    });
    remove.color = SGRed();
    remove.symbol = @"trash";

    SGModRow *phrase = SGStatRow(@"Ask Siri", ^NSString *{ return [NSString stringWithFormat:@"“Use %@ in %@”", current().name, appName()]; });
    return [[SGModPage alloc] initWithTitle:first.name intro:nil sections:@[
        SGSection(nil, @[name, speed, follows, pitch]),
        SGSection(nil, @[use, remove]),
        SGNotedSection(nil, @[phrase],
            @"Siri runs it by that phrase, with the app's name as it is on your Home Screen. In the Shortcuts app, add Use speed and pitch preset "
             "under this app's actions and pick this preset in it, to put it in a shortcut, a widget or an automation."),
    ] footer:nil];
}

#pragma mark - the list

typedef NS_ENUM(NSInteger, SGPresetSection) {
    SGPresetSectionSave,
    SGPresetSectionList,
    SGPresetSectionCount,
};

@interface SGSpeedPitchPresetsListPage : SGPage
@end

@implementation SGSpeedPitchPresetsListPage {
    NSArray<SGSpeedPitchPreset *> *_presets;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Speed and pitch presets";
    _presets = SGSpeedPitchPresets();
    return self;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

// A page of a preset renamed, or deleted, comes back to this one changed.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    _presets = SGSpeedPitchPresets();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return SGPresetSectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == SGPresetSectionList ? MAX((NSInteger)_presets.count, 1) : 1;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == SGPresetSectionList ? SGSectionHeader(table, @"Presets") : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == SGPresetSectionList ? SGSectionHeaderHeight : SGSectionGap;
}

- (NSString *)footerText:(NSInteger)section {
    if (section == SGPresetSectionSave) return @"Set the speed and pitch in the player's more menu, then save them here, or make a preset with nothing playing and set its numbers on its page.";
    return [NSString stringWithFormat:@"Ask Siri “Use <name> in %@”, or add Use speed and pitch preset in the Shortcuts app to run one from a shortcut, a widget or an automation. "
            "Siri and Shortcuts also have Set speed and pitch, for any numbers, and Reset speed and pitch. They apply as soon as a song plays when Spotify has to start for it.", appName()];
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return section == SGPresetSectionList ? SGSectionFooter(table, [self footerText:section]) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return section == SGPresetSectionList ? SGSectionFooterHeight(table, [self footerText:section]) : CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"preset");
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (path.section == SGPresetSectionSave) {
        SGFillCell(cell, @"Save the current speed and pitch…", nil, nil, @"plus.circle");
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    if (!_presets.count) {
        SGFillCell(cell, @"None yet", nil, SGGrey(), nil);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    SGSpeedPitchPreset *preset = _presets[(NSUInteger)path.row];
    SGFillCell(cell, preset.name, SGSpeedPitchPresetSummary(preset), nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (SGSpeedPitchPresetIsCurrent(preset)) {
        UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = SGGreen();
        cell.accessoryView = tick;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGPresetSectionList && _presets.count > 0;
}

- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    SGSpeedPitchPresetDelete(_presets[(NSUInteger)path.row]);
    [self reload];
}

// Swipe right to use one, without opening it.
- (UISwipeActionsConfiguration *)tableView:(UITableView *)table leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != SGPresetSectionList || !_presets.count) return nil;
    SGSpeedPitchPreset *preset = _presets[(NSUInteger)path.row];
    UIContextualAction *use = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Use"
                                                                    handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        SGSpeedPitchPresetApply(preset);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self.tableView reloadData]; });
        done(YES);
    }];
    use.backgroundColor = SGGreen();
    return [UISwipeActionsConfiguration configurationWithActions:@[use]];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == SGPresetSectionSave) {
        __weak SGSpeedPitchPresetsListPage *weak = self;
        SGSpeedPitchPresetPromptSave(^(SGSpeedPitchPreset *preset) {
            SGSpeedPitchPresetsListPage *page = weak;
            [page reload];
            UIViewController *editor = presetPage(preset.identifier);
            if (page && editor) SGShowPage(page, editor);
        });
        return;
    }
    if (!_presets.count) return;
    UIViewController *editor = presetPage(_presets[(NSUInteger)path.row].identifier);
    if (editor) SGShowPage(self, editor);
}

@end

UIViewController *SGSpeedPitchPresetsPage(void) {
    return [SGSpeedPitchPresetsListPage new];
}

NSString *SGSpeedPitchPresetsCountText(void) {
    NSUInteger count = SGSpeedPitchPresets().count;
    return count ? @(count).stringValue : @"None";
}
