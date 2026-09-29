// A mock of Spotify's playlist page under its own class names and accessibility identifiers, built from
// trees/clean/playlist/01.txt, so Redesigned/Playlist can be laid out and looked at on the Mac.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../download-mock.h"

#pragma mark - Spotify's classes, by name

@interface _TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController : UIViewController
- (void)sgr_creatorFired;
- (void)sgr_pillFired:(UIView *)pill;
@end
@implementation _TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController
- (void)sgr_creatorFired { NSLog(@"[harness] the creator line opened the playlist's owner"); }
- (void)sgr_pillFired:(UIView *)pill { NSLog(@"[harness] the sheet fired Spotify's %@ pill", pill.accessibilityLabel); }
@end

@interface _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView : UIScrollView @end
@implementation _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView @end

// The page's view model, as the device showed it (2026-09-18): the header controller's defaultHeaderViewModel.
// `other` on the launch line makes it someone else's playlist, `liked` Liked Songs.
@interface MockViewModel : NSObject
@property (nonatomic, copy) NSString *playlistName, *playlistDescription, *formatListType;
@property (nonatomic) BOOL isOwnedBySelf;
@end
@implementation MockViewModel @end

@interface MockHeaderController : NSObject
@property (nonatomic, strong) MockViewModel *defaultHeaderViewModel;
@end
@implementation MockHeaderController @end

@interface SPTFreeTierPlaylistEncoreHeaderViewController : UIViewController
@property (nonatomic, strong) MockHeaderController *headerController;
- (void)entityHeaderViewController:(id)controller didUpdateVisibleRect:(CGRect)rect;
@end
@implementation SPTFreeTierPlaylistEncoreHeaderViewController
- (MockHeaderController *)headerController {
    if (!_headerController) {
        NSArray *args = NSProcessInfo.processInfo.arguments;
        MockViewModel *model = [MockViewModel new];
        if ([args containsObject:@"liked"]) {
            model.playlistName = @"Liked Songs";
            model.formatListType = @"liked-songs";
        } else if ([args containsObject:@"mix"]) {
            model.playlistName = @"Indie Rock Mix";
        } else if ([args containsObject:@"other"]) {
            model.playlistName = @"Barre Beats";
            model.playlistDescription = @"All music for beat-driven barre classes. Some cool-downs too! I&#x27;m always adding to the list";
        } else {
            model.playlistName = @"crap.";
            model.isOwnedBySelf = YES;
        }
        _headerController = [MockHeaderController new];
        _headerController.defaultHeaderViewModel = model;
    }
    return _headerController;
}
// Spotify's own is what reports a scroll to the header; here it only gives the hook something to run after.
- (void)entityHeaderViewController:(id)controller didUpdateVisibleRect:(CGRect)rect {}
@end

@interface _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout @end

// What a mix Spotify makes gets instead of the cover square (trees/continuous/4.txt:1066).
@interface _TtC28EncoreConsumerMobile_BaseKit26HeaderFullbleedCentralView : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit26HeaderFullbleedCentralView @end

@interface _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView : UIView @end
@implementation _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView @end

@interface _TtC19LegacyUI_ECMCoreKit13GradientView : UIView @end
@implementation _TtC19LegacyUI_ECMCoreKit13GradientView @end

@interface _TtC44PlaylistCuration_ExpandableTextElementKit18ExpandableTextView : UITextView @end
@implementation _TtC44PlaylistCuration_ExpandableTextElementKit18ExpandableTextView @end

@interface _TtCE13Encore_FaceKitO16EncoreFoundation6Encore12FacepileView : UIView @end
@implementation _TtCE13Encore_FaceKitO16EncoreFoundation6Encore12FacepileView @end

@interface _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView @end

@interface _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell : UICollectionViewCell @end
@implementation _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell @end

@interface _TtGC13Element_UIKit11ElementViewT_P_P__ : UIView @end
@implementation _TtGC13Element_UIKit11ElementViewT_P_P__ @end

// What the element framework wraps a cell's content in, and what the device's tree shows between the
// playlist's Refresh cell and the black it paints (trees/continuous/1.txt:1919). It is a cell of its own,
// the full width of the one around it, so a clear that stops at the first nested cell stops before the paint.
@interface MockElementContentView : UICollectionViewCell @end
@implementation MockElementContentView @end

// A card inside a carousel: a cell too, but its own width, and its own colour to keep.
@interface MockCardCell : UICollectionViewCell @end
@implementation MockCardCell @end

// Encore's glyph view and the icon it is built from, which answers its own name: how the curation row tells
// Sort from Edit without reading the word on it.
@interface MockEncoreIcon : NSObject
@property (nonatomic, copy) NSString *name;
@end
@implementation MockEncoreIcon @end

@interface SPTEncoreIconView : UIView {
@public
    id icon;
}
@end
@implementation SPTEncoreIconView @end

@interface _TtC19LegacyUI_ECMCoreKit10ScrollView : UIScrollView @end
@implementation _TtC19LegacyUI_ECMCoreKit10ScrollView @end

// The header view the find-on-page toolbar sits in, which PlaylistHeader.x conceals whole.
@interface _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView : UIView @end
@implementation _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView @end

// Spotify's ⋯ sheet: a table of rows the mod cannot read, whose header is what PlaylistMenu.x sets.
@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController
@property (nonatomic, strong) UITableView *table;
@end
@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, 200, self.view.bounds.size.width, 400)];
    _table.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_table];
}
@end

// The plain UIView Liked Songs' shuffle stack sits in: its own pass puts the stack back where Spotify's
// constraints want it, on the right of the row, which is what made the shuffle flash there on the phone.
@interface MockRightHost : UIView @end
@implementation MockRightHost
- (void)layoutSubviews {
    [super layoutSubviews];
    // As Auto Layout does it: centre and bounds, never the frame or the transform.
    self.subviews.firstObject.bounds = CGRectMake(0, 0, 48, 48);
    self.subviews.firstObject.center = CGPointMake(76, 24);
}
@end

@interface MockCondensedButton : UIControl @end
@implementation MockCondensedButton @end

#pragma mark - building the tree

static UIView *box(UIView *parent, Class cls, CGRect frame, NSString *identifier) {
    UIView *view = [[cls alloc] initWithFrame:frame];
    view.accessibilityIdentifier = identifier;
    [parent addSubview:view];
    return view;
}

static UILabel *label(UIView *parent, CGRect frame, NSString *text, CGFloat size, UIColor *color, NSString *identifier) {
    UIView *encore = box(parent, UIView.class, frame, identifier);
    UILabel *inner = [[UILabel alloc] initWithFrame:encore.bounds];
    inner.text = text;
    inner.font = [UIFont systemFontOfSize:size];
    inner.textColor = color;
    inner.accessibilityIdentifier = [identifier stringByAppendingString:@"-internal"];
    [encore addSubview:inner];
    return inner;
}

static UIImage *artwork(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat components[] = {0.93, 0.30, 0.47, 1, 0.28, 0.12, 0.42, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(300, 300), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithWhite:1 alpha:0.35] setFill];
        for (int i = 0; i < 5; i++) {
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(30 + i * 50, 40 + (i % 3) * 60, 70, 70)] fill];
        }
    }];
}

static UIImage *playGlyph(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 48)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(19, 15)];
        [path addLineToPoint:CGPointMake(33, 24)];
        [path addLineToPoint:CGPointMake(19, 33)];
        [path closePath];
        [UIColor.blackColor setFill];
        [path fill];
    }];
}

static UIView *actionButton(UIView *row, CGRect frame, NSString *identifier, NSString *a11y) {
    UIView *action = box(row, UIView.class, frame, nil);
    UIView *element = box(action, UIView.class, action.bounds, nil);
    UIView *button = box(element, UIButton.class, element.bounds, identifier);
    button.accessibilityLabel = a11y;
    UIImageView *glyph = [[UIImageView alloc] initWithFrame:CGRectInset(button.bounds, 12, 12)];
    NSDictionary *glyphs = @{@"Components.UI.AddToButton": @"plus", @"Components.UI.ContextMenuButton": @"ellipsis",
                             @"DownloadButton.Granular.None": @"arrow.down.circle", @"Components.UI.WatchFeedEntityExplorerButton": @"play.rectangle"};
    // Encore bakes the colour into what it draws, and ⋯ sits in a Tertiary button, which draws it grey
    // (device 2026-09-20): drawn as an image of that colour, not as a template to be tinted.
    BOOL tertiary = [identifier isEqualToString:@"Components.UI.ContextMenuButton"];
    UIImage *symbol = [UIImage systemImageNamed:glyphs[identifier] ?: @"circle"];
    if (tertiary) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:symbol.size];
        symbol = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIColor colorWithWhite:0.70 alpha:1] set];
            [symbol drawInRect:(CGRect){CGPointZero, symbol.size}];
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    glyph.image = symbol;
    glyph.tintColor = UIColor.whiteColor;
    [button addSubview:glyph];
    return action;
}

// What the redesign's row shows on Play's right: the label of the Kit's last round button, the trailing one.
static NSString *trailingLabel(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) {
            UIView *trailing = nil;
            for (UIView *sub in v.subviews) {
                if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) trailing = sub;
            }
            return trailing && !trailing.hidden ? trailing.accessibilityLabel : @"nothing";
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return @"no header";
}

// Liked Songs (trees/continuous/1.txt, 2026-09-18): the same page with no cover, a 238pt header, a column of
// only the title and the count (the count in a stack of its own, 314pt of label and a 56pt spacer), no add or
// more in the row, the play button 80x48 with its 48pt disc at x=16, and LiquidGlass.gradientContainer, the
// scrim Spotify fades in as the page scrolls. `liked` on the launch line builds it; at 3 s it is scrolled.
static void buildLikedSongs(UIViewController *page, CGFloat W) {
    UIViewController *headerVC = [SPTFreeTierPlaylistEncoreHeaderViewController new];
    [page addChildViewController:headerVC];
    UIView *header = headerVC.view;
    header.frame = CGRectMake(0, -72, W, 310);
    header.accessibilityIdentifier = @"PL.Header";
    header.backgroundColor = UIColor.clearColor;
    [page.view addSubview:header];
    [headerVC didMoveToParentViewController:page];

    UIView *headerLayout = box(header, UIView.class, CGRectMake(0, 72, W, 238), nil);
    UIView *clipping = box(headerLayout, UIView.class, headerLayout.bounds, @"_clippingView");
    UIView *background = box(clipping, UIView.class, clipping.bounds, @"_backgroundViewContainer");
    UIView *wash = box(background, UIView.class, background.bounds, nil);
    UIView *gradient = box(wash, _TtC19LegacyUI_ECMCoreKit13GradientView.class, wash.bounds, nil);
    gradient.backgroundColor = [UIColor colorWithRed:0.25 green:0.2 blue:0.7 alpha:1];
    UIView *safeArea = box(clipping, UIView.class, clipping.bounds, @"_safeAreaView");
    UIView *contentContainer = box(safeArea, UIView.class, CGRectMake(0, -72, W, 310), @"_headerContentContainer");
    UIView *contentView = box(contentContainer, UIView.class, CGRectMake(0, 72, W, 238), @"_contentViewContainer");
    UIView *layout = box(contentView, _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout.class, contentView.bounds, nil);

    UIView *slot = box(layout, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(178.33, 68, 45.33, 45.33), nil);
    box(slot, UIView.class, slot.bounds, nil);

    // Loading, the block sits above the icon's slot (so the slot is the lowest child) and moves down after.
    UIView *block = box(layout, UIView.class, CGRectMake(0, 20, 386, 108.67), nil);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        block.frame = CGRectMake(0, 129.33, 386, 108.67);
        [layout setNeedsLayout];
        [layout layoutIfNeeded];
        __block NSUInteger infos = 0;
        NSMutableArray *stack = [NSMutableArray arrayWithObject:page.view];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) infos++;
            [stack addObjectsFromArray:v.subviews];
        }
        NSLog(@"[harness] liked: after loading, %lu redesign blocks on the page", (unsigned long)infos);
    });
    UIView *blockInner = box(box(block, UIView.class, block.bounds, nil), UIView.class, CGRectMake(0, 0, 386, 100.67), nil);
    UIView *columnStack = box(blockInner, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(16, 0, 370, 100.67), nil);
    UIView *columnAndRow = box(columnStack, UIView.class, columnStack.bounds, nil);
    UIView *columnHost = box(columnAndRow, UIView.class, CGRectMake(0, 0, 370, 44.67), nil);
    UIView *titleStack = box(columnHost, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, columnHost.bounds, nil);
    UIView *column = box(titleStack, UIView.class, titleStack.bounds, nil);
    label(column, CGRectMake(0, 0, 370, 25.33), @"Liked Songs", 21, UIColor.whiteColor, @"Encore.Label");
    UIView *countStack = box(column, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(0, 29.33, 370, 15.33), nil);
    UIView *countRow = box(countStack, UIView.class, countStack.bounds, nil);
    label(countRow, CGRectMake(0, 0, 314, 15.33), @"1 016 songs", 11, [UIColor colorWithWhite:1 alpha:0.4],
          @"Components.Header.UI.Metadata").textAlignment = NSTextAlignmentLeft;
    box(countRow, UIView.class, CGRectMake(314, 7.67, 56, 0), nil);

    UIView *rowHost = box(columnAndRow, UIView.class, CGRectMake(0, 52.67, 370, 48), nil);
    UIView *rowStack = box(rowHost, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, rowHost.bounds, nil);
    UIView *container = box(rowStack, UIView.class, rowStack.bounds, nil);
    UIView *left = box(container, UIView.class, CGRectMake(0, 0, 96, 48), nil);
    UIView *leftStack = box(left, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(-10, 0, 106, 48), nil);
    UIView *element = box(box(leftStack, UIView.class, leftStack.bounds, nil), _TtGC13Element_UIKit11ElementViewT_P_P__.class, CGRectMake(0, 0, 106, 48), nil);
    UIStackView *actions = (UIStackView *)box(element, UIStackView.class, element.bounds, @"HeaderActionsRow");
    actionButton(actions, CGRectMake(0, 4, 58, 40), @"Components.UI.WatchFeedEntityExplorerButton", @"Explore Liked Songs");
    actionButton(actions, CGRectMake(58, 0, 48, 48), @"DownloadButton.Granular.None", @"Download");
    box(container, UIView.class, CGRectMake(96, 23.67, 174, 1), nil);
    UIView *right = box(container, MockRightHost.class, CGRectMake(270, 0, 100, 48), nil);
    UIView *rightStack = box(right, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(-184, 0, 48, 48), nil);
    UIView *shuffleHost = box(box(rightStack, UIView.class, rightStack.bounds, nil), UIView.class, CGRectMake(0, 0, 48, 48), nil);
    UIView *shuffle = box(shuffleHost, UIButton.class, shuffleHost.bounds, @"Components.UI.ShuffleButton");
    shuffle.accessibilityLabel = @"Shuffle tracks";
    UIImageView *shuffleGlyph = [[UIImageView alloc] initWithFrame:CGRectInset(shuffle.bounds, 12, 12)];
    shuffleGlyph.image = [UIImage systemImageNamed:@"shuffle"];
    shuffleGlyph.tintColor = [UIColor colorWithRed:0.02 green:0.97 blue:0 alpha:1];
    [shuffle addSubview:shuffleGlyph];

    UIView *scrim = box(headerLayout, UIView.class, CGRectMake(0, 0, W, 124), @"LiquidGlass.gradientContainer");
    scrim.alpha = 0;
    box(scrim, UIView.class, scrim.bounds, @"LiquidGlass.GradientView").backgroundColor = [UIColor colorWithRed:0.25 green:0.3 blue:0.9 alpha:1];

    UIView *foreground = box(headerLayout, UIView.class, headerLayout.bounds, @"_foregroundViewContainer");
    UIView *playButton = box(foreground, _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView.class, CGRectMake(322, 182, 80, 48), @"header-play-button");
    UIControl *condensed = (UIControl *)box(playButton, MockCondensedButton.class, CGRectMake(16, 0, 48, 48), nil);
    condensed.accessibilityLabel = @"Shuffle Play";
    UIImageView *disc = [[UIImageView alloc] initWithFrame:condensed.bounds];
    disc.image = [[UIImage systemImageNamed:@"shuffle"] imageByApplyingSymbolConfiguration:
                  [UIImageSymbolConfiguration configurationWithPointSize:18]];
    disc.contentMode = UIViewContentModeCenter;
    disc.backgroundColor = [UIColor colorWithRed:0.02 green:0.97 blue:0 alpha:1];
    [condensed addSubview:disc];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        scrim.alpha = 1;
        [layout setNeedsLayout];
        [layout layoutIfNeeded];
        // Spotify's parent laying the shuffle out again, after every pass of the header's.
        [right setNeedsLayout];
        [right layoutIfNeeded];
        CGRect shuffleInRow = [container convertRect:shuffle.bounds fromView:shuffle];
        UIView *capsule = container.subviews.lastObject;
        NSLog(@"[harness] liked: after the shuffle's parent laid out: shuffle %@, capsule %@ (%@), screen middle %.1f",
              NSStringFromCGRect([container convertRect:shuffleInRow toView:nil]),
              NSStringFromCGRect([container convertRect:capsule.frame toView:nil]), capsule.class,
              CGRectGetMidX(page.view.bounds));
        NSLog(@"[harness] liked: scrolled, scrim a=%.2f hidden=%d masked=%d; column rows %@ / %@",
              scrim.alpha, scrim.layer.hidden, scrim.layer.mask != nil,
              NSStringFromCGRect(column.subviews[0].frame), NSStringFromCGRect(column.subviews[1].frame));
    });
}

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGRHarnessDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    CGFloat W = self.window.bounds.size.width, H = self.window.bounds.size.height;

    UIViewController *page = [_TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController new];
    page.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.window.rootViewController = page;
    // The device's page counts the navigation bar into its own safe area -- 116 against the window's 62 --
    // which is what put the pinned ⋯ a bar's height below the back button (trees/continuous/1.txt 2026-09-20).
    page.additionalSafeAreaInsets = UIEdgeInsetsMake(54, 0, 0, 0);

    // the list
    UIScrollView *list = (UIScrollView *)box(page.view, _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView.class,
                                             CGRectMake(0, 0, W, H), @"SPTFreeTierPlaylistTableView");
    list.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    NSArray<NSArray<NSString *> *> *tracks = @[@[@"Cry For Me", @"The Weeknd"], @[@"I Can't Fucking Sing", @"The Weeknd"],
                                              @[@"São Paulo", @"The Weeknd, Anitta"], @[@"Until We're Skin & Bones", @"The Weeknd"],
                                              @[@"Baptized In Fear", @"The Weeknd"]];
    // The curation row stands over the first track, where Spotify's list has it, and the tracks start under it.
    CGFloat tracksTop = 564;
    for (NSUInteger i = 0; i < tracks.count; i++) {
        UIView *cell = box(list, _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class,
                           CGRectMake(0, tracksTop + i * 64, W, 64), @"Playlist.ItemCell");
        cell.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
        UIView *row = box(cell, UIView.class, cell.bounds, @"Encore.ListRow");
        row.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
        UIView *art = box(row, UIView.class, CGRectMake(16, 8, 48, 48), @"Encore.ImageView");
        UIImageView *picture = [[UIImageView alloc] initWithFrame:art.bounds];
        picture.image = artwork();
        [art addSubview:picture];
        label(row, CGRectMake(76, 12, W - 130, 20), tracks[i][0], 16, UIColor.whiteColor, @"Track.Row.Content.Title");
        label(row, CGRectMake(76, 32, W - 130, 18), tracks[i][1], 14, [UIColor colorWithWhite:1 alpha:0.7], @"Track.Row.Content.Subtitle");
    }

    // The extender under the tracks (device, trees/continuous/2.txt 2026-09-20): Recommended songs, its
    // rows and Refresh, each cell painting the black the AMOLED made of Spotify's base surface over the
    // field. Only the paint is mocked -- what the clear has to take off and what it has to leave.
    CGFloat extenderTop = tracksTop + tracks.count * 64;
    UIView *heading = box(list, _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class,
                          CGRectMake(0, extenderTop, W, 68), nil);
    UIView *headingPaint = box(heading, UIView.class, heading.bounds, @"PlaylistExtender.Heading");
    headingPaint.backgroundColor = UIColor.blackColor;
    label(headingPaint, CGRectMake(16, 16, W - 32, 21), @"Recommended songs", 17, UIColor.whiteColor, @"title");
    label(headingPaint, CGRectMake(16, 37, W - 32, 16), @"Based on the songs of this playlist", 11,
          [UIColor colorWithWhite:0.7 alpha:1], @"subtitle");

    UIView *extenderRow = box(list, _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class,
                              CGRectMake(0, extenderTop + 68, W, 64), nil);
    UIView *extenderPaint = box(extenderRow, UIView.class, extenderRow.bounds, @"PlaylistExtender.Row");
    label(extenderPaint, CGRectMake(76, 22, W - 130, 20), @"Airplanes", 16, UIColor.whiteColor, nil);
    // A badge's disc is its own black and is not as wide as the cell: it stays.
    UIView *badge = box(extenderPaint, UIView.class, CGRectMake(W - 72, 19, 26, 26), @"PlaylistExtender.Badge");
    badge.backgroundColor = UIColor.blackColor;
    badge.layer.cornerRadius = 13;

    // A card in a carousel: a cell of its own inside the row, narrower than the page, whose colour is its own
    // and stays.
    UIView *card = box(extenderRow, MockCardCell.class, CGRectMake(16, 8, 140, 48), @"PlaylistExtender.Card");
    card.layer.backgroundColor = UIColor.blackColor.CGColor;

    // Refresh, nested the way the device has it: the cell, the element framework's own content cell the full
    // width of it, the element view, and the black on the layer rather than through the view
    // (trees/continuous/1.txt:1919-1922). Both of those are what the first clear walked past.
    UIView *refresh = box(list, _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class,
                          CGRectMake(0, extenderTop + 132, W, 48), nil);
    UIView *refreshContent = box(refresh, MockElementContentView.class, refresh.bounds, nil);
    UIView *refreshElement = box(refreshContent, _TtGC13Element_UIKit11ElementViewT_P_P__.class, refresh.bounds, nil);
    UIView *refreshPaint = box(refreshElement, UIView.class, refresh.bounds, @"PlaylistExtender.Refresh");
    refreshPaint.layer.backgroundColor = UIColor.blackColor.CGColor;
    UIView *button = box(refreshPaint, UIView.class, CGRectMake(W / 2 - 36, 8, 72, 32), @"section-header-button");
    button.backgroundColor = UIColor.whiteColor;
    button.layer.cornerRadius = 16;

    // The curation row over the first track (own-playlist/01.txt:33): Add, Mix, Notes, Video, Edit, Sort and
    // Name & details in a scroll view, of which the redesign keeps Sort and Mix.
    // `nohandover` builds the row in a cell the redesign's hook never sees, the way the device has it when
    // the collection has not laid the closed-up cell out yet: the sheet then has to find the row itself.
    BOOL handover = ![NSProcessInfo.processInfo.arguments containsObject:@"nohandover"];
    UIView *curation = box(list, handover ? _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class
                                          : UICollectionViewCell.class,
                           CGRectMake(0, tracksTop - 52, W, 52), nil);
    UIView *toolbar = box(curation, UIView.class, curation.bounds, @"PlaylistCuration.Row.CurationActionsToolbar");
    toolbar.layer.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1].CGColor;
    UIScrollView *pillScroll = (UIScrollView *)box(box(toolbar, UIView.class, toolbar.bounds, nil),
                                                   _TtC19LegacyUI_ECMCoreKit10ScrollView.class,
                                                   CGRectMake(0, 10, W, 32), nil);
    UIView *pillContent = box(pillScroll, UIView.class, CGRectMake(0, 0, 527, 32), nil);
    UIView *pillStack = box(pillContent, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, pillContent.bounds, nil);
    UIView *pillRow = box(pillStack, UIView.class, pillStack.bounds, nil);
    pillScroll.contentSize = pillContent.bounds.size;
    NSArray<NSArray<NSString *> *> *pills = @[@[@"Add", @"PlaylistCuration.AddButton", @"plus"],
                                              @[@"Mix", @"ListPlatform.ToolbarActions.MixButton", @"mix"],
                                              @[@"Video", @"Encore.Button.Primary", @"video"],
                                              @[@"Edit", @"Encore.Button.Primary", @"edit"],
                                              @[@"Sort", @"Encore.Button.Primary", @"sortDown"],
                                              @[@"Name & details", @"Encore.Button.Primary", @"playlist"]];
    CGFloat pillX = 0;
    NSMutableArray<UIView *> *pillViews = [NSMutableArray array];
    for (NSArray<NSString *> *pill in pills) {
        CGFloat width = 40 + pill[0].length * 6;
        UIView *wrapper = box(pillRow, _TtGC13Element_UIKit11ElementViewT_P_P__.class, CGRectMake(pillX, 0, width, 32), nil);
        UIButton *pillButton = (UIButton *)box(wrapper, UIButton.class, wrapper.bounds, pill[1]);
        pillButton.accessibilityLabel = pill[0];
        [pillButton addTarget:page action:@selector(sgr_pillFired:) forControlEvents:UIControlEventTouchUpInside];
        pillButton.layer.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
        pillButton.layer.cornerRadius = 16;
        SPTEncoreIconView *icon = (SPTEncoreIconView *)box(pillButton, SPTEncoreIconView.class, CGRectMake(10, 10, 12, 12), @"Encore.IconView");
        MockEncoreIcon *glyph = [MockEncoreIcon new];
        glyph.name = pill[2];
        icon->icon = glyph;
        label(pillButton, CGRectMake(26, 8, width - 32, 16), pill[0], 11, UIColor.whiteColor, @"Encore.Label");
        [pillViews addObject:wrapper];
        pillX += width + 8;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Cleared means an alpha of 0, whether the colour was taken off the layer or the view: the clear
        // colour lands on both and reads back with no alpha at all.
        CGFloat (^alpha)(UIView *) = ^(UIView *v) {
            return v.layer.backgroundColor ? CGColorGetAlpha(v.layer.backgroundColor) : 0;
        };
        NSLog(@"[harness] extender paint: heading a=%.0f row-badge a=%.0f card a=%.0f refresh a=%.0f",
              alpha(headingPaint), alpha(badge), alpha(card), alpha(refreshPaint));
    });

    if ([NSProcessInfo.processInfo.arguments containsObject:@"liked"]) {
        buildLikedSongs(page, W);
        [self.window makeKeyAndVisible];
        return YES;
    }

    // the header
    UIViewController *headerVC = [SPTFreeTierPlaylistEncoreHeaderViewController new];
    [page addChildViewController:headerVC];
    UIView *header = headerVC.view;
    header.frame = CGRectMake(0, -134, W, 639.33);
    header.accessibilityIdentifier = @"PL.Header";
    header.backgroundColor = UIColor.clearColor;
    [page.view addSubview:header];
    [headerVC didMoveToParentViewController:page];

    UIView *headerLayout = box(header, UIView.class, CGRectMake(0, 134, W, 505.33), nil);
    UIView *clipping = box(headerLayout, UIView.class, headerLayout.bounds, @"_clippingView");
    UIView *background = box(clipping, UIView.class, clipping.bounds, @"_backgroundViewContainer");
    UIView *wash = box(background, UIView.class, background.bounds, nil);
    wash.clipsToBounds = YES;
    UIView *gradient = box(wash, _TtC19LegacyUI_ECMCoreKit13GradientView.class, wash.bounds, nil);
    gradient.backgroundColor = [UIColor colorWithRed:0.5 green:0.1 blue:0.3 alpha:1];
    // The second wash of the plane: a plain view painted the base surface with a gradient of its own in it,
    // drawn after the hero. Spotify keeps it at alpha 0 on an ordinary playlist and raises it with the Mix
    // feature on, where its black covered the picture whole (trees/continuous/1.txt 2026-09-20).
    UIView *mixWash = box(wash, UIView.class, wash.bounds, nil);
    mixWash.backgroundColor = UIColor.blackColor;
    mixWash.alpha = [NSProcessInfo.processInfo.arguments containsObject:@"mixon"] ? 1 : 0;
    UIView *mixGradient = box(mixWash, _TtC19LegacyUI_ECMCoreKit13GradientView.class, CGRectMake(0, 8, 560, 560), nil);
    mixGradient.backgroundColor = [UIColor colorWithRed:0.1 green:0.4 blue:0.2 alpha:1];

    UIView *safeArea = box(clipping, UIView.class, clipping.bounds, @"_safeAreaView");
    UIView *contentContainer = box(safeArea, UIView.class, CGRectMake(0, -134, W, 639.33), @"_headerContentContainer");
    UIView *contentView = box(contentContainer, UIView.class, CGRectMake(0, 134, W, 505.33), @"_contentViewContainer");
    UIView *layout = box(contentView, _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout.class, contentView.bounds, nil);

    // The cover: a mix's full bleed picture, or a playlist's square. `mix` on the launch line builds the
    // header a playlist Spotify makes gets (trees/continuous/4.txt:1066): no Components.Header.UI.ArtworkImage
    // anywhere, and in its place a HeaderFullbleedCentralView holding the picture, the fade under it and
    // Spotify's own big title. It is the layout's first child and as wide as the page, which is what the
    // block used to be taken for.
    BOOL mix = [NSProcessInfo.processInfo.arguments containsObject:@"mix"];
    UIView *cover = nil, *fullbleed = nil;
    if (mix) {
        fullbleed = box(layout, _TtC28EncoreConsumerMobile_BaseKit26HeaderFullbleedCentralView.class,
                        CGRectMake(0, 0, W, 311), nil);
        fullbleed.clipsToBounds = YES;
        UIView *slot = box(fullbleed, UIView.class, CGRectMake(-10, 0, W + 20, W + 20), nil);
        UIView *slotImage = box(slot, UIView.class, slot.bounds, @"Encore.ImageView");
        UIImageView *slotPicture = [[UIImageView alloc] initWithFrame:slotImage.bounds];
        slotPicture.image = artwork();
        slotPicture.contentMode = UIViewContentModeScaleAspectFill;
        [slotImage addSubview:slotPicture];
        UIView *fade = box(fullbleed, _TtC19LegacyUI_ECMCoreKit13GradientView.class, CGRectMake(0, 225, W, 86), nil);
        fade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        UIView *titleStack = box(fullbleed, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class,
                                 CGRectMake(16, 249, W - 32, 54), nil);
        label(titleStack, titleStack.bounds, @"Indie Rock Mix", 45, UIColor.whiteColor, @"Encore.Label");
    } else {
        cover = box(layout, UIView.class, CGRectMake(round((W - 182) / 2), 68, 182, 182), @"Components.Header.UI.ArtworkImage");
        UIView *coverImage = box(cover, UIView.class, cover.bounds, @"Encore.ImageView");
        UIImageView *coverPicture = [[UIImageView alloc] initWithFrame:coverImage.bounds];
        coverPicture.image = artwork();
        coverPicture.contentMode = UIViewContentModeScaleAspectFill;
        [coverImage addSubview:coverPicture];
    }

    // the block: the column, then the action row
    UIView *block = box(layout, UIView.class, CGRectMake(0, 266.67, W - 16, 178.33), nil);
    UIView *blockStack = box(block, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, block.bounds, nil);
    UIView *blockInner = box(blockStack, UIView.class, blockStack.bounds, nil);

    UIView *columnHost = box(blockInner, UIView.class, CGRectMake(0, 0, block.bounds.size.width, 122.33), nil);
    UIView *columnStack = box(columnHost, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class,
                              CGRectMake(16, 0, columnHost.bounds.size.width - 16, 122.33), nil);
    UIView *column = box(columnStack, UIView.class, columnStack.bounds, nil);
    CGFloat columnWidth = column.bounds.size.width;

    label(column, CGRectMake(0, 0, columnWidth, 29.67), @"Hurry Up Tomorrow", 21, UIColor.whiteColor, @"Encore.Label");

    UIView *descriptionRow = box(column, UIView.class, CGRectMake(0, 33.67, columnWidth, 31.33), nil);
    UITextView *description = (UITextView *)box(descriptionRow, _TtC44PlaylistCuration_ExpandableTextElementKit18ExpandableTextView.class,
                                                descriptionRow.bounds, nil);
    description.text = @"On what was meant to be the last date of his 2022 tour, The Weeknd took the stage.";
    description.font = [UIFont systemFontOfSize:14];
    description.textColor = UIColor.whiteColor;
    description.backgroundColor = UIColor.clearColor;
    description.textContainerInset = UIEdgeInsetsZero;
    description.textContainer.lineFragmentPadding = 0;

    UIView *creatorRow = box(column, UIView.class, CGRectMake(0, 69, columnWidth, 34), nil);
    UIButton *creator = (UIButton *)box(creatorRow, UIButton.class, CGRectMake(0, 0, 109.67, 34),
                                        @"Components.PlaylistHeader.collaboratorsButton");
    creator.accessibilityLabel = @"Playlist created by The Weeknd";
    [creator addTarget:page action:@selector(sgr_creatorFired) forControlEvents:UIControlEventTouchUpInside];
    UIView *face = box(creator, _TtCE13Encore_FaceKitO16EncoreFoundation6Encore12FacepileView.class, CGRectMake(0, 5, 24, 24), nil);
    face.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1];
    face.layer.cornerRadius = 12;
    label(creator, CGRectMake(32, 9, 77, 16), @"The Weeknd", 13, UIColor.whiteColor, @"Encore.Label");
    box(creatorRow, UIView.class, CGRectMake(109.67, 0, columnWidth - 109.67, 34), nil);

    UIView *lengthRow = box(column, UIView.class, CGRectMake(0, 107, columnWidth, 15.33), nil);
    UIView *length = box(lengthRow, UIView.class, CGRectMake(0, 0, 126.33, 15.33), nil);
    label(length, CGRectMake(0, 0, 126.33, 15.33), @"4 637 saves • 20h 28m", 11, [UIColor colorWithWhite:1 alpha:0.7],
          @"Components.Header.UI.Metadata");
    box(lengthRow, UIView.class, CGRectMake(126.33, 0, columnWidth - 126.33, 15.33), nil);

    UIView *actionHost = box(blockInner, UIView.class, CGRectMake(0, 130.33, block.bounds.size.width, 48), nil);
    UIView *actionStack = box(actionHost, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class,
                              CGRectMake(4, 0, actionHost.bounds.size.width - 4, 48), nil);
    UIView *container = box(actionStack, UIView.class, actionStack.bounds, nil);
    UIView *rowElement = box(container, _TtGC13Element_UIKit11ElementViewT_P_P__.class, CGRectMake(0, 0, 198, 48), nil);
    UIStackView *actions = (UIStackView *)box(rowElement, UIStackView.class, rowElement.bounds, @"HeaderActionsRow");
    actionButton(actions, CGRectMake(0, 4, 58, 40), @"Components.UI.WatchFeedEntityExplorerButton", @"Explore");
    // `late` on the launch line: save is not in the row yet, the way a playlist opened for the first time has it,
    // and arrives at 2.5 s as an arranged subview of the row, which lays out the row and nothing above it.
    BOOL late = [NSProcessInfo.processInfo.arguments containsObject:@"late"];
    if (late) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [actions insertArrangedSubview:actionButton(actions, CGRectMake(58, 0, 48, 48), @"Components.UI.AddToButton", @"Like")
                                   atIndex:0];
            NSLog(@"[harness] late: save arrived in the row");
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] late: Play's right shows \"%@\"", trailingLabel(page.view));
        });
    } else {
        actionButton(actions, CGRectMake(58, 0, 48, 48), @"Components.UI.AddToButton", @"Like");
    }
    // Drawn by Lottie, its state in its identifier and in the Encore object behind it (issue #65).
    UIView *downloadAction = box(actions, UIView.class, CGRectMake(106, 0, 48, 48), nil);
    mockDownloadButton(box(downloadAction, UIView.class, downloadAction.bounds, nil));
    actionButton(actions, CGRectMake(154, 2, 44, 44), @"Components.UI.ContextMenuButton", @"More options");

    UIView *mixShuffle = box(container, UIView.class, CGRectMake(container.bounds.size.width - 124, 0, 124, 48), nil);
    UIView *mixShuffleStack = box(mixShuffle, UIStackView.class, CGRectMake(0, 0, 68, 48), nil);
    box(mixShuffleStack, UIView.class, CGRectMake(0, 0, 20, 48), @"MixAndShuffleComposedUI.mixView");
    UIView *shuffleView = box(mixShuffleStack, UIView.class, CGRectMake(20, 0, 48, 48), @"MixAndShuffleComposedUI.shuffleView");
    UIView *shuffleElement = box(shuffleView, UIView.class, shuffleView.bounds, nil);
    UIView *shuffle = box(shuffleElement, UIButton.class, shuffleElement.bounds, @"Components.UI.ShuffleButton");
    shuffle.accessibilityLabel = @"Shuffle tracks";
    mockShuffleGlyph(shuffle);

    // The find-on-page toolbar the header conceals, whose Sort button is what the ⋯ sheet fires: one
    // identifier, in the header rather than in a cell the list reuses (trees/continuous/1.txt:1000).
    UIView *topAccessory = box(headerLayout, UIView.class, CGRectMake(0, 16, W, 134), @"_topAccessoryViewContainer");
    UIView *toolbarHeader = box(topAccessory, _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView.class, CGRectMake(0, 0, W, 134), nil);
    UIView *toolbarContent = box(toolbarHeader, UIView.class, CGRectMake(16, 98, W - 32, 36), @"Components.Header.UI.Toolbar.Content");
    UIView *sortContainer = box(toolbarContent, UIView.class, CGRectMake(W - 94, 0, 62, 36), @"Components.Header.UI.Toolbar.ButtonContainer");
    sortContainer.hidden = YES;
    UIButton *headerSort = (UIButton *)box(sortContainer, UIButton.class, CGRectMake(16, 0, 30, 36), @"Components.Header.UI.Toolbar.Button");
    [headerSort setTitle:@"Sort" forState:UIControlStateNormal];
    [headerSort addTarget:page action:@selector(sgr_pillFired:) forControlEvents:UIControlEventTouchUpInside];
    headerSort.accessibilityLabel = @"Sort";

    // the play button, in the header's foreground plane
    UIView *foreground = box(headerLayout, UIView.class, headerLayout.bounds, @"_foregroundViewContainer");
    UIView *playHost = box(foreground, UIView.class, CGRectMake(W - 64, 457.33, 64, 48), nil);
    UIView *playButton = box(playHost, _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView.class, CGRectMake(0, 0, 48, 48), @"header-play-button");
    UIControl *condensed = (UIControl *)box(playButton, MockCondensedButton.class, playButton.bounds, nil);
    condensed.accessibilityLabel = @"Play";
    UIImageView *disc = [[UIImageView alloc] initWithFrame:condensed.bounds];
    disc.image = playGlyph();
    disc.backgroundColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
    disc.layer.cornerRadius = 24;
    disc.clipsToBounds = YES;
    [condensed addSubview:disc];

    // The pass that used to lose the picture: while Spotify is still measuring, the block has no width of
    // its own, and the full bleed view is then the only child of the layout wide enough to be taken for it.
    // Taken for the block, everything it holds -- the picture with it -- was concealed, and concealing does
    // not come undone, so the hero stayed black for as long as the page was open (trees/continuous/3.txt
    // against 4.txt, 2026-09-20). The mix runs that pass before any other, so a regression shows here too.
    if (mix) {
        CGRect settled = block.frame;
        block.frame = CGRectMake(0, 266.67, 0, 0);
        [layout setNeedsLayout];
        [layout layoutIfNeeded];
        block.frame = settled;
        NSLog(@"[harness] the measuring pass is done: the full bleed view is %@",
              fullbleed.layer.hidden ? @"concealed" : @"still drawn");
    }

    [self.window makeKeyAndVisible];

    // The header collapsing, and the page pulled down past the top, with the frames Spotify sets in each
    // (trees/continuous/2.txt and 4.txt). The hero has to slide up out of the clipping view with the plane
    // the wash is on, not be resized into a strip at the top of the screen.
    void (^setState)(NSString *) = ^(NSString *state) {
        BOOL collapsed = [state isEqualToString:@"collapsed"];
        BOOL pulled = [state isEqualToString:@"pulled"];
        CGFloat layoutHeight = collapsed ? 110 : (pulled ? 608 : 474);
        header.frame = CGRectMake(0, collapsed ? -498 : (pulled ? 0 : -134), W, 608);
        headerLayout.frame = CGRectMake(0, collapsed ? 498 : (pulled ? 0 : 134), W, layoutHeight);
        clipping.frame = CGRectMake(0, 0, W, layoutHeight);
        background.frame = CGRectMake(0, 0, W, layoutHeight);
        background.alpha = collapsed ? 0 : 1;
        wash.frame = collapsed ? CGRectMake(0, -364, W, 474) : CGRectMake(0, 0, W, layoutHeight);
        safeArea.frame = CGRectMake(0, 0, W, layoutHeight);
        contentContainer.frame = CGRectMake(0, pulled ? 0 : -134, W, collapsed ? 244 : 608);
        contentView.frame = CGRectMake(0, 134, W, collapsed ? 110 : 474);
        layout.frame = CGRectMake(0, 0, W, collapsed ? 110 : 474);
        cover.frame = collapsed ? CGRectMake(148.67, 68, 104.67, 104.67) : CGRectMake(round((W - 243) / 2), 68, 243, 243);
        // The full bleed picture is clipped away rather than shrunk: collapsed it is the width of the page
        // and no height at all, with the picture inside it still at its own size (trees/continuous/3.txt:1066).
        fullbleed.frame = collapsed ? CGRectMake(0, 0, W, 0) : CGRectMake(0, 0, W, 311);
        block.frame = collapsed ? CGRectMake(0, -26.33, W - 16, 136.33) : CGRectMake(0, pulled ? 461 : 327, W - 16, pulled ? 220 : 178.33);
        [layout setNeedsLayout];
        [layout layoutIfNeeded];
        UIView *hero = wash.subviews.firstObject;
        UIImageView *picture = (UIImageView *)hero.subviews.firstObject;
        NSLog(@"[harness] state %@: hero %@ in the plane, %@ in the window, picture %@", state,
              NSStringFromCGRect(hero.frame), NSStringFromCGRect([wash convertRect:hero.frame toView:nil]),
              [picture isKindOfClass:UIImageView.class] && picture.image ? @"drawn" : @"EMPTY");
    };
    // `download` plays the download button's states instead of the header's (download-mock.h), with the page
    // left at rest and no sheet over it, for screenshots.
    BOOL downloads = [NSProcessInfo.processInfo.arguments containsObject:@"download"];
    if (downloads) {
        downloadScript();
        return YES;
    }
    for (NSUInteger i = 0; i < 3; i++) {
        NSString *state = @[@"rest", @"collapsed", @"pulled"][i];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((4 + i * 4) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            setState(state);
        });
    }

    // Spotify fading its cover square and its colour wash back in as the header opens, which it does on the
    // scroll itself with nothing laid out: only the hook on that scroll sees it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(16 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setState(@"rest");
        cover.alpha = 1;
        gradient.alpha = 1;
        NSLog(@"[harness] Spotify's cover and wash faded back in");
        [(SPTFreeTierPlaylistEncoreHeaderViewController *)headerVC entityHeaderViewController:nil didUpdateVisibleRect:CGRectZero];
        NSLog(@"[harness] after Spotify's fade back in: cover a=%.2f layer.hidden=%d, wash a=%.2f layer.hidden=%d",
              cover.alpha, cover.layer.hidden, gradient.alpha, gradient.layer.hidden);
    });

    // The ⋯ the redesign pins over the page: outside the list and the header both, so it holds its place
    // while the header collapses and the list scrolls (issue #57). Tapped, it fires Spotify's own.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *pinned = nil;
        for (UIView *sub in page.view.subviews) {
            if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) pinned = sub;
        }
        UIImageView *pinnedGlyph = nil;
        for (UIView *sub in pinned.subviews) {
            if ([sub isKindOfClass:UIImageView.class]) pinnedGlyph = (UIImageView *)sub;
        }
        NSLog(@"[harness] pinned more: %@ on the page, hidden=%d, glyph %@ tinted %@",
              pinned ? NSStringFromCGRect(pinned.frame) : @"MISSING", pinned.hidden,
              pinnedGlyph.image.renderingMode == UIImageRenderingModeAlwaysTemplate ? @"template" : @"as Spotify drew it",
              pinnedGlyph.tintColor);
        UIView *hit = [page.view hitTest:CGPointMake(CGRectGetMidX(pinned.frame), CGRectGetMidY(pinned.frame)) withEvent:nil];
        NSLog(@"[harness] pinned more takes the touch: %@", NSStringFromClass(hit.class));
        // The wash over the hero: its gradient concealed and its own black taken off, so the picture shows
        // through whether the Mix feature raised its alpha or not.
        NSLog(@"[harness] the plane's second wash: a=%.2f, paint a=%.0f, gradient %@", mixWash.alpha,
              mixWash.layer.backgroundColor ? CGColorGetAlpha(mixWash.layer.backgroundColor) : 0,
              mixGradient.layer.mask ? @"masked" : @"DRAWN");
        // The creator line: a tap on the name, nowhere else.
        UIView *info = nil;
        for (UIView *v = block; v; v = nil) {
            for (UIView *sub in v.subviews) if ([NSStringFromClass(sub.class) isEqualToString:@"SGRHeaderInfo"]) info = sub;
        }
        UIView *name = nil;
        for (UIView *sub in info.subviews) {
            if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:@"The Weeknd"]) name = sub;
        }
        UIView *onName = [info hitTest:CGPointMake(CGRectGetMidX(name.bounds) + name.frame.origin.x, CGRectGetMidY(name.frame)) withEvent:nil];
        UIView *besideName = [info hitTest:CGPointMake(24, CGRectGetMidY(name.frame)) withEvent:nil];
        NSLog(@"[harness] creator line: on the name %@, beside it %@", onName ? NSStringFromClass(onName.class) : @"through",
              besideName ? NSStringFromClass(besideName.class) : @"through");
        for (UIGestureRecognizer *tap in name.gestureRecognizers) {
            [tap.view.superview performSelector:NSSelectorFromString(@"sgr_creatorTapped")];
        }
        // The list asks every cell how tall it wants to be, which is where the curation row answers 0 and
        // closes up: the harness's list is a plain scroll view, so it asks the way ListLayout does.
        if (handover) {
            UICollectionViewLayoutAttributes *wanted = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:
                                                        [NSIndexPath indexPathForItem:0 inSection:0]];
            wanted.frame = curation.frame;
            CGSize answered = [(UICollectionViewCell *)curation preferredLayoutAttributesFittingAttributes:wanted].size;
            curation.frame = CGRectMake(0, curation.frame.origin.y, answered.width, answered.height);
            NSLog(@"[harness] the curation row answered %.0fpt tall", answered.height);
        }
    });

    // The ⋯ sheet: tapping the pinned button records the page, and the menu that opens a moment later takes
    // Sort and Mix into its table's header (issue #53). Then Sort is tapped, which has to fire Spotify's own
    // pill even though its cell is closed up to nothing.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIControl *pinnedMore = nil;
        for (UIView *sub in page.view.subviews) {
            if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) pinnedMore = (UIControl *)sub;
        }
        [pinnedMore sendActionsForControlEvents:UIControlEventTouchDown];
        [pinnedMore sendActionsForControlEvents:UIControlEventTouchUpInside];
        _TtC24ContextMenu_InternalImpl25ContextMenuViewController *menu =
            [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
        [page presentViewController:menu animated:NO completion:^{
            [menu.view setNeedsLayout];
            [menu.view layoutIfNeeded];
            [menu.table layoutIfNeeded];
            UIView *block = menu.table.tableHeaderView;
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (UIView *row in block.subviews) {
                if (!row.hidden) [rows addObject:[NSString stringWithFormat:@"%@ %@", row.accessibilityLabel,
                                                  NSStringFromCGRect(row.frame)]];
            }
            NSLog(@"[harness] the sheet's header is %@ %.0fpt: %@ (handover %d)",
                  block ? NSStringFromClass(block.class) : @"MISSING", block.bounds.size.height,
                  [rows componentsJoinedByString:@", "], handover);
            for (UIView *row in block.subviews) {
                if (!row.hidden) [(UIControl *)row sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        }];
    });

    // Spotify lays the column and the action row out again after the header's pass: their children go back
    // where its own layout put them, and the redesign has to take them again from its own watch on each.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSArray<NSValue *> *columnFrames = @[[NSValue valueWithCGRect:CGRectMake(0, 0, columnWidth, 29.67)],
                                             [NSValue valueWithCGRect:CGRectMake(0, 33.67, columnWidth, 31.33)],
                                             [NSValue valueWithCGRect:CGRectMake(0, 69, columnWidth, 34)],
                                             [NSValue valueWithCGRect:CGRectMake(0, 107, columnWidth, 15.33)]];
        for (NSUInteger i = 0; i < columnFrames.count && i < column.subviews.count; i++) {
            column.subviews[i].frame = columnFrames[i].CGRectValue;
        }
        shuffleView.frame = CGRectMake(20, 0, 48, 48);
        for (NSUInteger i = 0; i < actions.subviews.count; i++) {
            actions.subviews[i].frame = CGRectMake(i * 48, i == 0 ? 4 : 0, i == 0 ? 58 : 48, i == 0 ? 40 : 48);
        }
        [column setNeedsLayout];
        [actions setNeedsLayout];
        NSLog(@"[harness] Spotify's own frames put back");
    });

    // Pressing Play: Spotify reconfigures the header and shows the wash and the play disc again with
    // -setHidden:NO (trees/continuous/1.txt, 2026-09-18). They must stay drawn by nothing.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(17 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gradient.hidden = NO;
        playButton.hidden = NO;
        cover.hidden = NO;
        NSLog(@"[harness] Pressing Play: wash hidden=%d masked=%d, disc hidden=%d masked=%d, cover hidden=%d masked=%d",
              gradient.hidden, gradient.layer.mask != nil, playButton.hidden, playButton.layer.mask != nil,
              cover.hidden, cover.layer.mask != nil);
    });
    return YES;
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
