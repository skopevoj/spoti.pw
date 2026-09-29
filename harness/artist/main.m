// A mock of Spotify's artist page under its own class names and accessibility identifiers, built from
// trees/clean/artist/01.txt and 05.txt (recorded 2026-09-16), so Redesigned/Artist can be laid out and looked
// at on the Mac. `collapsed` on the launch line shows the header scrolled into its 100pt bar; `late` holds
// the Follow button's word and then the photo back, one after the other, the way a page opened for the first
// time gets them -- each has to reach the redesign on its own (issue #52), and the artwork view carries
// Encore's Swift class name so that it can only be watched the way the phone makes the Kit watch it.
// The follow state comes from a mock of Spotify's collection platform under its real class and selector
// names: `none` at once, or in `late` a second in; Following, as saved, after the tap made at 2.5 s.
#import <UIKit/UIKit.h>

#pragma mark - Spotify's classes, by name

@interface _TtC32CreativeWorkPlatform_TemplateKit12TemplateView : UIView @end
@implementation _TtC32CreativeWorkPlatform_TemplateKit12TemplateView @end

@interface _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView : UIView @end
@implementation _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView @end

// TemplateKit's private HeaderContainer; the redesign finds it by the words in its name.
@interface MockTemplateKitHeaderContainer : UIView @end
@implementation MockTemplateKitHeaderContainer @end

@interface _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView : UIView @end
@implementation _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView @end

@interface MockHeaderForegroundView : UIView @end
@implementation MockHeaderForegroundView @end

@interface MockGradientView : UIView @end
@implementation MockGradientView @end

@interface _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView @end

@interface _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton : UIView @end
@implementation _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton @end

// The list's cell. Spotify's sizes itself from its element; the mock answers the height it was built for.
@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell
@property (nonatomic) CGFloat natural;
@end
@implementation _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = [attributes copy];
    result.size = CGSizeMake(attributes.size.width, self.natural);
    return result;
}
@end

@interface MockButton : UIControl @end
@implementation MockButton @end

// The collection platform as 9.1.78 has it: SPTCollectionPlatformState is an option set (saved 1, banned 2,
// none 4), and the provider answers subscribeCollectionStateForURL:completion: with a token to cancel.
@interface SPTCollectionPlatformState : NSObject
@property (nonatomic, readonly) NSInteger rawValue;
@end
@implementation SPTCollectionPlatformState
- (instancetype)initWithRawValue:(NSInteger)raw {
    if ((self = [super init])) _rawValue = raw;
    return self;
}
+ (instancetype)saved { return [[self alloc] initWithRawValue:1]; }
+ (instancetype)banned { return [[self alloc] initWithRawValue:2]; }
+ (instancetype)none { return [[self alloc] initWithRawValue:4]; }
- (BOOL)contains:(SPTCollectionPlatformState *)other { return (_rawValue & other.rawValue) == other.rawValue; }
@end

@interface MockRequestToken : NSObject
@property (nonatomic, copy) void (^onCancel)(void);
@end
@implementation MockRequestToken
- (void)cancel {
    NSLog(@"[harness] collection subscription cancelled");
    if (self.onCancel) self.onCancel();
}
@end

@interface _TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl : NSObject
@property (nonatomic) NSInteger raw;
@property (nonatomic, strong) NSMutableArray *subscribers;
- (void)push:(NSInteger)raw;
@end
@implementation _TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl
- (id)subscribeCollectionStateForURL:(NSURL *)url completion:(void (^)(SPTCollectionPlatformState *, NSError *))completion {
    if (!self.subscribers) self.subscribers = [NSMutableArray array];
    void (^copied)(SPTCollectionPlatformState *, NSError *) = [completion copy];
    [self.subscribers addObject:copied];
    NSLog(@"[harness] subscribed for %@", url);
    if (self.raw) completion([[SPTCollectionPlatformState alloc] initWithRawValue:self.raw], nil);
    MockRequestToken *token = [MockRequestToken new];
    __weak typeof(self) weakSelf = self;
    token.onCancel = ^{ [weakSelf.subscribers removeObject:copied]; };
    return token;
}
// As the collection does it: off the main thread.
- (void)push:(NSInteger)raw {
    self.raw = raw;
    for (void (^completion)(SPTCollectionPlatformState *, NSError *) in [self.subscribers copy]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            completion([[SPTCollectionPlatformState alloc] initWithRawValue:raw], nil);
        });
    }
}
@end
typedef _TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl MockStateProvider;

@interface SPTCollectionPlatformImplementation : NSObject
@property (nonatomic, strong) MockStateProvider *stateProvider;
@end
@implementation SPTCollectionPlatformImplementation @end

static SPTCollectionPlatformImplementation *sgh_platform;

// The page's controller, which Spotify's answer spt_pageURI with the artist's URI.
@interface MockArtistPageController : UIViewController @end
@implementation MockArtistPageController
- (NSURL *)spt_pageURI { return [NSURL URLWithString:@"spotify:artist:7n2wHs1TKAczGzO7Dd2rGr"]; }
@end

// Encore's image view, the one every picture Spotify loads arrives in (01.txt:48). Its name is the point of
// the mock: a Swift one, which the Kit refuses to give an instance its own subclass of, so the harness
// watches the photo the way the phone has to -- through an override on the class.
@interface _TtC19LegacyUI_ECMCoreKitP33_3DFE6A8953CA91BDEBA7A38450631F5815EncoreImageView : UIImageView @end
@implementation _TtC19LegacyUI_ECMCoreKitP33_3DFE6A8953CA91BDEBA7A38450631F5815EncoreImageView @end

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
    inner.font = [UIFont boldSystemFontOfSize:size];
    inner.textColor = color;
    inner.accessibilityIdentifier = [identifier stringByAppendingString:@"-internal"];
    [encore addSubview:inner];
    return inner;
}

// A portrait: warm light from the top left over a dark ground, a head and shoulders.
static UIImage *photo(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(213, 213)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat components[] = {0.78, 0.52, 0.38, 1, 0.18, 0.12, 0.14, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(213, 213), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithRed:0.35 green:0.24 blue:0.22 alpha:1] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(72, 40, 70, 84)] fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(36, 128, 142, 120) cornerRadius:50] fill];
    }];
}

static UIImageView *glyph(UIView *button, NSString *symbol, CGFloat inset) {
    UIImageView *image = [[UIImageView alloc] initWithFrame:CGRectInset(button.bounds, inset, inset)];
    image.image = [UIImage systemImageNamed:symbol];
    image.tintColor = UIColor.whiteColor;
    [button addSubview:image];
    return image;
}

#pragma mark - the list

// What each cell of the Music list holds, top to bottom (05.txt): its identifier and its height.
static NSArray<NSArray *> *musicList(void) {
    NSMutableArray *items = [NSMutableArray array];
    void (^section)(NSString *, NSArray *) = ^(NSString *heading, NSArray *content) {
        [items addObject:@[@"", @16]];
        [items addObject:@[@"Components.UI.SectionHeadingHome", @36.67, heading]];
        [items addObjectsFromArray:content];
    };
    NSArray *tracks = @[@[@"Components.UI.RetrievalRowElementUI", @64, @"Stitches"], @[@"Components.UI.RetrievalRowElementUI", @64, @"Treat You Better"],
                        @[@"Components.UI.RetrievalRowElementUI", @64, @"Mercy"], @[@"Components.UI.RetrievalRowElementUI", @64, @"There's Nothing Holdin' Me Back"]];
    [items addObject:@[@"Components.UI.SectionHeadingHome", @36.67, @"Popular"]];
    [items addObjectsFromArray:tracks];
    section(@"Artist pick", @[@[@"Components.UI.PinnedItemUI", @120]]);
    section(@"Popular Releases", @[@[@"Components.UI.RetrievalRowElementUI", @104, @"Shawn"], @[@"Components.UI.RetrievalRowElementUI", @104, @"Wonder"]]);
    section(@"Music videos", @[@[@"Components.UI.MusicVideoShelfHeader", @224]]);
    section(@"Watch more from Shawn Mendes", @[@[@"WatchFeedCarouselEntryPointElement", @208]]);
    section(@"About", @[@[@"Components.UI.CreatorBiographyCard", @180]]);
    section(@"Fans Also Like", @[@[@"Components.UI.HomeCard", @178]]);
    return items;
}

@interface SGRListSource : NSObject <UICollectionViewDataSource>
@property (nonatomic, copy) NSArray<NSArray *> *items;
@end

@implementation SGRListSource
- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    _TtC12Element_List18CollectionViewCell *cell = [view dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:path];
    for (UIView *old in cell.contentView.subviews) [old removeFromSuperview];
    NSArray *item = self.items[path.item];
    NSString *kind = item[0];
    CGFloat height = [item[1] doubleValue];
    cell.natural = height;
    // Left unpainted: on the phone the repaint hook clears the base surface, which the harness does not compile.
    cell.backgroundColor = UIColor.clearColor;
    UIView *content = box(cell.contentView, UIView.class, CGRectMake(0, 0, view.bounds.size.width, height), nil);
    if (!kind.length) return cell;
    UIView *element = box(content, UIView.class, content.bounds, kind);
    CGFloat W = view.bounds.size.width;
    if ([kind isEqualToString:@"Components.UI.SectionHeadingHome"]) {
        label(element, CGRectMake(16, 8, W - 32, 22), item[2], 19, UIColor.whiteColor, @"Encore.Label");
    } else if ([kind isEqualToString:@"Components.UI.RetrievalRowElementUI"]) {
        UIView *art = box(element, UIView.class, CGRectMake(16, 8, height - 16, height - 16), nil);
        art.backgroundColor = [UIColor colorWithRed:0.45 green:0.35 blue:0.30 alpha:1];
        art.layer.cornerRadius = 4;
        label(element, CGRectMake(height + 8, height / 2 - 18, W - height - 40, 18), item[2], 14, UIColor.whiteColor, @"EncoreConsumerMobile.View.Granular.Title");
        UILabel *sub = label(element, CGRectMake(height + 8, height / 2 + 2, W - height - 40, 16), @"Shawn Mendes", 12,
                             [UIColor colorWithWhite:1 alpha:0.6], @"EncoreConsumerMobile.View.Granular.Subtitle");
        sub.font = [UIFont systemFontOfSize:12];
    } else if ([kind isEqualToString:@"Components.UI.HomeCard"]) {
        // A carousel: its own collection painted the AMOLED black, and a page-wide fade, as on the phone.
        element.backgroundColor = UIColor.blackColor;
        UIView *fade = box(element, MockGradientView.class, element.bounds, nil);
        fade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
        UICollectionViewCell *card = [[UICollectionViewCell alloc] initWithFrame:CGRectMake(16, 4, 153, height - 8)];
        card.backgroundColor = UIColor.blackColor;
        [element addSubview:card];
    } else {
        UIView *card = box(element, UIView.class, CGRectMake(16, 4, W - 32, height - 8), nil);
        card.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
        card.layer.cornerRadius = 8;
        label(card, CGRectMake(12, 12, W - 60, 18), [kind componentsSeparatedByString:@"."].lastObject, 13,
              [UIColor colorWithWhite:1 alpha:0.7], @"Encore.Label");
    }
    return cell;
}
@end

#pragma mark - the page

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) SGRListSource *source;
@end

@implementation SGRHarnessDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    CGFloat W = self.window.bounds.size.width, H = self.window.bounds.size.height;
    BOOL collapsed = [NSProcessInfo.processInfo.arguments containsObject:@"collapsed"];
    BOOL late = [NSProcessInfo.processInfo.arguments containsObject:@"late"];
    sgh_platform = [SPTCollectionPlatformImplementation new];
    sgh_platform.stateProvider = [MockStateProvider new];
    if (!late) sgh_platform.stateProvider.raw = 4;
    // Some part of Spotify reaches for the provider before the page does.
    (void)sgh_platform.stateProvider;

    UIViewController *root = [MockArtistPageController new];
    root.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:1];
    self.window.rootViewController = root;

    UIView *page = box(root.view, _TtC32CreativeWorkPlatform_TemplateKit12TemplateView.class, CGRectMake(0, 0, W, H), @"creator-page");
    UIScrollView *scroll = (UIScrollView *)box(page, UIScrollView.class, page.bounds, @"PCFFTabLayoutViewController.containerScrollView");
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    UIView *stack = box(scroll, UIView.class, CGRectMake(0, 0, W, 3000), nil);

    // the header, 568pt with the headline
    UIView *container = box(stack, MockTemplateKitHeaderContainer.class, CGRectMake(0, 0, W, 568), nil);
    UIView *element = box(container, UIView.class, collapsed ? CGRectMake(0, 468, W, 100) : container.bounds, nil);
    UIView *header = box(element, _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView.class, element.bounds, nil);

    UIView *clip = box(header, UIView.class, CGRectMake(0, 0, W, collapsed ? 0 : 424.67), nil);
    clip.clipsToBounds = YES;
    UIView *artwork = box(clip, UIView.class, CGRectMake(-11.33, 0, 424.67, 424.67), @"Components.Header.UI.ArtworkImage");
    UIImageView *picture = [[_TtC19LegacyUI_ECMCoreKitP33_3DFE6A8953CA91BDEBA7A38450631F5815EncoreImageView alloc]
                            initWithFrame:artwork.bounds];
    if (!late) picture.image = photo();
    picture.accessibilityIdentifier = @"Components.Header.UI.ArtworkImage.ImageView";
    [artwork addSubview:picture];
    UIView *wash = box(clip, MockGradientView.class, CGRectMake(-11.33, 310.67, 424.67, 257.33), nil);
    wash.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];

    UIView *titleBox = box(header, UIView.class, CGRectMake(16, 334.67, 370, 54), nil);
    label(titleBox, CGRectMake(0, 0, 370, 54), @"Shawn Mendes", 45, UIColor.whiteColor, @"Encore.AdaptiveTitle");
    UIView *badge = box(header, UIStackView.class, CGRectMake(16, 390.67, 114.67, 24), @"ImageHeaderView.VerifiedBadge");
    label(badge, CGRectMake(20, 4, 94, 15), @"Verified by Spotify", 11, UIColor.whiteColor, @"Encore.Label");
    UIView *meta = box(header, UIView.class, CGRectMake(16, 432.67, 370, 15.33), nil);
    label(meta, CGRectMake(0, 0, 314, 15.33), @"58,4M monthly listeners", 11, [UIColor colorWithWhite:1 alpha:0.7],
          @"Components.Header.UI.Metadata");

    UIView *row = box(header, UIStackView.class, CGRectMake(4, 456, 394, 48), nil);
    UIView *follow = box(row, MockButton.class, CGRectMake(70, 8, 66, 32), @"Curation.FollowButtonElementKit.FollowButton");
    follow.accessibilityLabel = @"Follow";
    follow.layer.borderColor = UIColor.grayColor.CGColor;
    follow.layer.borderWidth = 1;
    follow.layer.cornerRadius = 16;
    UILabel *followWord = label(follow, CGRectMake(16, 8, 40, 16), late ? @"" : @"Follow", 11, UIColor.whiteColor, @"Encore.Label");
    if (late) follow.accessibilityLabel = nil;
    [(UIControl *)follow addTarget:self action:@selector(toggleFollow:) forControlEvents:UIControlEventTouchUpInside];
    glyph(box(row, MockButton.class, CGRectMake(148, 0, 48, 48), @"Components.UI.ContextMenuButton-7n2wHs1TKAczGzO7Dd2rGr"), @"ellipsis", 12);
    glyph(box(row, MockButton.class, CGRectMake(278, 0, 48, 48), @"Components.UI.ShuffleButton"), @"shuffle", 12);
    UIView *play = box(row, _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView.class, CGRectMake(334, 0, 48, 48), @"header-play-button");
    UIControl *condensed = (UIControl *)box(play, MockButton.class, play.bounds, nil);
    condensed.accessibilityLabel = @"Play";
    UIImageView *disc = glyph(condensed, @"play.fill", 0);
    disc.contentMode = UIViewContentModeCenter;
    disc.backgroundColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
    disc.layer.cornerRadius = 24;
    disc.clipsToBounds = YES;

    UIView *headline = box(header, UIStackView.class, CGRectMake(0, 504, W, 64), nil);
    UIView *banner = box(headline, UIView.class, CGRectMake(16, 16, W - 32, 40), @"Components.UI.ArtistHeadline");
    banner.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    label(banner, CGRectMake(40, 12, 280, 16), @"Pre-save the upcoming album", 11, UIColor.whiteColor, @"Encore.Label");

    UIView *foreground = box(header, MockHeaderForegroundView.class, CGRectMake(0, 0, W, 0), nil);
    UIView *bar = box(foreground, UIView.class, CGRectMake(0, 0, W, 100), nil);
    bar.hidden = !collapsed;
    UIView *barGradient = box(bar, MockGradientView.class, bar.bounds, nil);
    barGradient.backgroundColor = [UIColor colorWithWhite:0.03 alpha:1];
    UILabel *barName = label(bar, CGRectMake(80, 62, 242, 20), @"Shawn Mendes", 13, UIColor.whiteColor, @"Encore.Label");
    barName.textAlignment = NSTextAlignmentCenter;

    // the tabs and, under them, the Music list
    UIView *tabs = box(stack, UIView.class, CGRectMake(0, 568, W, 2400), @"PCFFTabLayoutViewController.tabsViewAccessibilityID");
    UIView *strip = box(tabs, UIView.class, CGRectMake(0, 0, W, 44), @"Components.UI.TabsSectionHeading");
    for (int i = 0; i < 3; i++) {
        UIView *tab = box(strip, _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton.class,
                          CGRectMake(16 + i * 64, 6, 56, 32), nil);
        label(tab, tab.bounds, @[@"Music", @"Video", @"Merch"][i], 13, UIColor.whiteColor, @"Encore.Label");
    }
    UIScrollView *pages = (UIScrollView *)box(tabs, UIScrollView.class, CGRectMake(0, 44, W, 2356), nil);
    UIView *listView = box(pages, _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView.class, pages.bounds, nil);
    listView.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:1];
    UICollectionViewFlowLayout *flow = [UICollectionViewFlowLayout new];
    flow.minimumLineSpacing = 0;
    flow.estimatedItemSize = CGSizeMake(W, 60);
    UICollectionView *list = [[UICollectionView alloc] initWithFrame:listView.bounds collectionViewLayout:flow];
    list.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:1];
    list.scrollEnabled = NO;
    [list registerClass:_TtC12Element_List18CollectionViewCell.class forCellWithReuseIdentifier:@"cell"];
    self.source = [SGRListSource new];
    self.source.items = musicList();
    list.dataSource = self.source;
    [listView addSubview:list];
    scroll.contentSize = CGSizeMake(W, 3000);
    if (collapsed) scroll.contentOffset = CGPointMake(0, 468);

    [self.window makeKeyAndVisible];

    // What the redesign's Follow draws: nothing before the state, then the glyph for it. A tap on it at
    // 2.5 s, which Spotify answers with Following.
    for (NSNumber *when in @[@0.5, @1.5, @2.5, @3.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(when.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSMutableArray *lines = [NSMutableArray array];
            UIControl *tapped = nil;
            NSMutableArray *queue = [NSMutableArray arrayWithObject:container];
            while (queue.count) {
                UIView *v = queue.firstObject;
                [queue removeObjectAtIndex:0];
                [queue addObjectsFromArray:v.subviews];
                if (![NSStringFromClass(v.class) isEqualToString:@"SGRMirrorButton"] || v.frame.origin.x < 200) continue;
                tapped = (UIControl *)v;
                NSMutableArray *drawn = [NSMutableArray array];
                for (UIView *sub in v.subviews) {
                    if (sub.hidden || sub.alpha < 0.01) continue;
                    NSString *what = NSStringFromClass(sub.class);
                    if ([sub isKindOfClass:UILabel.class]) what = [NSString stringWithFormat:@"\"%@\"", ((UILabel *)sub).text];
                    else if ([sub isKindOfClass:UIImageView.class]) {
                        NSString *symbol = [((UIImageView *)sub).image.description componentsSeparatedByString:@"symbol(system: "].lastObject;
                        what = [NSString stringWithFormat:@"%@ in %@", [symbol componentsSeparatedByString:@")"].firstObject,
                                ((UIImageView *)sub).tintColor];
                    }
                    [drawn addObject:what];
                }
                [lines addObject:[NSString stringWithFormat:@"%@ touches %d a11y \"%@\" draws %@", NSStringFromCGRect(v.frame),
                                  v.userInteractionEnabled, v.accessibilityLabel, [drawn componentsJoinedByString:@", "]]];
            }
            NSLog(@"[harness] follow at %.1fs: %@", when.doubleValue, [lines componentsJoinedByString:@" | "]);
            if (when.doubleValue == 2.5) [tapped sendActionsForControlEvents:UIControlEventTouchUpInside];
        });
    }

    // The photo and the follow state land after the header has laid out, and neither lays it out again.
    if (late) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            followWord.text = @"Follow";
            follow.accessibilityLabel = @"Follow";
            [sgh_platform.stateProvider push:4];
            NSLog(@"[harness] late: the follow state is in Spotify's collection now");
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            picture.image = photo();
            NSLog(@"[harness] late: the photo is in Spotify's header now");
        });
    }

    // What the Music list came to once every cell answered for itself and the dropped headings were asked
    // again: each cell's kind and height, top to bottom.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSMutableArray *lines = [NSMutableArray array];
        for (NSUInteger i = 0; i < self.source.items.count; i++) {
            UICollectionViewLayoutAttributes *a = [list layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
            NSArray *item = self.source.items[i];
            NSString *name = item.count > 2 ? item[2] : [item[0] length] ? [item[0] componentsSeparatedByString:@"."].lastObject : @"spacer";
            [lines addObject:[NSString stringWithFormat:@"%@ %.0f", name, a.size.height]];
        }
        NSLog(@"[harness] Music list: %@", [lines componentsJoinedByString:@" | "]);
        UICollectionViewCell *carousel = (UICollectionViewCell *)[list cellForItemAtIndexPath:[NSIndexPath indexPathForItem:self.source.items.count - 1 inSection:0]];
        UIView *band = carousel.contentView.subviews.firstObject.subviews.firstObject;
        UIView *fade = band.subviews.firstObject;
        UIView *card = band.subviews.lastObject;
        NSLog(@"[harness] carousel bg %@, fade masked %d, card bg %@", band.backgroundColor, fade.layer.mask != nil, card.backgroundColor);
        NSLog(@"[harness] strip a=%.2f, pages moved %.0f, list bg %@", strip.alpha, pages.transform.ty, list.backgroundColor);
        // ⋯ is pinned to the page now, not to the header's container, so it holds its place as the page
        // scrolls and the header collapses (issue #57), and it is the back button's 44pt glass.
        UIView *pinned = nil;
        for (UIView *sub in page.subviews) {
            if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) pinned = sub;
        }
        NSLog(@"[harness] pinned more: %@ on the page, a=%.2f",
              pinned ? NSStringFromCGRect(pinned.frame) : @"MISSING", pinned.alpha);
    });
    return YES;
}

// Spotify's Follow turns into Following, which the redesign's word has to follow.
- (void)toggleFollow:(UIControl *)follow {
    UILabel *word = nil;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:follow];
    while (queue.count && !word) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:UILabel.class]) word = (UILabel *)v;
        [queue addObjectsFromArray:v.subviews];
    }
    word.text = [word.text isEqualToString:@"Follow"] ? @"Following" : @"Follow";
    follow.accessibilityLabel = word.text;
    [sgh_platform.stateProvider push:[word.text isEqualToString:@"Following"] ? 1 : 4];
    NSLog(@"[harness] Spotify's Follow fired, now \"%@\"", word.text);
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
