// Playlist redesign: the track rows on the field, the way the Music app has them -- no surface of their own,
// artwork with rounded corners, and a hairline from the text's edge between one row and the next.
//
// Tree (trees/clean/playlist/02.txt:164-247): a cell id=Playlist.ItemCell holds an Encore.ListRow painted the
// base surface, and in it Encore.ImageView 48x48 (the artwork), Track.Row.Content.Title,
// Track.Row.Content.Subtitle and, at the trailing edge, Components.UI.ContextMenuButton. The row's own paint
// is cleared here rather than left to the Kit's repaint hook, which only hears about a colour when Spotify
// sets it and not when a reused cell already carries one.
//
// Spotify's type and its spacing are left alone: the row is 64pt for a title of 18pt, and a larger font of
// the Kit's would be cut off by the box the element framework measured for it.
//
// The pills over the first row (own-playlist/01.txt:33) are a cell of the list: Add, Mix, Notes, Video,
// Edit, Sort and Name & details. The row is closed up -- ListUXPlatform_LayoutKit.ListLayout gives every
// item its height, so the cell can only close up where the layout asks it how tall it wants to be -- and
// Sort and Mix are put on the ⋯ sheet instead (PlaylistMenu.x), where the rest of the row already is. The
// cell is handed over as it lays out, so the sheet has Spotify's own buttons to fire.
//
// Not every cell of the list is a track row. Under the tracks Spotify puts the extender -- Recommended
// songs, its rows and Refresh (ListUXPlatformConsumers_PlaylistExtenderImpl) -- and its heading and its
// Refresh cell paint the base surface over the field, where the black made bands of them (device,
// trees/continuous/2.txt 2026-09-20). So the paint comes off every cell of the page, the Kit's way, and
// only the row below is a row.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"

// Under the text rather than the whole row, as the Music app draws it; the trailing end clears the page margin.
static const CGFloat kHairline = 0.5, kHairlineGap = 12;

static char kRowKey, kArtKey, kSubtitleKey, kLineKey, kToolbarKey;

static UIView *identified(UIView *root, NSString *identifier, const void *cacheKey) {
    return SGRFindByIdentifier(root, identifier, cacheKey);
}

static void clearSurface(UIView *view) {
    UIColor *color = view.backgroundColor;
    if (color && SGIsBaseSurface(color.CGColor)) view.backgroundColor = UIColor.clearColor;
}

static void applyHairline(UIView *row, CGFloat leading) {
    CALayer *line = objc_getAssociatedObject(row, &kLineKey);
    if (!line) {
        line = [CALayer layer];
        line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        line.zPosition = 1;
        objc_setAssociatedObject(row, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (line.superlayer != row.layer) [row.layer addSublayer:line];
    CGRect bounds = row.bounds;
    CGRect frame = CGRectMake(leading, bounds.size.height - kHairline,
                              MAX(0, bounds.size.width - leading - SGRSideMargin), kHairline);
    if (CGRectEqualToRect(line.frame, frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    line.frame = frame;
    [CATransaction commit];
}

static void applyRow(UIView *cell) {
    clearSurface(cell);
    UIView *row = identified(cell, @"Encore.ListRow", &kRowKey);
    if (!row) return;
    clearSurface(row);

    // The first track with its title in is the list the page waits for (Kit/SGRReveal.h). A row still loading
    // is Components.UI.RetrievalRowLoadingElementUI rather than Encore.ListRow, grey bars with no text in them
    // (trees/continuous/1.txt).
    UIView *page = SGRPlaylistPageOf(cell);
    if (SGRRevealWaitsFor(page, SGRRevealList) && SGRRevealShowsText(row)) SGRRevealMark(page, SGRRevealList);

    CGFloat leading = SGRSideMargin + 48 + kHairlineGap;
    UIView *art = identified(row, @"Encore.ImageView", &kArtKey);
    if (art) {
        if (art.layer.cornerRadius != SGRRadiusThumb) {
            art.layer.cornerRadius = SGRRadiusThumb;
            art.layer.cornerCurve = kCACornerCurveContinuous;
            art.clipsToBounds = YES;
        }
        CGRect frame = [row convertRect:art.bounds fromView:art];
        if (frame.size.width > 0) leading = CGRectGetMaxX(frame) + kHairlineGap;
    }

    UIView *subtitle = identified(row, @"Track.Row.Content.Subtitle", &kSubtitleKey);
    SGForEachView(subtitle, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (![label.textColor isEqual:SGRSecondary()]) label.textColor = SGRSecondary();
    });

    applyHairline(row, leading);
}

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
- (void)layoutSubviews {
    %orig;
    UIView *cell = (UIView *)self;
    if (!SGRPlaylistHeaderOf(cell)) return;
    SGRClearCellPaint(cell);
    SGRPlaylistTakeCuration(cell);
    applyRow(cell);
}

- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    if (!SGRFindByIdentifier((UIView *)self, SGRPlaylistCurationIdentifier, &kToolbarKey)) return result;
    result.size = CGSizeMake(result.size.width, 0);
    ((UIView *)self).clipsToBounds = YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign playlist: curation pills asked for a height, answered 0"); });
    return result;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell"]);
}
