// Artist redesign: the Music list without the artist's videos, and nothing of it painted over the field.
//
// Tree (trees/clean/artist/05.txt, the Music list top to bottom): Popular, Artist pick, Popular releases and
// its Show all, Featuring, Release Countdown, Music videos, Watch more from…, About, Artist playlists, Fans
// also like, Appears on. Every section is three Element_List cells in a row -- a 16pt spacer, a heading
// (Components.UI.SectionHeadingHome) and what the section holds -- and every kind of content carries an
// identifier of its own, in any language: Components.UI.RetrievalRowElementUI (tracks), PinnedItemUI (the
// pick), HomeCard (a carousel), UpcomingReleaseRow, CreatorBiographyCard (About),
// Components.UI.MusicVideoShelfHeader and WatchFeedCarouselEntryPointElement (videos).
//
// So the rule is by kind, never by the heading's words, which are the app's language: a video shelf reports
// no height, and so do the heading and the spacer in the two cells before it. They were sized before it, so
// the list is asked to lay out again once they are known. Every carousel is the same kind whatever it holds,
// so the carousels all stay; merch has a tab of its own, which ArtistField.x takes away.
//
// A dropped cell is 0 tall but what it holds keeps the height it measured at, hidden and cut off by the
// cell: content squeezed to 0 breaks Spotify's required constraints on every pass (Album/AlbumSections.x).
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Artist.h"

static char kSettledKey, kKindsKey, kDroppedKey, kTrackKey;

typedef NS_ENUM(NSInteger, SGRArtistCell) {
    SGRArtistCellOther,
    SGRArtistCellSpacer,
    SGRArtistCellHeading,
    SGRArtistCellVideos,
};

static SGRArtistCell kindOf(UIView *content, CGFloat height) {
    __block SGRArtistCell kind = SGRArtistCellOther;
    SGForEachView(content, ^(UIView *v) {
        NSString *identifier = v.accessibilityIdentifier;
        if (kind != SGRArtistCellOther || !identifier.length) return;
        if ([identifier isEqualToString:@"Components.UI.MusicVideoShelfHeader"] ||
            [identifier isEqualToString:@"Music-Videos.Video-Card-Carousel"] ||
            [identifier isEqualToString:@"WatchFeedCarouselEntryPointElement"]) kind = SGRArtistCellVideos;
        else if ([identifier isEqualToString:@"Components.UI.SectionHeadingHome"]) kind = SGRArtistCellHeading;
    });
    if (kind == SGRArtistCellOther && height <= 16.5 && content.subviews.count <= 1) {
        __block BOOL empty = YES;
        SGForEachView(content, ^(UIView *v) { if (v.accessibilityIdentifier.length) empty = NO; });
        if (empty) kind = SGRArtistCellSpacer;
    }
    return kind;
}

static NSMutableDictionary<NSIndexPath *, NSNumber *> *kindsOf(UICollectionView *list) {
    NSMutableDictionary *kinds = objc_getAssociatedObject(list, &kKindsKey);
    if (!kinds) {
        kinds = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(list, &kKindsKey, kinds, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return kinds;
}

static NSMutableSet<NSIndexPath *> *droppedOf(UICollectionView *list) {
    NSMutableSet *dropped = objc_getAssociatedObject(list, &kDroppedKey);
    if (!dropped) {
        dropped = [NSMutableSet set];
        objc_setAssociatedObject(list, &kDroppedKey, dropped, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return dropped;
}

static UICollectionView *listOf(UIView *cell) {
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) return (UICollectionView *)v;
    }
    return nil;
}

static void settle(UICollectionViewCell *cell, CGFloat natural) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kSettledKey, @(natural), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (content.autoresizingMask & UIViewAutoresizingFlexibleHeight) content.autoresizingMask &= ~UIViewAutoresizingFlexibleHeight;
    CGRect frame = CGRectMake(0, 0, cell.bounds.size.width, natural);
    if (!CGRectEqualToRect(content.frame, frame)) content.frame = frame;
    if (!content.hidden) content.hidden = YES;
    if (!cell.clipsToBounds) cell.clipsToBounds = YES;
    cell.accessibilityElementsHidden = YES;
}

static void unsettle(UICollectionViewCell *cell) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kSettledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    content.autoresizingMask |= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    content.frame = cell.bounds;
    content.hidden = NO;
    cell.clipsToBounds = NO;
    cell.accessibilityElementsHidden = NO;
}

// The cell `back` items before `path` in the list, across the end of a section if it has to.
static NSIndexPath *before(UICollectionView *list, NSIndexPath *path, NSInteger back) {
    NSInteger section = path.section, item = path.item - back;
    while (item < 0 && section > 0) {
        section--;
        item += [list numberOfItemsInSection:section];
    }
    return item >= 0 ? [NSIndexPath indexPathForItem:item inSection:section] : nil;
}

// A video shelf takes its heading and the spacer over it with it. Those were sized before it, so the list lays
// out again, once, to ask them again.
static void dropHeadingOf(UICollectionView *list, NSIndexPath *path) {
    NSMutableDictionary *kinds = kindsOf(list);
    NSMutableSet *dropped = droppedOf(list);
    BOOL added = NO;
    NSIndexPath *heading = before(list, path, 1);
    if (heading && [kinds[heading] integerValue] == SGRArtistCellHeading && ![dropped containsObject:heading]) {
        [dropped addObject:heading];
        added = YES;
        NSIndexPath *spacer = before(list, path, 2);
        if (spacer && [kinds[spacer] integerValue] == SGRArtistCellSpacer) [dropped addObject:spacer];
    }
    if (!added) return;
    __weak UICollectionView *weakList = list;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakList.collectionViewLayout invalidateLayout]; });
}

static void logOnce(NSString *what) {
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    if ([logged containsObject:what]) return;
    [logged addObject:what];
    SGLog(@"redesign artist: %@", what);
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UICollectionView *list = listOf(cell);
    // Only the page's own list: a card inside a carousel is a cell of the same class, and its row decides.
    BOOL page = list && ![listOf(list) isKindOfClass:UICollectionView.class] && SGRArtistPageOf(cell) && attributes.indexPath;
    if (!page) {
        if (objc_getAssociatedObject(cell, &kSettledKey)) unsettle(cell);
        return %orig;
    }
    UICollectionViewLayoutAttributes *result = %orig;
    NSIndexPath *path = attributes.indexPath;
    UIView *content = cell.contentView.subviews.firstObject ?: cell.contentView;
    SGRArtistCell kind = kindOf(content, result.size.height);
    kindsOf(list)[path] = @(kind);

    BOOL drop = kind == SGRArtistCellVideos || [droppedOf(list) containsObject:path];
    if (kind == SGRArtistCellVideos) {
        [droppedOf(list) addObject:path];
        dropHeadingOf(list, path);
    }
    if (!drop) {
        if (objc_getAssociatedObject(cell, &kSettledKey)) unsettle(cell);
        return result;
    }
    settle(cell, MAX(1, result.size.height));
    result.size = CGSizeMake(result.size.width, 0);
    logOnce(@"the videos dropped from the Music list");
    return result;
}

// The cell's own passes size the content to the cell again.
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    NSNumber *settled = objc_getAssociatedObject(self, &kSettledKey);
    if (settled) settle(cell, settled.doubleValue);
    UICollectionView *list = listOf(cell);
    UIView *page = list && ![listOf(list) isKindOfClass:UICollectionView.class] ? SGRArtistPageOf(cell) : nil;
    if (page) {
        // What the cell paints over the field -- the "You liked" row, every carousel's collection and the
        // fade Popular's "See more" draws over its last track (device, trees/continuous/3.txt 2026-09-18).
        SGRClearCellPaint(cell);
        // The first of Popular's tracks with its title in is the list the page waits for (Kit/SGRReveal.h); a
        // row still loading is RetrievalRowLoadingElementUI, grey bars with empty labels.
        if (SGRRevealWaitsFor(page, SGRRevealList)) {
            UIView *track = SGRFindByIdentifier(cell, @"Components.UI.RetrievalRowElementUI*", &kTrackKey);
            if (track && SGRRevealShowsText(track)) SGRRevealMark(page, SGRRevealList);
        }
    }
}

- (void)prepareForReuse {
    %orig;
    if (objc_getAssociatedObject(self, &kSettledKey)) unsettle((UICollectionViewCell *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
