// Tab bar harness: TabBar.x and NowPlayingBar.x run for real on a mock of the bottom of Spotify's main
// screen, laid out with the constraints 9.1.78 makes (see the README for the addresses), under Spotify's
// class names, with Spotify's message bar (Offline, Private Session) able to come in under the tab bar.
#import <UIKit/UIKit.h>

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
// Spotify's bar opens the player on a tap; here the tap is logged, for the mini player's hand-over.
- (void)openPlayer {
    NSLog(@"[harness] Spotify's bar was tapped: the player would open");
}
- (void)loadView {
    self.view = [UIView new];
    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPlayer)]];
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
    image.image = [[UIImage systemImageNamed:@"music.note"] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    image.contentMode = UIViewContentModeCenter;
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
    play.frame = CGRectMake(330, 12, 32, 32);
    play.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [card addSubview:play];
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

// NavigationUI_TabBarImpl.TabBarContainerImpl in a compact width, as its viewDidLoad (0x1008409a8) and
// its size class pass (0x106fabb7c) lay it out: a guide from 49 pt above the safe area's bottom to the
// view's bottom, a stack as tall as the guide on the view's bottom, the tab bar as tall as the stack.
// The page gets 49 pt more safe area on top of what the container has (0x10707bde4).
@interface _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl : UIViewController
@property (nonatomic, strong) UILayoutGuide *compactGuide;
@property (nonatomic, strong) UIView *bar;
@end
@implementation _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (UILayoutGuide *)compactTabBarHeightLayoutGuide { return self.compactGuide; }
- (UIView *)tabBarView { return self.bar; }
- (void)setSelectedViewController:(UIViewController *)controller {}

// Spotify lights the tab it switches to and dims the rest; Create only opens its menu.
- (void)tabTapped:(UITapGestureRecognizer *)tap {
    UIView *tapped = tap.view;
    UILabel *label = tapped.subviews.lastObject;
    NSLog(@"[harness] Spotify's %@ tab was tapped", label.text);
    if ([tapped isKindOfClass:_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView.class]) return;
    for (UIView *item in ((UIStackView *)tapped.superview).arrangedSubviews) {
        ((UILabel *)item.subviews.lastObject).textColor = item == tapped ? UIColor.whiteColor : [UIColor colorWithWhite:0xB3 / 255.0 alpha:1];
        [item setNeedsLayout];
    }
}

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

    SGHarnessPage *page = [SGHarnessPage new];
    [self addChildViewController:page];
    page.view.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:page.view];
    [page didMoveToParentViewController:self];
    page.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, 49, 0);

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
    NSMutableArray<UIView *> *items = [NSMutableArray arrayWithObjects:
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Home", @"house.fill", YES),
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Search", @"magnifyingglass", NO),
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Your Library", @"books.vertical", NO), nil];
    // `library-last`: no Create, so Your Library ends the row.
    if (![NSProcessInfo.processInfo.arguments containsObject:@"library-last"])
        [items addObject:item(_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView.class, @"Create", @"plus", NO)];
    for (UIView *tab in items) [tab addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tabTapped:)]];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:items];
    row.distribution = UIStackViewDistributionFillEqually;
    row.accessibilityIdentifier = @"tabs-container-view-identifier";
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [compact addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [page.view.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [page.view.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [page.view.topAnchor constraintEqualToAnchor:view.topAnchor],
        [page.view.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
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
    UIViewController *page = self.tabs.childViewControllers.firstObject;
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
    UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
    CGFloat listEnd = CGRectGetMaxY([list convertRect:list.bounds toView:window]) - list.adjustedContentInset.bottom;
    NSLog(@"[harness] %@ screen %.0fx%.0f safe-bottom %.0f | banner %@ | stock bar %@ | system bar %@ | platter %@ | card %@ | "
          @"gap card-to-platter %.1f | container extra inset %.0f | list ends at %.0f (card top %.0f)",
          moment, window.bounds.size.width, window.bounds.size.height, window.safeAreaInsets.bottom,
          NSStringFromCGRect(banner), NSStringFromCGRect(stockFrame), NSStringFromCGRect(systemFrame), NSStringFromCGRect(platterFrame),
          NSStringFromCGRect(card), CGRectGetMinY(platterFrame) - CGRectGetMaxY(card), chrome.tabs.additionalSafeAreaInsets.bottom,
          listEnd, CGRectGetMinY(card));
}

#pragma mark - the app

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
    // `inline`: the mini player in the tab bar (SGRKeyInlinePlayer).
    BOOL inlinePlayer = [NSProcessInfo.processInfo.arguments containsObject:@"inline"];
    [NSUserDefaults.standardUserDefaults setBool:inlinePlayer forKey:@"spotifyglass.redesign.inlinePlayer"];
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
    SGHarnessChrome *chrome = [SGHarnessChrome new];
    self.window.rootViewController = chrome;
    [self.window makeKeyAndVisible];

    // What happens, from the launch argument: `none` no message bar, `shown` one sliding in at 1.5 s,
    // `away` one there from the start sliding away at 1.5 s, `cycle` in at 1.5 s and out at 4.5 s.
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSString *mode = args.count > 1 ? args[1] : @"none";
    if ([mode isEqualToString:@"away"]) [chrome setBanner:YES animated:NO];
    // What a touch on the mini player's middle and on its button lands on, up to the window.
    if ([mode isEqualToString:@"inline"]) after(3, ^{
        for (NSValue *value in @[[NSValue valueWithCGPoint:CGPointMake(200, 759)], [NSValue valueWithCGPoint:CGPointMake(352, 759)]]) {
            NSMutableString *chain = [NSMutableString string];
            for (UIView *v = [self.window hitTest:value.CGPointValue withEvent:nil]; v; v = v.superview) [chain appendFormat:@" < %@", NSStringFromClass(v.class)];
            NSLog(@"[harness] touch at %@ lands on%@", NSStringFromCGPoint(value.CGPointValue), chain);
        }
    });
    after(0.5, ^{
        UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
        [list scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:29 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        report(chrome, @"start");
    });
    if ([mode isEqualToString:@"shown"] || [mode isEqualToString:@"cycle"]) after(1.5, ^{ [chrome setBanner:YES animated:YES]; });
    if ([mode isEqualToString:@"away"]) after(1.5, ^{ [chrome setBanner:NO animated:YES]; });
    if ([mode isEqualToString:@"cycle"]) after(4.5, ^{ [chrome setBanner:NO animated:YES]; });
    // Half way through the slide, what the screen shows (the presentation layers).
    if (![mode isEqualToString:@"none"]) after(1.5 + 0.17, ^{
        CALayer *stock = chrome.tabs.bar.layer.presentationLayer, *npb = chrome.npb.layer.presentationLayer, *banner = chrome.banner.layer.presentationLayer;
        NSLog(@"[harness] mid-slide presented: banner top %.1f, tab bar top %.1f, now playing bar bottom %.1f",
              [banner convertPoint:CGPointZero toLayer:self.window.layer.presentationLayer].y,
              [stock convertPoint:CGPointZero toLayer:self.window.layer.presentationLayer].y,
              [npb convertPoint:CGPointMake(0, npb.bounds.size.height) toLayer:self.window.layer.presentationLayer].y);
    });
    after(2.5, ^{
        UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
        [list scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:29 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        report(chrome, mode);
    });
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessApp.class)); }
}
