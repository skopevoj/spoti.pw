// Tab bar: Spotify's own bar stays where it is but goes invisible, and a system UITabBar sits on top
// of it. On iOS 26+ with UIDesignRequiresCompatibility off, UIKit draws that bar as real Liquid Glass
// (selection bubble, lensing, light/dark adaptation) with no glass API of ours. Spotify's bar keeps
// its frame, so the page insets and the now playing bar stay where Spotify puts them; where the system
// bar is taller than Spotify's, Spotify is made to leave it the room (see "room for the glass bar").
//
// A tab picked on the system bar is passed on as a tap on the hidden Spotify item it mirrors, and the
// system bar's selection follows whichever Spotify label is painted white, or a tab of the mod's own
// while the page it opened is on the stack. Navbar.x composes the hidden row, so its order, hidden tabs
// and tabs of the mod's own carry over. Always on in the redesign.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView of
//   ElementContentView<TabBarItemElement>, each with an SPTEncoreIconView and an SPTEncoreLabel.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Settings/SGPage.h"
#import "Headers/SPTEncoreIconView.h"
#import "Shared/Player/PlayerState.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import <objc/message.h>

static char kBarKey, kHostKey;
static __weak UIView *sg_stockBar;
static CGFloat sg_room, sg_glassHeight;   // see "room for the glass bar"
static BOOL sg_inline;                     // see "the tab bar with the mini player"

@interface SGRSystemTabBar : UITabBar <UITabBarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *stockBar;
@property (nonatomic, copy) NSArray<UIView *> *sources;
@property (nonatomic, weak) UILongPressGestureRecognizer *hold;
@property (nonatomic) BOOL holding;
@end

static void syncBar(UIView *stockBar);

#pragma mark - reading Spotify's items

// The items the bar shows, left to right as Navbar/Navbar.x placed them.
static NSArray<UIView *> *tabItems(UIView *tabBar) {
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *item in SGRowIn(tabBar).arrangedSubviews) {
        if (!item.hidden && item.bounds.size.width >= 20) [items addObject:item];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(SGFrameIn(a, tabBar).origin.x) compare:@(SGFrameIn(b, tabBar).origin.x)];
    }];
}

// Navbar.x never reorders Spotify's row and appends the mod's own tabs after it, so Home stays first.
static BOOL isHome(UIView *item, UIView *tabBar) {
    return item && item == SGRowIn(tabBar).arrangedSubviews.firstObject;
}

static UILabel *labelIn(UIView *item) {
    __block UILabel *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = (UILabel *)v;
    });
    return label;
}

static UIView *iconIn(UIView *item) {
    __block UIView *icon = nil;
    SGForEachView(item, ^(UIView *v) {
        if (icon || v.bounds.size.width < 2) return;
        if ([v isKindOfClass:UIImageView.class] || [NSStringFromClass(v.class) containsString:@"IconView"]) icon = v;
    });
    return icon;
}

// Spotify paints the selected tab's label white and the rest #B3B3B3.
static BOOL isActive(UIView *item) {
    UIColor *color = labelIn(item).textColor;
    CGFloat white = 0, alpha = 0, r, g, b;
    if (![color getWhite:&white alpha:&alpha] && [color getRed:&r green:&g blue:&b alpha:&alpha]) white = MIN(r, MIN(g, b));
    return white > 0.95;
}

static BOOL hasInk(UIImage *image) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    if (!width || !height) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(context);
    const uint8_t *alpha = pixels.bytes;
    for (size_t i = 0; i < pixels.length; i++) if (alpha[i] > 16) return YES;
    return NO;
}

static UIImage *renderLayer(CALayer *layer, CGSize size) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [layer renderInContext:context.CGContext];
    }];
    return hasInk(image) ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

// The SPTEncoreIcon an icon view was built with. Encore keeps it in a Swift ivar with no getter.
static id encoreIconOf(UIView *view) {
    Ivar ivar = class_getInstanceVariable(view.class, "icon");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(view, ivar) : nil;
}

// Encore draws a tab's icon from one SPTEncoreIcon in two states: isActive picks its filled variant.
// Both are drawn on an icon view of our own, off screen, so the images do not wait for Spotify's
// views to lay out and paint, and UITabBar swaps image and selectedImage itself.
static UIImage *glyphOf(UIView *item, BOOL active) {
    UIView *live = iconIn(item);
    if (!live) return nil;
    CGSize size = live.bounds.size;
    id icon = encoreIconOf(live);
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    if (icon && viewClass) {
        static NSCache<NSString *, UIImage *> *cache;
        if (!cache) cache = [NSCache new];
        NSString *key = [NSString stringWithFormat:@"%@ %d %@", [icon respondsToSelector:@selector(name)] ? [icon name] : icon, active, NSStringFromCGSize(size)];
        UIImage *cached = [cache objectForKey:key];
        if (cached) return cached;
        SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
        view.frame = (CGRect){CGPointZero, size};
        [view setForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
        [view layoutIfNeeded];
        UIImage *image = renderLayer(view.layer, size);
        if (image) {
            [cache setObject:image forKey:key];
            return image;
        }
    }
    // Tabs of the mod's own draw a UIImageView, or an icon Encore would not draw off screen.
    return size.width >= 2 ? renderLayer(live.layer, size) : nil;
}

#pragma mark - passing a tap on

// NavigationUI_TabBarImpl's TabBarItemElementUI answers a tap recognizer (-handleTap), so the tap is
// replayed through the recognizer's own target-action pairs, the same call a real touch ends in.
BOOL SGRFireTapRecognizers(UIView *view) {
    Ivar targetsIvar = class_getInstanceVariable(UIGestureRecognizer.class, "_targets");
    if (!targetsIvar) return NO;
    BOOL fired = NO;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:UITapGestureRecognizer.class] || !recognizer.enabled) continue;
        for (id pair in object_getIvar(recognizer, targetsIvar)) {
            Ivar targetIvar = class_getInstanceVariable([pair class], "_target");
            Ivar actionIvar = class_getInstanceVariable([pair class], "_action");
            if (!targetIvar || !actionIvar) continue;
            id target = object_getIvar(pair, targetIvar);
            SEL action = *(SEL *)((char *)(__bridge void *)pair + ivar_getOffset(actionIvar));
            if (!target || !action || ![target respondsToSelector:action]) continue;
            SGLog(@"tab bar: tap -> %@ %@", NSStringFromClass([target class]), NSStringFromSelector(action));
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, recognizer);
            fired = YES;
        }
    }
    return fired;
}

static void forwardTap(UIView *item) {
    __block BOOL sent = NO;
    SGForEachView(item, ^(UIView *v) {
        if (!sent) sent = SGRFireTapRecognizers(v);
    });
    SGForEachView(item, ^(UIView *v) {
        if (sent || ![v isKindOfClass:UIControl.class]) return;
        SGLog(@"tab bar: tap -> control %@", NSStringFromClass(v.class));
        [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        sent = YES;
    });
    if (!sent) {
        NSMutableString *out = [NSMutableString stringWithFormat:@"tab bar: nothing to tap in %@", NSStringFromClass(item.class)];
        SGForEachView(item, ^(UIView *v) {
            for (UIGestureRecognizer *r in v.gestureRecognizers) [out appendFormat:@"\n  %@ on %@", r, NSStringFromClass(v.class)];
        });
        SGLogLong(@"navbar", out);
    }
}

static UITabBarItem *itemAtPoint(UITabBar *bar, CGPoint point) {
    __block UITabBarItem *nearest = nil;
    __block CGFloat best = CGFLOAT_MAX;
    SGForEachView(bar, ^(UIView *v) {
        BOOL label = [v isKindOfClass:UILabel.class], glyph = [v isKindOfClass:UIImageView.class];
        if ((!label && !glyph) || v.bounds.size.width < 1) return;
        CGFloat distance = fabs([v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), 0) toView:bar].x - point.x);
        if (distance >= best) return;
        for (UITabBarItem *item in bar.items) {
            UIImage *image = glyph ? ((UIImageView *)v).image : nil;
            if (label ? ![((UILabel *)v).text isEqualToString:item.title] : !image || (image != item.image && image != item.selectedImage)) continue;
            best = distance;
            nearest = item;
            break;
        }
    });
    return nearest;
}

#pragma mark - the system bar

@implementation SGRSystemTabBar

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    NSUInteger index = [self.items indexOfObject:item];
    if (index == NSNotFound || index >= self.sources.count) return;
    SGRTabPicked(self.sources[index]);
    // Home tapped while on Home pops Spotify's stack, which would take Mod Settings straight off it.
    if (!self.holding) forwardTap(self.sources[index]);
    // Spotify repaints its labels a moment later; a tap it did not take snaps the selection back.
    UIView *stockBar = self.stockBar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (stockBar) syncBar(stockBar);
    });
}

// UIKit's item views are private, so the item under a touch is the one whose title label or glyph is
// nearest. With the labels hidden only the glyph is left; UIKit shows the item's own image instance.
- (UITabBarItem *)itemAt:(CGPoint)point {
    return itemAtPoint(self, point);
}

// UIView asks itself this for its own recognizers too, so only the hold is answered here.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != self.hold) return [super gestureRecognizerShouldBegin:recognizer];
    NSUInteger index = [self.items indexOfObject:[self itemAt:[recognizer locationInView:self]]];
    return index < self.sources.count && isHome(self.sources[index], self.stockBar);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) {
        self.holding = YES;
        SGOpenModSettings(self);
    } else if (hold.state != UIGestureRecognizerStateChanged) {
        // The bar may still pick Home as the finger lifts, after this.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            weakSelf.holding = NO;
        });
    }
}

@end

// The system bar's own view in Spotify's bar. UIKit measures the system bar and lays it out by the safe
// area of the view it stands in, and the room made under Spotify's bar is not the phone's: on a phone
// with a home button it went under the platter as well, squeezing it to 49 pt. So this view hands the
// bar the safe area without the room.
//
// It also draws the fade over the pages behind the bars. Spotify darkens whatever scrolls under its bar
// with a TabBarGradientView reaching 112 pt above the bar's top (trees/continuous/5.txt:2200), but that
// sits in the compact view hidden above, so it went with it: only the field behind a page (Kit/SGRField.h)
// faded to black, and the rows, covers and text over it ran on bright under the now playing bar and the
// glass. The fade stands under the glass bar, so it moves and goes away with the bar.
static const CGFloat kFadeRise = 112;
static const NSUInteger kFadeStops = 7;
static const CGFloat kFadeDepth = 0.5;

@interface SGRTabBarHost : UIView
@end

@implementation SGRTabBarHost {
    CAGradientLayer *_fade;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _fade = [CAGradientLayer layer];
    NSNull *off = NSNull.null;
    _fade.actions = @{@"bounds": off, @"position": off, @"frame": off};
    // Clear to half black on a smoothstep, so there is no edge where it starts.
    NSMutableArray *colors = [NSMutableArray array], *locations = [NSMutableArray array];
    for (NSUInteger i = 0; i < kFadeStops; i++) {
        CGFloat t = (CGFloat)i / (kFadeStops - 1);
        [colors addObject:(id)[UIColor colorWithWhite:0 alpha:kFadeDepth * t * t * (3 - 2 * t)].CGColor];
        [locations addObject:@(t)];
    }
    _fade.colors = colors;
    _fade.locations = locations;
    [self.layer insertSublayer:_fade atIndex:0];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGRect fade = CGRectMake(0, -kFadeRise, bounds.size.width, bounds.size.height + kFadeRise);
    if (!CGRectEqualToRect(_fade.frame, fade)) _fade.frame = fade;
}

- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = [super safeAreaInsets];
    insets.bottom = MAX(0, insets.bottom - sg_room);
    return insets;
}
@end

@interface SGRHomeHold : UILongPressGestureRecognizer
@end

@implementation SGRHomeHold
+ (void)held:(SGRHomeHold *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) SGOpenModSettings(hold.view);
}
@end

// On Spotify's own bar a hold that begins fails the item's tap recognizer, so Home is not tapped too.
static void holdHome(UIView *stockBar) {
    UIView *home = SGRowIn(stockBar).arrangedSubviews.firstObject;
    if (!home) return;
    for (UIGestureRecognizer *recognizer in home.gestureRecognizers) {
        if ([recognizer isKindOfClass:SGRHomeHold.class]) return;
    }
    [home addGestureRecognizer:[[SGRHomeHold alloc] initWithTarget:SGRHomeHold.class action:@selector(held:)]];
}

static void logBarOnce(UITabBar *bar) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGLogLong(@"navbar", [NSString stringWithFormat:@"system tab bar %@\n%@", NSStringFromCGRect(bar.superview.frame), [bar recursiveDescription]]);
        });
    });
}

#pragma mark - room for the glass bar

// UIKit's glass bar asks for 83 pt, the platter the top 62 of it, over no more safe area than a Face ID
// phone's 34 (simulator, iOS 26.5 and 27). Spotify's bar is its 49 pt row over the bottom safe area of
// TabBarContainerImpl's view: a guide from 49 pt above the safe area's bottom to the view's bottom sets
// its height (its viewDidLoad, 0x100840a2c), the now playing bar stands on that guide's top
// (MainUIContainer's chrome bottom anchor, 0x100ae0178), the bar slides away by the inset plus 49 when
// Spotify hides it (0x1037169a4) and the pages get 49 on top of the inset (0x10707bde4). A Face ID
// phone gives the view 34 and the two bars match. A phone with a home button gives it none, and so does
// Spotify's message bar (LimitedExperienceIndicatorBar: Offline, Private Session) coming in under the
// tab bar, which takes the home indicator's inset for itself: the glass bar stood 34 pt above
// Spotify's, over the now playing bar. So the view gets the rest of the glass bar's height as safe
// area, and Spotify lays its bar, the now playing bar, the pages and the hide out for the glass bar
// itself, and moves them all with the message bar.
static const CGFloat kStockRow = 49;

// UIKit asks for 62 + max(21, inset) on a phone with a home button, max(83, 49 + inset) on a Face ID
// phone, by the safe area of the view the bar stands in. SGRTabBarHost keeps the room out of that; if
// it ever reached the bar again, the bar would ask for more room every pass, so what it asks for with
// no room made is what is kept.
static CGFloat glassHeight(UITabBar *bar, UIView *stockBar) {
    if (sg_room < 0.5 || sg_glassHeight <= 0) sg_glassHeight = [bar sizeThatFits:CGSizeMake(stockBar.bounds.size.width, kStockRow)].height;
    return sg_glassHeight;
}

static UIViewController *containerOf(UIView *stockBar) {
    Class containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    for (UIResponder *r = stockBar.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:containerClass]) return (UIViewController *)r;
    }
    return nil;
}

static void makeRoom(UIViewController *container) {
    UIView *stockBar = sg_stockBar;
    UITabBar *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    if (!bar.window || !container.isViewLoaded || ![stockBar isDescendantOfView:container.view]) return;
    UIEdgeInsets extra = container.additionalSafeAreaInsets;
    CGFloat inset = container.view.safeAreaInsets.bottom - extra.bottom;
    CGFloat height = glassHeight(bar, stockBar);
    // Spotify's regular width bar is a fixed 76 pt that ignores the inset.
    BOOL compact = container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    CGFloat room = compact && !sg_inline ? MAX(0, ceil(height - kStockRow - inset)) : 0;
    if (fabs(extra.bottom - room) < 0.5) return;
    sg_room = extra.bottom = room;
    container.additionalSafeAreaInsets = extra;
    SGLog(@"tab bar: %.0f pt of room made under Spotify's bar for the glass bar's %.0f, over an inset of %.0f", room, height, inset);
}

static void syncInline(UIView *stockBar) API_AVAILABLE(ios(26.0));

static void syncBar(UIView *stockBar) {
    sg_stockBar = stockBar;
    if (sg_inline) {
        if (@available(iOS 26.0, *)) syncInline(stockBar);
        return;
    }

    SGRSystemTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!bar) {
        bar = [[SGRSystemTabBar alloc] initWithFrame:stockBar.bounds];
        // UIKit draws the glass in the appearance the bar inherits, and the bar is outside the navigation
        // stacks Spotify makes dark itself (-[SPNavigationController viewDidLoad] while +[SPTLiquidGlass
        // isEnabled]), so a phone in light mode had it light over Spotify's black. Spotify is dark whatever
        // the system is, and so is the bar.
        bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        bar.delegate = bar;
        bar.stockBar = stockBar;
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:bar action:@selector(held:)];
        hold.delegate = bar;
        [bar addGestureRecognizer:hold];
        bar.hold = hold;
        objc_setAssociatedObject(stockBar, &kBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRTabBarHost *host = [SGRTabBarHost new];
        [host addSubview:bar];
        objc_setAssociatedObject(stockBar, &kHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *accent = SGRAccent();
    if (![bar.tintColor isEqual:accent]) bar.tintColor = accent;
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);

    for (UIView *sub in stockBar.subviews) {
        if (sub == host) continue;
        if (sub.alpha != 0) sub.alpha = 0;
        if (sub.userInteractionEnabled) sub.userInteractionEnabled = NO;
    }
    stockBar.superview.layer.backgroundColor = NULL;

    NSArray<UIView *> *sources = tabItems(stockBar);
    if (!sources.count) return;
    // An item with no title is drawn by UIKit as its glyph alone, centred, on a bar of the same height.
    BOOL hideLabels = SGHidden(SGRKeyNavbarHideLabels);

    if (![sources isEqualToArray:bar.sources]) {
        NSMutableArray<UITabBarItem *> *items = [NSMutableArray array];
        for (UIView *source in sources) [items addObject:[[UITabBarItem alloc] initWithTitle:hideLabels ? nil : labelIn(source).text image:nil tag:items.count]];
        bar.sources = sources;
        [bar setItems:items animated:NO];
        NSMutableString *out = [NSMutableString stringWithString:@"tab bar icons"];
        for (UIView *source in sources) {
            UIView *live = iconIn(source);
            id icon = live ? encoreIconOf(live) : nil;
            id variant = [icon respondsToSelector:NSSelectorFromString(@"active")] ? ((id (*)(id, SEL))objc_msgSend)(icon, NSSelectorFromString(@"active")) : nil;
            [out appendFormat:@"\n  %@: %@ icon %@ active-variant %@ live-isActive %d label-white %d", labelIn(source).text, NSStringFromClass(live.class),
                 [icon respondsToSelector:@selector(name)] ? [icon name] : icon, [variant respondsToSelector:@selector(name)] ? [variant name] : variant,
                 [live respondsToSelector:@selector(isActive)] ? [(SPTEncoreIconView *)live isActive] : -1, isActive(source)];
        }
        SGLogLong(@"navbar", out);
    }

    UITabBarItem *selected = nil;
    UIView *current = SGRCurrentModTab();
    NSUInteger modTab = current ? [sources indexOfObject:current] : NSNotFound;
    BOOL missing = NO;
    for (NSUInteger i = 0; i < sources.count; i++) {
        UITabBarItem *item = bar.items[i];
        if (!item.image) item.image = glyphOf(sources[i], NO);
        if (!item.selectedImage || item.selectedImage == item.image) item.selectedImage = glyphOf(sources[i], YES);
        missing |= !item.image || !item.selectedImage;
        NSString *title = hideLabels ? nil : labelIn(sources[i]).text;
        if (hideLabels ? item.title != nil : title.length && ![title isEqualToString:item.title]) item.title = title;
        if (!selected && (modTab != NSNotFound ? i == modTab : isActive(sources[i]))) selected = item;
    }
    if (selected && bar.selectedItem != selected) bar.selectedItem = selected;
    // An icon view Spotify has not built yet is looked for again shortly, not on the next touch.
    static NSUInteger retries;
    if (missing && retries++ < 40) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            syncBar(stockBar);
        });
    }

    CGRect bounds = stockBar.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = MAX(bounds.size.height, glassHeight(bar, stockBar));
    CGRect frame = CGRectMake(0, CGRectGetMaxY(bounds) - height, width, height);
    if (!CGRectEqualToRect(host.frame, frame)) host.frame = frame;
    if (!CGRectEqualToRect(bar.frame, host.bounds)) bar.frame = host.bounds;
    if (host.superview != stockBar) [stockBar addSubview:host];
    else if (stockBar.subviews.lastObject != host) [stockBar bringSubviewToFront:host];
    logBarOnce(bar);
    makeRoom(containerOf(stockBar));
}

#pragma mark - the tab bar with the mini player

// With the mini player on (SGRKeyInlinePlayer), the glass bar is a UITabBarController's instead, since
// the bottom accessory and minimizing on scroll are the controller's: UIKit then draws the mini player
// above the bar and, scrolled, moves it in between the first tab and the last, all of it its own
// morph. The controller's pages are empty and clear; Spotify's pages stay where they are, under it.
//
// Minimizing needs no private API: UIKit watches the scroll view the selected page names for its
// bottom edge (-setContentScrollView:forEdge:), and the one named is the page of Spotify's in front,
// which need not be inside the controller (checked in the simulator, iOS 26.5, with a real drag).
//
// The controller's view covers TabBarContainerImpl's (SGRInlineHost), since the mini player stands
// above Spotify's bar and a touch outside a view's bounds never reaches it; everything but the bar and
// the accessory is passed through. The controller is not made a child of Spotify's container, whose
// Swift code may count on the children it put there itself, so its appearance calls are made by hand.
// Spotify's bar stays under it, invisible, and so does the room made for the other glass bar: none.


@interface SGRInlinePage : UIViewController
@end

@interface SGRInlineHost : UIView
@property (nonatomic, weak) UITabBarController *tabs;
@end

@interface SGRInlineTabs : UITabBarController <UITabBarControllerDelegate, UIGestureRecognizerDelegate, SGPlayerStateObserver>
@property (nonatomic, weak) UIView *stockBar;
@property (nonatomic, copy) NSArray<UIView *> *sources;
@property (nonatomic, strong) UITabAccessory *accessory API_AVAILABLE(ios(26.0));
@property (nonatomic) BOOL holding;
@property (nonatomic, readonly) BOOL minimized;
// The last touch on the bar went down on the minimized leading tab, and its tap went to the first tab
// while UIKit selects the one under it.
@property (nonatomic) BOOL touchedLead, leadRedirected;
@end

static __weak SGRInlineTabs *sg_inlineTabs;
static __weak SGRInlineHost *sg_inlineHost;
static __weak UIScrollView *sg_pageScroll;

// Names Spotify's page in front to the page UIKit reads it from. UIKit looks the scroll view up when a
// page is selected, not when a page names another one later (simulator: toggling the behaviour or an
// appearance pass on the page do not do it), so the selection goes to another tab and back, unseen.
static BOOL sg_flipping;
static void searchPageScroll(void);

static void nameScrollView(void) {
    SGRInlineTabs *tabs = sg_inlineTabs;
    UIViewController *page = tabs.selectedViewController;
    UIScrollView *scroll = sg_pageScroll;
    if (!page || !scroll.window) return;
    if ([page contentScrollViewForEdge:NSDirectionalRectEdgeBottom] == scroll) return;
    [page setContentScrollView:scroll forEdge:NSDirectionalRectEdgeAll];
    if (sg_flipping || !tabs.viewIfLoaded.window) return;
    if (@available(iOS 26.0, *)) {
        UITab *selected = tabs.selectedTab;
        UITab *other = nil;
        for (UITab *tab in tabs.tabs) if (tab != selected && ![tab isKindOfClass:UISearchTab.class]) { other = tab; break; }
        if (!selected || !other) return;
        SGLog(@"tab bar: reselects %@ so UIKit reads the list", selected.title);
        sg_flipping = YES;
        [UIView performWithoutAnimation:^{
            tabs.selectedTab = other;
            tabs.selectedTab = selected;
        }];
        sg_flipping = NO;
    }
}

@implementation SGRInlinePage
- (void)loadView {
    UIView *view = [UIView new];
    view.backgroundColor = UIColor.clearColor;
    view.userInteractionEnabled = NO;
    self.view = view;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    nameScrollView();
}
@end

@implementation SGRInlineHost
// The bar's own view, anything in it and the accessory take a touch; the rest is Spotify's.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    UITabBar *bar = self.tabs.tabBar;
    // Expanded, the accessory is not inside the bar and UIKit's views around it are not named for it.
    if (@available(iOS 26.0, *)) {
        UIView *mini = self.tabs.bottomAccessory.contentView;
        if (mini && [hit isDescendantOfView:mini]) return hit;
    }
    for (UIView *v = hit; v && v != self; v = v.superview) {
        if (v == bar) return hit == bar ? nil : hit;
        if ([NSStringFromClass(v.class) containsString:@"Accessory"]) return hit;
    }
    return nil;
}
@end


@implementation SGRInlineTabs

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.delegate = self;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if (@available(iOS 26.0, *)) {
        self.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorOnScrollDown;
        self.accessory = [[UITabAccessory alloc] initWithContentView:SGRMakeMiniPlayer()];
        [self.accessory.contentView registerForTraitChanges:@[UITraitTabAccessoryEnvironment.class] withTarget:self action:@selector(minimizedChanged)];
    }
    SGAddPlayerStateObserver(self);
    // Setting the controller up above can load its view, so viewDidLoad may have run with no accessory yet.
    [self playerStateDidChange:SGPlayerState()];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
    hold.delegate = self;
    [self.tabBar addGestureRecognizer:hold];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(leadingTapped:)];
    tap.delegate = self;
    tap.cancelsTouchesInView = NO;
    [self.tabBar addGestureRecognizer:tap];
    [self playerStateDidChange:SGPlayerState()];
}

// The accessory is inline beside the minimized bar; with no track there is no accessory and no telling.
- (BOOL)minimized {
    if (@available(iOS 26.0, *)) return self.bottomAccessory.contentView.traitCollection.tabAccessoryEnvironment == UITabAccessoryEnvironmentInline;
    return NO;
}

- (void)minimizedChanged {
    SGLog(@"tab bar: %@", self.minimized ? @"minimized" : @"expanded");
    if (self.stockBar) syncBar(self.stockBar);
}

// Between the first tab and the trailing circle.
- (BOOL)isMiddle:(NSUInteger)index {
    return index > 0 && index + 1 < self.sources.count;
}

// A tap on the minimized selected tab only expands the bar, with no shouldSelectTab.
- (void)leadingTapped:(UITapGestureRecognizer *)tap {
    SGLog(@"tab bar: the minimized leading tab takes the tap for %@", labelIn(self.sources.firstObject).text);
    SGRTabPicked(self.sources.firstObject);
    forwardTap(self.sources.firstObject);
}

// The mini player is there while Spotify has a track to show on its bar, paused or not.
- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (@available(iOS 26.0, *)) {
        BOOL track = SGURIString(state.track.URI).length > 0;
        UITabAccessory *want = track ? self.accessory : nil;
        if (self.bottomAccessory != want) [self setBottomAccessory:want animated:self.viewIfLoaded.window != nil];
    }
}

- (BOOL)tabBarController:(UITabBarController *)controller shouldSelectTab:(UITab *)tab API_AVAILABLE(ios(26.0)) {
    if (sg_flipping) return YES;
    NSUInteger index = [self.tabs indexOfObject:tab];
    self.leadRedirected = self.touchedLead && [self isMiddle:index];
    if (self.leadRedirected) index = 0;
    if (index < self.sources.count) SGRTabPicked(self.sources[index]);
    // Home tapped while on Home pops Spotify's stack, which would take Mod Settings straight off it.
    if (index < self.sources.count && !self.holding) forwardTap(self.sources[index]);
    UIView *stockBar = self.stockBar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (stockBar) syncBar(stockBar);
    });
    return YES;
}

- (void)tabBarController:(UITabBarController *)controller didSelectTab:(UITab *)tab previousTab:(UITab *)previous API_AVAILABLE(ios(26.0)) {
    // Selecting another tab in here leaves UIKit lighting this one.
    if (self.leadRedirected) {
        self.leadRedirected = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ self.selectedTab = self.tabs.firstObject; });
    }
    nameScrollView();
}

// Held on Home, Mod Settings, as on the other glass bar.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if ([recognizer isKindOfClass:UITapGestureRecognizer.class]) return YES;
    UIView *home = self.sources.firstObject;
    if (!home || !isHome(home, self.stockBar)) return NO;
    UITabBarItem *item = itemAtPoint(self.tabBar, [recognizer locationInView:self.tabBar]);
    NSString *title = labelIn(home).text;
    if (item && title.length && [item.title isEqualToString:title]) return YES;
    if (@available(iOS 26.0, *)) return item && self.tabs.count && item.image == self.tabs.firstObject.image;
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    if (![recognizer isKindOfClass:UITapGestureRecognizer.class]) return YES;
    self.touchedLead = NO;
    if (@available(iOS 26.0, *)) {
        UIView *mini = self.minimized ? self.bottomAccessory.contentView : nil;
        self.touchedLead = mini.window && [touch locationInView:nil].x < CGRectGetMinX([mini convertRect:mini.bounds toView:nil]);
        return self.touchedLead && [self isMiddle:[self.tabs indexOfObject:self.selectedTab]];
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) {
        self.holding = YES;
        SGOpenModSettings(self.tabBar);
    } else if (hold.state != UIGestureRecognizerStateChanged) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            weakSelf.holding = NO;
        });
    }
}

@end

static UIViewController *inlinePage(UITab *tab) API_AVAILABLE(ios(26.0)) {
    return [SGRInlinePage new];
}

static void syncInline(UIView *stockBar) API_AVAILABLE(ios(26.0)) {
    UIViewController *container = containerOf(stockBar);
    if (!container.isViewLoaded) return;

    SGRInlineTabs *tabs = sg_inlineTabs;
    SGRInlineHost *host = sg_inlineHost;
    if (!tabs) {
        tabs = [SGRInlineTabs new];
        tabs.stockBar = stockBar;
        host = [SGRInlineHost new];
        host.tabs = tabs;
        // The host holds the controller: nothing else of Spotify's or UIKit's does.
        objc_setAssociatedObject(host, &kBarKey, tabs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        sg_inlineTabs = tabs;
        sg_inlineHost = host;
    }
    tabs.stockBar = stockBar;
    tabs.tabBar.tintColor = SGRAccent();

    for (UIView *sub in stockBar.subviews) {
        sub.alpha = 0;
        sub.userInteractionEnabled = NO;
    }
    stockBar.superview.layer.backgroundColor = NULL;

    UIView *view = container.view;
    if (!CGRectEqualToRect(host.frame, view.bounds)) {
        SGLog(@"tab bar: host frame %@ -> %@", NSStringFromCGRect(host.frame), NSStringFromCGRect(view.bounds));
        host.frame = view.bounds;
    }
    if (host.superview != view) {
        [tabs beginAppearanceTransition:YES animated:NO];
        [view addSubview:host];
        tabs.view.frame = host.bounds;
        tabs.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host addSubview:tabs.view];
        [tabs endAppearanceTransition];
        SGLog(@"tab bar: the mini player's tab bar controller is up over %@", NSStringFromCGRect(view.bounds));
        dispatch_async(dispatch_get_main_queue(), ^{ searchPageScroll(); });
    } else if (view.subviews.lastObject != host) {
        [view bringSubviewToFront:host];
    }
    // A page that hides Spotify's bar hides this one too.
    BOOL hidden = stockBar.hidden || stockBar.superview.hidden || stockBar.alpha < 0.01 || !stockBar.window;
    if (host.hidden != hidden) {
        SGLog(@"tab bar: %@ with Spotify's bar", hidden ? @"hidden" : @"shown");
        host.hidden = hidden;
    }

    NSArray<UIView *> *sources = tabItems(stockBar);
    if (!sources.count) return;
    BOOL hideLabels = SGHidden(SGRKeyNavbarHideLabels);

    if (![sources isEqualToArray:tabs.sources]) {
        NSMutableArray<UITab *> *list = [NSMutableArray array];
        for (UIView *source in sources) {
            NSString *title = hideLabels ? @"" : (labelIn(source).text ?: @"");
            UITab *tab;
            // UIKit keeps a search tab in its own circle beside the minimized bar, so the last tab of the
            // Navbar order is one, whichever it is.
            if (sources.count > 1 && source == sources.lastObject) {
                UISearchTab *search = [[UISearchTab alloc] initWithViewControllerProvider:^UIViewController *(UITab *t) { return inlinePage(t); }];
                search.title = title;
                search.image = glyphOf(source, NO);
                search.automaticallyActivatesSearch = NO;
                tab = search;
            } else {
                NSString *identifier = [NSString stringWithFormat:@"spotifyglass.tab.%lu", (unsigned long)list.count];
                tab = [[UITab alloc] initWithTitle:title image:glyphOf(source, NO) identifier:identifier
                            viewControllerProvider:^UIViewController *(UITab *t) { return inlinePage(t); }];
            }
            [list addObject:tab];
        }
        tabs.sources = sources;
        tabs.tabs = list;
        SGLog(@"tab bar: %lu tabs on the mini player's bar, %@ in the trailing circle", (unsigned long)list.count, labelIn(sources.lastObject).text);
    }

    // Spotify's selected tab shows its filled icon, as UITabBarItem's selectedImage did on the other bar.
    // Minimized, UIKit leads with the selected tab, or with the last one picked while the trailing one is
    // selected. The middle tabs all wear the first tab's glyph, unlit, so the first is what leads.
    UITab *selected = nil;
    UIView *current = SGRCurrentModTab();
    NSUInteger modTab = current ? [sources indexOfObject:current] : NSNotFound;
    BOOL missing = NO;
    static UIImage *leadFrom, *lead;
    UIImage *leadGlyph = tabs.minimized ? glyphOf(sources.firstObject, NO) : nil;
    if (leadGlyph != leadFrom) {
        leadFrom = leadGlyph;
        lead = [leadGlyph imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    for (NSUInteger i = 0; i < sources.count && i < tabs.tabs.count; i++) {
        UITab *tab = tabs.tabs[i];
        BOOL active = modTab != NSNotFound ? i == modTab : isActive(sources[i]);
        if (active && !selected) selected = tab;
        UIImage *image = glyphOf(sources[i], active);
        missing |= !image;
        if (lead && [tabs isMiddle:i]) image = lead;
        if (image && tab.image != image) tab.image = image;
    }
    if (selected && tabs.selectedTab != selected) {
        SGLog(@"tab bar: selection follows Spotify to %@", selected.title);
        tabs.selectedTab = selected;
    }
    if (!sg_pageScroll.window) searchPageScroll();
    static NSUInteger retries;
    if (missing && retries++ < 40) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            syncBar(stockBar);
        });
    }
    nameScrollView();
}

// The scroll view UIKit should minimize the bar by is Spotify's page in front: a vertical list over most
// of the screen inside the tab bar container, the innermost when one holds another. Horizontal pagers
// are left out. Spotify's first page is on screen before the bar is, so the container is searched once
// the bar is up; later pages are taken as they come on screen, and whichever list a finger starts
// dragging up or down is taken on the spot, in case the guess was another.
static BOOL isPageScroll(UIScrollView *scroll) {
    SGRInlineHost *host = sg_inlineHost;
    UIView *container = host.superview;
    if (!container || !scroll.window || scroll.hidden || scroll.pagingEnabled) return NO;
    if (![scroll isDescendantOfView:container] || [scroll isDescendantOfView:host]) return NO;
    return scroll.bounds.size.height >= container.bounds.size.height * 0.5;
}

static void takePageScroll(UIScrollView *scroll, NSString *why) {
    if (sg_pageScroll == scroll) return;
    sg_pageScroll = scroll;
    static NSUInteger logged;
    if (logged++ < 20) SGLog(@"tab bar: follows %@ %p %@ (%@)", NSStringFromClass(scroll.class), scroll, NSStringFromCGRect(scroll.frame), why);
    nameScrollView();
}

static void considerScrollView(UIScrollView *scroll) {
    if (!isPageScroll(scroll)) return;
    UIScrollView *current = sg_pageScroll;
    if (current == scroll) return;
    if (current.window && [current isDescendantOfView:scroll]) return;
    takePageScroll(scroll, @"came on screen");
}

static void searchPageScroll(void) {
    UIView *container = sg_inlineHost.superview;
    if (!container) return;
    // The bar lays out often; a page with no list is searched at most once a second.
    static CFTimeInterval last;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 1) return;
    last = now;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:container];
    NSUInteger found = 0;
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view == sg_inlineHost || view.hidden || view.alpha < 0.01) continue;
        if ([view isKindOfClass:UIScrollView.class] && isPageScroll((UIScrollView *)view)) {
            found++;
            considerScrollView((UIScrollView *)view);
        }
        [queue addObjectsFromArray:view.subviews];
    }
    static NSUInteger logged;
    if (!sg_pageScroll.window && logged++ < 5) SGLog(@"tab bar: no page list found to minimize by (%lu looked at)", (unsigned long)found);
}

@interface SGRScrollDrag : NSObject
@end

@implementation SGRScrollDrag
+ (void)dragged:(UIPanGestureRecognizer *)pan {
    UIScrollView *scroll = (UIScrollView *)pan.view;
    if (pan.state == UIGestureRecognizerStateEnded && scroll == sg_pageScroll) {
        static NSUInteger logged;
        UIEdgeInsets inset = scroll.adjustedContentInset;
        if (logged++ < 40) SGLog(@"tab bar: drag ended on the followed list, offset %.0f, inset top %.0f bottom %.0f, content %.0f of %.0f, page names it %d",
                                 scroll.contentOffset.y, inset.top, inset.bottom, scroll.contentSize.height, scroll.bounds.size.height,
                                 [sg_inlineTabs.selectedViewController contentScrollViewForEdge:NSDirectionalRectEdgeBottom] == scroll);
    }
    if (pan.state != UIGestureRecognizerStateBegan) return;
    if (![scroll isKindOfClass:UIScrollView.class] || scroll == sg_pageScroll || !isPageScroll(scroll)) return;
    CGPoint velocity = [pan velocityInView:scroll];
    if (fabs(velocity.y) <= fabs(velocity.x)) return;
    takePageScroll(scroll, @"dragged");
}
@end

static char kDragKey;

%group SGRInlinePlayerScroll
%hook UIScrollView
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (!objc_getAssociatedObject(self, &kDragKey)) {
        objc_setAssociatedObject(self, &kDragKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self.panGestureRecognizer addTarget:SGRScrollDrag.class action:@selector(dragged:)];
    }
    considerScrollView(self);
    // A page arriving in a transition may not have its size yet.
    __weak UIScrollView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIScrollView *scroll = weakSelf;
        if (scroll) considerScrollView(scroll);
    });
}
%end
%end

#pragma mark - hooks

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

// Set while the bar lays its items out itself, so each item's pass leaves the work to the bar's one.
static BOOL sg_barPass, sg_itemsLaidOut;

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
- (void)layoutSubviews {
    %orig;
    SGRComposeTabBar((UIView *)self);
    sg_barPass = YES;
    sg_itemsLaidOut = NO;
    for (UIView *sub in ((UIView *)self).subviews) {
        if (![sub isKindOfClass:SGRTabBarHost.class]) [sub layoutIfNeeded];
    }
    sg_barPass = NO;
    if (sg_itemsLaidOut) SGRComposeTabBar((UIView *)self);
    holdHome((UIView *)self);
    syncBar((UIView *)self);
    SGRLogTabBarRow((UIView *)self);
}
%end

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive.
static void itemDidLayOut(UIView *item) {
    if (sg_barPass) {
        sg_itemsLaidOut = YES;
        return;
    }
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    SGRComposeTabBar(bar);
    holdHome(bar);
    syncBar(bar);
    SGRLogTabBarRow(bar);
}

%hook _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%hook _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

// A page pushed or popped decides whether a tab of the mod's own is the one lit.
%hook SPNavigationController
- (void)navigationController:(UINavigationController *)controller didShowViewController:(UIViewController *)page animated:(BOOL)animated {
    %orig;
    UIView *bar = sg_stockBar;
    if (bar) syncBar(bar);
}
%end

// A tab changed from elsewhere (a link, the side drawer) repaints the labels without a layout pass.
%hook _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (void)setSelectedViewController:(UIViewController *)controller {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *bar = sg_stockBar;
        if (bar) syncBar(bar);
    });
}
// The message bar coming or going changes the view's safe area before Spotify lays the bar out for it,
// so the room follows in that same pass, and inside the message bar's animation.
- (void)viewSafeAreaInsetsDidChange {
    %orig;
    makeRoom((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (@available(iOS 26.0, *)) sg_inline = SGRInlinePlayer();
    %init;
    if (sg_inline) %init(SGRInlinePlayerScroll);
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
        @"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl",
        @"SPNavigationController",
    ]);
}
