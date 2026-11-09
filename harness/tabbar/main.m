// Tab bar harness: TabBar.x and NowPlayingBar.x run for real on a mock of the bottom of Spotify's main
// screen, laid out with the constraints 9.1.78 makes (see the README for the addresses), under Spotify's
// class names, with Spotify's message bar (Offline, Private Session) able to come in under the tab bar.
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRBarGeometry.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Core/SGCore.h"

#pragma mark - Spotify's classes, by the names the hooks look for

@interface _TtC23NavigationUI_TabBarImpl10TabBarView : UIView
@end
@implementation _TtC23NavigationUI_TabBarImpl10TabBarView
@end

@interface _TtC23NavigationUI_TabBarImpl17TabBarCompactView : UIView
@end
@implementation _TtC23NavigationUI_TabBarImpl17TabBarCompactView
@end

@interface _TtC23NavigationUI_TabBarImpl21TabBarItemElementView : UIView
@end
@implementation _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
@end

@interface _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView : UIView
@end
@implementation _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
@end

@interface _TtC44LimitedExperienceIndicator_MessageBarRuntime29LimitedExperienceIndicatorBar : UIView
@end
@implementation _TtC44LimitedExperienceIndicator_MessageBarRuntime29LimitedExperienceIndicatorBar
@end

@interface _TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView : UIView
@end
@implementation _TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView
@end

@interface _TtC18NowPlaying_BarImpl27NowPlayingBarViewController : UIViewController
@end
@implementation _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)loadView {
    self.view = [UIView new];
    // The card, 386x56 at {8,0} with the album colour, the artwork, two lines and the progress line
    // (trees/clean/home/01.txt, SPTNowPlayingBar).
    UIView *card = [UIView new];
    card.accessibilityIdentifier = @"SPTNowPlayingBar";
    card.backgroundColor = [UIColor colorWithRed:0x18 / 255.0 green:0x14 / 255.0 blue:0x1C / 255.0 alpha:1];
    card.layer.cornerRadius = 8;
    card.clipsToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [card.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    UIView *art = [[UIView alloc] initWithFrame:CGRectMake(8, 8, 40, 40)];
    art.layer.cornerRadius = 4;
    art.clipsToBounds = YES;
    UIImageView *image = [[UIImageView alloc] initWithFrame:art.bounds];
    image.backgroundColor = [UIColor colorWithRed:0.85 green:0.35 blue:0.55 alpha:1];
    [art addSubview:image];
    [card addSubview:art];
    UILabel *title = [UILabel new], *artist = [UILabel new];
    title.text = @"Stay High";
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textColor = UIColor.whiteColor;
    artist.text = @"Juice WRLD";
    artist.font = [UIFont systemFontOfSize:13];
    artist.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    UIStackView *lines = [[UIStackView alloc] initWithArrangedSubviews:@[title, artist]];
    lines.axis = UILayoutConstraintAxisVertical;
    lines.frame = CGRectMake(56, 8, 200, 40);
    [card addSubview:lines];
    UIButton *play = [UIButton systemButtonWithImage:[UIImage systemImageNamed:@"play.fill"] target:nil action:nil];
    play.tintColor = UIColor.whiteColor;
    play.translatesAutoresizingMaskIntoConstraints = NO;
    play.accessibilityIdentifier = @"harness.miniplayer-play";
    [card addSubview:play];
    [NSLayoutConstraint activateConstraints:@[
        [play.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [play.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [play.widthAnchor constraintEqualToConstant:32],
        [play.heightAnchor constraintEqualToConstant:32],
    ]];
    UIView *progress = [[UIView alloc] initWithFrame:CGRectMake(8, 54, 370, 2)];
    progress.backgroundColor = UIColor.whiteColor;
    [card addSubview:progress];
}
@end

@interface _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController : UIViewController
@end
@implementation _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    UIViewController *bar = [_TtC18NowPlaying_BarImpl27NowPlayingBarViewController new];
    [self addChildViewController:bar];
    bar.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar.view];
    [NSLayoutConstraint activateConstraints:@[
        [bar.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [bar.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [bar.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [bar didMoveToParentViewController:self];
}
@end

// A page on the tab's stack: a list, inset the way Spotify's pages are, by the safe area it inherits.
@interface SGHarnessPage : UITableViewController
@end
@implementation SGHarnessPage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = UIColor.blackColor;
    self.tableView.rowHeight = 48;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 30; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:path];
    cell.backgroundColor = path.row == 29 ? [UIColor colorWithRed:0.1 green:0.3 blue:0.6 alpha:1] : UIColor.blackColor;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.text = path.row == 29 ? @"Last row of the list" : [NSString stringWithFormat:@"Row %ld", (long)path.row + 1];
    return cell;
}
@end

// The live 9.1.94 navigation wrapper owns the tab-row inset separately from the page.
@interface SPNavigationController : UIViewController
@end
@implementation SPNavigationController
@end

// NavigationUI_TabBarImpl.TabBarContainerImpl in a compact width, as its viewDidLoad (0x1008409a8) and
// its size class pass (0x106fabb7c) lay it out: a guide from 49 pt above the safe area's bottom to the
// view's bottom, a stack as tall as the guide on the view's bottom, the tab bar as tall as the stack.
// The page gets 49 pt more safe area on top of what the container has (0x10707bde4).
@interface _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl : UIViewController
@property (nonatomic, strong) UILayoutGuide *compactGuide;
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) SPNavigationController *navigation;
@property (nonatomic, strong) SGHarnessPage *page;
@end
@implementation _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (UILayoutGuide *)compactTabBarHeightLayoutGuide { return self.compactGuide; }
- (UIView *)tabBarView { return self.bar; }
- (void)setSelectedViewController:(UIViewController *)controller {}

static UIView *item(Class cls, NSString *title, NSString *symbol, BOOL active) {
    UIView *item = [cls new];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.frame = CGRectMake(0, 5.67, 24, 24);
    icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:10];
    label.textColor = active ? UIColor.whiteColor : [UIColor colorWithWhite:0xB3 / 255.0 alpha:1];
    label.textAlignment = NSTextAlignmentCenter;
    label.frame = CGRectMake(0, 35, 100, 14);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [item addSubview:icon];
    [item addSubview:label];
    return item;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    self.compactGuide = [UILayoutGuide new];
    [view addLayoutGuide:self.compactGuide];

    SPNavigationController *navigation = self.navigation = [SPNavigationController new];
    [self addChildViewController:navigation];
    navigation.view.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:navigation.view];
    [navigation didMoveToParentViewController:self];
    // Nonzero unrelated edges must survive the tab-row correction.
    navigation.additionalSafeAreaInsets = UIEdgeInsetsMake(3, 4, 49, 5);
    SGHarnessPage *page = self.page = [SGHarnessPage new];
    [navigation addChildViewController:page];
    page.view.translatesAutoresizingMaskIntoConstraints = NO;
    [navigation.view addSubview:page.view];
    [page didMoveToParentViewController:navigation];
    [NSLayoutConstraint activateConstraints:@[
        [page.view.leadingAnchor constraintEqualToAnchor:navigation.view.leadingAnchor],
        [page.view.trailingAnchor constraintEqualToAnchor:navigation.view.trailingAnchor],
        [page.view.topAnchor constraintEqualToAnchor:navigation.view.topAnchor],
        [page.view.bottomAnchor constraintEqualToAnchor:navigation.view.bottomAnchor],
    ]];

    UIView *stack = [UIView new];
    stack.accessibilityIdentifier = @"TabBarContainer.stackView";
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:stack];
    self.bar = [_TtC23NavigationUI_TabBarImpl10TabBarView new];
    self.bar.accessibilityIdentifier = @"elements-tabs-view-identifier";
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addSubview:self.bar];
    UIView *compact = [_TtC23NavigationUI_TabBarImpl17TabBarCompactView new];
    compact.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bar addSubview:compact];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Home", @"house.fill", YES),
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Search", @"magnifyingglass", NO),
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Your Library", @"books.vertical", NO),
        item(_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView.class, @"Create", @"plus", NO),
    ]];
    row.distribution = UIStackViewDistributionFillEqually;
    row.accessibilityIdentifier = @"tabs-container-view-identifier";
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [compact addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [navigation.view.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [navigation.view.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [navigation.view.topAnchor constraintEqualToAnchor:view.topAnchor],
        [navigation.view.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [self.compactGuide.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor constant:-49],
        [self.compactGuide.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [stack.heightAnchor constraintEqualToAnchor:self.compactGuide.heightAnchor],
        [self.bar.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor],
        [self.bar.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor],
        [self.bar.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor],
        [self.bar.heightAnchor constraintEqualToAnchor:stack.heightAnchor],
        [compact.leadingAnchor constraintEqualToAnchor:self.bar.leadingAnchor],
        [compact.trailingAnchor constraintEqualToAnchor:self.bar.trailingAnchor],
        [compact.topAnchor constraintEqualToAnchor:self.bar.topAnchor],
        [compact.bottomAnchor constraintEqualToAnchor:self.bar.bottomAnchor],
        [row.leadingAnchor constraintEqualToAnchor:compact.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:compact.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:compact.topAnchor],
        [row.heightAnchor constraintEqualToConstant:49],
    ]];
}
@end

#pragma mark - the chrome

// ClientChrome_ChromeContainerKit.ClientChromeViewController in a compact width: the primary content
// (the tab bar container) above the bottom attachment, which is Spotify's message bar, and the
// floating chrome (the now playing bar's page) standing on MainUIContainer's bottom anchor, the top of
// the tab bar container's compact height guide (0x100ae0178).
@interface SGHarnessChrome : UIViewController
@property (nonatomic, strong) _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl *tabs;
@property (nonatomic, strong) UIView *banner;
@property (nonatomic, strong) NSLayoutConstraint *bannerHeight;
@property (nonatomic, strong) UIView *npb;
@end

@implementation SGHarnessChrome

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    view.backgroundColor = UIColor.blackColor;

    self.tabs = [_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl new];
    [self addChildViewController:self.tabs];
    UIView *primary = self.tabs.view;
    primary.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:primary];
    [self.tabs didMoveToParentViewController:self];

    // LimitedExperienceIndicatorBar: its height is its message plus the safe area it pads its label by
    // (barHeightConstraint, backgroundContainerBottomPaddingConstraint, lastSafeAreaBottomInset).
    self.banner = [_TtC44LimitedExperienceIndicator_MessageBarRuntime29LimitedExperienceIndicatorBar new];
    self.banner.accessibilityIdentifier = @"LimitedExperienceIndicatorBar";
    self.banner.backgroundColor = UIColor.blackColor;
    self.banner.clipsToBounds = YES;
    self.banner.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:self.banner];
    UILabel *message = [UILabel new];
    message.text = @"Private Session";
    message.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    message.textColor = UIColor.whiteColor;
    message.translatesAutoresizingMaskIntoConstraints = NO;
    [self.banner addSubview:message];
    self.bannerHeight = [self.banner.heightAnchor constraintEqualToConstant:0];

    UIView *npb = [_TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView new];
    npb.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:npb];
    self.npb = npb;
    UIViewController *content = [_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController new];
    [self addChildViewController:content];
    content.view.translatesAutoresizingMaskIntoConstraints = NO;
    [npb addSubview:content.view];
    [content didMoveToParentViewController:self];

    [NSLayoutConstraint activateConstraints:@[
        [primary.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [primary.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [primary.topAnchor constraintEqualToAnchor:view.topAnchor],
        [primary.bottomAnchor constraintEqualToAnchor:self.banner.topAnchor],
        [self.banner.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.banner.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [self.banner.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        self.bannerHeight,
        [message.centerXAnchor constraintEqualToAnchor:self.banner.centerXAnchor],
        [message.bottomAnchor constraintEqualToAnchor:self.banner.safeAreaLayoutGuide.bottomAnchor constant:-4],
        [npb.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [npb.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [npb.bottomAnchor constraintEqualToAnchor:self.tabs.compactTabBarHeightLayoutGuide.topAnchor],
        [npb.heightAnchor constraintEqualToConstant:64],
        // CompactNowPlayingViewController: the content 8 pt above its own bottom (0x105345190).
        [content.view.leadingAnchor constraintEqualToAnchor:npb.leadingAnchor],
        [content.view.trailingAnchor constraintEqualToAnchor:npb.trailingAnchor],
        [content.view.topAnchor constraintEqualToAnchor:npb.topAnchor],
        [content.view.bottomAnchor constraintEqualToAnchor:npb.bottomAnchor constant:-8],
    ]];

    // The now playing bar's share of the pages' inset, which Spotify adds on its own path; here a
    // stand-in on the page, so the list's end shows where Spotify thinks the bars begin.
    UIViewController *page = self.tabs.page;
    UIEdgeInsets inset = page.additionalSafeAreaInsets;
    inset.bottom += 64;
    page.additionalSafeAreaInsets = inset;
}

- (CGFloat)bannerTarget {
    return 22 + self.view.safeAreaInsets.bottom;
}

- (void)setBanner:(BOOL)shown animated:(BOOL)animated {
    self.bannerHeight.constant = shown ? [self bannerTarget] : 0;
    if (!animated) {
        [self.view layoutIfNeeded];
        return;
    }
    [UIView animateWithDuration:0.35 animations:^{ [self.view layoutIfNeeded]; }];
}

@end

#pragma mark - what the harness measures

extern CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius);

static UIView *platterIn(UIView *root) {
    // UIKit._UITabBarItemPlatterView on iOS 27; BarTransition.x looks for the same suffix.
    if ([NSStringFromClass(root.class) hasSuffix:@"PlatterView"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = platterIn(sub);
        if (found) return found;
    }
    return nil;
}

static UITabBar *systemBarIn(UIView *root) {
    if ([root isKindOfClass:UITabBar.class]) return (UITabBar *)root;
    for (UIView *sub in root.subviews) {
        UITabBar *found = systemBarIn(sub);
        if (found) return found;
    }
    return nil;
}

static UIView *identifiedView(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = identifiedView(child, identifier);
        if (found) return found;
    }
    return nil;
}

static void report(SGHarnessChrome *chrome, NSString *moment) {
    UIWindow *window = chrome.view.window;
    UIView *stock = chrome.tabs.bar;
    UITabBar *system = systemBarIn(stock);
    UIView *platter = platterIn(system);
    CGRect stockFrame = [stock convertRect:stock.bounds toView:window];
    CGRect systemFrame = system ? [system convertRect:system.bounds toView:window] : CGRectNull;
    CGRect platterFrame = platter ? [platter convertRect:platter.bounds toView:window] : CGRectNull;
    CGRect card = SGRNowPlayingCardFrameIn(window, NULL);
    CGRect banner = [chrome.banner convertRect:chrome.banner.bounds toView:window];
    UIView *play = identifiedView(chrome.npb, @"harness.miniplayer-play");
    NSCAssert(play != nil, @"Miniplayer play control must exist");
    CGRect playFrame = [play convertRect:play.bounds toView:window];
    NSCAssert(CGRectContainsRect(card, playFrame), @"Miniplayer play control must remain in the card");
    CGPoint center = CGPointMake(CGRectGetMidX(playFrame), CGRectGetMidY(playFrame));
    UIView *playHit = [window hitTest:center withEvent:nil];
    NSCAssert(playHit == play || [playHit isDescendantOfView:play], @"Miniplayer play button must receive touches");
    NSLog(@"[harness] PASS miniplayer play target %@", NSStringFromCGRect(playFrame));
    UITableView *list = chrome.tabs.page.tableView;
    CGFloat listEnd = CGRectGetMaxY([list convertRect:list.bounds toView:window]) - list.adjustedContentInset.bottom;
    CGRect rail = SGRVerticalBarFrameIn(window, SGRVerticalBarExtent);
    UIEdgeInsets expectedNavigation = UIEdgeInsetsMake(3, 4, CGRectIsNull(rail) ? 49 : 0, 5);
    NSCAssert(UIEdgeInsetsEqualToEdgeInsets(chrome.tabs.navigation.additionalSafeAreaInsets, expectedNavigation),
              @"Only the navigation wrapper's exact 49pt tab-row inset may be removed in vertical mode");
    NSCAssert(chrome.tabs.page.additionalSafeAreaInsets.bottom == 64,
              @"The independent miniplayer/page inset must remain unchanged");
    NSLog(@"[harness] PASS separate navigation %@ and page %@ insets", NSStringFromUIEdgeInsets(chrome.tabs.navigation.additionalSafeAreaInsets), NSStringFromUIEdgeInsets(chrome.tabs.page.additionalSafeAreaInsets));
    if (!CGRectIsNull(rail)) {
        UIView *railView = nil;
        for (UIView *child in chrome.tabs.view.subviews)
            if ([child.accessibilityIdentifier isEqualToString:@"spoti.vertical-navigation"]) railView = child;
        NSCAssert(railView != nil, @"Vertical mode must have the navigation rail");
        CGRect actual = [railView convertRect:railView.bounds toView:window];
        NSCAssert(CGRectEqualToRect(actual, rail), @"Rail must match the system layout region");
        UIView *group = railView.subviews.firstObject;
        NSCAssert([group.accessibilityIdentifier isEqualToString:@"spoti.vertical-navigation.group"], @"One compact group must own the glass");
        NSCAssert(fabs(CGRectGetMaxY(group.frame) - CGRectGetHeight(railView.bounds)) < 0.5, @"Group must align to the region bottom");
        BOOL hideLabels = SGHidden(SGRKeyNavbarHideLabels);
        CGFloat rowHeight = SGRVerticalBarNavigationRowHeight(hideLabels);
        UITabBar *railBar = [railView valueForKey:@"bar"];
        NSCAssert(railBar.items.count == 4, @"The rail must retain all four default tabs");
        CGFloat groupHeight = MIN(rail.size.height - SGRVerticalBarTopReservation(rail.size.height), railBar.items.count * (rowHeight + 2) + 2);
        NSCAssert(fabs(CGRectGetHeight(group.frame) - groupHeight) < 0.5, @"The group must fit the composed tabs");
        UIScrollView *scroll = nil;
        for (UIView *child in group.subviews) if ([child isKindOfClass:UIScrollView.class]) scroll = (UIScrollView *)child;
        NSCAssert(scroll != nil, @"Group must contain scrolling controls");
        NSUInteger count = 0;
        for (UIView *button in scroll.subviews) {
            if (![button isKindOfClass:UIButton.class]) continue;
            count++;
            UIButton *control = (UIButton *)button;
            NSCAssert(hideLabels ? control.configuration.attributedTitle.length == 0 : control.configuration.attributedTitle.length > 0,
                      @"Vertical controls must follow the Hide labels preference");
            NSCAssert(control.accessibilityLabel.length > 0, @"Icon-only tabs must retain accessible names");
            if ([control.accessibilityLabel isEqualToString:@"Home"])
                NSCAssert(control.gestureRecognizers.count > 0, @"Home must retain its hold gesture");
            NSCAssert(fabs(button.bounds.size.width - 48) < 0.5 && fabs(button.bounds.size.height - rowHeight) < 0.5,
                      @"Vertical controls must retain 48pt-wide hit targets");
            NSCAssert(CGRectContainsRect(scroll.bounds, button.frame), @"Default tabs must fit within the system rail");
            CGPoint point = [button convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) toView:window];
            UIView *hit = [window hitTest:point withEvent:nil];
            NSCAssert(hit == button || [hit isDescendantOfView:button], @"Rail button must receive touches outside stock bar");
        }
        NSCAssert(count == 4, @"The default Home, Search, Library and Create tabs must remain present");
        NSCAssert(CGRectGetMaxX(card) <= CGRectGetMinX(rail), @"Miniplayer must not extend under rail");
        NSCAssert(fabs(CGRectGetMaxY(card) + 8 - CGRectGetMinY(stockFrame)) < 1, @"Miniplayer must sit above remaining bottom safe area");
        NSLog(@"[harness] PASS vertical rail region, one bottom-aligned glass pill, accessible targets honoring label preferences, miniplayer separation and bottom alignment");
    } else {
        NSCAssert(system != nil, @"Normal phone must retain native bottom tab bar");
        NSCAssert(system.items.count == 4, @"Normal phone must preserve all default tabs");
        NSLog(@"[harness] PASS normal bottom bar retained");
    }
    NSLog(@"[harness] vertical-region %@ side-insets %@ container-insets %@", NSStringFromCGRect(rail),
          NSStringFromUIEdgeInsets(SGRVerticalBarContentInsets(window, SGRVerticalBarExtent)), NSStringFromUIEdgeInsets(chrome.tabs.additionalSafeAreaInsets));
    NSLog(@"[harness] %@ screen %.0fx%.0f safe-bottom %.0f | banner %@ | stock bar %@ | system bar %@ | platter %@ | card %@ | "
          @"gap card-to-platter %.1f | container extra inset %.0f | list ends at %.0f (card top %.0f)",
          moment, window.bounds.size.width, window.bounds.size.height, window.safeAreaInsets.bottom,
          NSStringFromCGRect(banner), NSStringFromCGRect(stockFrame), NSStringFromCGRect(systemFrame), NSStringFromCGRect(platterFrame),
          NSStringFromCGRect(card), CGRectGetMinY(platterFrame) - CGRectGetMaxY(card), chrome.tabs.additionalSafeAreaInsets.bottom,
          listEnd, CGRectGetMinY(card));
}

// Focused reservation regression, using the production rail and actual composed custom tabs.
@interface UIView (HarnessRailSync)
- (void)sync;
@end
static void reservationChecks(SGHarnessChrome *chrome) {
    UIWindow *window = chrome.view.window;
    if (CGRectIsNull(SGRVerticalBarFrameIn(window, SGRVerticalBarExtent))) return;
    UIView *rail = identifiedView(chrome.tabs.view, @"spoti.vertical-navigation");
    UITabBar *system = nil;
    CGRect original = rail.frame;
    CGFloat rowHeight = SGRVerticalBarNavigationRowHeight(SGHidden(SGRKeyNavbarHideLabels));
    NSArray *saved = SGRNavbarLayout();
    NSMutableArray *many = [NSMutableArray array];
    for (NSUInteger i = 0; i < 12; i++)
        [many addObject:@{SGRNavbarID: [NSString stringWithFormat:@"fixture%lu", (unsigned long)i],
            SGRNavbarTitle: [NSString stringWithFormat:@"Custom %lu", (unsigned long)i],
            SGRNavbarURI: @"spotify:collection", SGRNavbarIcon: @"heart"}];
    SGRSetNavbarLayout(many);
    SGRComposeTabBar(chrome.tabs.bar);
    [chrome.tabs.bar setNeedsLayout];
    [chrome.tabs.bar layoutIfNeeded];
    system = [rail valueForKey:@"bar"];
    NSCAssert(system.items.count == 16, @"Four default and twelve custom tabs must remain present");
    system.selectedItem = system.items.lastObject;
    for (NSNumber *height in @[@470, @220, @164, @112, @80, @470]) {
        rail.frame = CGRectMake(original.origin.x, original.origin.y, original.size.width, height.doubleValue);
        [rail sync];
        UIView *group = [rail valueForKey:@"group"];
        UIScrollView *scroll = [rail valueForKey:@"scroll"];
        NSArray<UIButton *> *buttons = [rail valueForKey:@"buttons"];
        CGFloat reserve = SGRVerticalBarTopReservation(height.doubleValue);
        NSCAssert(group.frame.origin.y >= reserve && group.bounds.size.height >= rowHeight + 4,
                  @"Short rail must keep a complete nav row below reserved top controls");
        NSCAssert([rail pointInside:CGPointMake(26, reserve - 1) withEvent:nil] == NO,
                  @"Rail must not intercept Back/menu reservation");
        if (reserve >= 112) NSCAssert(group.frame.origin.y >= 104 + 8, @"Menu bottom must keep an 8pt gap from tabs");
        for (UIButton *button in buttons) {
            CGFloat offset = MIN(MAX(0, button.frame.origin.y - 2), MAX(0, scroll.contentSize.height - scroll.bounds.size.height));
            scroll.contentOffset = CGPointMake(0, offset);
            NSCAssert(CGRectContainsRect(scroll.bounds, button.frame), @"Every custom tab must scroll fully into view");
            NSCAssert(button.bounds.size.width == 48 && button.bounds.size.height == rowHeight, @"Custom tab keeps its full labeled or icon-only target");
            CGPoint samples[] = {{24, rowHeight / 2}, {4, 4}, {44, rowHeight - 4}};
            for (NSUInteger i = 0; i < 3; i++) {
                CGPoint point = [button convertPoint:samples[i] toView:window];
                UIView *hit = [window hitTest:point withEvent:nil];
                NSCAssert(hit == button || [hit isDescendantOfView:button], @"Every scrolled custom tab must receive window hits");
            }
        }
        NSCAssert((buttons.lastObject.accessibilityTraits & UIAccessibilityTraitSelected) != 0,
                  @"Selection must survive shrinking and expanding the rail");
        NSLog(@"[harness] PASS reserved rail height %.0f, group %@, %lu tabs reachable, selected last", height.doubleValue,
              NSStringFromCGRect(group.frame), (unsigned long)buttons.count);
    }
    SGRSetNavbarLayout(saved);
    SGRComposeTabBar(chrome.tabs.bar);
    [chrome.tabs.bar setNeedsLayout];
    [chrome.tabs.bar layoutIfNeeded];
    rail.frame = original;
    [rail sync];
    UIScrollView *scroll = [rail valueForKey:@"scroll"];
    [scroll layoutIfNeeded];
    NSCAssert(scroll.contentOffset.y == 0, @"Removing custom tabs must restore the default scroll offset");
    UIView *group = [rail valueForKey:@"group"];
    NSCAssert(fabs(group.frame.size.height - (4 * (rowHeight + 2) + 2)) < 0.5, @"Default four-tab geometry must return after expansion");
    NSLog(@"[harness] PASS reservation restored default geometry and scroll offset");
}

#pragma mark - the app

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyNavbar];
    const char *labels = getenv("HARNESS_HIDE_LABELS");
    [NSUserDefaults.standardUserDefaults setBool:labels && labels[0] == '1' forKey:SGRKeyNavbarHideLabels];
}

@interface SGHarnessApp : UIResponder <UIApplicationDelegate>
@end
@implementation SGHarnessApp
@end

@interface SGHarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessScene

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if ([NSProcessInfo.processInfo.arguments containsObject:@"reservation"]) SGRSetNavbarLayout(@[]);
    SGHarnessChrome *chrome = [SGHarnessChrome new];
    self.window.rootViewController = chrome;
    [self.window makeKeyAndVisible];

    // What happens, from the launch argument: `none` no message bar, `shown` one sliding in at 1.5 s,
    // `away` one there from the start sliding away at 1.5 s, `cycle` in at 1.5 s and out at 4.5 s.
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSString *mode = args.count > 1 ? args[1] : @"none";
    if ([mode isEqualToString:@"away"]) [chrome setBanner:YES animated:NO];
    after(0.5, ^{
        UITableView *list = chrome.tabs.page.tableView;
        [list scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:29 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        report(chrome, @"start");
    });
    if ([mode isEqualToString:@"shown"] || [mode isEqualToString:@"cycle"]) after(1.5, ^{ [chrome setBanner:YES animated:YES]; });
    if ([mode isEqualToString:@"away"]) after(1.5, ^{ [chrome setBanner:NO animated:YES]; });
    if ([mode isEqualToString:@"cycle"]) after(4.5, ^{ [chrome setBanner:NO animated:YES]; });
    after(7, ^{
        SPNavigationController *navigation = chrome.tabs.navigation;
        // A caller replacing the tab contribution must retain its full, unrelated inset.
        navigation.additionalSafeAreaInsets = UIEdgeInsetsMake(7, 8, 61, 9);
        [chrome.tabs.view setNeedsLayout];
        [chrome.tabs.view layoutIfNeeded];
        NSCAssert(UIEdgeInsetsEqualToEdgeInsets(navigation.additionalSafeAreaInsets, UIEdgeInsetsMake(7, 8, 61, 9)), @"Non-49pt caller insets must remain intact");
        // Moving the same controller outside the tab container restores ordinary semantics.
        [navigation willMoveToParentViewController:nil];
        [navigation removeFromParentViewController];
        navigation.additionalSafeAreaInsets = UIEdgeInsetsMake(3, 4, 49, 5);
        NSCAssert(navigation.additionalSafeAreaInsets.bottom == 49, @"Navigation outside tabs must retain its 49pt inset");
        [chrome.tabs addChildViewController:navigation];
        [navigation didMoveToParentViewController:chrome.tabs];
        [chrome.tabs.view setNeedsLayout];
        [chrome.tabs.view layoutIfNeeded];
        report(chrome, @"navigation-restored");
        NSLog(@"[harness] PASS caller inset replacement and navigation ownership restoration");
        NSArray *saved = SGRNavbarLayout();
        NSArray *custom = @[@{SGRNavbarID: @"Search", SGRNavbarHidden: @YES},
            @{SGRNavbarID: @"fixture", SGRNavbarTitle: @"Favorites", SGRNavbarURI: @"spotify:collection", SGRNavbarIcon: @"heart"},
            @{SGRNavbarID: @"Create", SGRNavbarHidden: @NO}];
        SGRSetNavbarLayout(custom);
        SGRComposeTabBar(chrome.tabs.bar);
        BOOL foundCustom = NO;
        for (UIView *source in SGRowIn(chrome.tabs.bar).arrangedSubviews) {
            __block NSString *title = nil;
            SGForEachView(source, ^(UIView *view) { if ([view isKindOfClass:UILabel.class]) title = ((UILabel *)view).text; });
            if ([title isEqualToString:@"Create"]) NSCAssert(!source.hidden, @"The visible Create preference must survive");
            if ([title isEqualToString:@"Search"]) NSCAssert(source.hidden, @"Existing hidden-tab preference must survive");
            if ([title isEqualToString:@"Favorites"]) foundCustom = !source.hidden;
        }
        NSCAssert(foundCustom && [SGRNavbarLayout() isEqualToArray:custom], @"Custom tab and saved composition must survive untouched");
        SGRSetNavbarLayout(saved);
        [chrome.tabs.bar setNeedsLayout];
        [chrome.tabs.bar layoutIfNeeded];
        NSLog(@"[harness] PASS visible Create action, custom tabs and hidden preferences preserved");
    });
    if ([mode isEqualToString:@"reservation"]) after(8.5, ^{ reservationChecks(chrome); });
    // Half way through the slide, what the screen shows (the presentation layers).
    if (![mode isEqualToString:@"none"]) after(1.5 + 0.17, ^{
        CALayer *stock = chrome.tabs.bar.layer.presentationLayer, *npb = chrome.npb.layer.presentationLayer, *banner = chrome.banner.layer.presentationLayer;
        NSLog(@"[harness] mid-slide presented: banner top %.1f, tab bar top %.1f, now playing bar bottom %.1f",
              [banner convertPoint:CGPointZero toLayer:self.window.layer.presentationLayer].y,
              [stock convertPoint:CGPointZero toLayer:self.window.layer.presentationLayer].y,
              [npb convertPoint:CGPointMake(0, npb.bounds.size.height) toLayer:self.window.layer.presentationLayer].y);
    });
    if ([mode isEqualToString:@"cycle"]) after(6, ^{ report(chrome, @"restored"); });
    after(2.5, ^{
        UITableView *list = chrome.tabs.page.tableView;
        [list scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:29 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        report(chrome, mode);
    });
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessApp.class)); }
}
