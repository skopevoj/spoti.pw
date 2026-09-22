#import "NavbarIconPicker.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Headers/SPTEncoreIconView.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

static NSArray<NSString *> *sfSymbolCandidates(void) {
    return @[
        @"house", @"house.fill", @"magnifyingglass", @"music.note", @"music.note.list", @"music.quarternote.3",
        @"heart", @"heart.fill", @"star", @"star.fill", @"play", @"play.fill", @"pause", @"pause.fill",
        @"forward", @"forward.fill", @"backward", @"backward.fill", @"forward.end", @"backward.end",
        @"speaker.wave.2", @"speaker.wave.3", @"speaker.wave.3.fill", @"speaker.slash", @"volume.2", @"volume.slash",
        @"shuffle", @"shuffle.circle", @"repeat", @"repeat.1", @"list.bullet", @"list.bullet.rectangle", @"list.number",
        @"list.star", @"rectangle.stack", @"rectangle.stack.fill", @"square.grid.2x2", @"rectangle.grid.2x2",
        @"books.vertical", @"book", @"book.fill", @"album", @"opticaldisc", @"disc", @"radio", @"headphones",
        @"headphones.circle", @"music.mic", @"music.note.tv", @"music.note.house", @"guitars", @"pianokeys", @"waveform",
        @"waveform.circle", @"bookmark", @"bookmark.fill", @"tag", @"tag.fill", @"folder", @"folder.fill", @"tray",
        @"photo", @"camera", @"mic", @"bell", @"clock", @"calendar", @"location", @"map", @"globe", @"wifi",
        @"airplayaudio", @"airplayvideo", @"tv", @"iphone", @"lock", @"lock.open", @"eye", @"eye.slash",
        @"paintpalette", @"paintbrush", @"textformat", @"quote.bubble", @"text.bubble", @"square.text.square",
        @"link", @"person", @"person.fill", @"person.2", @"person.2.fill", @"person.crop.circle", @"person.crop.circle.fill",
        @"gearshape", @"gearshape.2", @"slider.horizontal.3", @"switch.2", @"sparkles", @"wand.and.stars", @"wand.and.rays",
        @"flame", @"flame.fill", @"bolt", @"gift", @"cart", @"cart.fill", @"ticket", @"crown", @"medal", @"rosette",
        @"plus", @"plus.circle", @"minus", @"minus.circle", @"xmark", @"checkmark", @"checkmark.circle", @"checkmark.seal",
        @"ellipsis", @"ellipsis.circle", @"ellipsis.circle.fill", @"line.3.horizontal", @"circle", @"circle.fill", @"square", @"square.fill",
        @"questionmark", @"questionmark.circle", @"exclamationmark", @"exclamationmark.triangle", @"info.circle",
        @"trash", @"pencil", @"arrow.down", @"arrow.up", @"arrow.left", @"arrow.right", @"arrow.uturn.backward",
        @"arrow.clockwise", @"arrow.counterclockwise", @"share", @"square.and.arrow.up", @"square.and.arrow.down",
        @"play.circle", @"play.circle.fill", @"pause.circle", @"pause.circle.fill", @"stop.circle", @"moon", @"sun.max",
        @"circle.lefthalf.filled", @"globe.europe.africa", @"heart.text.square", @"text.badge.plus", @"plus.app",
        @"music.note.badge.plus", @"rectangle.portrait.and.arrow.forward", @"star.circle", @"star.square", @"dock.rectangle",
        @"sidebar.left", @"rectangle.bottomthird.inset.filled", @"platter.filled.top.iphone", @"house.and.flag", @"magnifyingglass.circle",
    ];
}

static NSArray<NSString *> *sfSymbolNames(void) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *available = [NSMutableArray array];
        for (NSString *name in sfSymbolCandidates()) if ([UIImage systemImageNamed:name]) [available addObject:name];
        names = [available copy];
    });
    return names;
}

static id encoreIconNamed(NSString *name) {
    Class iconClass = NSClassFromString(@"SPTEncoreIcon");
    SEL selector = NSSelectorFromString(name);
    if (!iconClass || !name.length || ![iconClass respondsToSelector:selector]) return nil;
    id (*makeIcon)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return makeIcon(iconClass, selector);
}

// SPTEncoreIcon exposes one zero-argument class method per glyph. Reading the class at runtime keeps
// this page current when Spotify adds an icon, without maintaining a second hard-coded Encore list.
static NSArray<NSString *> *encoreIconNames(void) {
    Class iconClass = NSClassFromString(@"SPTEncoreIcon");
    if (!iconClass) return @[];

    NSMutableSet<NSString *> *names = [NSMutableSet set];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(object_getClass(iconClass), &count);
    for (unsigned int i = 0; i < count; i++) {
        Method method = methods[i];
        if (method_getNumberOfArguments(method) != 2) continue;
        const char *types = method_getTypeEncoding(method);
        if (!types || types[0] != '@') continue;
        const char *cName = sel_getName(method_getName(method));
        if (!cName || strchr(cName, ':')) continue;
        NSString *name = [NSString stringWithUTF8String:cName];
        id icon = encoreIconNamed(name);
        NSString *reportedName = [icon respondsToSelector:@selector(name)] ? [icon name] : nil;
        if ([reportedName isKindOfClass:NSString.class] && reportedName.length) [names addObject:name];
    }
    free(methods);
    return [[names allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

NSInteger SGNavbarIconLibraryValue(void) {
    NSInteger value = SGInt(SGKeyNavbarIconLibrary, SGNavbarIconLibraryEncore);
    return value == SGNavbarIconLibrarySFSymbols ? value : SGNavbarIconLibraryEncore;
}

NSString *SGNavbarIconLibraryLabel(void) {
    return SGNavbarIconLibraryValue() == SGNavbarIconLibrarySFSymbols ? @"SF Symbols" : @"Spotify Encore";
}

static UIView *previewForIcon(NSString *name, SGNavbarIconLibrary library) {
    if (library == SGNavbarIconLibrarySFSymbols) {
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
        UIImage *image = [UIImage systemImageNamed:name withConfiguration:configuration];
        if (image) {
            UIImageView *symbol = [[UIImageView alloc] initWithImage:image];
            symbol.tintColor = UIColor.whiteColor;
            symbol.contentMode = UIViewContentModeCenter;
            return symbol;
        }
    } else {
        id icon = encoreIconNamed(name);
        Class viewClass = NSClassFromString(@"SPTEncoreIconView");
        UIView *preview = icon && viewClass ? [[viewClass alloc] initWithIcon:icon] : nil;
        if ([preview respondsToSelector:@selector(setForegroundColor:)]) [(SPTEncoreIconView *)preview setForegroundColor:UIColor.whiteColor];
        if (preview) return preview;
    }
    return SGSymbolView(@"questionmark", 20, UIImageSymbolWeightRegular, 32);
}

@interface SGNavbarIconCell : UITableViewCell
@property (nonatomic, strong) UIView *preview;
- (void)setIconName:(NSString *)name library:(SGNavbarIconLibrary)library;
@end

@implementation SGNavbarIconCell

- (void)prepareForReuse {
    [super prepareForReuse];
    [_preview removeFromSuperview];
    _preview = nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = 32;
    _preview.frame = CGRectMake(16, round((self.contentView.bounds.size.height - side) / 2), side, side);
}

- (void)setIconName:(NSString *)name library:(SGNavbarIconLibrary)library {
    [_preview removeFromSuperview];
    _preview = previewForIcon(name, library);
    _preview.userInteractionEnabled = NO;
    [self.contentView addSubview:_preview];

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = name;
    content.secondaryText = @"Tap to copy";
    content.textProperties.font = SGTitleFont();
    content.textProperties.color = UIColor.whiteColor;
    content.secondaryTextProperties.font = SGSubtitleFont();
    content.secondaryTextProperties.color = SGGrey();
    content.textToSecondaryTextVerticalPadding = 0;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(8, 58, 8, 16);
    self.contentConfiguration = content;
    self.backgroundColor = SGCardBackground();
    self.accessoryView = nil;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    [self setNeedsLayout];
}

@end

@interface SGNavbarIconPickerController : SGPage
@property (nonatomic, copy) NSArray<NSString *> *iconNames;
@property (nonatomic, strong) UIView *footer;
@property (nonatomic) SGNavbarIconLibrary library;
@end

@implementation SGNavbarIconPickerController

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"All Icons";
    _library = SGNavbarIconLibraryEncore;
    _iconNames = encoreIconNames();
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UISegmentedControl *selector = [[UISegmentedControl alloc] initWithItems:@[@"Encore", @"SF Symbols"]];
    selector.selectedSegmentIndex = self.library;
    [selector addTarget:self action:@selector(libraryChanged:) forControlEvents:UIControlEventValueChanged];
    selector.frame = CGRectMake(0, 0, 190, 32);
    self.navigationItem.titleView = selector;
    [self updateCatalog];
}

- (void)updateCatalog {
    self.iconNames = self.library == SGNavbarIconLibrarySFSymbols ? sfSymbolNames() : encoreIconNames();
    NSString *kind = self.library == SGNavbarIconLibrarySFSymbols ? @"SF Symbol" : @"Encore";
    self.footer = SGNote([NSString stringWithFormat:@"Tap an icon to copy its name for the Icon field. %@ icons available. %@ names are accepted by custom tabs.", @(self.iconNames.count), kind]);
    self.tableView.tableFooterView = self.footer;
    [self.tableView reloadData];
}

- (void)libraryChanged:(UISegmentedControl *)selector {
    self.library = selector.selectedSegmentIndex == SGNavbarIconLibrarySFSymbols ? SGNavbarIconLibrarySFSymbols : SGNavbarIconLibraryEncore;
    [self updateCatalog];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, self.footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 1; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.iconNames.count; }

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return SGSectionHeader(table, self.library == SGNavbarIconLibrarySFSymbols ? @"SF Symbols" : @"Spotify Encore icons");
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section { return SGSectionHeaderHeight; }
- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section { return CGFLOAT_MIN; }

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGNavbarIconCell *cell = (SGNavbarIconCell *)[table dequeueReusableCellWithIdentifier:@"navbar-icon"];
    if (!cell) cell = [[SGNavbarIconCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"navbar-icon"];
    [cell setIconName:self.iconNames[(NSUInteger)path.row] library:self.library];
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    UIPasteboard.generalPasteboard.string = self.iconNames[(NSUInteger)path.row];
    [table deselectRowAtIndexPath:path animated:YES];
}

@end

UIViewController *SGNavbarIconPickerPage(void) {
    return [SGNavbarIconPickerController new];
}

UIViewController *SGNavbarIconSettingsPage(void) {
    SGModRow *library = SGChoiceRow(@"Default custom-tab icons", nil, SGKeyNavbarIconLibrary,
                                    @[@"Spotify Encore", @"SF Symbols"], SGNavbarIconLibraryEncore);
    library.choiceFooter = @"This default is used when you create a new custom tab. Existing tabs keep their selected library.";
    SGModRow *browse = SGWithSymbol(SGPageRow(@"Browse all icons", ^UIViewController *{ return SGNavbarIconPickerPage(); }), @"square.grid.2x2");
    return [[SGModPage alloc] initWithTitle:@"Icons" intro:SGRestartNote
                                   sections:@[SGSection(@"Custom navbar tabs", @[library]), SGSection(nil, @[browse])]
                                      footer:@"Global Spotify icon replacement is planned for a later step. For now, this page controls custom tabs only."];
}
