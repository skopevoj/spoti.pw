#import "Core/SGCore.h"
#import "Core/SGSFSymbolCatalog.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Headers/SPTEncoreIconView.h"
#import "Shared/Navigation/Links.h"
#import "Navbar.h"
#import <objc/message.h>
#import <objc/runtime.h>

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

// The presets the dispatcher can send somewhere, each verdict logged. When it cannot be asked (not set
// up yet, or 9.1.78's registry is not where it was) every preset stays.
static NSArray<NSDictionary *> *openablePresets(void) {
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    for (NSDictionary *tab in tabPresets()) {
        NSString *via = nil;
        SGLinkRoute route = SGSpotifyURIRoute([NSURL URLWithString:tab[SGNavbarURI]], &via);
        SGLog(@"navbar: preset %@ -> %@", tab[SGNavbarURI],
              route == SGLinkRouteOpens ? via : route == SGLinkRouteNone ? @"no handler, left out" : @"unknown");
        if (route != SGLinkRouteNone) [kept addObject:tab];
    }
    return kept;
}

// Set in the draft once an icon is picked by hand, so choosing a page afterwards keeps it.
static NSString *const kIconChosen = @"iconChosen";

// An icon as the bar draws it: an SPTEncoreIcon method name, or `sf:` and an SF Symbol's.
static UIView *iconPreview(NSString *name, CGFloat size) {
    if ([name hasPrefix:@"sf:"]) {
        UIImage *image = [UIImage systemImageNamed:[name substringFromIndex:3] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]];
        UIImageView *preview = [[UIImageView alloc] initWithImage:[image imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal]];
        preview.contentMode = UIViewContentModeScaleAspectFit;
        preview.frame = CGRectMake(0, 0, size, size);
        return preview;
    }
    Class iconClass = NSClassFromString(@"SPTEncoreIcon");
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    SEL selector = NSSelectorFromString(name.length ? name : @"star");
    if (iconClass && viewClass && [iconClass respondsToSelector:selector]) {
        id icon = ((id (*)(id, SEL))objc_msgSend)(iconClass, selector);
        SPTEncoreIconView *preview = icon ? [[viewClass alloc] initWithIcon:icon] : nil;
        if (preview) {
            preview.frame = CGRectMake(0, 0, size, size);
            [preview setForegroundColor:UIColor.whiteColor];
            [preview setIsActive:NO];
            return preview;
        }
    }
    UIImageView *fallback = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"star.fill"]];
    fallback.tintColor = UIColor.whiteColor;
    fallback.frame = CGRectMake(0, 0, size, size);
    return fallback;
}

static NSString *iconDescription(NSString *name) {
    if ([name hasPrefix:@"sf:"]) return [NSString stringWithFormat:@"SF Symbols · %@", [name substringFromIndex:3]];
    return [NSString stringWithFormat:@"Spotify Encore · %@", name.length ? name : @"star"];
}

static UIView *iconAccessory(NSString *name) {
    UIView *accessory = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 52, 28)];
    UIView *preview = iconPreview(name, 24);
    preview.frame = CGRectMake(0, 2, 24, 24);
    [accessory addSubview:preview];
    UIImageView *chevron = SGSymbolView(@"chevron.right", 12, UIImageSymbolWeightRegular, 16);
    chevron.tintColor = SGGrey();
    chevron.frame = CGRectMake(34, 6, 16, 16);
    [accessory addSubview:chevron];
    return accessory;
}

@interface SGTabLinkPickerPage : SGPage
- (instancetype)initWithDraft:(NSMutableDictionary *)draft;
@end

@interface SGTabIconPickerPage : SGPage <UISearchBarDelegate, UISearchResultsUpdating>
- (instancetype)initWithDraft:(NSMutableDictionary *)draft;
@end

// Add a tab: a name, a link and an icon, in a sheet of its own.
@interface SGTabEditorPage : SGPage <UITextFieldDelegate>
@property (nonatomic, copy) void (^added)(void);
- (instancetype)initWithDraft:(NSMutableDictionary *)draft;
@end

@implementation SGTabEditorPage {
    NSMutableDictionary *_draft;
    UITextField *_nameField;
}

- (instancetype)initWithDraft:(NSMutableDictionary *)draft {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _draft = draft;
    self.title = @"Add a Tab";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Add" style:UIBarButtonItemStyleDone target:self action:@selector(add)];
}

// The link and icon pages write into the draft, so it is read again on the way back.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _nameField.text = _draft[SGNavbarTitle];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    self.navigationItem.rightBarButtonItem.enabled = [_draft[SGNavbarURI] length] > 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : 2; }
- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return SGSectionHeader(table, section == 0 ? @"Name" : @"Customize");
}
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section { return SGSectionHeaderHeight; }
- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section { return CGFLOAT_MIN; }
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path { return path.section == 0 ? 56 : UITableViewAutomaticDimension; }

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.backgroundColor = SGCardBackground();
        UITextField *field = [UITextField new];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        field.textColor = UIColor.whiteColor;
        field.tintColor = SGGreen();
        field.placeholder = @"Name";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.returnKeyType = UIReturnKeyDone;
        field.delegate = self;
        field.text = _draft[SGNavbarTitle];
        [field addTarget:self action:@selector(nameChanged:) forControlEvents:UIControlEventEditingChanged];
        [cell.contentView addSubview:field];
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [field.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        ]];
        _nameField = field;
        return cell;
    }
    UITableViewCell *cell = SGDequeueCell(table, @"tab-editor");
    if (path.row == 0) {
        NSString *uri = _draft[SGNavbarURI];
        SGFillCell(cell, @"Link", uri.length ? uri : @"Choose a Spotify page or enter a custom link", nil, nil);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        SGFillCell(cell, @"Icon", iconDescription(_draft[SGNavbarIcon]), nil, nil);
        cell.accessoryView = iconAccessory(_draft[SGNavbarIcon]);
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)nameChanged:(UITextField *)field {
    _draft[SGNavbarTitle] = field.text ?: @"";
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return YES;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section != 1) return;
    [_nameField resignFirstResponder];
    UIViewController *page = path.row == 0 ? [[SGTabLinkPickerPage alloc] initWithDraft:_draft]
                                           : [[SGTabIconPickerPage alloc] initWithDraft:_draft];
    [self.navigationController pushViewController:page animated:YES];
}

- (void)cancel {
    [_nameField resignFirstResponder];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)add {
    [_nameField resignFirstResponder];
    NSString *uri = _draft[SGNavbarURI];
    if (!uri.length) return;
    NSString *title = [_draft[SGNavbarTitle] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    appendTab(@{SGNavbarTitle: title.length ? title : uri, SGNavbarURI: uri, SGNavbarIcon: _draft[SGNavbarIcon] ?: @"star"});
    if (self.added) self.added();
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end

@implementation SGTabLinkPickerPage {
    NSMutableDictionary *_draft;
    NSArray<NSDictionary *> *_presets;
}

- (instancetype)initWithDraft:(NSMutableDictionary *)draft {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _draft = draft;
    _presets = openablePresets();
    self.title = @"Choose a Link";
    return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 0 ? (NSInteger)_presets.count : 1; }
- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return SGSectionHeader(table, section == 0 ? @"Spotify's pages" : @"Custom link");
}
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section { return SGSectionHeaderHeight; }
- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section { return CGFLOAT_MIN; }

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"tab-link");
    if (path.section == 0) {
        NSDictionary *tab = _presets[(NSUInteger)path.row];
        SGFillCell(cell, tab[SGNavbarTitle], tab[SGNavbarURI], nil, nil);
    } else {
        SGFillCell(cell, @"Enter a custom link…", @"Paste a Spotify share link or spotify: URI", nil, @"link");
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0) {
        NSDictionary *tab = _presets[(NSUInteger)path.row];
        _draft[SGNavbarURI] = tab[SGNavbarURI];
        if (![_draft[SGNavbarTitle] length]) _draft[SGNavbarTitle] = tab[SGNavbarTitle];
        if (![_draft[kIconChosen] boolValue]) _draft[SGNavbarIcon] = tab[SGNavbarIcon];
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom link" message:@"Paste a Spotify share link or enter a spotify: URI." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"spotify:playlist:… or open.spotify.com/…";
        field.text = self->_draft[SGNavbarURI];
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.keyboardType = UIKeyboardTypeURL;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Use Link" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSURL *url = SGSpotifyURIFromText(alert.textFields.firstObject.text);
        if (!url) {
            [self showLinkError:@"Enter a Spotify share link or spotify: URI."];
            return;
        }
        NSString *via = nil;
        SGLinkRoute route = SGSpotifyURIRoute(url, &via);
        SGLog(@"navbar: custom %@ -> %@", url.absoluteString,
              route == SGLinkRouteOpens ? via : route == SGLinkRouteNone ? @"no handler" : @"unknown");
        // Said here rather than by Spotify's alert on the bar later, every time the tab is tapped.
        if (route == SGLinkRouteNone) {
            [self showLinkError:[NSString stringWithFormat:@"Spotify has nowhere to open %@.", url.absoluteString]];
            return;
        }
        self->_draft[SGNavbarURI] = url.absoluteString;
        if (![self->_draft[SGNavbarTitle] length]) self->_draft[SGNavbarTitle] = url.absoluteString;
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showLinkError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Can't use that link" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

static BOOL encoreHasGlyph(Class iconClass, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!iconClass || ![iconClass respondsToSelector:selector]) return NO;
    id icon = ((id (*)(id, SEL))objc_msgSend)(iconClass, selector);
    return icon && [icon respondsToSelector:@selector(name)];
}

// Every glyph SPTEncoreIcon has, one argumentless class method each, the ones a tab is likeliest to
// want first.
static NSArray<NSString *> *encoreIconNames(void) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *priority = @[
            @"home", @"search", @"collection", @"heart", @"playlist", @"album", @"artist", @"podcasts", @"audiobook", @"downloaded",
            @"bookmark", @"browse", @"star", @"user", @"events", @"queue", @"plus", @"radio", @"gears", @"spotifyLogo",
            @"play", @"pause", @"previous", @"next", @"shuffle", @"repeat", @"devices", @"download", @"headphones", @"microphone",
            @"lyrics", @"clock", @"history", @"folder", @"music", @"musicNote", @"musicNoteList", @"userPlus", @"add", @"link",
            @"menu", @"more", @"settings", @"volume", @"volumeDown", @"volumeUp", @"volumeOff", @"checkmark", @"close", @"list",
        ];
        Class iconClass = NSClassFromString(@"SPTEncoreIcon");
        NSMutableArray<NSString *> *available = [NSMutableArray array];
        NSMutableArray<NSString *> *remaining = [NSMutableArray array];
        for (NSString *name in priority) if (encoreHasGlyph(iconClass, name)) [available addObject:name];

        unsigned int methodCount = 0;
        Method *methods = iconClass ? class_copyMethodList(object_getClass(iconClass), &methodCount) : NULL;
        for (unsigned int i = 0; i < methodCount; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            if ([name containsString:@":"] || [name hasPrefix:@"_"] || [available containsObject:name]) continue;
            if (encoreHasGlyph(iconClass, name)) [remaining addObject:name];
        }
        free(methods);
        [remaining sortUsingSelector:@selector(compare:)];
        [available addObjectsFromArray:remaining];
        names = [available copy];
    });
    return names;
}

static const NSUInteger kSymbolMatches = 200;

// Keep the initial SF Symbols list focused on common tab icons; search still covers the full catalog.
static NSArray<NSString *> *symbolNames(void) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *candidates = @[
            @"house.fill", @"magnifyingglass", @"square.stack.3d.up.fill", @"heart.fill", @"music.note.list", @"music.note", @"music.mic", @"person.crop.circle.fill", @"mic.fill", @"headphones",
            @"arrow.down.circle.fill", @"bookmark.fill", @"sparkles", @"star.fill", @"person.2.fill", @"dot.radiowaves.left.and.right", @"gearshape.fill", @"plus", @"link", @"list.bullet",
            @"clock", @"clock.arrow.circlepath", @"tray.and.arrow.down.fill", @"folder.fill", @"waveform", @"chart.bar.fill", @"globe.americas.fill", @"flame.fill", @"moon.stars.fill", @"sun.max.fill",
            @"bolt.fill", @"play.circle.fill", @"shuffle", @"repeat", @"antenna.radiowaves.left.and.right", @"ear", @"guitar", @"pianokeys", @"drum", @"ticket.fill",
            @"calendar", @"mappin.and.ellipse", @"bag.fill", @"tv.fill", @"video.fill", @"speaker.wave.2.fill", @"airplayaudio", @"ellipsis.circle.fill", @"clock.fill", @"arrow.up.right.circle.fill",
        ];
        NSMutableArray<NSString *> *available = [NSMutableArray array];
        for (NSString *name in candidates) if ([UIImage systemImageNamed:name]) [available addObject:name];
        names = [available copy];
    });
    return names;
}

@implementation SGTabIconPickerPage {
    NSMutableDictionary *_draft;
    UISegmentedControl *_catalog;
    UILabel *_symbolHint;
    UISearchController *_searchController;
    NSArray<NSString *> *_encore;
    NSArray<NSString *> *_symbols;
    NSArray<NSString *> *_displayedIcons;
    NSUInteger _searchGeneration;
}

- (instancetype)initWithDraft:(NSMutableDictionary *)draft {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _draft = draft;
    _encore = encoreIconNames();
    _symbols = symbolNames();
    self.title = @"Choose an Icon";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tintColor = UIColor.whiteColor;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 48)];
    _catalog = [[UISegmentedControl alloc] initWithItems:@[@"Spotify Encore", @"SF Symbols"]];
    _catalog.selectedSegmentIndex = 0;
    _catalog.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    _catalog.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.16];
    [_catalog setTitleTextAttributes:@{NSForegroundColorAttributeName: SGGrey()} forState:UIControlStateNormal];
    [_catalog setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
    [_catalog addTarget:self action:@selector(catalogChanged) forControlEvents:UIControlEventValueChanged];
    [header addSubview:_catalog];
    self.tableView.tableHeaderView = header;

    _symbolHint = [UILabel new];
    _symbolHint.text = @"Use search to find any SF Symbol";
    _symbolHint.textColor = SGGrey();
    _symbolHint.font = [UIFont systemFontOfSize:13];
    _symbolHint.textAlignment = NSTextAlignmentCenter;
    _symbolHint.numberOfLines = 2;

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.hidesNavigationBarDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"Search all icons";
    _searchController.searchBar.tintColor = UIColor.whiteColor;
    _searchController.searchBar.delegate = self;
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    // From 26 the field folds into a button on the toolbar, out of the way of the list.
    if (@available(iOS 26.0, *)) {
        self.navigationItem.preferredSearchBarPlacement = UINavigationItemSearchBarPlacementIntegratedButton;
        self.navigationItem.searchBarPlacementAllowsToolbarIntegration = YES;
        UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        self.toolbarItems = @[space, self.navigationItem.searchBarPlacementBarButtonItem];
    }

    [self updateSymbolHint];
    [self refreshIconResults];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.toolbarItems.count) return;
    self.navigationController.toolbar.tintColor = UIColor.whiteColor;
    [self.navigationController setToolbarHidden:NO animated:NO];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _searchGeneration++;
    _searchController.active = NO;
    [self.navigationController setToolbarHidden:YES animated:NO];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    CGFloat width = self.tableView.bounds.size.width;
    if (header && header.bounds.size.width != width) {
        header.frame = CGRectMake(0, 0, width, 48);
        self.tableView.tableHeaderView = header;
    }
    CGFloat controlWidth = MIN(MAX(0, width - 32), 280);
    _catalog.frame = CGRectMake((width - controlWidth) / 2, 7, controlWidth, 34);
    if (_symbolHint.frame.size.width != width) {
        _symbolHint.frame = CGRectMake(0, 0, width, 52);
        if (self.tableView.tableFooterView == _symbolHint) self.tableView.tableFooterView = _symbolHint;
    }
}

- (void)updateSymbolHint {
    _symbolHint.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, 52);
    self.tableView.tableFooterView = _catalog.selectedSegmentIndex == 1 ? _symbolHint : nil;
}

// Typing is let settle for a moment before the catalog is searched again.
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSUInteger generation = ++_searchGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) page = weakSelf;
        if (!page || generation != page->_searchGeneration) return;
        [page refreshIconResults];
        [page.tableView reloadData];
    });
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    [bar resignFirstResponder];
}

- (void)catalogChanged {
    _searchGeneration++;
    [self refreshIconResults];
    [self.tableView reloadData];
    [self updateSymbolHint];
}

- (BOOL)showsSymbols {
    return _catalog.selectedSegmentIndex == 1;
}

- (void)refreshIconResults {
    NSString *query = [_searchController.searchBar.text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) {
        _displayedIcons = [self showsSymbols] ? _symbols : _encore;
        return;
    }
    BOOL symbols = [self showsSymbols];
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (NSString *name in symbols ? SGSFSymbolCatalog() : _encore) {
        if ([name rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        // The catalog runs ahead of older systems, and asking about every name of a one letter query
        // held the page for seconds, so the list stops at the first few hundred.
        if (symbols && ![UIImage systemImageNamed:name]) continue;
        [matches addObject:name];
        if (symbols && matches.count == kSymbolMatches) break;
    }
    _displayedIcons = [matches copy];
}

- (NSString *)iconAt:(NSIndexPath *)path {
    NSString *name = _displayedIcons[(NSUInteger)path.row];
    return [self showsSymbols] ? [@"sf:" stringByAppendingString:name] : name;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 1; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return (NSInteger)_displayedIcons.count; }
- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section { return CGFLOAT_MIN; }
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path { return 52; }

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"tab-icon");
    SGFillCell(cell, _displayedIcons[(NSUInteger)path.row], nil, nil, nil);
    cell.accessoryView = iconPreview([self iconAt:path], 28);
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    _draft[SGNavbarIcon] = [self iconAt:path];
    _draft[kIconChosen] = @YES;
    [self.navigationController popViewControllerAnimated:YES];
}

@end

// A sheet over the Navbar page, which is told once a tab is added since a sheet leaves it on screen.
static void presentTabEditor(UIViewController *owner, void (^added)(void)) {
    NSMutableDictionary *draft = [@{SGNavbarTitle: @"", SGNavbarURI: @"", SGNavbarIcon: @"star"} mutableCopy];
    SGTabEditorPage *editor = [[SGTabEditorPage alloc] initWithDraft:draft];
    editor.added = added;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UISheetPresentationController *sheet = navigation.sheetPresentationController;
    UISheetPresentationControllerDetent *compact = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"spotifyglass.custom-tab.compact"
        resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return MIN(context.maximumDetentValue, MIN(360.0, MAX(280.0, context.maximumDetentValue * 0.44)));
        }];
    sheet.detents = @[compact, UISheetPresentationControllerDetent.largeDetent];
    sheet.selectedDetentIdentifier = compact.identifier;
    sheet.prefersGrabberVisible = YES;
    sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    [owner presentViewController:navigation animated:YES completion:nil];
}

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

- (void)reload {
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
        __weak typeof(self) weakSelf = self;
        presentTabEditor(self, ^{ [weakSelf reload]; });
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
        [self reload];
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
