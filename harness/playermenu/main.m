// The redesign's player menu (Redesigned/Player/PlayerMenu.x) run for real over a mock of Spotify's context
// menu sheet: a player with its ⋯ (id=Context menu), and the sheet presented from it the way Spotify nests
// it -- a container presented as a sheet, holding a navigation controller, holding a page, holding
// ContextMenu_InternalImpl.ContextMenuViewController under its own class name -- whose table rows are
// ListRow-like controls carrying the item's number as their accessibility identifier, as 9.1.78's do
// (trees/continuous/1.txt:648). The table has no didSelectRowAtIndexPath:, like Spotify's binder; a row
// fires through its control. Share (9) pushes a page onto the sheet, Lyrics (28) turns itself on in place,
// every other row dismisses the sheet, as Spotify's do. Speed and pitch are stubs that log.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/PlayerMenuHarness.app
//     xcrun simctl launch --console-pty <udid> com.vojta.playermenuharness [scenario] [loading|slow|stuck] [differ] [late]
//
// Every run taps the ⋯ at 1 s and reports at 2.2 s the system menu, as built (its groups and rows) and as
// on screen (its words top to bottom), and whether Spotify's sheet is out of sight. A pick calls the row's
// handler and closes the menu, in that order, or the other way round with `late`. Scenarios: hold (nothing
// more), tile (Add to playlist at 3 s), share (Share at 3 s: Spotify's page is pushed and its sheet shown),
// lyrics (Lyrics at 3 s: Spotify changes the row in place and its sheet is then taken away), speed (Speed and
// pitch at 3 s: the popover with the sliders), follow (as speed, then pitch following speed on at 4.5 s and
// off at 9 s: the popover folds away its pitch slider and back), outside (the menu closed at 3 s with nothing
// picked), pending (Add to playlist picked before Spotify's rows are in: fired once they are with `loading`,
// Spotify's sheet shown 4 s later with `stuck`). `loading` hands the sheet its rows 1.5 s after it is up,
// `slow` 7 s after; `stuck` never does. `differ` gives it another track's rows than the ones the run before
// kept, which the menu opens on, so the open menu has to move to these.
#import <UIKit/UIKit.h>

#pragma mark - what the hooks call and the harness does not build

static double sg_speed = 1;
static float sg_pitch;
void SGPlayFeedback(NSInteger feedback) {}
void SGPrepareFeedback(NSInteger feedback) {}
double SGPlayerSpeed(void) { return sg_speed; }
BOOL SGPlayerSpeedAllowed(void) { return YES; }
void SGSetPlayerSpeed(double speed) { sg_speed = speed; NSLog(@"[harness] speed %.2f", speed); }
float SGPlayerPitch(void) { return sg_pitch; }
void SGSetPlayerPitch(float semitones) { sg_pitch = semitones; NSLog(@"[harness] pitch %.0f", semitones); }
BOOL SGPlayerPitchAvailable(void) { return YES; }
static BOOL sg_follows;
BOOL SGPlayerPitchFollowsSpeed(void) { return sg_follows; }
void SGSetPlayerPitchFollowsSpeed(BOOL follows) {
    sg_follows = follows;
    if (follows) sg_pitch = 0;
    NSLog(@"[harness] pitch follows speed %d", follows);
}
UIColor *SGRAccentColor(void) { return nil; }

static BOOL argument(NSString *name) {
    return [NSProcessInfo.processInfo.arguments containsObject:name];
}

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

#pragma mark - Spotify's rows

// Spotify's order on the phone (trees/continuous/1.txt) for the numbers known, then rows whose numbers the
// menu does not know, standing in for the rest of the sheet below the fold.
static NSMutableArray<NSMutableArray<NSString *> *> *spotifyRows(void) {
    static NSMutableArray *rows;
    if (!rows) rows = [@[
        [@[@"9", @"square.and.arrow.up", @"Share"] mutableCopy],
        [@[@"28", @"captions.bubble", @"Lyrics • Off"] mutableCopy],
        [@[@"19", @"plus.circle", @"Add to playlist"] mutableCopy],
        [@[@"59", @"xmark.circle", @"Exclude track from your taste profile"] mutableCopy],
        [@[@"27", @"minus.circle", @"Remove from this playlist"] mutableCopy],
        [@[@"11", @"text.append", @"Add to Queue"] mutableCopy],
        [@[@"34", @"list.bullet", @"Go to Queue"] mutableCopy],
        [@[@"3", @"dot.radiowaves.left.and.right", @"Go to song radio"] mutableCopy],
        [@[@"4", @"opticaldisc", @"Go to album"] mutableCopy],
        [@[@"5", @"person", @"Go to artist"] mutableCopy],
        [@[@"41", @"info.circle", @"View song credits"] mutableCopy],
        [@[@"12", @"barcode", @"Show Spotify Code"] mutableCopy],
        [@[@"70", @"point.3.connected.trianglepath.dotted", @"Explore Song DNA"] mutableCopy],
        [@[@"66", @"ticket", @"Go to artist's concerts"] mutableCopy],
        [@[@"22", @"moon", @"Sleep timer"] mutableCopy],
    ] mutableCopy];
    // Another track's menu: not the rows the last run kept, so the card has to move to these.
    static BOOL differed;
    if (argument(@"differ") && !differed) {
        differed = YES;
        [rows removeObjectAtIndex:4];
        rows[1][2] = @"Lyrics • On";
    }
    return rows;
}

// Encore's ListRow: a control, the item's number as its identifier, a 24pt glyph and a label in it.
@interface SGHarnessListRow : UIControl
@property (nonatomic, strong) UIImageView *glyph;
@property (nonatomic, strong) UILabel *label;
@end

@implementation SGHarnessListRow
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glyph = [[UIImageView alloc] initWithFrame:CGRectMake(12, 16, 24, 24)];
    _glyph.tintColor = [UIColor colorWithWhite:0.7 alpha:1];
    _label = [[UILabel alloc] initWithFrame:CGRectMake(48, 0, 300, 56)];
    _label.textColor = UIColor.whiteColor;
    [self addSubview:_glyph];
    [self addSubview:_label];
    return self;
}
@end

@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController <UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic) BOOL loaded;
@end

@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    self.loaded = !argument(@"loading") && !argument(@"slow") && !argument(@"stuck");
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.rowHeight = 56;
    self.table.dataSource = self;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:self.table];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ((argument(@"loading") || argument(@"slow")) && !self.loaded) after(argument(@"slow") ? 7 : 1.5, ^{
        self.loaded = YES;
        [self.table reloadData];
        NSLog(@"[harness] the sheet has its rows");
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.loaded ? spotifyRows().count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    cell.backgroundColor = UIColor.clearColor;
    SGHarnessListRow *row = (SGHarnessListRow *)[cell.contentView viewWithTag:7];
    if (!row) {
        row = [[SGHarnessListRow alloc] initWithFrame:cell.contentView.bounds];
        row.tag = 7;
        row.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [row addTarget:self action:@selector(rowFired:) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:row];
    }
    NSArray<NSString *> *data = spotifyRows()[indexPath.row];
    row.accessibilityIdentifier = data[0];
    row.glyph.image = [UIImage systemImageNamed:data[1]];
    row.label.text = data[2];
    return cell;
}

- (void)rowFired:(SGHarnessListRow *)row {
    NSString *identifier = row.accessibilityIdentifier;
    NSLog(@"[harness] Spotify's row %@ \"%@\" fired", identifier, row.label.text);
    if ([identifier isEqualToString:@"9"]) {
        UIViewController *page = [UIViewController new];
        page.view.backgroundColor = [UIColor colorWithRed:0.1 green:0.2 blue:0.15 alpha:1];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, 300, 30)];
        label.text = @"Spotify's share page";
        label.textColor = UIColor.whiteColor;
        [page.view addSubview:label];
        [self.navigationController pushViewController:page animated:YES];
    } else if ([identifier isEqualToString:@"28"]) {
        for (NSMutableArray *data in spotifyRows()) {
            if ([data[0] isEqualToString:@"28"]) data[2] = @"Lyrics • On";
        }
        [self.table reloadData];
        [self.view setNeedsLayout];
    } else {
        UIViewController *top = self;
        while (top.parentViewController) top = top.parentViewController;
        [top dismissViewControllerAnimated:YES completion:nil];
    }
}

@end

#pragma mark - Spotify's sheet presentation

static void collect(UIView *view, NSString *className, NSMutableArray<UIView *> *out) {
    if ([NSStringFromClass(view.class) isEqualToString:className]) [out addObject:view];
    for (UIView *child in view.subviews) collect(child, className, out);
}


// NavigationUI_SheetImpl.SheetPresentationController: a sheet with a dimming view of Spotify's own, black
// at 0.7 fading in with the transition, added as the presentation begins.
@interface _TtC22NavigationUI_SheetImpl27SheetPresentationController : UISheetPresentationController
@end

@implementation _TtC22NavigationUI_SheetImpl27SheetPresentationController
- (void)presentationTransitionWillBegin {
    [super presentationTransitionWillBegin];
    UIView *dimming = [[UIView alloc] initWithFrame:self.containerView.bounds];
    dimming.accessibilityIdentifier = @"Components.UI.SheetPresentation.Dimming";
    dimming.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    dimming.alpha = 0;
    dimming.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerView insertSubview:dimming atIndex:0];
    [self.presentedViewController.transitionCoordinator animateAlongsideTransition:^(id context) { dimming.alpha = 1; } completion:nil];
}
- (void)containerViewDidLayoutSubviews {
    [super containerViewDidLayoutSubviews];
}
@end

@interface SGHarnessSheetDelegate : NSObject <UIViewControllerTransitioningDelegate>
@end

@implementation SGHarnessSheetDelegate
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source {
    _TtC22NavigationUI_SheetImpl27SheetPresentationController *sheet = [[_TtC22NavigationUI_SheetImpl27SheetPresentationController alloc] initWithPresentedViewController:presented presentingViewController:presenting];
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
    return sheet;
}
@end

// Every frame for a second from the tap on the ⋯: does anything of Spotify's sheet or its dimming show?
@interface SGHarnessFlashWatch : NSObject
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic) NSInteger frames, shown;
@property (nonatomic) CFTimeInterval start;
@end

@implementation SGHarnessFlashWatch
static BOOL onScreen(UIView *view) {
    if (!view.window) return NO;
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
        if (v.layer.mask && v.layer.mask.frame.size.width <= 1) return NO;
    }
    return YES;
}
- (void)tick:(CADisplayLink *)link {
    if (!self.start) self.start = link.timestamp;
    UIPresentationController *presentation = self.window.rootViewController.presentedViewController.presentationController;
    // Spotify's dimming, and the system's UIDimmingViews wherever they are: in the sheet's container, and over
    // the view the sheet came up over.
    BOOL dim = NO;
    for (UIView *v in presentation.containerView.subviews) {
        if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.SheetPresentation.Dimming"] && onScreen(v)) dim = YES;
    }
    NSMutableArray<UIView *> *system = [NSMutableArray array];
    collect(self.window, @"UIDimmingView", system);
    for (UIView *v in system) {
        CGFloat white = 0, alpha = 0;
        [v.backgroundColor getWhite:&white alpha:&alpha];
        if (onScreen(v) && alpha > 0.01) dim = YES;
    }
    BOOL sheet = presentation && onScreen(presentation.presentedView);
    self.frames++;
    if (sheet || dim) {
        self.shown++;
        NSLog(@"[harness] frame %ld: %@%@ shows", (long)self.frames, sheet ? @"the sheet " : @"", dim ? @"the dimming" : @"");
    }
    if (link.timestamp - self.start > 1) {
        [link invalidate];
        NSLog(@"[harness] flash check: %ld of the first %ld frames after the tap showed Spotify's sheet or its dimming", (long)self.shown, (long)self.frames);
    }
}
@end

#pragma mark - the player

@interface NowPlayingHarnessViewController : UIViewController
@property (nonatomic, strong) UIButton *more;
@end

@implementation NowPlayingHarnessViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.32 green:0.08 blue:0.1 alpha:1];
    UIView *cover = [[UIView alloc] initWithFrame:CGRectMake(24, 160, 354, 354)];
    cover.backgroundColor = [UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:1];
    cover.layer.cornerRadius = 12;
    [self.view addSubview:cover];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(24, 560, 354, 34)];
    title.text = @"máme toho moc";
    title.font = [UIFont boldSystemFontOfSize:26];
    title.textColor = UIColor.whiteColor;
    [self.view addSubview:title];

    void SGRPlayerMenuWatchMoreButton(UIView *button);
    self.more = [UIButton buttonWithType:UIButtonTypeSystem];
    self.more.frame = CGRectMake(402 - 12 - 48, 62, 48, 48);
    self.more.accessibilityIdentifier = @"Context menu";
    [self.more setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
    self.more.tintColor = UIColor.whiteColor;
    self.more.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    self.more.layer.cornerRadius = 24;
    [self.view addSubview:self.more];
    // The menu watches the button first, as PlayerHeader.x hands it over before the button is ever tapped.
    SGRPlayerMenuWatchMoreButton(self.more);
    [self.more addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
}

// The nesting Spotify's sheet has: a container presented as a sheet > navigation > page > menu.
- (void)openMenu {
    _TtC24ContextMenu_InternalImpl25ContextMenuViewController *menu = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
    UIViewController *page = [UIViewController new];
    [page addChildViewController:menu];
    menu.view.frame = page.view.bounds;
    menu.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [page.view addSubview:menu.view];
    [menu didMoveToParentViewController:page];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:page];
    navigation.navigationBarHidden = YES;
    UIViewController *container = [UIViewController new];
    [container addChildViewController:navigation];
    navigation.view.frame = container.view.bounds;
    navigation.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container.view addSubview:navigation.view];
    [navigation didMoveToParentViewController:container];
    static SGHarnessSheetDelegate *delegate;
    if (!delegate) delegate = [SGHarnessSheetDelegate new];
    container.modalPresentationStyle = UIModalPresentationCustom;
    container.transitioningDelegate = delegate;
    [self presentViewController:container animated:YES completion:nil];
}

@end

#pragma mark - reading what is on screen

static UIView *find(UIView *root, NSString *className, NSString *label) {
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    collect(root, className, found);
    for (UIView *view in found) {
        if (!label || [view.accessibilityLabel isEqualToString:label]) return view;
    }
    return nil;
}

static void collectKind(UIView *view, Class kind, NSMutableArray<UIView *> *out) {
    if ([view isKindOfClass:kind]) [out addObject:view];
    for (UIView *child in view.subviews) collectKind(child, kind, out);
}

// The button PlayerMenu.x lays over the ⋯ for the system menu to open from.
static UIButton *anchorOf(UIWindow *window) {
    return (UIButton *)find(window, @"SGRPlayerMenuAnchor", nil);
}

static void describe(UIMenuElement *element, int depth, NSMutableArray<NSString *> *out) {
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    if ([element isKindOfClass:UIMenu.class]) {
        UIMenu *menu = (UIMenu *)element;
        if (depth > 0) {
            BOOL inlined = (menu.options & UIMenuOptionsDisplayInline) != 0;
            [out addObject:inlined ? [NSString stringWithFormat:@"%@--%@", indent, menu.preferredElementSize == UIMenuElementSizeMedium ? @" tiles" : @""]
                                   : [NSString stringWithFormat:@"%@%@ >", indent, menu.title]];
        }
        for (UIMenuElement *child in menu.children) describe(child, depth + 1, out);
    } else if ([element isKindOfClass:UIAction.class]) {
        UIAction *action = (UIAction *)element;
        [out addObject:[NSString stringWithFormat:@"%@%@%@%@%@", indent, action.title,
                        action.subtitle ? [NSString stringWithFormat:@" (%@)", action.subtitle] : @"",
                        action.attributes & UIMenuElementAttributesDestructive ? @" [red]" : @"",
                        action.attributes & UIMenuElementAttributesDisabled ? @" [off]" : @""]];
    } else {
        [out addObject:[NSString stringWithFormat:@"%@(loading)", indent]];
    }
}

static UIAction *actionNamed(UIMenuElement *element, NSString *title) {
    if ([element isKindOfClass:UIAction.class]) return [((UIAction *)element).title isEqualToString:title] ? (UIAction *)element : nil;
    if (![element isKindOfClass:UIMenu.class]) return nil;
    for (UIMenuElement *child in ((UIMenu *)element).children) {
        UIAction *found = actionNamed(child, title);
        if (found) return found;
    }
    return nil;
}

// The words of the menu on screen, top to bottom.
static NSArray<NSString *> *menuOnScreen(UIWindow *window) {
    UIView *container = find(window, @"_UIContextMenuContainerView", nil);
    NSMutableArray<UIView *> *labels = [NSMutableArray array];
    if (container) collectKind(container, UILabel.class, labels);
    NSMutableArray<UILabel *> *shown = [NSMutableArray array];
    for (UILabel *label in (NSArray<UILabel *> *)labels) {
        BOOL visible = label.text.length && label.window;
        for (UIView *v = label; v && visible; v = v.superview) visible = !v.hidden && v.alpha > 0.01;
        if (visible) [shown addObject:label];
    }
    [shown sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGRect ra = [a convertRect:a.bounds toView:window], rb = [b convertRect:b.bounds toView:window];
        if (fabs(ra.origin.y - rb.origin.y) > 4) return ra.origin.y < rb.origin.y ? NSOrderedAscending : NSOrderedDescending;
        return ra.origin.x < rb.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    return [shown valueForKey:@"text"];
}

static void report(UIWindow *window, NSString *when) {
    UIButton *anchor = anchorOf(window);
    UIViewController *presented = window.rootViewController.presentedViewController;
    BOOL isSheet = presented.presentationController.class == NSClassFromString(@"_TtC22NavigationUI_SheetImpl27SheetPresentationController");
    UIView *sheet = isSheet ? presented.presentationController.presentedView : nil;
    NSString *sheetState = !isSheet ? @"none" : !sheet.hidden && sheet.alpha > 0.01 && !(sheet.layer.mask && sheet.layer.mask.frame.size.width <= 1) ? @"SHOWN" : @"out of sight";
    NSMutableArray<NSString *> *model = [NSMutableArray array];
    if (anchor.menu) describe(anchor.menu, 0, model);
    NSArray<NSString *> *screen = menuOnScreen(window);
    NSString *panel = @"";
    if ([NSStringFromClass(presented.class) isEqualToString:@"SGRSpeedPitchPanel"]) {
        NSMutableArray<UIView *> *sliders = [NSMutableArray array];
        collectKind(presented.view, UISlider.class, sliders);
        panel = [NSString stringWithFormat:@"; Speed and pitch's popover %@ with %lu sliders", NSStringFromCGSize(presented.preferredContentSize), (unsigned long)sliders.count];
    }
    NSLog(@"[harness] %@: menu %@; Spotify's sheet %@; presented %@%@\n  built:\n  %@\n  on screen: %@", when,
          screen.count ? @"ON SCREEN" : @"not on screen", sheetState, presented ? NSStringFromClass(presented.class) : @"nothing", panel,
          [model componentsJoinedByString:@"\n  "], [screen componentsJoinedByString:@" | "]);
}

// A row picked: its handler, then the menu closed, as a tap does (the other way round with `late`).
static void choose(UIWindow *window, NSString *title) {
    UIButton *anchor = anchorOf(window);
    UIAction *action = actionNamed(anchor.menu, title);
    void (^handler)(UIAction *) = nil;
    @try { handler = [action valueForKey:@"handler"]; } @catch (NSException *e) {}
    NSLog(@"[harness] picking \"%@\": %@", title, handler ? @"found" : @"NOT FOUND");
    if (!handler) return;
    if (argument(@"late")) {
        [anchor.contextMenuInteraction dismissMenu];
        after(0.15, ^{ handler(action); });
    } else {
        handler(action);
        [anchor.contextMenuInteraction dismissMenu];
    }
}

static void dump(UIView *view, int depth, NSMutableString *out) {
    if (!view || depth > 4) return;
    [out appendFormat:@"\n%*s%@ %@ a=%.2f%@%@", depth * 2, "", NSStringFromClass(view.class), NSStringFromCGRect(view.frame), view.alpha,
     view.hidden ? @" hidden" : @"", view.layer.mask ? [NSString stringWithFormat:@" mask=%@", NSStringFromCGRect(view.layer.mask.frame)] : @""];
    for (UIView *child in view.subviews) dump(child, depth + 1, out);
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

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    NowPlayingHarnessViewController *player = [NowPlayingHarnessViewController new];
    self.window.rootViewController = player;
    [self.window makeKeyAndVisible];
    UIWindow *window = self.window;

    after(1, ^{
        static SGHarnessFlashWatch *watch;
        watch = [SGHarnessFlashWatch new];
        watch.window = window;
        [[CADisplayLink displayLinkWithTarget:watch selector:@selector(tick:)] addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [player.more sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    after(2.2, ^{ report(window, @"open"); });
    if (argument(@"hold")) after(5, ^{ report(window, @"still open at 5 s"); });
    if (argument(@"dimmings")) for (NSNumber *at in @[@1.05, @1.5, @4]) after(at.doubleValue, ^{
        NSMutableArray<UIView *> *found = [NSMutableArray array];
        collect(window, @"UIDimmingView", found);
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (UIView *v in found) [lines addObject:[NSString stringWithFormat:@"in %@ hidden %d alpha %.2f", NSStringFromClass(v.superview.class), v.hidden, v.alpha]];
        NSLog(@"[harness] %.2f s: UIDimmingViews: %@", at.doubleValue, [lines componentsJoinedByString:@"; "]);
    });
    if (argument(@"dump")) after(2.4, ^{
        NSMutableString *out = [NSMutableString string];
        dump(window, 0, out);
        NSLog(@"[harness] window:%@", out);
    });
    if (argument(@"loading")) after(4.5, ^{ report(window, @"after the late rows"); });
    if (argument(@"stuck")) after(6, ^{ report(window, @"no rows at 6 s"); });
    if (argument(@"slow")) {
        after(6, ^{ report(window, @"no rows yet at 6 s"); });
        after(10, ^{ report(window, @"after the slow rows"); });
    }
    if (argument(@"speed") || argument(@"follow")) {
        after(3, ^{ choose(window, @"Speed and pitch"); });
        after(4, ^{ report(window, @"Speed and pitch picked"); });
    }
    if (argument(@"follow")) {
        for (NSNumber *at in @[@4.5, @9]) after(at.doubleValue, ^{
            UIViewController *panel = window.rootViewController.presentedViewController;
            NSMutableArray<UIView *> *switches = [NSMutableArray array];
            collectKind(panel.view, UISwitch.class, switches);
            UISwitch *toggle = (UISwitch *)switches.firstObject;
            NSLog(@"[harness] switching pitch follows speed %@: %@", toggle.on ? @"off" : @"on", toggle ? @"found" : @"NOT FOUND");
            toggle.on = !toggle.on;
            [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        });
        after(5.5, ^{ report(window, @"pitch follows speed"); });
        after(10, ^{ report(window, @"pitch no longer follows"); });
    } else if (argument(@"tile")) {
        after(3, ^{ choose(window, @"Add to playlist"); });
        after(4, ^{ report(window, @"after Add to playlist"); });
    } else if (argument(@"share")) {
        after(3, ^{ choose(window, @"Share"); });
        after(4, ^{ report(window, @"after Share"); });
    } else if (argument(@"lyrics")) {
        after(3, ^{ choose(window, @"Lyrics"); });
        after(3.4, ^{ report(window, @"just after Lyrics"); });
        after(5, ^{ report(window, @"2 s after Lyrics"); });
    } else if (argument(@"pending")) {
        // With `loading`: Add to playlist picked on the last menu's rows before Spotify's are in.
        after(1.6, ^{ choose(window, @"Add to playlist"); });
        after(4, ^{ report(window, @"after the held pick"); });
        after(7, ^{ report(window, @"5 s after the held pick"); });
    } else if (argument(@"outside")) {
        after(3, ^{
            NSLog(@"[harness] closing the menu with nothing picked");
            [anchorOf(window).contextMenuInteraction dismissMenu];
        });
        after(4, ^{ report(window, @"after closing it"); });
    }
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
