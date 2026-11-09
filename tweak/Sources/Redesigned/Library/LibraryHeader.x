// Library redesign: the header of Your Library and of a folder inside it, the way Home and Search have theirs
// (Redesigned/Home/HomeHeader.x, Redesigned/Search/SearchPage.x). A large title at the leading edge, the avatar
// that opens the side drawer at the trailing edge, and the scrim Spotify lays behind the header gone, the soft
// scroll edge (Kit/SGREdgeEffect.x) being what keeps the header clear of the list scrolling under it.
//
// The filter chips under the row stay Spotify's, untouched. They were taken out when the redesign was first
// built and the header closed up by the 49pt they left, and sorting a library turned out to be something the
// page cannot do without (issue #20). Spotify already draws them on the system's own glass
// (Reprise_LiquidGlassKit.LiquidGlass.ChipGlassView, trees/clean/library/03.txt:1210), so they belong here as
// they are; with them back the header keeps the height Spotify gives it and the list keeps Spotify's own inset,
// and there is nothing here to resize or to hold.
//
// Tree (trees/clean/library/03.txt:1159-1247): YourLibraryView holds YourLibraryContentView, the size of the
// page, and after it -- so over it -- YourLibraryHeaderView 402x159.33: LiquidGlass.GradientView (the scrim), a
// 402x48 row at {0, 62} holding an AutoLayoutStackView {8, 0} 390x48 of
// ListeningActivity_ElementsKit.AdaptiveFaceContainer (the avatar, id=Components.UI.SideDrawerButton),
// id=YourLibraryHeader.title ("Your Library", 21pt), a spacer, a hidden id=YourLibraryHeader.recents,
// id=YourLibraryHeader.search and id=YourLibraryHeader.plus; and under the row
// YourLibraryHeaderContentFiltersView {0, 110} 402x49.33, the chips. Recents is hidden on the account the tree
// is of; the header's model shows it where it says isRecentsAvailable, a clock between the spacer and Search
// (issue #21), and it goes to the trailing edge with the others. A folder (trees/continuous/1.txt:325-344)
// is the same header under YourLibrary_FolderImpl, with id=YourLibraryFolderHeader.back at the leading edge,
// its title, then contextMenu, plus and play or pause, and the chips at {0, 118}.
//
// The header neither moves nor shrinks as the list scrolls -- 03.txt, 05.txt and 06.txt hold it at
// {0, 0} 402x159.33 at three scroll positions -- so there is nothing here to follow: the row is laid out once a
// pass and stays where it is put.
//
// Each control moves by a transform rather than by a frame. Spotify's stack lays them out from constraints of
// its own on every pass, and Auto Layout sets a view's centre and bounds and leaves its transform alone, so the
// move outlives the pass that made it (Search moves the Browse cells the same way). Nothing leaves the stack:
// an arranged view of Spotify's that hides traps its stack in updateConstraints (Kit/SGRRestyle.h), so what
// goes is alpha, touches and accessibility, and the title Spotify draws goes that way while ours is a subview
// of the header the stack does not arrange.
//
// A move is worked out from where the stack put the control, so it holds only until the stack puts it somewhere
// else, and the stack does that on passes of its own that reach neither the header nor the page: the header's
// model arriving after the page first laid out shows or hides a button, the title gets its text, the avatar
// its size. A button just shown stands where it stood hidden, at the row's leading edge (Recents in 03.txt),
// until the stack's next pass places it. Moves worked out on the page's pass alone were then off by however
// far each control went since -- over the title, off the screen -- until the page laid out again on the way
// back from a playlist (issue #21). So the row the controls stand in is watched too, and every pass of its own
// places them again.

#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Library.h"
#import "Redesigned/Kit/SGRBarGeometry.h"
#import "LibraryGeometry.h"

NSString *const SGRLibraryListIdentifier = @"YourLibraryContent.collectionView";

// Spotify's own inset for the header's controls: a 48pt button flush against the header's trailing edge has its
// 24pt glyph 20pt from the screen, and the 32pt avatar inside its own 48pt box 16pt from it, which is the
// margin Home gives the avatar.
static const CGFloat kRowInset = 8;
static char kTitleKey, kRowWatchedKey;

static char kRecentsKey, kSearchKey, kPlusKey, kHeaderTitleKey, kSideDrawerKey;
static char kBackKey, kMenuKey, kFolderPlusKey, kPlayKey, kPauseKey, kFolderTitleKey;

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

// 9.1.94 added headerContainerView to YourLibraryView (binary ivar table). The
// header is no longer necessarily an immediate child. Keep discovery bounded to
// this page and match the verified class, not a guessed container selector.
static UIView *descendantNamed(UIView *host, NSString *marker) {
    UIView *direct = childNamed(host, marker);
    if (direct) return direct;
    for (UIView *sub in host.subviews) {
        UIView *found = descendantNamed(sub, marker);
        if (found) return found;
    }
    return nil;
}

static UIEdgeInsets headerRailInsets(UIView *header) {
    UIEdgeInsets insets = SGRVerticalBarContentInsets(header, SGRVerticalBarExtent);
    if (!CGRectIsNull(SGRVerticalBarFrameIn(header, SGRVerticalBarExtent))) {
        insets.left = MAX(insets.left, header.safeAreaInsets.left);
        insets.right = MAX(insets.right, header.safeAreaInsets.right);
    }
    return insets;
}

void SGRLibraryClearScrim(UIView *header) {
    vanish(childNamed(header, @"GradientView"));
}

#pragma mark - the controls

// The header's controls, in the order they are to read from the leading edge, leaving out what this build does
// not have, what Spotify has hidden (a folder shows play or pause, never both) and what has not been laid out.
static NSMutableArray<UIView *> *controlsIn(UIView *header, NSArray<NSString *> *identifiers, const void **keys) {
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    for (NSUInteger i = 0; i < identifiers.count; i++) {
        UIView *control = SGRFindByIdentifier(header, identifiers[i], keys[i]);
        if (control && !control.hidden && control.alpha > 0.01 && control.bounds.size.width > 1) [found addObject:control];
    }
    return found;
}

// Puts the controls at the header's trailing edge, the last of them flush against it and each keeping the width
// it has, and answers where the leading edge of the first of them fell.
static CGFloat placeTrailing(UIView *header, NSArray<UIView *> *controls) {
    CGFloat right = header.bounds.size.width - headerRailInsets(header).right - kRowInset;
    for (UIView *control in controls.reverseObjectEnumerator) {
        CGFloat width = control.bounds.size.width;
        // The centre is where Auto Layout put the control, whatever transform is on it; its frame is not.
        CGFloat natural = [control.superview convertPoint:CGPointZero toView:header].x + control.center.x - width / 2;
        CGAffineTransform move = CGAffineTransformMakeTranslation(right - width - natural, 0);
        if (!CGAffineTransformEqualToTransform(control.transform, move)) control.transform = move;
        right -= width;
    }
    return right;
}

// `place` again after every pass of the row the controls stand in (see the top of the file), for as long as it
// is in the header. The row is the stack's container, a plain UIView the Kit can watch; what `place` does not
// touch -- the header's height, the list under it -- stays the page's pass's.
static void watchRow(UIView *row, UIView *header, NSArray<UIView *> *(*place)(UIView *header)) {
    if (!row || objc_getAssociatedObject(row, &kRowWatchedKey)) return;
    objc_setAssociatedObject(row, &kRowWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakHeader = header;
    SGRObserveLayout(row, ^(UIView *view) {
        UIView *owner = weakHeader;
        if (!owner || ![view isDescendantOfView:owner]) return;
        // Once, the first time the row's pass finds a control away from where the page's pass left it.
        static BOOL logged;
        NSMutableArray<NSNumber *> *before = logged ? nil : [NSMutableArray array];
        for (UIView *sub in before ? view.subviews : @[]) [before addObject:@(sub.transform.tx)];
        NSArray<UIView *> *placed = place(owner);
        if (!before || !owner.window) return;
        for (NSUInteger i = 0; i < before.count && i < view.subviews.count; i++) {
            if (fabs(view.subviews[i].transform.tx - before[i].doubleValue) < 0.5) continue;
            logged = YES;
            SGLog(@"redesign library: the header's row laid out on its own after the page, its %lu controls placed again",
                  (unsigned long)placed.count);
            break;
        }
    });
}

#pragma mark - the title

static NSString *textIn(UIView *label) {
    __block NSString *text = nil;
    SGForEachView(label, ^(UIView *view) {
        if (!text && [view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) text = ((UILabel *)view).text;
    });
    return text;
}

static UILabel *titleIn(UIView *header) {
    UILabel *title = objc_getAssociatedObject(header, &kTitleKey);
    if (!title) {
        title = [UILabel new];
        title.textColor = SGRPrimary();
        title.accessibilityTraits = UIAccessibilityTraitHeader;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.6;
        title.userInteractionEnabled = NO;
        objc_setAssociatedObject(header, &kTitleKey, title, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (title.superview != header) [header addSubview:title];
    return title;
}

// The title Spotify's own says, so it follows the app's language, in the Music app's size on the row's middle.
static void layoutTitle(UIView *header, UIView *spotifyTitle, CGFloat leading, CGFloat trailing, CGFloat middle) {
    UILabel *title = titleIn(header);
    NSString *text = textIn(spotifyTitle);
    if (text.length && ![title.text isEqualToString:text]) {
        title.text = text;
        title.accessibilityLabel = text;
    }
    UIFont *font = SGRFont(UIFontTextStyleLargeTitle, UIFontWeightBold, UIContentSizeCategoryLarge);
    if (![title.font isEqual:font]) title.font = font;

    CGFloat height = ceil(font.lineHeight);
    CGRect frame = CGRectMake(leading, round(middle - height / 2), MAX(0, trailing - SGRGrid - leading), height);
    if (!CGRectEqualToRect(title.frame, frame)) title.frame = frame;
}

#pragma mark - the two headers

static BOOL isFace(UIView *view) {
    static Class faceClass;
    if (!faceClass) faceClass = NSClassFromString(@"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer");
    return faceClass && [view isKindOfClass:faceClass];
}

// The root header's controls at its trailing edge, the avatar last, and the title before them. Answers what it
// placed in the order it reads, nothing while the header has no control laid out.
static NSArray<UIView *> *placeRoot(UIView *header) {
    UIView *spotifyTitle = SGRFindByIdentifier(header, @"YourLibraryHeader.title", &kHeaderTitleKey);
    vanish(spotifyTitle);
    static const void *keys[] = {&kRecentsKey, &kSearchKey, &kPlusKey};
    NSMutableArray<UIView *> *trailing = controlsIn(header, @[
        @"YourLibraryHeader.recents", @"YourLibraryHeader.search", @"YourLibraryHeader.plus",
    ], keys);
    __block UIView *face = nil;
    SGForEachView(header, ^(UIView *view) {
        if (!face && isFace(view) && view.bounds.size.width > 1) face = view;
    });
    // 9.1.94's live Duo tree uses an EncoreButton for the entire side-drawer
    // control, with the avatar and activity indicator nested inside it. Retain
    // the legacy face-container path, otherwise move the verified control as a
    // whole so its hit target and all its content follow the avatar.
    if (!face) face = SGRFindByIdentifier(header, @"Components.UI.SideDrawerButton", &kSideDrawerKey);
    if (face && !face.hidden && face.alpha > 0.01 && face.bounds.size.width > 1) [trailing addObject:face];
    if (!trailing.count) return trailing;

    CGFloat leading = placeTrailing(header, trailing);
    CGRect row = SGFrameIn(trailing.firstObject, header);
    layoutTitle(header, spotifyTitle, SGRSideMargin + headerRailInsets(header).left, leading, CGRectGetMidY(row));
    for (UIView *control in trailing) watchRow(control.superview, header, placeRoot);
    return trailing;
}

// The folder header's controls at its trailing edge and the title between them and the back button, which stays
// where Spotify has it. Answers what it placed in the order it reads, the back button first.
static NSArray<UIView *> *placeFolder(UIView *header) {
    UIView *spotifyTitle = SGRFindByIdentifier(header, @"YourLibraryFolderHeader.title", &kFolderTitleKey);
    vanish(spotifyTitle);
    UIView *back = SGRFindByIdentifier(header, @"YourLibraryFolderHeader.back", &kBackKey);
    static const void *keys[] = {&kMenuKey, &kFolderPlusKey, &kPlayKey, &kPauseKey};
    NSMutableArray<UIView *> *placed = controlsIn(header, @[
        @"YourLibraryFolderHeader.contextMenu", @"YourLibraryFolderHeader.plus",
        @"YourLibraryFolderHeader.play", @"YourLibraryFolderHeader.pause",
    ], keys);
    if (!placed.count && !back) return placed;

    CGFloat trailingEdge = placed.count ? placeTrailing(header, placed) : header.bounds.size.width - headerRailInsets(header).right - kRowInset;
    if (back) [placed insertObject:back atIndex:0];
    CGRect rowFrame = SGFrameIn(placed.firstObject, header);
    CGFloat leading = back ? CGRectGetMaxX(rowFrame) + SGRGrid : SGRSideMargin;
    layoutTitle(header, spotifyTitle, leading, trailingEdge, CGRectGetMidY(rowFrame));
    for (UIView *control in placed) watchRow(control.superview, header, placeFolder);
    return placed;
}

static void layoutRoot(UIView *page) {
    UIView *header = descendantNamed(page, @"YourLibraryHeaderView");
    if (!header) return;
    [header layoutIfNeeded];
    SGRLibraryClearScrim(header);

    NSArray<UIView *> *trailing = placeRoot(header);
    if (!trailing.count) return;

    // The first pass that laid the header out, not the first pass at all: a page appearing lays out before
    // its controls have a size, and a line off that pass would say the header was left as Spotify's.
    UIView *face = trailing.lastObject;
    if (!isFace(face) && ![face.accessibilityIdentifier isEqualToString:@"Components.UI.SideDrawerButton"]) face = nil;
    static BOOL logged;
    if (!logged && header.window && face) {
        logged = YES;
        SGLog(@"redesign library: header %@, %lu controls at the trailing edge, avatar %@, chips %@",
              NSStringFromCGRect(header.frame), (unsigned long)trailing.count, face ? @"found" : @"not found",
              childNamed(header, @"YourLibraryHeaderContentFiltersView") ? @"Spotify's" : @"not found");
    }
}

static void layoutFolder(UIView *page) {
    UIView *header = descendantNamed(page, @"FolderHeaderView");
    if (!header) return;
    [header layoutIfNeeded];
    SGRLibraryClearScrim(header);

    NSArray<UIView *> *placed = placeFolder(header);
    if (!placed.count) return;

    UIView *back = SGRFindByIdentifier(header, @"YourLibraryFolderHeader.back", &kBackKey);
    NSUInteger trailing = placed.count - (back ? 1 : 0);
    static BOOL logged;
    if (!logged && header.window && trailing) {
        logged = YES;
        SGLog(@"redesign library: folder header %@, back %@, %lu controls at the trailing edge, chips %@",
              NSStringFromCGRect(header.frame), back ? @"found" : @"not found", (unsigned long)trailing,
              childNamed(header, @"YourLibraryHeaderContentFiltersView") ? @"Spotify's" : @"not found");
    }
}

// Both selectors are present in Spotify 9.1.94's Objective-C symbol table.
// A header can lay out after its page (or inside the new wrapper); styling at
// its own layout boundary keeps late model changes from restoring the stock row.
%hook _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView
- (void)layoutSubviews {
    %orig;
    SGRLibraryClearScrim((UIView *)self);
    placeRoot((UIView *)self);
}
%end

%hook _TtC22YourLibrary_FolderImpl16FolderHeaderView
- (void)layoutSubviews {
    %orig;
    SGRLibraryClearScrim((UIView *)self);
    placeFolder((UIView *)self);
}
%end

%hook _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView
- (void)layoutSubviews {
    UIView *appearanceOwner = (UIView *)self;
    SGRApplyNativeLightSurface(appearanceOwner, YES);
    SGRegisterAppearanceView(appearanceOwner);
    SGRLibraryExtendPage((UIView *)self);
    %orig;
    layoutRoot((UIView *)self);
    SGRLibraryPrepareList((UIView *)self);
}
%end

// Both APIs must agree. Copy attributes rather than mutate Spotify/UIKit caches.
// The elements selector is present in the 9.1.94 binary; the per-item selector is
// UICollectionViewLayout's inherited public API on this exact subclass.
%hook _TtC28YourLibrary_YourLibraryXImpl30YourLibraryCompositionalLayout
- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSArray<UICollectionViewLayoutAttributes *> *original = %orig;
    NSMutableArray<UICollectionViewLayoutAttributes *> *result = [NSMutableArray arrayWithCapacity:original.count];
    for (UICollectionViewLayoutAttributes *attributes in original)
        [result addObject:SGRLibraryFullWidthAttribute((UICollectionViewLayout *)self, attributes)];
    return original ? result : nil;
}
- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    return SGRLibraryFullWidthAttribute((UICollectionViewLayout *)self, %orig);
}
%end

// UICollectionView rejects the Kit's dynamic layout observer. Hook its public
// inherited layout boundary on the binary-verified Library subclass instead.
%hook _TtC21YourLibrary_CommonKit25YourLibraryCollectionView
- (void)layoutSubviews {
    %orig;
    if (objc_getAssociatedObject(self, &sgrLibraryPreparedListKey)) {
        SGRLibraryAdaptBottomEdge((UIScrollView *)self);
        SGRLibraryScheduleLayoutCheck((UIScrollView *)self);
    }
}
%end

%hook _TtC22YourLibrary_FolderImpl10FolderView
- (void)layoutSubviews {
    %orig;
    layoutFolder((UIView *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC28YourLibrary_YourLibraryXImpl15YourLibraryView",
        @"_TtC21YourLibrary_CommonKit25YourLibraryCollectionView",
        @"_TtC28YourLibrary_YourLibraryXImpl30YourLibraryCompositionalLayout",
        @"_TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView",
        @"_TtC22YourLibrary_FolderImpl16FolderHeaderView",
        @"_TtC22YourLibrary_FolderImpl10FolderView",
        @"_TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView",
        @"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer",
    ]);
}
