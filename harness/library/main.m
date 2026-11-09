// A mock of Spotify's Your Library page under its own class names and accessibility identifiers, built from
// trees/clean/library/03.txt (recorded 2026-09-16), so Redesigned/Library/LibraryHeader.x can be laid out and
// looked at on the Mac. It plays issue #21: the header's model arriving after the page has laid out, the buttons
// it shows placed by Spotify's stack on a pass of its own. `first` on the launch line stops there, `back` then
// gives the page the pass it gets on the way back from a playlist, `steady` builds the header with the model
// already in it. `nocreate` leaves Create out of the model, `norecents` Recents (the account the tree is of).
#import <UIKit/UIKit.h>
#import <os/log.h>
#import "Redesigned/Kit/SGRBarGeometry.h"

#define HLog(fmt, ...) os_log(OS_LOG_DEFAULT, "[harness] %{public}s", [NSString stringWithFormat:(fmt), ##__VA_ARGS__].UTF8String)

static const CGFloat kHeaderHeight = 159.33;
static BOOL sgHarnessGrid;

#pragma mark - Spotify's classes, by name

@interface _TtCO22Reprise_LiquidGlassKit11LiquidGlass12GradientView : UIView @end
@implementation _TtCO22Reprise_LiquidGlassKit11LiquidGlass12GradientView @end

@interface _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer : UIView @end
@implementation _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer @end

@interface _TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView : UIView @end
@implementation _TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView @end

@interface _TtC28YourLibrary_YourLibraryXImpl22YourLibraryContentView : UIView @end
@implementation _TtC28YourLibrary_YourLibraryXImpl22YourLibraryContentView @end

@interface _TtC22YourLibrary_FolderImpl10FolderView : UIView @end
@implementation _TtC22YourLibrary_FolderImpl10FolderView @end

@interface _TtC21YourLibrary_CommonKit25YourLibraryCollectionView : UICollectionView @end
@implementation _TtC21YourLibrary_CommonKit25YourLibraryCollectionView @end

@interface _TtC28YourLibrary_YourLibraryXImpl30YourLibraryCompositionalLayout : UICollectionViewCompositionalLayout
@property NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *upstreamItems;
@property NSArray<UICollectionViewLayoutAttributes *> *upstreamElements;
@end
@implementation _TtC28YourLibrary_YourLibraryXImpl30YourLibraryCompositionalLayout
- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewLayoutAttributes *attributes = [[super layoutAttributesForItemAtIndexPath:indexPath] copy];
    if (!self.upstreamItems) self.upstreamItems = [NSMutableDictionary dictionary];
    if (attributes) self.upstreamItems[indexPath] = attributes;
    return attributes;
}
- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray *copies = [NSMutableArray array];
    for (UICollectionViewLayoutAttributes *attributes in [super layoutAttributesForElementsInRect:rect]) [copies addObject:[attributes copy]];
    self.upstreamElements = copies;
    return copies;
}
@end

// Encore's button: a 48pt box with its 24pt glyph in the middle.
@interface MockEncoreButton : UIControl @end
@implementation MockEncoreButton @end

// LegacyUI_ECMCoreKit.AutoLayoutStackView: the arranged views in a plain container view, chained by constraints
// the stack rebuilds when one of them shows or hides. The real one watches its views' hidden and folds the
// changes into one update (its ivars: observationsDictionary, needsCoalescedLayoutUpdate); the mock folds them
// into the next turn of the main queue, so a page laying out in the turn the header's model lands in still
// sees each button where it stood before. A hidden view leaves the chain and sits at the container's origin,
// where 03.txt has the hidden Recents.
@interface _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView : UIView
@property (nonatomic, readonly) UIView *containerView;
@property (nonatomic, copy) NSArray<UIView *> *arrangedSubviews;
@end

@implementation _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView {
    NSArray<NSLayoutConstraint *> *_layoutConstraints;
    BOOL _needsCoalescedLayoutUpdate;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _containerView = [[UIView alloc] initWithFrame:self.bounds];
    _containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_containerView];
    return self;
}

- (void)setArrangedSubviews:(NSArray<UIView *> *)views {
    _arrangedSubviews = [views copy];
    for (UIView *view in views) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:view];
        [view addObserver:self forKeyPath:@"hidden" options:0 context:NULL];
    }
    [self rebuild];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (_needsCoalescedLayoutUpdate) return;
    _needsCoalescedLayoutUpdate = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_needsCoalescedLayoutUpdate = NO;
        [self rebuild];
        HLog(@"stack rebuilt its constraints");
    });
}

- (void)rebuild {
    if (_layoutConstraints) [NSLayoutConstraint deactivateConstraints:_layoutConstraints];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
    UIView *previous = nil;
    for (UIView *view in _arrangedSubviews) {
        if (view.hidden) {
            [constraints addObject:[view.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor]];
            [constraints addObject:[view.topAnchor constraintEqualToAnchor:_containerView.topAnchor]];
            continue;
        }
        [constraints addObject:[view.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor]];
        [constraints addObject:[view.leadingAnchor constraintEqualToAnchor:previous ? previous.trailingAnchor : _containerView.leadingAnchor]];
        previous = view;
    }
    if (previous) [constraints addObject:[previous.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor]];
    _layoutConstraints = constraints;
    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)dealloc {
    for (UIView *view in _arrangedSubviews) [view removeObserver:self forKeyPath:@"hidden"];
}
@end

// The header lays its own children out by frame: the scrim over all of it, the control row off the safe area,
// the chips under the row.
@interface _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView : UIView
@property (nonatomic, strong) UIView *gradient, *row, *filters;
@end

@implementation _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat top = self.window ? self.window.safeAreaInsets.top : 62;
    self.gradient.frame = CGRectMake(0, 0, width, kHeaderHeight);
    self.row.frame = CGRectMake(0, top, width, 48);
    self.filters.frame = CGRectMake(0, top + 48, width, 49.33);
}
@end

// The page: its content the size of it, the header over it at its full height and the list inset by that height,
// all three stated again on every pass the way Spotify's does.
@interface _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView : UIView
@property (nonatomic, strong) UIView *content, *header, *headerContainer;
@property (nonatomic, strong) UICollectionView *list;
@end

@implementation _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView
- (void)layoutSubviews {
    [super layoutSubviews];
    self.content.frame = self.bounds;
    self.list.frame = self.content.bounds;
    if ([NSProcessInfo.processInfo.arguments containsObject:@"rows"] && [self.list.collectionViewLayout isKindOfClass:UICollectionViewFlowLayout.class]) {
        UICollectionViewFlowLayout *layout = (id)self.list.collectionViewLayout;
        layout.itemSize = CGSizeMake(self.list.bounds.size.width, 80);
        layout.sectionInset = UIEdgeInsetsZero;
        layout.minimumLineSpacing = 0;
    }
    self.headerContainer.frame = CGRectMake(0, 0, self.bounds.size.width, kHeaderHeight);
    self.header.frame = CGRectMake(0, 0, self.bounds.size.width, kHeaderHeight);
    UIEdgeInsets inset = self.list.contentInset;
    inset.top = kHeaderHeight;
    self.list.contentInset = inset;
}
@end

#pragma mark - building the page

static UIView *box(UIView *parent, Class cls, CGRect frame, NSString *identifier) {
    UIView *view = [[cls alloc] initWithFrame:frame];
    view.accessibilityIdentifier = identifier;
    if (parent) [parent addSubview:view];
    return view;
}

static void pinSize(UIView *view, CGFloat width, CGFloat height) {
    [view.widthAnchor constraintEqualToConstant:width].active = YES;
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
}

static UIView *button(NSString *identifier, NSString *symbol) {
    UIView *control = box(nil, MockEncoreButton.class, CGRectMake(0, 0, 48, 48), identifier);
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:config]];
    glyph.frame = CGRectMake(12, 12, 24, 24);
    glyph.contentMode = UIViewContentModeCenter;
    glyph.tintColor = UIColor.whiteColor;
    [control addSubview:glyph];
    pinSize(control, 48, 48);
    return control;
}

static UIImage *avatar(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, 64)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithRed:0.55 green:0.85 blue:0.55 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, 64, 64));
        [[UIColor colorWithRed:0.25 green:0.22 blue:0.2 alpha:1] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(18, 10, 28, 32)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(6, 40, 52, 40)] fill];
    }];
}

static UIView *face(BOOL encoreAvatar) {
    UIView *container = box(nil, encoreAvatar ? MockEncoreButton.class : _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer.class, CGRectMake(0, 0, 48, 48), encoreAvatar ? @"Components.UI.SideDrawerButton" : nil);
    UIView *drawer = encoreAvatar ? container : box(container, MockEncoreButton.class, CGRectMake(0, 0, 48, 48), @"Components.UI.SideDrawerButton");
    UIImageView *image = [[UIImageView alloc] initWithImage:avatar()];
    image.frame = CGRectMake(8, 8, 32, 32);
    image.layer.cornerRadius = 16;
    image.clipsToBounds = YES;
    [drawer addSubview:image];
    pinSize(container, 48, 48);
    return container;
}

static UIView *spotifyTitle(void) {
    UIView *encore = box(nil, UIView.class, CGRectZero, @"YourLibraryHeader.title");
    UILabel *label = [UILabel new];
    label.text = @"Your Library";
    label.font = [UIFont boldSystemFontOfSize:21];
    label.textColor = UIColor.whiteColor;
    label.accessibilityIdentifier = @"YourLibraryHeader.title-internal";
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [encore addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:encore.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:encore.trailingAnchor],
        [label.topAnchor constraintEqualToAnchor:encore.topAnchor],
        [label.bottomAnchor constraintEqualToAnchor:encore.bottomAnchor],
    ]];
    return encore;
}

static UIView *chips(UIView *filters) {
    CGFloat x = 16;
    for (NSString *word in @[@"Playlists", @"Podcasts", @"Albums", @"Artists"]) {
        UILabel *chip = [UILabel new];
        chip.text = word;
        chip.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        chip.textColor = UIColor.whiteColor;
        chip.textAlignment = NSTextAlignmentCenter;
        chip.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        chip.layer.cornerRadius = 14.7;
        chip.clipsToBounds = YES;
        CGFloat width = ceil([word sizeWithAttributes:@{NSFontAttributeName: chip.font}].width) + 32;
        chip.frame = CGRectMake(x, 8, width, 29.33);
        [filters addSubview:chip];
        x += width + 8;
    }
    return filters;
}

// Exact row constraints from the 9.1.94 physical snapshot, with full-width cells.
@interface _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer : UICollectionViewCell @end
@implementation _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer @end
@interface SGRHarnessRow : _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer
@property UIView *row;
@property UIView *inner;
@end
@implementation SGRHarnessRow
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.row = box(self.contentView, UIView.class, self.contentView.bounds, @"Playlist.Row.Library");
    self.row.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.inner = box(self.row, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectZero, nil);
    self.inner.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.inner.leadingAnchor constraintEqualToAnchor:self.row.leadingAnchor constant:16],
        [self.inner.trailingAnchor constraintEqualToAnchor:self.row.trailingAnchor constant:-16],
        [self.inner.topAnchor constraintEqualToAnchor:self.row.topAnchor constant:8],
        [self.inner.bottomAnchor constraintEqualToAnchor:self.row.bottomAnchor constant:-8],
    ]];
    UIView *art = box(self.inner, UIView.class, CGRectMake(0, 0, 64, 64), @"Artwork.Row.Library");
    art.backgroundColor = UIColor.systemIndigoColor;
    UILabel *text = [[UILabel alloc] initWithFrame:CGRectMake(76, 0, 200, 64)];
    text.text = @"Full width library row";
    text.textColor = UIColor.whiteColor;
    [self.inner addSubview:text];
    return self;
}
@end

@interface SGRHarnessCard : UICollectionViewCell
@property (nonatomic, strong) UIView *cover;
@property (nonatomic, strong) UILabel *title;
@end

@implementation SGRHarnessCard
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.accessibilityIdentifier = @"Components.UI.CardLibrary";
    CGFloat side = frame.size.width;
    _cover = [[UIView alloc] initWithFrame:CGRectMake(0, 0, side, side)];
    _cover.layer.cornerRadius = 6;
    [self.contentView addSubview:_cover];
    _title = [[UILabel alloc] initWithFrame:CGRectMake(0, side + 6, side, 18)];
    _title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _title.textColor = UIColor.whiteColor;
    [self.contentView addSubview:_title];
    return self;
}
@end

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate, UICollectionViewDataSource>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView *page;
@property (nonatomic, strong) NSDictionary<NSString *, UIView *> *controls;
@end

@implementation SGRHarnessDelegate

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return 12;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"rows"] && !sgHarnessGrid)
        return [collectionView dequeueReusableCellWithReuseIdentifier:@"row" forIndexPath:indexPath];
    SGRHarnessCard *card = [collectionView dequeueReusableCellWithReuseIdentifier:@"card" forIndexPath:indexPath];
    NSArray<NSString *> *names = @[@"Great songs", @"70s Hits", @"80s Hits", @"Early 2000's", @"Lofi Girl", @"hololive",
                                   @"Skepta", @"Real Music", @"Aitch", @"New Episodes", @"Tame Impala", @"Chill Mix"];
    card.title.text = names[indexPath.item % names.count];
    CGFloat hue = fmod(indexPath.item * 0.137, 1);
    card.cover.backgroundColor = [UIColor colorWithHue:hue saturation:0.55 brightness:0.6 alpha:1];
    return card;
}

- (UIView *)control:(NSString *)name {
    return self.controls[name];
}

// What the header's model says: which buttons it shows. Setting them is all Spotify's header does on a render;
// the stack places what changed on its own, later.
- (void)render:(NSArray<NSString *> *)shown {
    for (NSString *name in @[@"recents", @"search", @"plus"]) {
        BOOL hidden = ![shown containsObject:name];
        UIView *control = self.controls[name];
        if (control.hidden != hidden) control.hidden = hidden;
    }
    HLog(@"model: %@ shown", [shown componentsJoinedByString:@", "]);
}

- (void)report:(NSString *)moment {
    UIView *header = self.page.header;
    if ([NSProcessInfo.processInfo.arguments containsObject:@"safepage"]) {
        BOOL vertical = !CGRectIsNull(SGRVerticalBarFrameIn(self.page, SGRVerticalBarExtent));
        CGFloat expected = vertical ? self.page.superview.bounds.size.width : self.page.superview.safeAreaLayoutGuide.layoutFrame.size.width;
        NSCAssert(fabs(self.page.bounds.size.width - expected) < 0.5, @"Page width must follow full bounds only with vertical navigation");
        NSCAssert(fabs(self.page.list.bounds.size.width - expected) < 0.5, @"Collection must fill page width");
        HLog(@"page width %.0f collection %.0f expected %.0f vertical %d", self.page.bounds.size.width, self.page.list.bounds.size.width, expected, vertical);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"rows"] && !sgHarnessGrid) {
        BOOL vertical = !CGRectIsNull(SGRVerticalBarFrameIn(self.page, SGRVerticalBarExtent));
        NSCAssert(self.page.list.contentInset.left == 0 && self.page.list.contentInset.right == 0, @"No global side inset");
        if (@available(iOS 26.0, *)) NSCAssert(self.page.list.bottomEdgeEffect.hidden == vertical, @"Bottom edge hidden only in Duo");
        SGRHarnessRow *cell = (id)self.page.list.visibleCells.firstObject;
        NSCAssert(cell != nil, @"Realistic row must be visible");
        NSCAssert(fabs(cell.bounds.size.width - self.page.list.bounds.size.width) < 0.5, @"Cell must span viewport");
        UIEdgeInsets clearance = vertical ? SGRVerticalBarContentInsets(cell.row, SGRVerticalBarExtent) : UIEdgeInsetsZero;
        if (vertical) { clearance.left = MAX(clearance.left, cell.row.safeAreaInsets.left); clearance.right = MAX(clearance.right, cell.row.safeAreaInsets.right); }
        NSCAssert(fabs(CGRectGetMinX(cell.inner.frame) - 16 - clearance.left) < 0.5, @"Inner leading clearance");
        NSCAssert(fabs(CGRectGetMaxX(cell.inner.frame) - cell.bounds.size.width + 16 + clearance.right) < 0.5, @"Inner trailing clearance");
        if ([self.page.list.collectionViewLayout isKindOfClass:UICollectionViewCompositionalLayout.class]) {
            UICollectionViewCompositionalLayout *composition = (id)self.page.list.collectionViewLayout;
            NSCAssert(composition.configuration.contentInsetsReference == UIContentInsetsReferenceNone, @"Configuration unchanged");
            _TtC28YourLibrary_YourLibraryXImpl30YourLibraryCompositionalLayout *mock = (id)composition;
            NSIndexPath *index = [self.page.list indexPathForCell:cell];
            CGSize contentBefore = mock.collectionViewContentSize;
            UICollectionViewLayoutAttributes *item = [mock layoutAttributesForItemAtIndexPath:index];
            UICollectionViewLayoutAttributes *upstream = mock.upstreamItems[index];
            CGFloat safeWidth = self.page.list.bounds.size.width - self.page.list.safeAreaInsets.left - self.page.list.safeAreaInsets.right;
            NSCAssert(fabs(upstream.frame.size.width - safeWidth) < 0.5, @"Upstream per-item attributes remain safe width");
            NSCAssert(fabs(item.frame.size.width - self.page.list.bounds.size.width) < 0.5, @"Per-item query widened");
            NSCAssert(item.frame.origin.x == upstream.frame.origin.x && item.frame.origin.y == upstream.frame.origin.y && item.frame.size.height == upstream.frame.size.height, @"Only width changes");
            NSArray *elements = [mock layoutAttributesForElementsInRect:self.page.list.bounds];
            for (NSUInteger i = 0; i < elements.count; i++) {
                UICollectionViewLayoutAttributes *output = elements[i], *input = mock.upstreamElements[i];
                if (input.representedElementCategory != UICollectionElementCategoryCell) continue;
                NSCAssert(fabs(input.frame.size.width - safeWidth) < 0.5, @"Upstream elements not mutated");
                NSCAssert(fabs(output.frame.size.width - self.page.list.bounds.size.width) < 0.5, @"Elements query widened");
                if (vertical) NSCAssert(input != output, @"Attributes repaired on copies");
            }
            NSCAssert(CGSizeEqualToSize(contentBefore, mock.collectionViewContentSize), @"Content size unchanged");
        }
        BOOL fullSeparator = NO;
        for (CALayer *layer in cell.layer.sublayers) {
            if (layer.bounds.size.height > 0 && layer.bounds.size.height <= 1 && fabs(CGRectGetMaxX(layer.frame) - cell.bounds.size.width) < 0.5) fullSeparator = YES;
        }
        NSCAssert(fullSeparator, @"Separator must reach full cell edge");
        BOOL bottomHidden = NO;
        if (@available(iOS 26.0, *)) bottomHidden = self.page.list.bottomEdgeEffect.hidden;
        HLog(@"row %.0f inner %@ inset %@ bottom hidden %d separator full %d", cell.bounds.size.width, NSStringFromCGRect(cell.inner.frame), NSStringFromUIEdgeInsets(self.page.list.contentInset), bottomHidden, fullSeparator);
    }
    if (sgHarnessGrid) {
        UICollectionViewCompositionalLayout *layout = (id)self.page.list.collectionViewLayout;
        NSCAssert(layout.configuration.contentInsetsReference == UIContentInsetsReferenceNone, @"Grid configuration unchanged");
        CGRect first = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].frame;
        CGRect third = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:2 inSection:0]].frame;
        CGFloat expected = self.page.list.bounds.size.width - self.page.list.safeAreaInsets.left - self.page.list.safeAreaInsets.right;
        NSCAssert(fabs(CGRectGetMaxX(third) - CGRectGetMinX(first) - expected) < 1, @"Grid stays within safe width");
        HLog(@"grid restored safe width %.0f expected %.0f", CGRectGetMaxX(third) - CGRectGetMinX(first), expected);
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    CGFloat previousRight = 0;
    CGFloat allowedRight = header.bounds.size.width - SGRVerticalBarContentInsets(header, SGRVerticalBarExtent).right;
    for (NSString *name in @[@"recents", @"search", @"plus", @"face"]) {
        UIView *control = self.controls[name];
        if (control.hidden) {
            [parts addObject:[NSString stringWithFormat:@"%@ hidden", name]];
            continue;
        }
        CGRect frame = [control.superview convertRect:control.frame toView:header];
        NSCAssert(CGRectGetMinX(frame) >= previousRight - 0.5, @"Header controls must not overlap");
        NSCAssert(CGRectGetMaxX(frame) <= allowedRight + 0.5, @"Header controls must clear the rail");
        previousRight = CGRectGetMaxX(frame);
        [parts addObject:[NSString stringWithFormat:@"%@ %.0f-%.0f", name, CGRectGetMinX(frame), CGRectGetMaxX(frame)]];
    }
    UILabel *title = nil;
    for (UIView *sub in header.subviews) {
        if ([sub isMemberOfClass:UILabel.class]) title = (UILabel *)sub;
    }
    NSCAssert(title.text.length > 0, @"Redesigned title must exist, including with a wrapped header");
    NSCAssert(self.controls[@"title"].alpha == 0, @"Stock title must be concealed");
    CGFloat textRight = title ? CGRectGetMinX(title.frame) + MIN(title.bounds.size.width, [title.text sizeWithAttributes:@{NSFontAttributeName: title.font}].width) : 0;
    UIView *filters = [header valueForKey:@"filters"];
    HLog(@"%@: %@; title text %.0f-%.0f, header %.0fpt, list inset %.0f, chips %@", moment,
         [parts componentsJoinedByString:@", "], CGRectGetMinX(title.frame), textRight,
         header.bounds.size.height, self.page.list.contentInset.top,
         !filters ? @"missing" : (filters.alpha < 0.5 ? @"HIDDEN" : [NSString stringWithFormat:@"%.0fpt at y=%.0f",
                                  filters.bounds.size.height, filters.frame.origin.y]));
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options { return YES; }

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Library" sessionRole:session.role];
    configuration.delegateClass = self.class;
    return configuration;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    BOOL steady = [args containsObject:@"steady"];
    BOOL back = [args containsObject:@"back"];
    NSArray<NSString *> *model = @[@"recents", @"search", @"plus"];
    if ([args containsObject:@"nocreate"]) model = @[@"recents", @"search"];
    if ([args containsObject:@"norecents"]) model = @[@"search", @"plus"];

    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.backgroundColor = UIColor.blackColor;
    UIViewController *root = [UIViewController new];

    _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView *page = [[_TtC28YourLibrary_YourLibraryXImpl15YourLibraryView alloc] initWithFrame:self.window.bounds];
    page.backgroundColor = UIColor.blackColor;
    self.page = page;

    page.content = box(page, _TtC28YourLibrary_YourLibraryXImpl22YourLibraryContentView.class, page.bounds, nil);
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    CGFloat side = floor((page.bounds.size.width - 32 - 2 * 14) / 3);
    layout.itemSize = CGSizeMake(side, side + 44);
    layout.minimumInteritemSpacing = 14;
    layout.minimumLineSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(40, 16, 0, 16);
    _TtC21YourLibrary_CommonKit25YourLibraryCollectionView *list = [[_TtC21YourLibrary_CommonKit25YourLibraryCollectionView alloc] initWithFrame:page.bounds collectionViewLayout:layout];
    if ([args containsObject:@"compositional"]) {
        list.collectionViewLayout = [[_TtC28YourLibrary_YourLibraryXImpl30YourLibraryCompositionalLayout alloc]
            initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger index, id<NSCollectionLayoutEnvironment> environment) {
                NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:sgHarnessGrid ? 1.0 / 3 : 1]
                    heightDimension:[NSCollectionLayoutDimension absoluteDimension:80]];
                NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
                NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
                    heightDimension:[NSCollectionLayoutDimension absoluteDimension:80]];
                NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:sgHarnessGrid ? @[item, item, item] : @[item]];
                NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
                section.contentInsetsReference = UIContentInsetsReferenceSafeArea;
                return section;
            }];
        UICollectionViewCompositionalLayout *composition = (id)list.collectionViewLayout;
        UICollectionViewCompositionalLayoutConfiguration *configuration = [composition.configuration copy];
        configuration.contentInsetsReference = UIContentInsetsReferenceNone;
        composition.configuration = configuration;
    }
    list.accessibilityIdentifier = @"YourLibraryContent.collectionView";
    list.backgroundColor = UIColor.blackColor;
    list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [list registerClass:SGRHarnessCard.class forCellWithReuseIdentifier:@"card"];
    [list registerClass:SGRHarnessRow.class forCellWithReuseIdentifier:@"row"];
    list.dataSource = self;
    [page.content addSubview:list];
    page.list = list;

    if ([args containsObject:@"wrapped"]) {
        page.headerContainer = box(page, UIView.class, CGRectMake(0, 0, page.bounds.size.width, kHeaderHeight), nil);
    }
    _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView *header = (id)box(page.headerContainer ?: page, _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView.class, CGRectMake(0, 0, page.bounds.size.width, kHeaderHeight), nil);
    page.header = header;
    header.gradient = box(header, _TtCO22Reprise_LiquidGlassKit11LiquidGlass12GradientView.class, header.bounds, @"LiquidGlass.GradientView");
    header.gradient.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    header.row = box(header, UIView.class, CGRectMake(0, 62, header.bounds.size.width, 48), nil);
    UIView *inner = box(header.row, UIView.class, header.row.bounds, nil);
    inner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView *stack = (id)box(inner, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(8, 0, inner.bounds.size.width - 16, 48), nil);
    stack.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.filters = chips(box(header, _TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView.class, CGRectMake(0, 110, header.bounds.size.width, 49.33), nil));

    UIView *avatarBox = face([args containsObject:@"encoreavatar"]);
    UIView *title = spotifyTitle();
    UIView *spacer = [UIView new];
    [spacer.heightAnchor constraintEqualToConstant:0].active = YES;
    [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIView *recents = button(@"YourLibraryHeader.recents", @"clock.arrow.circlepath");
    UIView *search = button(@"YourLibraryHeader.search", @"magnifyingglass");
    UIView *plus = button(@"YourLibraryHeader.plus", @"plus");
    self.controls = @{@"recents": recents, @"search": search, @"plus": plus, @"face": avatarBox, @"title": title};

    // Built with what the header knows before its model arrives -- Search alone -- unless `steady`.
    NSArray<NSString *> *initial = steady ? model : @[@"search"];
    for (NSString *name in @[@"recents", @"search", @"plus"]) self.controls[name].hidden = ![initial containsObject:name];
    stack.arrangedSubviews = @[avatarBox, title, spacer, recents, search, plus];

    if ([args containsObject:@"safepage"]) {
        UIView *host = [[UIView alloc] initWithFrame:self.window.bounds];
        [host addSubview:page];
        page.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [page.leadingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.leadingAnchor],
            [page.trailingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.trailingAnchor],
            [page.topAnchor constraintEqualToAnchor:host.topAnchor],
            [page.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        ]];
        root.view = host;
    } else root.view = page;
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self report:@"page up"];
        if (steady) return;
        // The model lands, and the page lays out in the same turn -- Spotify's page states its list and header
        // again from the same update -- before the stack's own pass has placed what the model showed.
        [self render:model];
        [page setNeedsLayout];
        [page layoutIfNeeded];
        [self report:@"page pass in the model's turn"];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self report:@"first look"];
    });
    if ([args containsObject:@"gridtransition"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            sgHarnessGrid = YES;
            [list reloadData];
            [list.collectionViewLayout invalidateLayout];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self report:@"grid transition"]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            sgHarnessGrid = NO;
            [list reloadData];
            [list.collectionViewLayout invalidateLayout];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self report:@"list restored"]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 7 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ list.contentOffset = CGPointMake(0, 300); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self report:@"reused rows after scroll"]; });
    }
    if (back) {
        // Opening a playlist and coming back: the page lays out again, nothing else changes.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [page setNeedsLayout];
            [page layoutIfNeeded];
            [self report:@"back from a playlist"];
        });
    }
}

@end

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRHarnessDelegate.class));
    }
}
