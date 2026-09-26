// Playlist redesign: Sort and Mix on the playlist's ⋯ sheet, where the rest of Spotify's curation row
// already is.
//
// Spotify puts seven pills over the first track -- Add, Mix, Notes, Video, Edit, Sort, Name & details
// (own-playlist/01.txt:33) -- and the Music app has none of them: its playlist sorts from its own ⋯ menu.
// So PlaylistRows.x closes the row up and these two rows stand in its place, because Sort and Mix are the
// only two of the seven the ⋯ menu does not already offer.
//
// **Why these are rows of the mod's own and not rows of Spotify's menu.** The sheet is
// ContextMenu_InternalImpl.ContextMenuViewController, a table whose rows come from Swift item factories
// with no ObjC surface: nothing can be read out of them and nothing can be put between them. What can be
// set is the table's header or footer view, which is how Speed and pitch has ridden on the player's menu
// since it shipped (Shared/Player/SpeedPitchMenu.x). So the block goes in the header, above Spotify's own
// rows, and is laid out by hand at the table's width.
//
// **And why not a menu of the redesign's own instead.** Building the sheet would mean owning its contents:
// every row Spotify offers for a playlist, which varies by whose playlist it is, by market, by account and
// by flag, each in the app's language and each doing something only Spotify's own code knows how to do.
// None of that can be read off the item factories, so it would have to be a hard-coded list in one
// language that goes stale the day Spotify adds a row -- the same trap the album's footer and the artist's
// sections are written to avoid. Spotify keeps its rows; the mod adds to them.
//
// Which sheet is the playlist's: the ⋯ that opened it is the redesign's own pinned button
// (Kit/SGRActionRow.h), so it records its page as it is tapped and a sheet that appears within
// SGRPinnedMoreWindow of that belongs to it. Under the native look nothing pins a ⋯ and nothing here runs.
//
// What each row does is fire Spotify's own pill, so the action, the sheet Sort opens and the state Mix
// keeps are all Spotify's; the words are read off the pills for the same reason. The pills sit in a list
// cell closed up to nothing, which the page hands over as it lays out (SGRPlaylistTakeCuration) and which
// is held from the page, so they are still there to fire once the list has scrolled past them.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"

NSString *const SGRPlaylistCurationIdentifier = @"PlaylistCuration.Row.CurationActionsToolbar";

// Mix says what it is in its identifier; Sort is an Encore.Button.Primary like Video, Edit and Name &
// details, and its only word is the word in the app's language, so it is told apart by the glyph it draws
// (SpotifyShared has `sort`, `sortDown`, `sortUp` and `arrowUpDown`, and Encore's icon knows its own name).
static NSString *const kMixIdentifier = @"ListPlatform.ToolbarActions.MixButton";

// The sheet's own measures and type: this draws on Spotify's sheet, not on a page of the redesign's, so it
// takes the sheet's side margin and row height rather than the Kit's tokens, as Speed and pitch does.
static const CGFloat kRowHeight = 56, kSideMargin = 16, kGlyphSide = 24, kGlyphGap = 16;

static char kToolbarKey, kSortKey, kBlockKey, kDecidedKey;

#pragma mark - Spotify's pills

// The SPTEncoreIcon an Encore icon view was built with, which knows its own name. Encore keeps it in a
// Swift ivar with no getter, as Redesigned/Navbar/TabBar.x found -- but not always the same one: the view
// holds both `icon` and `experimentalIcon` (nm on SpotifyShared), and reading `icon` alone left the Sort
// pill unrecognised on the phone while Mix, which is known by its identifier, came through
// (device 2026-09-20). So every object ivar the view has is asked, and the first that knows a name answers.
static NSString *glyphName(UIView *iconView) {
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(iconView.class, &count);
    NSString *found = nil;
    for (unsigned int i = 0; i < count && !found; i++) {
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') continue;
        id value = object_getIvar(iconView, ivars[i]);
        if (![value respondsToSelector:@selector(name)]) continue;
        NSString *name = [value name];
        if ([name isKindOfClass:NSString.class] && name.length) found = name;
    }
    free(ivars);
    return found;
}

static NSString *pillGlyph(UIView *pill) {
    static Class iconClass;
    if (!iconClass) iconClass = NSClassFromString(@"SPTEncoreIconView");
    __block NSString *name = nil;
    SGForEachView(pill, ^(UIView *v) {
        if (!name && iconClass && [v isKindOfClass:iconClass]) name = glyphName(v);
    });
    return name;
}

static NSString *pillWord(UIView *pill) {
    __block NSString *word = nil;
    SGForEachView(pill, ^(UIView *v) {
        if (word || ![v isKindOfClass:UILabel.class]) return;
        NSString *text = [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) word = text;
    });
    return word ?: pill.accessibilityLabel;
}

// The two pills of the row, in the order they are to read on the sheet. Either may be missing: a playlist
// of someone else's has no Mix, and a build without sorting has no Sort.
static BOOL isSortGlyph(NSString *glyph) {
    NSString *name = glyph.lowercaseString;
    return [name containsString:@"sort"] || [name containsString:@"arrowupdown"] || [name containsString:@"filter"];
}

static void pillsIn(UIView *toolbar, UIView **sort, UIView **mix) {
    __block UIView *foundSort = nil, *foundMix = nil;
    __block NSMutableArray<NSString *> *seen = [NSMutableArray array];
    SGForEachView(toolbar, ^(UIView *v) {
        NSString *identifier = v.accessibilityIdentifier;
        // The pills, and only the pills: the toolbar itself carries an identifier too, and the first glyph
        // under it is whichever pill comes first.
        if (!identifier.length || [identifier isEqualToString:SGRPlaylistCurationIdentifier]) return;
        if (!foundMix && [identifier containsString:kMixIdentifier]) {
            foundMix = v;
            return;
        }
        NSString *glyph = pillGlyph(v);
        if (glyph) [seen addObject:[NSString stringWithFormat:@"%@=%@", pillWord(v) ?: identifier, glyph]];
        if (!foundSort && isSortGlyph(glyph)) foundSort = v;
    });
    // Said once, so a build that renames the sort glyph says what it calls it instead of going quiet.
    static BOOL logged;
    if (!logged && seen.count) {
        logged = YES;
        SGLog(@"redesign playlist: the curation pills draw %@; sort %@", [seen componentsJoinedByString:@", "],
              foundSort ? @"found" : @"NOT FOUND");
    }
    *sort = foundSort;
    *mix = foundMix;
}

void SGRPlaylistTakeSort(UIView *page, UIView *button) {
    if (page && button && objc_getAssociatedObject(page, &kSortKey) != button) {
        objc_setAssociatedObject(page, &kSortKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// The cell that carries the curation row, as it lays out. Held from the page rather than from the cell: the
// list reuses the cell once it has scrolled past, and the sheet is opened from the top of a page one is
// usually well down. Held strongly for the same reason -- the element view Spotify binds to the toolbar is
// the toolbar's own, so it goes on answering wherever the cell it was in ends up.
void SGRPlaylistTakeCuration(UIView *cell) {
    UIView *toolbar = SGRFindByIdentifier(cell, SGRPlaylistCurationIdentifier, &kToolbarKey);
    UIView *page = toolbar ? SGRPlaylistPageOf(cell) : nil;
    if (!page || objc_getAssociatedObject(page, &kToolbarKey) == toolbar) return;
    objc_setAssociatedObject(page, &kToolbarKey, toolbar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *sort = nil, *mix = nil;
    pillsIn(toolbar, &sort, &mix);
    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign playlist: the curation row is the page's, sort %@, mix %@",
              sort ? pillWord(sort) : @"not found", mix ? pillWord(mix) : @"not found");
    }
}

#pragma mark - the block on the sheet

// One row: a glyph, a word, and the whole width of the sheet to be tapped on. Spotify's own rows are drawn
// by its table, so this only has to read as one of them.
@interface SGRMenuRow : UIControl
@property (nonatomic, weak) UIView *pill;
@end

@implementation SGRMenuRow {
    UIImageView *_glyph;
    UILabel *_word;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _glyph.tintColor = UIColor.whiteColor;
    _glyph.userInteractionEnabled = NO;
    [self addSubview:_glyph];

    _word = [UILabel new];
    _word.textColor = UIColor.whiteColor;
    _word.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize
                                   weight:UIFontWeightRegular];
    _word.userInteractionEnabled = NO;
    [self addSubview:_word];

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(sgr_down) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(sgr_up)
   forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return self;
}

- (void)showWord:(NSString *)word symbol:(NSString *)symbol {
    if (![_word.text isEqualToString:word]) {
        _word.text = word;
        self.accessibilityLabel = word;
    }
    if (!_glyph.image) _glyph.image = [UIImage systemImageNamed:symbol];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _glyph.frame = CGRectMake(kSideMargin, round((bounds.size.height - kGlyphSide) / 2), kGlyphSide, kGlyphSide);
    CGFloat lead = kSideMargin + kGlyphSide + kGlyphGap;
    [_word sizeToFit];
    _word.frame = CGRectMake(lead, round((bounds.size.height - _word.bounds.size.height) / 2),
                             MAX(0, bounds.size.width - lead - kSideMargin), _word.bounds.size.height);
}

- (void)sgr_down {
    self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
}

- (void)sgr_up {
    self.backgroundColor = UIColor.clearColor;
}

@end

@interface SGRMenuBlock : UIView
@property (nonatomic, weak) UIViewController *menu;
- (void)showSort:(UIView *)sort mix:(UIView *)mix;
- (CGFloat)wantedHeight;
@end

@implementation SGRMenuBlock {
    SGRMenuRow *_sort, *_mix;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _sort = [[SGRMenuRow alloc] initWithFrame:CGRectZero];
    _mix = [[SGRMenuRow alloc] initWithFrame:CGRectZero];
    for (SGRMenuRow *row in @[_sort, _mix]) {
        row.hidden = YES;
        [row addTarget:self action:@selector(sgr_rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:row];
    }
    return self;
}

// The glyphs are the system's rather than Spotify's: Encore draws its own into a view of its own, and a
// copy of one is a snapshot to keep right, where these two say the same thing on every build. The words
// stay Spotify's, so the rows are in the app's language.
- (void)showSort:(UIView *)sort mix:(UIView *)mix {
    _sort.pill = sort;
    _mix.pill = mix;
    if (sort) [_sort showWord:pillWord(sort) symbol:@"arrow.up.arrow.down"];
    if (mix) [_mix showWord:pillWord(mix) symbol:@"slider.horizontal.3"];
    _sort.hidden = sort == nil;
    _mix.hidden = mix == nil;
    [self setNeedsLayout];
}

- (CGFloat)wantedHeight {
    CGFloat height = 0;
    for (SGRMenuRow *row in @[_sort, _mix]) height += row.hidden ? 0 : kRowHeight;
    return height;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat y = 0;
    for (SGRMenuRow *row in @[_sort, _mix]) {
        if (row.hidden) continue;
        row.frame = CGRectMake(0, y, self.bounds.size.width, kRowHeight);
        y += kRowHeight;
    }
}

// Spotify's Sort opens a sheet of its own and its Mix changes the page under this one, so the menu closes
// first and the pill is fired once it has: firing under an open sheet would put Spotify's next sheet behind
// this one.
- (void)sgr_rowTapped:(SGRMenuRow *)row {
    UIView *pill = row.pill;
    UIViewController *menu = self.menu;
    void (^fire)(void) = ^{
        SGRActivate(pill);
        static BOOL logged;
        if (!logged) {
            logged = YES;
            SGLog(@"redesign playlist: the sheet fired %@, still on screen: %@", row.accessibilityLabel,
                  pill.window ? @"yes" : @"no");
        }
    };
    UIViewController *presented = menu.navigationController ?: menu;
    if (presented.presentingViewController) [presented dismissViewControllerAnimated:YES completion:fire];
    else fire();
}

@end

#pragma mark - the sheet's pass

static UITableView *tableIn(UIView *root, int depth) {
    if ([root isKindOfClass:UITableView.class]) return (UITableView *)root;
    if (depth > 5) return nil;
    for (UIView *child in root.subviews) {
        UITableView *table = tableIn(child, depth + 1);
        if (table) return table;
    }
    return nil;
}

// The curation row of the page, held from the cell's own pass where there has been one, and looked for on
// the page where there has not: the row is a cell closed up to nothing, and a collection view lays out
// what it has to draw, so a page opened and left alone can reach the sheet before that cell has ever run
// a pass. It was the only thing keeping Mix off the sheet, and the sheet only came right after the menu
// had been opened and closed a few times (device 2026-09-20). The walk is the page's live views, which is
// the cells on screen and no more, and it is done once per sheet.
static UIView *curationIn(UIView *page) {
    UIView *held = objc_getAssociatedObject(page, &kToolbarKey);
    if (held && held.window) return held;
    UIView *found = SGRFindByIdentifier(page, SGRPlaylistCurationIdentifier, NULL);
    if (found) objc_setAssociatedObject(page, &kToolbarKey, found, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return found ?: held;
}

// The page this sheet belongs to, decided once and only from the ⋯ that opened it. What the page has to
// show is decided pass by pass below, never here: a sheet turned down because the page was not ready yet
// would stay turned down for as long as it was open.
static UIView *pageFor(UIViewController *menu) {
    id decided = objc_getAssociatedObject(menu, &kDecidedKey);
    if (decided) return decided == NSNull.null ? nil : decided;
    UIView *page = SGRPinnedMoreRecentPage();
    if (page) curationIn(page);
    objc_setAssociatedObject(menu, &kDecidedKey, page ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return page;
}

static void install(UIViewController *menu) {
    UIView *root = menu.viewIfLoaded;
    UIView *page = root ? pageFor(menu) : nil;
    if (!page) return;
    UITableView *table = tableIn(root, 0);
    CGFloat width = table.bounds.size.width;
    if (!table || width <= 0) return;
    // Spotify already uses the header on some sheets; there the rows go under its own instead.
    SGRMenuBlock *block = objc_getAssociatedObject(menu, &kBlockKey);
    BOOL inFooter = block ? [objc_getAssociatedObject(block, &kBlockKey) boolValue] : NO;
    if (!block) {
        BOOL headerFree = !table.tableHeaderView || table.tableHeaderView.bounds.size.height < 1;
        inFooter = !headerFree;
        if (inFooter && table.tableFooterView && table.tableFooterView.bounds.size.height >= 1) {
            SGLog(@"redesign playlist: the sheet's header and footer are both Spotify's, sort and mix left out");
            objc_setAssociatedObject(menu, &kDecidedKey, NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        block = [[SGRMenuBlock alloc] initWithFrame:CGRectZero];
        block.menu = menu;
        objc_setAssociatedObject(block, &kBlockKey, @(inFooter), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(menu, &kBlockKey, block, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Sort is Spotify's own header button where the page has one -- one identifier, in the header, never
    // reused -- and the curation pill only where it has not, which is how it was found before the header's
    // button was (device 2026-09-20: the pill's glyph did not answer and the row went missing).
    UIView *sort = nil, *mix = nil;
    pillsIn(curationIn(page), &sort, &mix);
    sort = objc_getAssociatedObject(page, &kSortKey) ?: sort;
    [block showSort:sort mix:mix];
    // Nothing to show yet is not an answer: the page fills in as it lays out, and the next pass is asked
    // again rather than the sheet being written off.
    CGFloat height = [block wantedHeight];
    if (height < 1) return;

    CGRect frame = CGRectMake(0, 0, width, height);
    UIView *placed = inFooter ? table.tableFooterView : table.tableHeaderView;
    if (placed == block && CGRectEqualToRect(block.frame, frame)) return;
    block.frame = frame;
    if (inFooter) table.tableFooterView = block;
    else table.tableHeaderView = block;
    [table invalidateIntrinsicContentSize];
    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign playlist: the ⋯ sheet took %.0fpt of sort and mix in its %@", height,
              inFooter ? @"footer" : @"header");
    }
}

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLayoutSubviews {
    %orig;
    install((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC24ContextMenu_InternalImpl25ContextMenuViewController"]);
}
