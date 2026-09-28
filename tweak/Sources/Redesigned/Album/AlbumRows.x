// Album redesign: the track rows on the field, the way the Music app has them -- no surface of their own
// and a hairline from the text's edge between one row and the next.
//
// Tree (trees/clean/album/03.txt:524-575): every row of the page is an Element_List.CollectionViewCell
// holding an Encore.ListRow, id=Components.UI.RetrievalRowElementUI, with the title
// (EncoreConsumerMobile.View.Granular.Title), the artists under it (…Granular.Subtitle) and, at the
// trailing edge, Components.UI.ContextMenuButton. An album row carries no artwork -- every track on the
// page shares the cover the header is already showing -- so the hairline runs from the page's own margin,
// where the text starts.
//
// The row's paint is cleared here rather than left to the Kit's repaint hook, which only hears about a
// colour when Spotify sets it and not when a reused cell already carries one.
//
// Repeated artist credits are omitted (issue #118). Spotify still measures the row, preserving its
// controls and Dynamic Type. Explicit badges sit inline with the centred title.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Album.h"
#import "AlbumArtistPolicy.h"

// Under the text rather than the whole row, as the Music app draws it; the trailing end clears the page
// margin.
static const CGFloat kHairline = 0.5;

static char kRowKey, kSubtitleKey, kTitleKey, kLineKey, kArtistKey, kCreditKey;

@interface SGRAlbumArtistContext : NSObject
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, strong) NSHashTable<UIView *> *rows;
@end
@implementation SGRAlbumArtistContext
@end

static SGRAlbumArtistContext *artistContext(UIView *page) {
    SGRAlbumArtistContext *context = objc_getAssociatedObject(page, &kArtistKey);
    if (!context && page) {
        context = [SGRAlbumArtistContext new];
        context.rows = NSHashTable.weakObjectsHashTable;
        objc_setAssociatedObject(page, &kArtistKey, context, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return context;
}

void SGRAlbumSetArtist(UIView *page, NSString *artist) {
    SGRAlbumArtistContext *context = artistContext(page);
    if ([context.artist isEqualToString:artist] || (!context.artist && !artist)) return;
    context.artist = artist;
    for (UIView *cell in context.rows) [cell setNeedsLayout];
}

@interface SGRAlbumRowCredit : NSObject
@property (nonatomic, weak) UIView *label;
@property (nonatomic, weak) UIView *title;
@property (nonatomic, weak) UILabel *name;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) CGAffineTransform transform;
@property (nonatomic) CGRect nameFrame;
@property (nonatomic, strong) NSArray<UIView *> *badges;
@property (nonatomic, strong) NSArray<NSNumber *> *badgeAlphas;
@property (nonatomic, strong) NSArray<UIImageView *> *inlineBadges;
@end
@implementation SGRAlbumRowCredit
@end

static void restoreCredit(UIView *cell) {
    SGRAlbumRowCredit *credit = objc_getAssociatedObject(cell, &kCreditKey);
    if (!credit) return;
    credit.label.alpha = credit.alpha;
    credit.title.transform = credit.transform;
    if (credit.badges.count) credit.name.frame = credit.nameFrame;
    [credit.badges enumerateObjectsUsingBlock:^(UIView *badge, NSUInteger i, BOOL *stop) {
        badge.alpha = credit.badgeAlphas[i].doubleValue;
    }];
    for (UIView *badge in credit.inlineBadges) [badge removeFromSuperview];
    objc_setAssociatedObject(cell, &kCreditKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UILabel *onlyTextLabel(UIView *root) {
    __block UILabel *label = nil;
    __block NSUInteger count = 0;
    SGForEachView(root, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class] || !SGRAlbumCreditText(((UILabel *)view).text).length) return;
        label = (UILabel *)view;
        count++;
    });
    return count == 1 ? label : nil;
}

static void applyCredit(UIView *cell, UIView *row, UIView *subtitle, UIView *page) {
    SGRAlbumArtistContext *context = artistContext(page);
    [context.rows addObject:cell];
    UIView *title = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Title", &kTitleKey);
    UILabel *artist = onlyTextLabel(subtitle), *name = onlyTextLabel(title);
    if (!artist || !name || !SGRAlbumArtistCreditIsRedundant(context.artist, artist.text, name.text)) return;

    NSMutableArray<UIView *> *badges = [NSMutableArray array];
    NSMutableArray<NSNumber *> *alphas = [NSMutableArray array];
    __block CGFloat badgeWidth = 0;
    // Device tree: ExplicitIcon is a label-backed sibling of the subtitle, not an image
    // inside it. Match the verified semantic identifier so other row controls stay untouched.
    SGForEachView(row, ^(UIView *view) {
        if (![view.accessibilityIdentifier isEqualToString:@"Components.UI.ExplicitIcon"] ||
            CGRectIsEmpty(view.bounds)) return;
        for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
            if (ancestor.hidden || ancestor.alpha <= 0) return;
            if (ancestor == row) break;
        }
        [badges addObject:view];
        [alphas addObject:@(view.alpha)];
        badgeWidth += view.bounds.size.width + 4;
    });
    // Keep the native layout if a transitional transform or unusually narrow label prevents a
    // legible inline arrangement. No constraint or arranged-subview membership is changed.
    if (!CGAffineTransformIsIdentity(title.transform) ||
        (badges.count && name.bounds.size.width - badgeWidth < name.font.lineHeight)) return;

    SGRAlbumRowCredit *credit = [SGRAlbumRowCredit new];
    credit.label = subtitle;
    credit.alpha = subtitle.alpha;
    credit.title = title;
    credit.transform = title.transform;
    credit.name = name;
    credit.nameFrame = name.frame;
    credit.badges = badges;
    credit.badgeAlphas = alphas;
    objc_setAssociatedObject(cell, &kCreditKey, credit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Never set hidden on an Encore/OverflowStackView arranged subview. Keep the original text and
    // Spotify's combined row accessibility label, including artist credits and explicit status.
    // Conceal the subtitle wrapper: Encore refreshes its internal label's alpha later.
    subtitle.alpha = 0;
    BOOL rtl = name.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    if (badges.count) {
        CGRect frame = name.frame;
        frame.size.width -= badgeWidth;
        if (rtl) frame.origin.x += badgeWidth;
        name.frame = frame;
    }
    CGRect bounds = [title convertRect:title.bounds toView:row];
    CGFloat shift = CGRectGetMidY(row.bounds) - CGRectGetMidY(bounds);
    title.transform = CGAffineTransformMakeTranslation(0, shift);

    // Draw Spotify's own badge at row level: moving its subtitle siblings outside their
    // containers clips them. Leave the native hierarchy/text/accessibility intact for reuse.
    CGRect labelBounds = [name convertRect:name.bounds toView:row];
    CGFloat textWidth = MIN(labelBounds.size.width,
        [name textRectForBounds:name.bounds limitedToNumberOfLines:name.numberOfLines].size.width);
    CGFloat textX = CGRectGetMinX(labelBounds);
    if (name.textAlignment == NSTextAlignmentCenter)
        textX += (labelBounds.size.width - textWidth) / 2;
    else if (name.textAlignment == NSTextAlignmentRight ||
             (name.textAlignment == NSTextAlignmentNatural && rtl))
        textX += labelBounds.size.width - textWidth;
    CGFloat edge = rtl ? textX - 4 : textX + textWidth + 4;
    NSMutableArray<UIImageView *> *inlineBadges = [NSMutableArray array];
    for (UIView *source in badges) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:source.bounds.size];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [source.layer renderInContext:context.CGContext];
        }];
        UIImageView *badge = [[UIImageView alloc] initWithImage:image];
        badge.alpha = source.alpha;
        badge.accessibilityElementsHidden = YES;
        badge.isAccessibilityElement = NO;
        badge.userInteractionEnabled = NO;
        CGSize size = source.bounds.size;
        badge.frame = CGRectMake(rtl ? edge - size.width : edge,
            CGRectGetMidY(labelBounds) - size.height / 2, size.width, size.height);
        edge += (rtl ? -1 : 1) * (size.width + 4);
        [row addSubview:badge];
        [inlineBadges addObject:badge];
        source.alpha = 0;
    }
    credit.inlineBadges = inlineBadges;
}

static void clearSurface(UIView *view) {
    UIColor *color = view.backgroundColor;
    if (color && SGIsBaseSurface(color.CGColor)) view.backgroundColor = UIColor.clearColor;
}

static void applyHairline(UIView *row) {
    CALayer *line = objc_getAssociatedObject(row, &kLineKey);
    if (!line) {
        line = [CALayer layer];
        line.zPosition = 1;
        objc_setAssociatedObject(row, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    line.backgroundColor = SGRHairline().CGColor;
    if (line.superlayer != row.layer) [row.layer addSublayer:line];
    CGRect bounds = row.bounds;
    CGRect frame = CGRectMake(SGRSideMargin, bounds.size.height - kHairline,
                              MAX(0, bounds.size.width - 2 * SGRSideMargin), kHairline);
    if (CGRectEqualToRect(line.frame, frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    line.frame = frame;
    [CATransaction commit];
}

static void applyRow(UIView *cell, UIView *page) {
    clearSurface(cell);
    UIView *row = SGRFindByIdentifier(cell, @"Components.UI.RetrievalRow*", &kRowKey);
    if (!row) return;
    // The first track with its title in is the list the page waits for (Kit/SGRReveal.h); a row still loading
    // draws grey bars with empty labels.
    if (SGRRevealWaitsFor(page, SGRRevealList) && SGRRevealShowsText(row)) SGRRevealMark(page, SGRRevealList);
    // The row, and every box the element framework wraps it in on the way back up to the cell.
    for (UIView *v = row; v; v = v.superview) {
        clearSurface(v);
        if (v == cell) break;
    }

    UIView *subtitle = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle", &kSubtitleKey);
    SGForEachView(subtitle, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (![label.textColor isEqual:SGRSecondary()]) label.textColor = SGRSecondary();
    });

    applyCredit(cell, row, subtitle, page);

    applyHairline(row);
}

// Which cells of Element_List belong to an album's track list, answered once per content class: the same
// cell class carries Home's sections and the album's footer too, and a walk up to the page on every pass of
// every cell is what the answer is cached to avoid.
static BOOL isTrackContent(UIView *content) {
    static NSMutableDictionary<id, NSNumber *> *answers;
    if (!answers) answers = [NSMutableDictionary dictionary];
    Class cls = object_getClass(content);
    if (!cls) return NO;
    NSNumber *answer = answers[(id<NSCopying>)cls];
    if (!answer) {
        answer = @([NSStringFromClass(cls) containsString:@"RetrievalListStructuredData"]);
        answers[(id<NSCopying>)cls] = answer;
    }
    return answer.boolValue;
}

%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    restoreCredit((UIView *)self);
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *page = isTrackContent(cell.contentView.subviews.firstObject) ? SGRAlbumPageOf(cell) : nil;
    if (page) {
        // The cell lays out before Encore's descendants. Finish that pass before measuring text
        // and badges; otherwise a newly created row still reports zero-sized content here.
        [cell.contentView layoutIfNeeded];
        applyRow(cell, page);
    }
    else if (objc_getAssociatedObject(cell, &kRowKey)) {
        UIView *row = SGRFindByIdentifier(cell, @"Components.UI.RetrievalRow*", &kRowKey);
        [((CALayer *)objc_getAssociatedObject(row, &kLineKey)) removeFromSuperlayer];
    }
}

- (void)prepareForReuse {
    restoreCredit((UIView *)self);
    %orig;
    // Spotify can redisplay a cached row at the same size without another layout pass. Restoring
    // its native presentation for reuse must also invalidate layout so the new context is applied.
    [(UIView *)self setNeedsLayout];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
