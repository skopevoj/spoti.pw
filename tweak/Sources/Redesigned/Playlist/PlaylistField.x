// Playlist redesign: the artwork field behind the whole page, and what the switch forces.
//
// Tree (trees/clean/playlist/02.txt:23 and :1096): FTPViewController's view holds the list
// (ListUXPlatform_FreeTierPlaylistImpl.FTPTouchCancellingCollectionView, id=SPTFreeTierPlaylistTableView,
// the size of the window) and, after it and so over it, the header (id=PL.Header). Neither scrolls the
// other: the list keeps its frame and the header's y runs from -134 at rest to -529 scrolled, so a field
// put behind both stays still while the cover at the top of the header slides up over it -- which is what
// the Music app does with the page colour.
//
// So the field is the page's bottom-most view, the size of the view and bleeding past it, with no backdrop
// of its own: the sharp cover at the top of the header is the picture, and PlaylistHeader.x fades it into
// exactly this field's colour. What Spotify paints over the field -- the page, the list and every row, all
// of them the base surface -- is kept clear by the Kit's repaint hook while sgr_playlistRoot is this page.
//
// The colour is read from the cover the header shows (PlaylistHeader.x hands it over), and until that has
// loaded the field is the neutral one, as it is for a playlist with no cover at all.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"

NSString *const SGRPlaylistListIdentifier = @"SPTFreeTierPlaylistTableView";

// Above for the bounce at the top of the list, below for the one at the end of it.
static const UIEdgeInsets kBleed = {600, 0, 600, 0};

static char kFieldKey;

#pragma mark - the page's field

static SGRArtworkField *fieldOn(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        SGRArtworkField *field = objc_getAssociatedObject(v, &kFieldKey);
        if (field) return field;
    }
    return nil;
}

UIColor *SGRPlaylistFieldColor(UIView *view) {
    SGRArtworkField *field = fieldOn(view);
    return field.fieldColor ?: SGRNeutralField();
}

void SGRPlaylistSetArtwork(UIView *view, UIImage *image) {
    if (image) [fieldOn(view) setArtwork:image identity:nil animated:YES];
}

static SGRArtworkField *fieldIn(UIView *page) {
    SGRArtworkField *field = objc_getAssociatedObject(page, &kFieldKey);
    if (field) return field;
    field = [[SGRArtworkField alloc] initWithFrame:page.bounds];
    field.bleed = kBleed;
    objc_setAssociatedObject(page, &kFieldKey, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakPage = page;
    [field whenColored:^{ SGRRevealMark(weakPage, SGRRevealColor); }];
    SGLog(@"redesign playlist: field on the page %.0fx%.0f", page.bounds.size.width, page.bounds.size.height);
    return field;
}

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    if (!page || page.bounds.size.height < 200) return;
    sgr_playlistRoot = page;
    // Behind a curtain until the cover, the field's colour, the header and the first track are all in, so the
    // page comes in at once rather than a piece at a time (Kit/SGRReveal.h). A playlist is always laid out by
    // the redesign, so it waits for all of them from the first pass.
    SGRRevealHold(page, SGRRevealPage);
    SGRArtworkField *field = fieldIn(page);
    if (field.superview != page) [page insertSubview:field atIndex:0];
    else if (page.subviews.firstObject != field) [page sendSubviewToBack:field];
    if (!CGRectEqualToRect(field.frame, page.bounds)) field.frame = page.bounds;
}

// The page the repaint hook keeps clear is the one on screen; another playlist pushed over this one sets
// itself from its own pass, and this one sets itself again when it comes back.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    if (page) sgr_playlistRoot = page;
}
%end

// The list paints itself the base surface from its own pass rather than through a layer that the repaint
// hook would hear about, so it is cleared where it is laid out.
%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    UIScrollView *list = (UIScrollView *)self;
    if (list.backgroundColor && SGIsBaseSurface(list.backgroundColor.CGColor)) list.backgroundColor = UIColor.clearColor;
}
%end

%ctor {
    // Registered whatever the switch says: the flag rows elsewhere lock to these while it is on.
    SGRedesignForceFlags(@"playlist", @{
        // The page the trees were recorded with (trees/clean/playlist/02.txt).
        @"ios-feature-freetierplaylist.use_collection_view": @YES,
        // More stays in Spotify's own header row, concealed with the rest of the block, and the redesign
        // pins its own glass ⋯ over the page (Kit/SGRActionRow.h). Moving it into the navigation bar --
        // which this flag is Spotify's own way of doing, and which the redesign forced until 2026-09-20 --
        // put it somewhere Spotify empties on the way down the page: scrolled, the bar's trailing slot held
        // an empty 48x44 view and there was no ⋯ anywhere (trees/continuous/1.txt, issue #57).
        @"ios-feature-freetierplaylist.context_menu_in_navigation_bar_enabled": @NO,
        // A row is a cover, a title and an artist. The video badge is none of them.
        @"ios-feature-freetierplaylist.hide_video_badge_for_tracks": @YES,
        // The curation row keeps Sort and Mix and gives the rest up to ⋯ (PlaylistRows.x). It scrolls away
        // with the tracks rather than pinning itself over them, as the Music app's sort does.
        @"ios-feature-freetierplaylist.pin_curation_actions": @NO,
    });
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController",
        @"_TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView",
    ]);
}
