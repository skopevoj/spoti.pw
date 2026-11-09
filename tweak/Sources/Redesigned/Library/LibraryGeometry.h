// Spotify 9.1.94 live Duo tree: YourLibraryView is pinned horizontally to its
// controller view's safe-area guide (382pt inside a 466pt view), while its top
// and bottom already span the view. Only swap those two verified constraints.
static void SGRLibraryExtendPage(UIView *page) {
    static char pairsKey;
    BOOL vertical = !CGRectIsNull(SGRVerticalBarFrameIn(page, SGRVerticalBarExtent));
    NSArray<NSArray<NSLayoutConstraint *> *> *pairs = objc_getAssociatedObject(page, &pairsKey);
    UIView *host = page.superview;
    for (NSArray<NSLayoutConstraint *> *pair in pairs) {
        NSLayoutConstraint *original = pair[0], *full = pair[1];
        if (full.secondItem == host && (original.active || full.active)) continue;
        // A caller replacing/deactivating our relationship owns the new layout. Do not
        // revive the cached pair on a later pass, even when the page keeps the same host.
        for (NSArray<NSLayoutConstraint *> *stale in pairs) [stale[1] setActive:NO];
        objc_setAssociatedObject(page, &pairsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        pairs = nil;
        break;
    }
    if (!pairs && vertical && host) {
        NSMutableArray *found = [NSMutableArray array];
        for (NSLayoutConstraint *original in host.constraints) {
            NSLayoutAttribute attribute = original.firstAttribute;
            if (original.firstItem != page || original.secondItem != host.safeAreaLayoutGuide
                || (attribute != NSLayoutAttributeLeading && attribute != NSLayoutAttributeTrailing)
                || original.secondAttribute != attribute || original.relation != NSLayoutRelationEqual
                || original.multiplier != 1 || original.constant != 0 || !original.active) continue;
            NSLayoutConstraint *full = [NSLayoutConstraint constraintWithItem:page attribute:attribute
                relatedBy:NSLayoutRelationEqual toItem:host attribute:attribute multiplier:1 constant:0];
            full.priority = original.priority;
            [found addObject:@[original, full]];
        }
        if (found.count != 2) return;
        pairs = found;
        objc_setAssociatedObject(page, &pairsKey, pairs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (NSArray<NSLayoutConstraint *> *pair in pairs) {
        NSLayoutConstraint *original = pair[0], *full = pair[1];
        // Do not revive a relationship after Spotify reparents/replaces the page.
        if (full.secondItem != host) continue;
        NSLayoutConstraint *wanted = vertical ? full : original;
        NSLayoutConstraint *other = vertical ? original : full;
        if (!wanted.active || other.active) {
            other.active = NO;
            wanted.active = YES;
            [host setNeedsLayout];
        }
    }
}

// Keep Spotify's scroll insets, including bottom reachability, untouched. The
// bottom glass/chrome is floating in Duo; do not obscure the rows behind it.
static void SGRLibraryAdaptBottomEdge(UIScrollView *list) {
    if (@available(iOS 26.0, *)) {
        static char hiddenKey;
        BOOL vertical = !CGRectIsNull(SGRVerticalBarFrameIn(list, SGRVerticalBarExtent));
        NSNumber *original = objc_getAssociatedObject(list, &hiddenKey);
        if (vertical) {
            if (!original) objc_setAssociatedObject(list, &hiddenKey, @(list.bottomEdgeEffect.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (!list.bottomEdgeEffect.hidden) list.bottomEdgeEffect.hidden = YES;
        } else if (original) {
            list.bottomEdgeEffect.hidden = original.boolValue;
            objc_setAssociatedObject(list, &hiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

// The final physical probe has configuration None and a 466pt viewport, but
// Spotify still supplies 382x80 cell attributes. Changing configuration cannot
// correct its section geometry. Track only heights of verified visible list rows;
// the exact layout subclass's attribute hooks below repair matching copies.
static char sgrLibraryRowHeightsKey;

static void SGRLibraryAdaptCompositionalLayout(UIScrollView *scroll) {
    if (![scroll isKindOfClass:UICollectionView.class]) return;
    UICollectionViewLayout *layout = ((UICollectionView *)scroll).collectionViewLayout;
    Class libraryLayout = NSClassFromString(@"_TtC28YourLibrary_YourLibraryXImpl30YourLibraryCompositionalLayout");
    if (!libraryLayout || ![layout isKindOfClass:libraryLayout]) return;
    BOOL vertical = !CGRectIsNull(SGRVerticalBarFrameIn(scroll, SGRVerticalBarExtent));
    NSMutableSet<NSNumber *> *heights = [NSMutableSet set];
    __block BOOL cards = NO;
    if (vertical) for (UICollectionViewCell *cell in ((UICollectionView *)scroll).visibleCells) {
        __block BOOL row = NO;
        SGForEachView(cell, ^(UIView *view) {
            NSString *identifier = view.accessibilityIdentifier;
            if ([@[@"Playlist.Row.Library", @"Album.Row.Library", @"Podcast.Row.Library"] containsObject:identifier ?: @""]) row = YES;
            if ([identifier isEqualToString:@"Components.UI.CardLibrary"]) cards = YES;
        });
        if (row && cell.bounds.size.height > 1) [heights addObject:@(cell.bounds.size.height)];
    }
    if (cards) [heights removeAllObjects];
    NSSet *old = objc_getAssociatedObject(layout, &sgrLibraryRowHeightsKey);
    if (![old isEqualToSet:heights]) {
        objc_setAssociatedObject(layout, &sgrLibraryRowHeightsKey, [heights copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [layout invalidateLayout];
    }
}

static UICollectionViewLayoutAttributes *SGRLibraryFullWidthAttribute(UICollectionViewLayout *layout, UICollectionViewLayoutAttributes *original) {
    UICollectionView *list = layout.collectionView;
    if (!original || original.representedElementCategory != UICollectionElementCategoryCell
        || CGRectIsNull(SGRVerticalBarFrameIn(list, SGRVerticalBarExtent))) return original;
    NSSet<NSNumber *> *heights = objc_getAssociatedObject(layout, &sgrLibraryRowHeightsKey);
    BOOL rowHeight = NO;
    for (NSNumber *height in heights) if (fabs(height.doubleValue - original.frame.size.height) < 0.5) { rowHeight = YES; break; }
    if (!rowHeight) return original;
    CGRect frame = original.frame;
    CGFloat fullWidth = list.bounds.size.width;
    UIEdgeInsets safe = list.safeAreaInsets;
    CGFloat safeWidth = fullWidth - safe.left - safe.right;
    // The physical layout's complete rows start at x=0. Do not reinterpret
    // offset cards, partial-width content or other section geometry.
    if (safe.left + safe.right < 1 || fabs(frame.origin.x) > 0.5
        || fabs(frame.size.width - safeWidth) > 0.5 || safeWidth < 1) return original;
    UICollectionViewLayoutAttributes *copy = [original copy];
    frame.size.width = fullWidth;
    copy.frame = frame;
    return copy;
}

// UICollectionView can replace visible cells after its layout callback. Recheck
// once on the next main-queue turn so an in-place list/grid change is observed.
static void SGRLibraryScheduleLayoutCheck(UIScrollView *list) {
    static char pendingKey;
    if ([objc_getAssociatedObject(list, &pendingKey) boolValue]) return;
    objc_setAssociatedObject(list, &pendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIScrollView *weakList = list;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIScrollView *live = weakList;
        if (!live) return;
        objc_setAssociatedObject(live, &pendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRLibraryAdaptCompositionalLayout(live);
    });
}

static char sgrLibraryPreparedListKey;

static void SGRLibraryPrepareList(UIView *page) {
    static char listKey;
    UIView *candidate = SGRFindByIdentifier(page, @"YourLibraryContent.collectionView", &listKey);
    if (![candidate isKindOfClass:UIScrollView.class]) return;
    UIScrollView *list = (UIScrollView *)candidate;
    objc_setAssociatedObject(list, &sgrLibraryPreparedListKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRLibraryAdaptBottomEdge(list);
    SGRLibraryAdaptCompositionalLayout(list);
    SGRLibraryScheduleLayoutCheck(list);
}
