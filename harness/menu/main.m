// Spotify's context menu sheet mocked under its class name, presented from a now playing controller,
// so SpeedPitchMenu.x's hook adds Speed and pitch the way it would on the phone.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/MenuHarness.app
//     xcrun simctl launch --console-pty <udid> com.vojta.menuharness [footer] [nospeed] [loading] [stuck] [open] [follow]
//
// The plain run opens the menu at 1 s, opens the block at 3 s, moves both sliders at 5 s and closes the
// block at 7 s. `loading` builds the sheet the way Spotify's is (the ivars of ContextMenuViewController in
// 9.1.78: a header, a content container holding a ContextMenuTableView whose height follows its
// contentSize by KVO, a loading spinner) and hands it its rows only 4 s after it is up, as Spotify does
// once its item factories have answered; `stuck` never hands them over. `open` opens the block on a first
// menu, closes it, and brings up a second one with the block open, as it stays for the session. `follow`
// opens the block, sets 1.25x and turns pitch following speed on and off again, reporting the block and
// the sheet each time and drawing the screen into the app's tmp. Every frame of the first second the block is on screen
// is checked for a colour of the system tint on anything it draws, and what the sheet shows is reported.
#import <UIKit/UIKit.h>

#pragma mark - what SpeedPitchMenu.x calls

static double sg_speed = 1;
static float sg_pitch;
static BOOL sg_speedAllowed = YES, sg_follows;
void SGPlayFeedback(NSInteger feedback) { NSLog(@"[harness] feedback %ld", (long)feedback); }
void SGPrepareFeedback(NSInteger feedback) {}
double SGPlayerSpeed(void) { return sg_speed; }
BOOL SGPlayerSpeedAllowed(void) { return sg_speedAllowed; }
void SGSetPlayerSpeed(double speed) { sg_speed = speed; NSLog(@"[harness] speed %.2f", speed); }
float SGPlayerPitch(void) { return sg_pitch; }
void SGSetPlayerPitch(float semitones) { sg_pitch = semitones; NSLog(@"[harness] pitch %.0f", semitones); }
BOOL SGPlayerPitchAvailable(void) { return YES; }
BOOL SGPlayerPitchFollowsSpeed(void) { return sg_follows && sg_speedAllowed; }
void SGSetPlayerPitchFollowsSpeed(BOOL follows) {
    sg_follows = follows;
    if (follows) sg_pitch = 0;
    NSLog(@"[harness] pitch follows speed %d", follows);
}

static BOOL argument(NSString *name) {
    return [NSProcessInfo.processInfo.arguments containsObject:name];
}

static NSArray<NSArray<NSString *> *> *spotifyRows(void) {
    return @[@[@"plus.circle", @"Add to playlist"], @[@"music.note.list", @"Add to queue"], @[@"person", @"Go to artist"],
             @[@"square.stack", @"Go to album"], @[@"square.and.arrow.up", @"Share"], @[@"moon", @"Sleep timer"],
             @[@"dot.radiowaves.left.and.right", @"Go to song radio"], @[@"info.circle", @"View credits"]];
}

#pragma mark - Spotify's sheet

// ContextMenu_InternalImpl.(anon).ContextMenuTableView: sized to its content, its intrinsic size is its
// contentSize (it overrides intrinsicContentSize, layoutSubviews and reloadData in 9.1.78).
@interface SGHarnessMenuTable : UITableView
@end

@implementation SGHarnessMenuTable
- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, self.contentSize.height);
}
- (void)reloadData {
    [super reloadData];
    [self invalidateIntrinsicContentSize];
}
@end

@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController <UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSLayoutConstraint *contentHeight;
@property (nonatomic) BOOL loaded;
@end

@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    BOOL loading = argument(@"loading") || argument(@"stuck");
    self.loaded = !loading;
    self.table = [[(loading ? SGHarnessMenuTable.class : UITableView.class) alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.rowHeight = 56;
    self.table.dataSource = self;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
    if (argument(@"footer")) {
        UILabel *heading = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 80)];
        heading.text = @"   Spotify's heading";
        heading.textColor = UIColor.whiteColor;
        self.table.tableHeaderView = heading;
    }
    if (!loading) {
        self.table.frame = self.view.bounds;
        self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.table];
        return;
    }

    // Spotify's layout: its own header (the track), a divider, then the content container with the table
    // in it, the spinner over the container while the rows are not in.
    UILabel *header = [UILabel new];
    header.text = @"   Blinding Lights · The Weeknd";
    header.textColor = UIColor.whiteColor;
    UIView *container = [UIView new];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = UIColor.whiteColor;
    for (UIView *view in @[header, container, self.table, self.spinner]) view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];
    [self.view addSubview:container];
    [container addSubview:self.table];
    [container addSubview:self.spinner];
    self.contentHeight = [self.table.heightAnchor constraintEqualToConstant:0];
    self.contentHeight.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:16],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:56],
        [container.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [container.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [container.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor],
        [container.heightAnchor constraintGreaterThanOrEqualToConstant:120],
        [self.table.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.table.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor],
        self.contentHeight,
        [self.spinner.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    ]];
    [self.spinner startAnimating];
    // ContextMenuTableViewCoordinator.tableViewContentSizeObservation
    [self.table addObserver:self forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)dealloc {
    if (self.spinner) [self.table removeObserver:self forKeyPath:@"contentSize"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    self.contentHeight.constant = self.table.contentSize.height;
}

// What the model publisher does once the item factories have answered.
- (void)takeRows {
    self.loaded = YES;
    [self.spinner stopAnimating];
    self.spinner.hidden = YES;
    [self.table reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.loaded ? spotifyRows().count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = spotifyRows()[indexPath.row][1];
    content.textProperties.color = UIColor.whiteColor;
    content.image = [UIImage systemImageNamed:spotifyRows()[indexPath.row][0]];
    content.imageProperties.tintColor = [UIColor colorWithWhite:0.7 alpha:1];
    cell.contentConfiguration = content;
    cell.backgroundColor = UIColor.clearColor;
    return cell;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

@end

#pragma mark - the player

@interface NowPlayingHarnessViewController : UIViewController
@end

@implementation NowPlayingHarnessViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.25 green:0.1 blue:0.2 alpha:1];
}
@end

static UIView *findBlock(UIView *root) {
    if ([NSStringFromClass(root.class) isEqualToString:@"SGSpeedPitchView"]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = findBlock(child);
        if (found) return found;
    }
    return nil;
}

static NSArray<UISlider *> *sliders(UIView *root) {
    NSMutableArray *found = [NSMutableArray array];
    if ([root isKindOfClass:UISlider.class]) [found addObject:root];
    for (UIView *child in root.subviews) [found addObjectsFromArray:sliders(child)];
    return found;
}

#pragma mark - the tint check

// A colour is the system tint's when it resolves, in the view's own traits, to the system blue.
static BOOL isTint(UIColor *color, UIView *view) {
    if (!color) return NO;
    UIColor *resolved = [color resolvedColorWithTraitCollection:view.traitCollection];
    UIColor *blue = [UIColor.systemBlueColor resolvedColorWithTraitCollection:view.traitCollection];
    CGFloat r, g, b, a, br, bg, bb, ba;
    if (![resolved getRed:&r green:&g blue:&b alpha:&a] || ![blue getRed:&br green:&bg blue:&bb alpha:&ba]) return NO;
    return a > 0.05 && fabs(r - br) < 0.08 && fabs(g - bg) < 0.08 && fabs(b - bb) < 0.08;
}

// Everything the block draws in a colour of its own: labels' text, buttons' titles, and whatever takes the
// tint (templated glyphs, sliders' thumbs and tracks).
static void tintedViews(UIView *view, NSMutableArray<NSString *> *out) {
    if (view.isHidden || view.alpha < 0.01) return;
    NSString *name = NSStringFromClass(view.class);
    if ([view isKindOfClass:UILabel.class] && isTint(((UILabel *)view).textColor, view)) [out addObject:[name stringByAppendingFormat:@" text \"%@\"", ((UILabel *)view).text]];
    if ([view isKindOfClass:UIImageView.class]) {
        UIImage *image = ((UIImageView *)view).image;
        // Drawn in the tint when templated, or left automatic on a symbol; a bitmap left automatic keeps
        // its own colours (the sliders' end images).
        BOOL templated = image.renderingMode == UIImageRenderingModeAlwaysTemplate
            || (image.renderingMode == UIImageRenderingModeAutomatic && image.isSymbolImage);
        if (templated && isTint(view.tintColor, view)) [out addObject:[name stringByAppendingString:@" glyph"]];
    }
    if ([view isKindOfClass:UIButton.class] && isTint([(UIButton *)view titleColorForState:((UIButton *)view).state], view)) [out addObject:[name stringByAppendingString:@" title"]];
    if ([view isKindOfClass:UISlider.class]) {
        UISlider *slider = (UISlider *)view;
        if (isTint(slider.minimumTrackTintColor ?: slider.tintColor, view)) [out addObject:@"UISlider track"];
    }
    if (isTint(view.backgroundColor, view)) [out addObject:[name stringByAppendingString:@" background"]];
    for (UIView *child in view.subviews) tintedViews(child, out);
}

@interface SGHarnessFrameWatch : NSObject
@property (nonatomic, weak) UIView *root;
@property (nonatomic) NSInteger frames, tinted;
@property (nonatomic) CFTimeInterval firstSeen;
@end

@implementation SGHarnessFrameWatch
- (void)tick:(CADisplayLink *)link {
    UIView *block = findBlock(self.root);
    if (!block.window) return;
    if (!self.firstSeen) self.firstSeen = link.timestamp;
    self.frames++;
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    tintedViews(block, found);
    if (found.count) {
        self.tinted++;
        NSLog(@"[harness] %p frame %ld: system tint on %@", self, (long)self.frames, [found componentsJoinedByString:@", "]);
    }
    if (link.timestamp - self.firstSeen > 1) {
        [link invalidate];
        NSLog(@"[harness] %p tint check: %ld of the block's first %ld frames drew something in the system tint", self, (long)self.tinted, (long)self.frames);
    }
}
@end

static void report(_TtC24ContextMenu_InternalImpl25ContextMenuViewController *menu, NSString *when) {
    UITableView *table = menu.table;
    NSInteger cells = 0;
    for (UITableViewCell *cell in table.visibleCells) cells += CGRectIntersectsRect([cell convertRect:cell.bounds toView:menu.view], menu.view.bounds) ? 1 : 0;
    UIView *block = findBlock(menu.view);
    NSLog(@"[harness] %@: table %@ content %.0f, %ld of %ld rows on screen, spinner %@, block %@ in the %@",
          when, NSStringFromCGRect(table.frame), table.contentSize.height, (long)cells, (long)[table numberOfRowsInSection:0],
          menu.spinner ? (menu.spinner.isAnimating ? @"spinning" : @"stopped") : @"none",
          block ? NSStringFromCGRect([block convertRect:block.bounds toView:menu.view]) : @"missing",
          table.tableHeaderView == block ? @"header" : table.tableFooterView == block ? @"footer" : @"nowhere");
}

#pragma mark - the run

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

static void tapRow(UIViewController *menu) {
    UIControl *row = (UIControl *)findBlock(menu.view).subviews.firstObject;
    [row sendActionsForControlEvents:UIControlEventTouchUpInside];
}

static UISwitch *findSwitch(UIView *root) {
    if ([root isKindOfClass:UISwitch.class]) return (UISwitch *)root;
    for (UIView *child in root.subviews) {
        UISwitch *found = findSwitch(child);
        if (found) return found;
    }
    return nil;
}

// The block's parts that show: what each is and where, in the block.
static void describeBlock(UIView *block, NSString *when) {
    NSMutableArray<NSString *> *shown = [NSMutableArray array];
    UIView *panel = block.subviews.count > 1 ? block.subviews[1] : nil;
    for (UIView *view in panel.subviews) {
        if (view.alpha < 0.01) continue;
        CGRect frame = [view convertRect:view.bounds toView:block];
        if (CGRectGetMinY(frame) >= block.bounds.size.height) continue;
        NSString *what = [view isKindOfClass:UILabel.class] ? [NSString stringWithFormat:@"\"%@\"", ((UILabel *)view).text]
                       : [view isKindOfClass:UIButton.class] ? [NSString stringWithFormat:@"[%@]", [(UIButton *)view titleForState:UIControlStateNormal]]
                       : [view isKindOfClass:UISwitch.class] ? (((UISwitch *)view).on ? @"switch on" : @"switch off")
                       : [view isKindOfClass:UISlider.class] ? [NSString stringWithFormat:@"slider %.2f", ((UISlider *)view).value] : NSStringFromClass(view.class);
        [shown addObject:[NSString stringWithFormat:@"%@ at y %.0f", what, CGRectGetMinY(frame)]];
    }
    NSLog(@"[harness] %@: block %.0f tall showing %@", when, block.bounds.size.height, [shown componentsJoinedByString:@", "]);
}

static void drawScreen(UIWindow *window, NSString *name) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
    [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
    NSLog(@"[harness] drew %@", path);
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    sg_speedAllowed = !argument(@"nospeed");
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    NowPlayingHarnessViewController *player = [NowPlayingHarnessViewController new];
    self.window.rootViewController = player;
    [self.window makeKeyAndVisible];

    static SGHarnessFrameWatch *watch;
    __block _TtC24ContextMenu_InternalImpl25ContextMenuViewController *menu;
    BOOL loading = argument(@"loading"), stuck = argument(@"stuck");
    void (^present)(void) = ^{
        menu = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:menu];
        navigation.navigationBarHidden = YES;
        navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        watch = [SGHarnessFrameWatch new];
        watch.root = navigation.view;
        [[CADisplayLink displayLinkWithTarget:watch selector:@selector(tick:)] addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [player presentViewController:navigation animated:YES completion:nil];
    };
    if (argument(@"follow")) {
        after(1, present);
        after(3, ^{ tapRow(menu); });
        after(4.5, ^{
            describeBlock(findBlock(menu.view), @"opened");
            report(menu, @"opened");
            NSArray<UISlider *> *found = sliders(findBlock(menu.view));
            found[0].value = 1.25;
            [found[0] sendActionsForControlEvents:UIControlEventValueChanged];
            [found[0] sendActionsForControlEvents:UIControlEventTouchUpInside];
            found[1].value = 2;
            [found[1] sendActionsForControlEvents:UIControlEventValueChanged];
            [found[1] sendActionsForControlEvents:UIControlEventTouchUpInside];
        });
        after(5.5, ^{
            describeBlock(findBlock(menu.view), @"1.25x, +2 st");
            drawScreen(self.window, @"follow-off");
            UISwitch *toggle = findSwitch(findBlock(menu.view));
            toggle.on = YES;
            [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        });
        after(7, ^{
            describeBlock(findBlock(menu.view), @"pitch follows");
            report(menu, @"pitch follows");
            drawScreen(self.window, @"follow-on");
            tapRow(menu);
        });
        after(8.5, ^{
            report(menu, @"closed while following");
            drawScreen(self.window, @"follow-closed");
            tapRow(menu);
        });
        after(10, ^{
            UISwitch *toggle = findSwitch(findBlock(menu.view));
            toggle.on = NO;
            [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        });
        after(11.5, ^{
            describeBlock(findBlock(menu.view), @"no longer following");
            report(menu, @"no longer following");
        });
        return;
    }
    if (argument(@"open")) {
        // The block keeps whether it was open for the session: open it on a first menu, close that menu,
        // and watch a second one come up with the block already open.
        after(1, present);
        after(3, ^{ tapRow(menu); });
        after(4.5, ^{ [player dismissViewControllerAnimated:YES completion:nil]; });
        after(6, present);
        after(8, ^{ report(menu, @"reopened"); });
        return;
    }
    after(1, present);
    if (loading || stuck) {
        after(3, ^{ report(menu, @"loading"); });
        if (loading) after(5, ^{ [menu takeRows]; });
        after(6.5, ^{ report(menu, loading ? @"rows in" : @"still loading"); });
        if (stuck) return;
        after(7, ^{ tapRow(menu); });
        after(8.5, ^{ report(menu, @"block toggled"); });
        return;
    }
    after(3, ^{
        NSLog(@"[harness] block %@", findBlock(menu.view));
        tapRow(menu);
    });
    after(5, ^{
        NSArray<UISlider *> *found = sliders(findBlock(menu.view));
        found[0].value = 1.27;
        [found[0] sendActionsForControlEvents:UIControlEventValueChanged];
        [found[0] sendActionsForControlEvents:UIControlEventTouchUpInside];
        found[1].value = -3.2;
        [found[1] sendActionsForControlEvents:UIControlEventValueChanged];
        [found[1] sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    after(7, ^{ tapRow(menu); });
}

@end

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessApp.class));
    }
}
