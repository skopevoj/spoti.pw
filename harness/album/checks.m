// Exercises the production Logos hooks against the recorded album hierarchy, including reuse.
#import <UIKit/UIKit.h>
#import "Redesigned/Album/Album.h"
#import "Redesigned/Album/AlbumArtistPolicy.h"

// The recommendation heading uses UIKit's plain cell, not the playlist track-cell subclass.
@interface _TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController : UIViewController @end
@implementation _TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController @end
@interface _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView : UICollectionView @end
@implementation _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView @end

@interface SGRHeadingFixture : NSObject <UICollectionViewDataSource>
@end
@implementation SGRHeadingFixture
- (NSInteger)collectionView:(UICollectionView *)list numberOfItemsInSection:(NSInteger)section { return 1; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)list cellForItemAtIndexPath:(NSIndexPath *)path {
    UICollectionViewCell *cell = [list dequeueReusableCellWithReuseIdentifier:@"heading" forIndexPath:path];
    for (UIView *view in cell.contentView.subviews.copy) [view removeFromSuperview];
    UIView *element = [[UIView alloc] initWithFrame:cell.bounds];
    [cell.contentView addSubview:element];
    UIView *label = [[UIView alloc] initWithFrame:CGRectMake(16, 4, 358, 21)];
    label.accessibilityIdentifier = @"Encore.Label";
    label.layer.backgroundColor = UIColor.blackColor.CGColor;
    UILabel *title = [[UILabel alloc] initWithFrame:label.bounds];
    title.text = @"Localized recommendations";
    [label addSubview:title];
    [element addSubview:label];
    return cell;
}
@end

static NSUInteger checks;
static void check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) {
        NSLog(@"[album-checks] FAIL: %@", message);
        abort();
    }
}

static UIView *identified(UIView *parent, CGRect frame, NSString *identifier) {
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.accessibilityIdentifier = identifier;
    [parent addSubview:view];
    return view;
}

static UILabel *text(UIView *parent, NSString *value) {
    UILabel *label = [[UILabel alloc] initWithFrame:parent.bounds];
    label.text = value;
    [parent addSubview:label];
    return label;
}

void SGRRunAlbumChecks(UIView *page, NSArray<UICollectionViewCell *> *footer, BOOL native) {
    NSArray *cases = @[
        @[@"The Weeknd", @"The Weeknd", @"Cry For Me", @YES],
        @[@" The  Weeknd ", @"THE WEEKND", @"Song", @YES],
        @[@"Beyoncé", @"Beyonce\u0301", @"Song", @YES],
        @[@"Beyoncé", @"Beyonce", @"Song", @NO],
        @[@"אמן", @"אמן", @"שיר", @YES],
        @[@"Various Artists", @"The Weeknd", @"Song", @NO],
        @[@"The Weeknd", @"The Weeknd, Anitta", @"São Paulo", @NO],
        @[@"The Weeknd", @"The Weeknd, Anitta", @"São Paulo (feat. Anitta)", @YES],
        @[@"The Weeknd", @"The Weeknd, Justice", @"Wake Me Up - featuring Justice", @YES],
        @[@"The Weeknd", @"The Weeknd, Justice", @"Justice", @NO],
        @[@"The Weeknd", @"The Weeknd, Ann", @"Song (feat. Anne)", @NO],
        @[@"The Weeknd", @"The Weeknd, A, B", @"Song (with A)", @NO],
        @[@"The Weeknd", @"The Weeknd, A, B", @"Song [ft. A, B]", @YES],
        @[@"A", @"AB", @"Song", @NO],
        @[@"A", @"A & B", @"Song (with B)", @NO],
        @[@"A & B", @"A & B", @"Song", @YES],
        @[@"A, B", @"A, B, C", @"Song (feat. C)", @YES],
        @[@"Shae • Lava Dome", @"Shae, Lava Dome", @"4X4", @YES],
        @[@"Shae • Lava Dome", @"Shae, Lava Dome", @"בוהדנה", @YES],
        @[@"A • B • C", @"A, B, C", @"Song", @YES],
        @[@"Shae • Lava Dome", @"Shae, Lava Dome, Guest", @"Song", @NO],
        @[@"Shae • Lava Dome", @"Shae, Lava Dome, Guest", @"Song (feat. Guest)", @YES],
        @[@"Shae • Lava Dome", @"Shae", @"Song", @NO],
        @[@"A & B • C/D", @"A & B, C/D", @"Song", @YES],
        @[@"A • B", @"A, BC", @"Song", @NO],
        @[@"", @"Artist", @"Song", @NO],
        @[@"Artist", @"", @"Song", @NO],
    ];
    for (NSArray *item in cases) {
        check(SGRAlbumArtistCreditIsRedundant(item[0], item[1], item[2]) == [item[3] boolValue],
              [NSString stringWithFormat:@"credit policy %@", item]);
    }

    // Keep the actual footer content and original self-sizing. This includes unknown/localized
    // sections, spacer cells, links and carousels, rather than an English allow list.
    for (UICollectionViewCell *cell in footer) {
        CGFloat height = cell.bounds.size.height;
        for (int pass = 0; pass < 3; pass++) {
            UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes
                layoutAttributesForCellWithIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
            attributes.size = cell.bounds.size;
            UICollectionViewLayoutAttributes *result = [cell preferredLayoutAttributesFittingAttributes:attributes];
            check(fabs(result.size.height - height) < 0.01, @"footer preserves natural height on repeated measurement");
            [cell setNeedsLayout]; [cell layoutIfNeeded];
            check(!cell.contentView.hidden && !cell.accessibilityElementsHidden, @"footer remains visible and accessible");
        }
    }

    // Device 2026-09-24: related releases have their own nested Element_List cells. The black is
    // on ContentCardAlbum, not on its labels. Exercise attachment, repaint/reuse and isolation.
    UICollectionViewCell *shelf = [[UICollectionViewCell alloc] initWithFrame:CGRectMake(0, 0, 390, 194)];
    UICollectionViewCell *release = [[NSClassFromString(@"_TtC12Element_List18CollectionViewCell") alloc]
        initWithFrame:CGRectMake(16, 0, 153, 194)];
    [shelf.contentView addSubview:release];
    UIView *card = identified(release.contentView, release.bounds, @"Components.UI.ContentCardAlbum");
    UIView *art = identified(card, CGRectMake(0, 0, 153, 153), @"Encore.ImageView");
    art.backgroundColor = UIColor.blackColor;
    UIView *cardBadge = identified(card, CGRectMake(4, 4, 26, 26), @"badge");
    cardBadge.backgroundColor = UIColor.blackColor;
    UILabel *caption = text(identified(card, CGRectMake(0, 161, 153, 33), @"caption"), @"Album");
    card.layer.backgroundColor = UIColor.blackColor.CGColor;
    [release setNeedsLayout]; [release layoutIfNeeded];
    check(CGColorGetAlpha(card.layer.backgroundColor) == 1, @"album-card paint outside album is untouched");
    [page addSubview:shelf];
    for (int pass = 0; pass < 3; pass++) {
        [release prepareForReuse];
        card.layer.backgroundColor = UIColor.blackColor.CGColor;
        [release setNeedsLayout]; [release layoutIfNeeded];
        check(CGColorGetAlpha(card.layer.backgroundColor) == (native ? 1 : 0), @"album card backing follows look after reuse");
        check(CGColorGetAlpha(art.layer.backgroundColor) == 1 && CGColorGetAlpha(cardBadge.layer.backgroundColor) == 1,
              @"artwork and badge backgrounds survive card cleanup");
        check(card.alpha == 1 && [caption.text isEqualToString:@"Album"] && card.bounds.size.height == 194,
              @"card content and geometry survive cleanup");
    }
    card.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    [release setNeedsLayout]; [release layoutIfNeeded];
    check(CGColorGetAlpha(card.layer.backgroundColor) == 1, @"non-base card color survives");
    [shelf removeFromSuperview];

    UICollectionViewFlowLayout *flow = [UICollectionViewFlowLayout new];
    flow.itemSize = CGSizeMake(390, 33);
    UICollectionView *recommendations = [[_TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView alloc]
        initWithFrame:CGRectMake(0, 0, 390, 100) collectionViewLayout:flow];
    SGRHeadingFixture *fixture = [SGRHeadingFixture new];
    recommendations.dataSource = fixture;
    [recommendations registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"heading"];
    [page addSubview:recommendations];
    for (int pass = 0; pass < 3; pass++) {
        [recommendations reloadData];
        [recommendations setNeedsLayout]; [recommendations layoutIfNeeded];
        UICollectionViewCell *heading = recommendations.visibleCells.firstObject;
        UIView *paint = heading.contentView.subviews.firstObject.subviews.firstObject;
        check(heading.class == UICollectionViewCell.class && paint != nil, @"playlist heading uses plain visible UIKit cell");
        CGFloat alpha = paint.layer.backgroundColor ? CGColorGetAlpha(paint.layer.backgroundColor) : 0;
        check(alpha == (native ? 1 : 0), @"playlist heading paint follows look on reload");
    }
    // Spotify also mounts footer cells directly, outside the collection's data-source items.
    UICollectionViewCell *mounted = [[UICollectionViewCell alloc] initWithFrame:CGRectMake(0, 40, 390, 33)];
    UIView *mountedPaint = identified(mounted.contentView, CGRectMake(16, 4, 358, 21), @"Encore.Label");
    text(mountedPaint, @"Another localized heading");
    [recommendations addSubview:mounted];
    check(![recommendations.visibleCells containsObject:mounted], @"mounted footer is outside managed visible cells");
    for (int pass = 0; pass < 3; pass++) {
        mountedPaint.layer.backgroundColor = UIColor.blackColor.CGColor;
        [recommendations setNeedsLayout]; [recommendations layoutIfNeeded];
        CGFloat alpha = mountedPaint.layer.backgroundColor ? CGColorGetAlpha(mountedPaint.layer.backgroundColor) : 0;
        check(alpha == (native ? 1 : 0), @"mounted playlist footer clears retained paint after layout");
    }
    [recommendations removeFromSuperview];

    // A separate page makes metadata isolation observable without disturbing the visual fixture.
    UIView *owner = [[NSClassFromString(@"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView") alloc]
        initWithFrame:CGRectMake(0, 0, 390, 844)];
    owner.accessibilityIdentifier = @"CreativeWorkPlatform.CreativeWorkTemplateView";
    UICollectionViewCell *cell = [[NSClassFromString(@"_TtC12Element_List18CollectionViewCell") alloc]
        initWithFrame:CGRectMake(0, 0, 390, 56)];
    [owner addSubview:cell];
    UIView *content = [[NSClassFromString(@"MockRetrievalListStructuredDataView") alloc] initWithFrame:cell.bounds];
    [cell.contentView addSubview:content];
    UIView *row = identified(content, cell.bounds, @"Components.UI.RetrievalRowElementUI");
    UIView *title = identified(row, CGRectMake(16, 8, 300, 18), @"EncoreConsumerMobile.View.Granular.Title");
    UILabel *name = text(title, @"Song");
    UIView *subtitle = identified(row, CGRectMake(16, 30, 300, 16), @"EncoreConsumerMobile.View.Granular.Subtitle");
    UILabel *artist = text(subtitle, @"The Weeknd");
    row.isAccessibilityElement = YES;
    row.accessibilityLabel = @"Song, The Weeknd, explicit";
    void (^layout)(void) = ^{ [cell setNeedsLayout]; [cell layoutIfNeeded]; };
    layout();
    check(subtitle.alpha == 1, @"missing album metadata keeps credits");
    SGRAlbumSetArtist(owner, @"The Weeknd");
    [cell layoutIfNeeded];
    if (native) {
        check(subtitle.alpha == 1 && CGAffineTransformIsIdentity(title.transform), @"native look is untouched");
        NSLog(@"[album-checks] PASS %lu checks (native)", (unsigned long)checks);
        return;
    }
    check(subtitle.alpha == 0, @"late album metadata refreshes existing row");
    check(fabs(title.transform.ty - 11) < 0.01, @"single title is centred");
    check([row.accessibilityLabel isEqualToString:@"Song, The Weeknd, explicit"], @"combined accessibility credit is preserved");
    for (int pass = 0; pass < 25; pass++) layout();
    check(fabs(title.transform.ty - 11) < 0.01, @"layout does not accumulate title movement");
    check(cell.bounds.size.height == 56, @"native touch targets and measurement survive");
    artist.text = @"The Weeknd, Anitta";
    layout();
    check(subtitle.alpha == 1 && CGAffineTransformIsIdentity(title.transform), @"uncredited guest restores subtitle and title position");
    name.text = @"Song (feat. Anitta)"; layout();
    check(subtitle.alpha == 0, @"guest named in title is redundant");

    UIView *badge = identified(row, CGRectMake(16, 32, 11, 11), @"Components.UI.ExplicitIcon");
    badge.backgroundColor = UIColor.lightGrayColor;
    badge.layer.cornerRadius = 2;
    UILabel *glyph = text(badge, @"E");
    glyph.font = [UIFont boldSystemFontOfSize:9];
    glyph.textAlignment = NSTextAlignmentCenter;
    subtitle.clipsToBounds = YES;
    layout();
    UIImageView *(^inlineBadge)(void) = ^UIImageView *{
        for (UIView *view in row.subviews) if (view != badge && [view isKindOfClass:UIImageView.class]) return (UIImageView *)view;
        return nil;
    };
    CGRect nameBounds = [name convertRect:name.bounds toView:row];
    check(subtitle.alpha == 0 && badge.alpha == 0 && inlineBadge().image != nil,
          @"explicit badge is drawn inline using Spotify's original image");
    check(fabs(CGRectGetMidY(inlineBadge().frame) - CGRectGetMidY(nameBounds)) < 0.01 &&
          fabs(title.transform.ty - 11) < 0.01, @"badge and title share the centred text line");
    check(inlineBadge().frame.origin.x > nameBounds.origin.x &&
          CGRectGetMaxX(inlineBadge().frame) <= 316 && name.bounds.size.width == 285,
          @"inline badge reserves title space and clears the menu");
    for (int pass = 0; pass < 25; pass++) layout();
    check(name.bounds.size.width == 285 && inlineBadge() != nil,
          @"repeated layout does not accumulate shrinking or duplicate badges");
    name.text = @"A very long song title that must truncate before its explicit badge (feat. Anitta)";
    layout();
    check(CGRectGetMaxX(inlineBadge().frame) <= 316, @"long title cannot push badge into menu");
    row.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    name.textAlignment = NSTextAlignmentNatural;
    name.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    layout();
    check(CGRectGetMinX(inlineBadge().frame) >= 16 &&
          CGRectGetMaxX(inlineBadge().frame) < CGRectGetMinX([name convertRect:name.bounds toView:row]),
          @"RTL badge is on the text's trailing side and inside the row");
    [cell prepareForReuse];
    check(badge.alpha == 1 && !inlineBadge() && name.bounds.size.width == 300 &&
          CGAffineTransformIsIdentity(title.transform), @"reuse restores source badge, title width and position");
    [cell layoutIfNeeded];
    check(subtitle.alpha == 0 && inlineBadge() != nil,
          @"same-size cached row reapplies credits and badge when redisplayed after reuse");
    [cell prepareForReuse];
    row.semanticContentAttribute = UISemanticContentAttributeUnspecified;
    name.semanticContentAttribute = UISemanticContentAttributeUnspecified;
    name.text = @"Song (feat. Anitta)";
    [badge removeFromSuperview];
    SGRAlbumSetArtist(owner, @"Shae • Lava Dome");
    artist.text = @"Shae, Lava Dome"; name.text = @"בוהדנה"; layout();
    artist.alpha = 1; // Encore can refresh the inner label after the parent pass.
    check(subtitle.alpha == 0, @"co-artist header hides the same complete credit on a track");
    artist.text = @"Shae, Lava Dome, Guest"; layout();
    check(subtitle.alpha == 1, @"co-artist album still retains an extra guest");
    artist.text = @"The Weeknd"; name.text = @"Song";
    SGRAlbumSetArtist(owner, @"Various Artists"); [cell layoutIfNeeded];
    check(subtitle.alpha == 1, @"compilation context restores artist");
    SGRAlbumSetArtist(owner, @"The Weeknd"); layout();
    [cell prepareForReuse];
    check(subtitle.alpha == 1 && CGAffineTransformIsIdentity(title.transform), @"reuse restores original presentation");
    UIView *playlist = [UIView new]; [playlist addSubview:cell]; layout();
    check(subtitle.alpha == 1 && CGAffineTransformIsIdentity(title.transform), @"non-album row keeps credits");
    [owner addSubview:cell]; layout();
    check(subtitle.alpha == 0, @"reused album row reapplies policy");
    cell.frame = CGRectMake(0, 0, 700, 100);
    content.frame = cell.bounds; row.frame = cell.bounds;
    title.transform = CGAffineTransformIdentity;
    title.frame = CGRectMake(90, 8, 560, 48);
    name.font = [UIFont systemFontOfSize:32];
    name.numberOfLines = 2;
    name.frame = title.bounds;
    row.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    layout();
    check(fabs(title.transform.ty - 18) < 0.01 && title.frame.origin.x == 90,
          @"larger multiline RTL title stays centred without horizontal movement");
    check(cell.bounds.size.height == 100 && name.font.pointSize == 32,
          @"larger text retains Spotify's font and measured row height");
    UIView *anotherAlbum = [UIView new];
    anotherAlbum.accessibilityIdentifier = @"CreativeWorkPlatform.CreativeWorkTemplateView";
    [anotherAlbum addSubview:cell]; layout();
    check(subtitle.alpha == 1, @"new album cannot borrow old album credits");
    SGRAlbumSetArtist(owner, @"Anitta"); [cell layoutIfNeeded];
    check(subtitle.alpha == 1, @"late metadata from old page cannot hide a new page's credit");
    SGRAlbumSetArtist(anotherAlbum, @"The Weeknd"); [cell layoutIfNeeded];
    check(subtitle.alpha == 0, @"new page's own metadata reapplies policy");
    // A new subtree in the same cell must not use the old cached labels.
    [content removeFromSuperview];
    UIView *replacement = [UIView new]; [cell.contentView addSubview:replacement]; layout();
    check(subtitle.alpha == 1 && CGAffineTransformIsIdentity(title.transform), @"replacement content restores detached views");
    SGRAlbumSetArtist(page, @"The Weeknd");
    NSLog(@"[album-checks] PASS %lu checks (redesign)", (unsigned long)checks);
}
