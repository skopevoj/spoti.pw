#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Navbar.h"
#import "Shared/NavbarIconPicker.h"

// What "Add a tab" offers: URIs Spotify's own router resolves to a page of its own, each with the
// name of the SPTEncoreIcon class method that draws its glyph.
static NSArray<NSDictionary *> *tabPresets(void) {
    return @[
        @{SGNavbarTitle: @"Home", SGNavbarURI: @"spotify:home", SGNavbarIcon: @"home"},
        @{SGNavbarTitle: @"Search", SGNavbarURI: @"spotify:search", SGNavbarIcon: @"search"},
        @{SGNavbarTitle: @"Your Library", SGNavbarURI: @"spotify:collection", SGNavbarIcon: @"collection"},
        @{SGNavbarTitle: @"Liked Songs", SGNavbarURI: @"spotify:collection:tracks", SGNavbarIcon: @"heart"},
        @{SGNavbarTitle: @"Playlists", SGNavbarURI: @"spotify:playlists", SGNavbarIcon: @"playlist"},
        @{SGNavbarTitle: @"Albums", SGNavbarURI: @"spotify:collection:albums", SGNavbarIcon: @"album"},
        @{SGNavbarTitle: @"Artists", SGNavbarURI: @"spotify:collection:artists", SGNavbarIcon: @"artist"},
        @{SGNavbarTitle: @"Podcasts", SGNavbarURI: @"spotify:collection:podcasts", SGNavbarIcon: @"podcasts"},
        @{SGNavbarTitle: @"Audiobooks", SGNavbarURI: @"spotify:collection:audiobooks", SGNavbarIcon: @"audiobook"},
        @{SGNavbarTitle: @"Downloads", SGNavbarURI: @"spotify:collection:downloads", SGNavbarIcon: @"downloaded"},
        @{SGNavbarTitle: @"Your Episodes", SGNavbarURI: @"spotify:collection:your-episodes", SGNavbarIcon: @"bookmark"},
        @{SGNavbarTitle: @"Browse", SGNavbarURI: @"spotify:browse", SGNavbarIcon: @"browse"},
        @{SGNavbarTitle: @"New Releases", SGNavbarURI: @"spotify:new-releases", SGNavbarIcon: @"star"},
        @{SGNavbarTitle: @"Made For You", SGNavbarURI: @"spotify:made-for-you", SGNavbarIcon: @"user"},
        @{SGNavbarTitle: @"Concerts", SGNavbarURI: @"spotify:concerts", SGNavbarIcon: @"events"},
        @{SGNavbarTitle: @"Queue", SGNavbarURI: @"spotify:now-playing:queue", SGNavbarIcon: @"queue"},
        @{SGNavbarTitle: @"Create", SGNavbarURI: @"spotify:create-menu", SGNavbarIcon: @"plus"},
    ];
}

// The list the Navbar page edits: the saved order first, then every tab of Spotify's it does not
// name, in Spotify's order. Entries for tabs Spotify no longer has drop out.
static NSMutableArray<NSMutableDictionary *> *navbarEntries(void) {
    NSArray<NSString *> *stock = SGNavbarStock();
    NSMutableArray<NSMutableDictionary *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *entry in SGNavbarLayout()) {
        NSString *ident = entry[SGNavbarID];
        if (![ident isKindOfClass:NSString.class] || [seen containsObject:ident]) continue;
        if (!entry[SGNavbarURI] && ![stock containsObject:ident]) continue;
        [seen addObject:ident];
        [entries addObject:[entry mutableCopy]];
    }
    for (NSString *ident in stock) {
        if ([seen containsObject:ident]) continue;
        [entries addObject:[@{SGNavbarID: ident, SGNavbarTitle: ident} mutableCopy]];
    }
    return entries;
}

// A tab of the mod's own carries an identity of its own, so the same page can sit on the bar twice
// and renaming one does not shuffle the order.
static void appendTab(NSDictionary *tab) {
    NSMutableDictionary *entry = [tab mutableCopy];
    entry[SGNavbarID] = NSUUID.UUID.UUIDString;
    SGSetNavbarLayout([navbarEntries() arrayByAddingObject:entry]);
    SGRefreshTabBar();
}

@interface SGTabPickerPage : SGPage
@end

@implementation SGTabPickerPage {
    UIView *_footer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Add a Tab";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _footer = SGNote(@"Paste a share link or a spotify: URI. Icons: home, search, collection, heart, "
                   "playlist, album, artist, podcasts, audiobook, downloaded, bookmark, browse, star, "
                   "user, events, queue, plus, radio, gears, spotifyLogo. Use All icons to browse "
                   "Encore or SF Symbols and copy a name for a custom tab.");
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 3;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)tabPresets().count : 1;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = section == 0 ? @"Spotify's pages" : section == 1 ? @"Anywhere else" : @"Icon reference";
    return SGSectionHeader(table, title);
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return SGSectionHeaderHeight;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"pick");
    if (path.section == 0) {
        NSDictionary *tab = tabPresets()[(NSUInteger)path.row];
        SGFillCell(cell, tab[SGNavbarTitle], tab[SGNavbarURI], nil, nil);
    } else if (path.section == 1) {
        SGFillCell(cell, @"Any link…", nil, nil, @"link");
    } else {
        SGFillCell(cell, @"All icons", @"Preview and copy Encore or SF Symbols", nil, @"square.grid.2x2");
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0) {
        appendTab(tabPresets()[(NSUInteger)path.row]);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (path.section == 2) {
        [self.navigationController pushViewController:SGNavbarIconPickerPage() animated:YES];
        return;
    }
    [self chooseIconLibrary];
}

- (void)chooseIconLibrary {
    UIAlertController *choice = [UIAlertController alertControllerWithTitle:@"Icon library"
                                                                        message:[NSString stringWithFormat:@"Choose the icon type for this custom tab. Default: %@.", SGNavbarIconLibraryLabel()]
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];
    SGNavbarIconLibrary defaultLibrary = SGNavbarIconLibraryValue();
    [choice addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Use default (%@)", SGNavbarIconLibraryLabel()]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [self presentAnyLinkWithLibrary:defaultLibrary];
    }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Spotify Encore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self presentAnyLinkWithLibrary:SGNavbarIconLibraryEncore];
    }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"SF Symbols" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self presentAnyLinkWithLibrary:SGNavbarIconLibrarySFSymbols];
    }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    choice.popoverPresentationController.sourceView = self.view;
    choice.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:choice animated:YES completion:nil];
}

- (void)presentAnyLinkWithLibrary:(SGNavbarIconLibrary)library {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Any link" message:@"Where the tab goes, and the glyph on it." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"Name"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"spotify:playlist:…";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = library == SGNavbarIconLibrarySFSymbols ? @"SF Symbol name" : @"Encore icon name";
        field.text = library == SGNavbarIconLibrarySFSymbols ? @"star.fill" : @"star";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *title = alert.textFields[0].text, *uri = alert.textFields[1].text, *icon = alert.textFields[2].text;
        if (!uri.length) return;
        NSString *kind = library == SGNavbarIconLibrarySFSymbols ? SGNavbarIconKindSymbol : SGNavbarIconKindEncore;
        NSString *fallback = library == SGNavbarIconLibrarySFSymbols ? @"star.fill" : @"star";
        appendTab(@{SGNavbarTitle: title.length ? title : uri, SGNavbarURI: uri, SGNavbarIcon: icon.length ? icon : fallback, SGNavbarIconKind: kind});
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

typedef NS_ENUM(NSInteger, SGNavbarSection) {
    SGNavbarSectionSwitch,
    SGNavbarSectionTabs,
    SGNavbarSectionAdd,
    SGNavbarSectionReset,
    SGNavbarSectionCount,
};

// The tabs, in the order the bar shows them: drag to reorder, tap to show or hide, swipe a tab of
// your own away. Spotify's own tabs can only be hidden, never removed. Mod Settings and the welcome
// tour show the same editor.
@interface SGNavbarPage : SGPage
@end

@implementation SGNavbarPage {
    NSMutableArray<NSMutableDictionary *> *_entries;
    UIView *_intro;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Navbar";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.editing = YES;
    _intro = SGNote(@"Drag to reorder, tap to show or hide.");
    self.tableView.tableHeaderView = _intro;
    _entries = navbarEntries();
}

// The Add page writes straight to the layout, so the list is read again on the way back.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _entries = navbarEntries();
    [self.tableView reloadData];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _intro, 24, 0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)save {
    SGSetNavbarLayout(_entries);
    SGRefreshTabBar();
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return SGNavbarSectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == SGNavbarSectionTabs ? (NSInteger)_entries.count : 1;
}

- (NSString *)headerFor:(NSInteger)section {
    return section == SGNavbarSectionTabs ? @"Tabs" : nil;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self headerFor:section];
    return title ? SGSectionHeader(table, title) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    if ([self headerFor:section]) return SGSectionHeaderHeight;
    return [self tableView:table numberOfRowsInSection:section] ? SGSectionGap : CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"navbar");
    switch (path.section) {
        case SGNavbarSectionSwitch: {
            SGFillCell(cell, @"Custom navbar", nil, nil, nil);
            UISwitch *toggle = [UISwitch new];
            toggle.onTintColor = SGGreen();
            toggle.on = SGEnabled(SGKeyNavbar);
            [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            break;
        }
        case SGNavbarSectionTabs: {
            NSDictionary *entry = _entries[(NSUInteger)path.row];
            BOOL hidden = [entry[SGNavbarHidden] boolValue];
            NSString *uri = entry[SGNavbarURI];
            SGFillCell(cell, entry[SGNavbarTitle], hidden ? @"Hidden" : (uri ?: @"Spotify's own tab"),
                     hidden ? SGGrey() : nil, hidden ? @"eye.slash" : @"eye");
            break;
        }
        case SGNavbarSectionAdd:
            SGFillCell(cell, @"Add a tab…", nil, nil, @"plus");
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        default:
            SGFillCell(cell, @"Use Spotify's order", nil, nil, @"arrow.uturn.backward");
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGNavbarSectionTabs;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGNavbarSectionTabs;
}

// Spotify's own tabs stay on the list to be switched back on; only the mod's own can go.
- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != SGNavbarSectionTabs) return UITableViewCellEditingStyleNone;
    return _entries[(NSUInteger)path.row][SGNavbarURI] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (NSIndexPath *)tableView:(UITableView *)table targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    return to.section == SGNavbarSectionTabs ? to : from;
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSMutableDictionary *entry = _entries[(NSUInteger)from.row];
    [_entries removeObjectAtIndex:(NSUInteger)from.row];
    [_entries insertObject:entry atIndex:(NSUInteger)to.row];
    [self save];
}

- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    [_entries removeObjectAtIndex:(NSUInteger)path.row];
    [self save];
    [table deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == SGNavbarSectionTabs) {
        NSMutableDictionary *entry = _entries[(NSUInteger)path.row];
        entry[SGNavbarHidden] = [entry[SGNavbarHidden] boolValue] ? nil : @YES;
        [self save];
        [table reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    } else if (path.section == SGNavbarSectionAdd) {
        [self.navigationController pushViewController:[SGTabPickerPage new] animated:YES];
    } else if (path.section == SGNavbarSectionReset) {
        [self reset];
    }
}

- (void)toggled:(UISwitch *)toggle {
    SGSetEnabled(SGKeyNavbar, toggle.on);
    SGRefreshTabBar();
}

- (void)reset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Use Spotify's order"
                                                                  message:@"Every tab of Spotify's comes back where Spotify put it, and the tabs you added go."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGSetNavbarLayout(@[]);
        SGRefreshTabBar();
        self->_entries = navbarEntries();
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

UIViewController *SGNavbarSettingsPage(void) {
    return [SGNavbarPage new];
}

UIViewController *SGNavbarEditorPage(void) {
    return [SGNavbarPage new];
}
