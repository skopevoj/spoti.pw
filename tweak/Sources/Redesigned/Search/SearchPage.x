// Search redesign: the Browse page's header the way Home has it (Redesigned/Home/HomeHeader.x). A large title at the
// leading edge in place of Spotify's small one; the avatar that opens the side drawer at the trailing edge; the camera
// that scans Spotify codes gone, and the scrim Spotify lays behind the header, the soft scroll edge
// (Kit/SGREdgeEffect.x) being what keeps the header clear of the cards scrolling under it. The page's layout pass also
// closes the gap the collapsed sections leave (SearchSections.x).
//
// Tree (trees/clean/search/01.txt:376-427): BrowsePageViewController's view holds the list (id=BrowsePage.ContentScrollView),
// a 402x216 UIView around Reprise_LiquidGlassKit LiquidGlass.GradientView (the scrim), and at {0, 62} the header's
// ElementView 402x124: a vertical UIStackView {16, 0} 370x108 of the toolbar row and the search field. The toolbar row
// is a UIStackView id=SearchToolBar.Header 370x48 of ListeningActivity_ElementsKit.AdaptiveFaceContainer {0, 7} 32x34
// (the avatar), SPTEncoreLabel id=SearchHeaderFind.HeaderLabel {40, 0} 278x48 ("Search", 21pt), the camera
// (id=SearchToolBar.AccessoryItem.ScannablesButton) and a hidden accessory button.
//
// Scrolled, Spotify slides the header up 56pt and fades the toolbar row out (03.txt:647-651, a=0.00), keeping the search
// field. So the title goes into that row as a subview the stack does not arrange: it slides and fades with the row, and
// its avatar moves to the trailing edge by the row's layout direction, as on Home. The title's text is Spotify's own
// label's, so it follows the app's language.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Search.h"

// Layout passes without the header before that is logged.
static const NSUInteger kMissesLogged = 60;

static char kTitleKey;

static __weak UICollectionView *sg_list;
static __weak UIStackView *sg_row;
static __weak UIView *sg_scrim;

static void vanish(UIView *view) {
    if (!view) return;
    if (view.alpha != 0) view.alpha = 0;
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static UIView *childNamed(UIView *host, NSString *marker) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) containsString:marker]) return sub;
    }
    return nil;
}

// A depth first search that leaves the list out: the header and the scrim sit beside it, and its cells are hundreds of views.
static UIView *findOutsideList(UIView *view, NSString *identifier) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UICollectionView.class]) continue;
        if ([sub.accessibilityIdentifier isEqualToString:identifier]) return sub;
        UIView *found = findOutsideList(sub, identifier);
        if (found) return found;
    }
    return nil;
}

// The page's parts, found once per page: the page lays out on every step of its header sliding. A miss costs a walk of the
// header alone, so the page keeps looking while it loads.
static BOOL findParts(UIView *view) {
    if (sg_row && sg_list && [sg_row isDescendantOfView:view] && [sg_list isDescendantOfView:view]) return YES;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UICollectionView.class] && [sub.accessibilityIdentifier isEqualToString:SGRSearchListIdentifier]) {
            sg_list = (UICollectionView *)sub;
        }
        UIView *scrim = childNamed(sub, @"GradientView");
        if (scrim) sg_scrim = scrim;
    }
    UIView *row = findOutsideList(view, @"SearchToolBar.Header");
    sg_row = [row isKindOfClass:UIStackView.class] ? (UIStackView *)row : nil;
    if (sg_row && sg_list) return YES;
    static NSUInteger misses;
    if (++misses == kMissesLogged) {
        SGLog(@"redesign search: page parts not found in %lu passes (toolbar row %@, list %@), the header left as Spotify's",
              (unsigned long)misses, sg_row ? @"found" : @"missing", sg_list ? @"found" : @"missing");
    }
    return NO;
}

static NSString *titleText(UIStackView *row) {
    UIView *label = nil;
    for (UIView *part in row.arrangedSubviews) {
        if ([part.accessibilityIdentifier isEqualToString:@"SearchHeaderFind.HeaderLabel"]) label = part;
    }
    for (UIView *sub in label.subviews) {
        if ([sub isKindOfClass:UILabel.class] && ((UILabel *)sub).text.length) return ((UILabel *)sub).text;
    }
    return @"Search";
}

static UILabel *titleIn(UIStackView *row) {
    UILabel *title = objc_getAssociatedObject(row, &kTitleKey);
    if (!title) {
        title = [UILabel new];
        title.textColor = SGRPrimary();
        title.accessibilityTraits = UIAccessibilityTraitHeader;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.6;
        title.userInteractionEnabled = NO;
        objc_setAssociatedObject(row, &kTitleKey, title, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (title.superview != row) [row addSubview:title];
    return title;
}

static void layoutHeader(UIStackView *row) {
    vanish(sg_scrim);

    static Class faceClass;
    if (!faceClass) faceClass = NSClassFromString(@"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer");
    UIView *face = nil;
    NSString *text = titleText(row);
    for (UIView *part in row.arrangedSubviews) {
        if (faceClass && [part isKindOfClass:faceClass]) face = part;
        else vanish(part);
    }
    if (row.semanticContentAttribute != UISemanticContentAttributeForceRightToLeft) {
        row.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        [row setNeedsLayout];
    }
    [row layoutIfNeeded];

    UILabel *title = titleIn(row);
    if (![title.text isEqualToString:text]) {
        title.text = text;
        title.accessibilityLabel = text;
    }
    UIFont *font = SGRFont(UIFontTextStyleLargeTitle, UIFontWeightBold, UIContentSizeCategoryLarge);
    if (![title.font isEqual:font]) title.font = font;

    CGFloat trailing = face ? CGRectGetMinX(face.frame) - SGRGrid : row.bounds.size.width;
    CGFloat height = ceil(font.lineHeight);
    CGRect frame = CGRectMake(0, round(CGRectGetMidY(row.bounds) - height / 2), MAX(0, trailing), height);
    if (!CGRectEqualToRect(title.frame, frame)) title.frame = frame;

    static BOOL logged;
    if (!logged && row.window && CGRectGetMinX(row.frame) >= 0 && row.bounds.size.width > 0) {
        logged = YES;
        SGLog(@"redesign search: toolbar row %@, avatar %@, title %@ \"%@\", scrim %@", NSStringFromCGRect(row.frame),
              face ? NSStringFromCGRect(face.frame) : @"not found", NSStringFromCGRect(frame), text, sg_scrim ? @"found" : @"not found");
    }
}

%hook _TtC21Browse_BrowsePageImpl24BrowsePageViewController
- (void)viewDidLayoutSubviews {
    UIViewController *appearanceOwner = (UIViewController *)self;
    SGRApplyNativeLightSurface(appearanceOwner.viewIfLoaded, YES);
    SGRegisterAppearanceController(appearanceOwner);
    %orig;
    UIView *view = ((UIViewController *)self).viewIfLoaded;
    if (!view || !findParts(view)) return;
    layoutHeader(sg_row);
    SGRSearchCloseGap(sg_list);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    %orig;
    [((UIViewController *)self).viewIfLoaded setNeedsLayout];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC21Browse_BrowsePageImpl24BrowsePageViewController",
        @"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer",
    ]);
}
