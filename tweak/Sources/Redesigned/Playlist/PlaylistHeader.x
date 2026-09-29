// Playlist redesign: the header the Music app gives a playlist (iOS 26.4). The cover runs full bleed across
// the top of the page and dissolves into the page's colour; the title, the creator and the length are centred
// on the bottom of that dissolve; under them one row -- shuffle, a white Play capsule, and save (someone
// else's playlist) or download (one's own, Liked Songs) -- and the description last.
//
// Tree (trees/clean/playlist/01.txt:640-869). Spotify's header is id=PL.Header, and at rest its
// HeaderContentLayout starts at the very top of the page. It holds exactly two things:
//
//     Components.Header.UI.ArtworkImage   a ShadowContainer, the cover square, centred at {80, 68} 243x243
//     the block                           a plain UIView at {0, 327} 386x178: a column of title, description,
//                                         creator row and length, and under it the action row
//
// A mix Spotify makes (Indie Rock Mix, Discover Weekly) is laid out the same way but draws its cover
// differently: there is no artwork square, and in its place a HeaderFullbleedCentralView holds the picture
// full bleed with Spotify's own big title over the bottom of it (trees/continuous/4.txt:1066). So the cover
// is whichever of the two the layout has, and the block is the one thing that is neither.
//
// Nothing is measured from what the header shows: -[SPTFreeTierPlaylistEncoreHeaderViewController update]
// counts a stored fullHeaderHeight and pins headerViewHeightConstraint to it. So the redesign changes no
// height: the cover's square is where the full bleed picture goes, and the block keeps its place, its size
// and its fading as the header collapses.
//
// What is in the block is the redesign's own (the Kit's SGRHeaderInfo), not Spotify's rearranged. Moving Spotify's
// column and controls meant answering every layout pass of theirs -- stacks re-arranging, Auto Layout putting
// frames back, buttons flashing where Spotify wanted them -- so Spotify's contents of the block are concealed
// whole and one view of the redesign's own is drawn in their place, which nothing of Spotify's lays out. It
// reads what it shows from the page's view model (FTPViewModelImplementation: the name, the description,
// whose playlist it is; device 2026-09-18) and from Spotify's concealed labels where the model has no getter
// (the creator, and the length line, already in the app's language). Its buttons draw Spotify's glyphs and
// fire Spotify's own concealed controls, so every action, state and language stays Spotify's.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"
#import <objc/message.h>

// How much of the cover's height the dissolve into the field covers, and the scrim over the top of it that
// keeps the status bar and the back button legible on a bright picture.
static const CGFloat kDissolve = 0.46, kTopScrim = 140, kTopScrimAlpha = 0.28;
// A header whose cover square is smaller than this is one mid collapse or mid load, not one to measure
// the hero from; and an artwork view narrower than this is a placeholder glyph rather than the cover.
static const CGFloat kMinHero = 120, kMinCover = 80;

static char kCoverKey, kMetaKey, kPlayKey, kLayoutKey, kToolbarKey, kScrimKey, kBarScrimKey;
static char kShuffleKey, kAddKey, kDownloadKey, kInfoKey, kBlockHeightKey, kBlockWatchedKey;
static char kHeroKey, kHeroHeightKey, kRestPlaneKey, kRowKey, kRowWatchedKey, kMoreKey, kCreatorKey, kPinnedMoreKey, kSortKey;

#pragma mark - finding things

@interface SGRWeakView : NSObject
@property (nonatomic, weak) UIView *view;
@end
@implementation SGRWeakView
@end

// The page the header is on: FTPViewController's own view, which holds the field, the list and the header
// and does not scroll. Walked from the header rather than taken off sgr_playlistRoot, so a playlist under
// another one on the stack pins its own ⋯ and not the one on top.
UIView *SGRPlaylistPageOf(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        if ([NSStringFromClass(r.class) containsString:@"FTPViewController"]) return ((UIViewController *)r).viewIfLoaded;
    }
    return nil;
}

UIViewController *SGRPlaylistHeaderOf(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        return [NSStringFromClass(r.class) containsString:@"FreeTierPlaylist"] ? (UIViewController *)r : nil;
    }
    return nil;
}

// Invisible for good, whatever Spotify does to it. It fades its cover square and its colour wash back in
// from the scroll itself (trees/continuous/1.txt, 2026-09-17), which a hidden layer shrugs off; but pressing
// Play reconfigures the header, and that shows the wash, the find bar and the play disc again with
// -setHidden:NO, which writes the layer's own hidden and so undid this: the wash came back over the
// picture as a dark band and the green disc beside the capsule (trees/continuous/1.txt, 2026-09-18).
//
// So two things, each for what the other cannot do. `hidden` on the layer costs nothing while it holds --
// the layer is not drawn at all -- and, unlike -[UIView setHidden:], tells neither KVO nor the stack views,
// which is what makes it safe on Spotify's Encore layouts. An empty mask is what holds when Spotify shows
// the view anyway: nothing Spotify does to these views touches a mask, and a layer masked by nothing draws
// nothing. The album page found the same (Album/AlbumHeader.x) and masks its gradients.
static void conceal(UIView *view) {
    if (!view) return;
    if (!view.layer.hidden) view.layer.hidden = YES;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static UIView *firstOfClass(UIView *root, Class wanted) {
    __block UIView *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!found && [v isKindOfClass:wanted]) found = v;
    });
    return found;
}

#pragma mark - the cover, full bleed

// The picture across the top of the page, a scrim over its top for the status bar, and its bottom masked
// away so the field shows through whatever colour it is at that height: pulled down, the hero ends where
// the field is already fading to black, and a fade to the field's flat colour showed as an edge.
@interface SGRPlaylistHero : UIView
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic) CGFloat coverPixels;   // the widest copy of the artwork it has been shown
// The cover in Spotify's artwork view, and every cover it puts there afterwards: the hero keeps itself
// right, rather than being handed a picture on each of the header's passes and staying empty between them.
- (void)followCover:(UIImageView *)source;
@end

@implementation SGRPlaylistHero {
    CAGradientLayer *_scrim, *_dissolve;   // the dissolve is the layer's mask
    __weak UIImageView *_cover;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;

    _picture = [[UIImageView alloc] initWithFrame:self.bounds];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    _picture.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_picture];

    // Above the picture's own layer whatever else is added to the view later.
    _scrim = [CAGradientLayer layer];
    _scrim.zPosition = 1;
    _scrim.colors = @[(id)[UIColor colorWithWhite:0 alpha:kTopScrimAlpha].CGColor, (id)UIColor.clearColor.CGColor];
    [self.layer addSublayer:_scrim];

    _dissolve = [CAGradientLayer layer];
    _dissolve.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor,
                         (id)[UIColor colorWithWhite:0 alpha:0.28].CGColor, (id)UIColor.clearColor.CGColor];
    self.layer.mask = _dissolve;
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrim.frame = CGRectMake(0, 0, bounds.size.width, MIN(kTopScrim, bounds.size.height));
    CGFloat height = MAX(1, bounds.size.height), fade = round(height * kDissolve);
    _dissolve.frame = bounds;
    _dissolve.locations = @[@0, @((height - fade) / height), @((height - fade * 0.38) / height), @1];
    [CATransaction commit];
}

- (void)followCover:(UIImageView *)source {
    if (!source) return;
    [self takeCover:source late:NO];
    if (_cover == source) return;
    _cover = source;
    __weak SGRPlaylistHero *weakSelf = self;
    SGRObserveImage(source, ^(UIImageView *view) { [weakSelf takeCover:view late:YES]; });
}

// Spotify loads the artwork at the size the cover square is asking for, and the square shrinks as the
// header collapses: scrolled down it swapped a 105px copy in for the 254px one and the picture across the
// top of the page went soft with it (trees/continuous/2.txt, 2026-09-17). So a copy is taken only while the
// square is still at full size, which is the only time Spotify asks for one worth showing.
//
// `late` is a cover that arrived after the header had laid out -- a playlist opened for the first time,
// whose artwork is still being fetched while the page is already on screen. The log line says once that the
// watch, and not one of the header's passes, is what filled the hero.
- (void)takeCover:(UIImageView *)source late:(BOOL)late {
    UIImage *image = source.image;
    if (!image || source.bounds.size.width < kMinHero || _picture.image == image) return;

    self.coverPixels = image.size.width;
    _picture.image = image;
    // The page's field takes its colour from the same picture.
    SGRPlaylistSetArtwork(self, image);
    static BOOL logged;
    if (late && !logged) {
        logged = YES;
        SGLog(@"redesign playlist: the cover landed after the header had laid out; the hero took it");
    }
}

@end

// The image view of Spotify's artwork square: the one with the cover in it, or, before the cover has been
// fetched, the empty one it will land in, so it can be watched from the first pass.
static UIImageView *coverImageIn(UIView *cover) {
    __block UIImageView *found = nil, *empty = nil;
    SGForEachView(cover, ^(UIView *v) {
        if (found || ![v isKindOfClass:UIImageView.class]) return;
        UIImageView *image = (UIImageView *)v;
        if (image.bounds.size.width < kMinCover) return;
        if (image.image) found = image;
        else if (!empty) empty = image;
    });
    return found ?: empty;
}

// The hero sits in the plane Spotify's colour wash is drawn on, which slides away as the header collapses, so
// Core Animation carries it and its frame is only measured at rest: reading the header per frame flickers.
// Pulled down past the top the plane grows and the hero stretches with it, bottom kept in place.
static void applyHero(UIView *layout, UIView *cover, UIView *plane, UIView *block, CGFloat reach, CGFloat stretch) {
    if (!plane || !block) return;
    SGRPlaylistHero *hero = objc_getAssociatedObject(plane, &kHeroKey);
    if (!hero) {
        hero = [[SGRPlaylistHero alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(plane, &kHeroKey, hero, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hero.superview != plane) [plane insertSubview:hero atIndex:0];
    else if (plane.subviews.firstObject != hero) [plane sendSubviewToBack:hero];

    // Grow-only: a header still loading puts the block higher than it ends up.
    CGFloat height = [objc_getAssociatedObject(hero, &kHeroHeightKey) doubleValue];
    CGFloat top = CGRectGetMinY(block.frame);
    if (stretch < 0.5 && top > height + 0.5) {
        height = top;
        objc_setAssociatedObject(hero, &kHeroHeightKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign playlist: hero %.0fpt across the top of the plane", height);
    }
    if (height < kMinHero) return;
    // On past the block's top by `reach`, so the title sits on the bottom of the dissolve the way the Music app
    // sets it on the picture. `reach` comes from the block at rest (applyHeader).
    CGFloat bottom = MAX(kMinHero, round(height + reach)) + stretch;
    // Flexible height as well, for a plane resized after this pass in the same frame.
    hero.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    CGRect frame = CGRectMake(0, 0, plane.bounds.size.width, bottom);
    if (!CGRectEqualToRect(hero.frame, frame)) hero.frame = frame;

    [hero followCover:coverImageIn(cover)];
    conceal(cover);
}

#pragma mark - the block, the redesign's own

// The page's view model: the header controller's defaultHeaderViewModel, FTPViewModelImplementation on every
// playlist, Liked Songs and a shared playlist alike (device, 2026-09-18). Its getters are plain ObjC --
// playlistName and playlistDescription @, isOwnedBySelf B, formatListType @ (Spotify 9.1.78) -- and each is
// checked before it is called, so a Spotify without one shows Spotify's text for it rather than crashing.
static id viewModelOf(UIViewController *headerVC) {
    SEL controllerSel = NSSelectorFromString(@"headerController"), modelSel = NSSelectorFromString(@"defaultHeaderViewModel");
    if (![headerVC respondsToSelector:controllerSel]) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)(headerVC, controllerSel);
    if (![controller respondsToSelector:modelSel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(controller, modelSel);
}

static NSString *modelString(id model, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (![model respondsToSelector:sel]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(model, sel);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static BOOL modelFlag(id model, NSString *name, BOOL fallback) {
    SEL sel = NSSelectorFromString(name);
    if (![model respondsToSelector:sel]) return fallback;
    return ((BOOL (*)(id, SEL))objc_msgSend)(model, sel);
}

// A description is HTML: links to other playlists as <a> and entities for quotes and ampersands.
static NSString *plainText(NSString *html) {
    if (!html.length) return nil;
    static NSRegularExpression *tags;
    if (!tags) tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:NULL];
    NSMutableString *text = [[tags stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0, html.length)
                                                       withTemplate:@""] mutableCopy];
    NSDictionary<NSString *, NSString *> *entities = @{@"&amp;": @"&", @"&quot;": @"\"", @"&#x27;": @"'", @"&#39;": @"'",
                                                       @"&lt;": @"<", @"&gt;": @">", @"&nbsp;": @" "};
    for (NSString *entity in entities) {
        [text replaceOccurrencesOfString:entity withString:entities[entity] options:0 range:NSMakeRange(0, text.length)];
    }
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length ? trimmed : nil;
}

static NSString *firstText(UIView *root, UIView *skip) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (found || ![v isKindOfClass:UILabel.class] || (skip && [v isDescendantOfView:skip])) return;
        NSString *text = [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length > 1) found = text;
    });
    return found;
}

// The creator is on no getter of the page's model; Spotify's own creator row has the name beside the facepile
// (its avatars, whose initial is a one-letter label of its own: "D | Darkk" on the device, 2026-09-18). A
// shared playlist's reads "Darkk" as well, with the others in the facepile. Looked for no further up than the
// facepile's own row, where the title would be the next label found.
static NSString *creatorIn(UIView *block) {
    __block UIView *facepile = nil;
    SGForEachView(block, ^(UIView *v) {
        if (!facepile && [NSStringFromClass(v.class) containsString:@"FacepileView"]) facepile = v;
    });
    UIView *row = facepile.superview;
    for (NSUInteger level = 0; row && row != block && level < 3; level++, row = row.superview) {
        NSString *name = firstText(row, facepile);
        if (name) return name;
    }
    return nil;
}

// The length line, as Spotify words it in the app's language: "8 saves • 41h 14m", "1 038 songs".
static NSString *lengthIn(UIView *block) {
    return firstText(SGRFindByIdentifier(block, @"Components.Header.UI.Metadata", &kMetaKey), nil);
}

// What the playlist's header shows: the name and the description from the page's model, the creator and the
// length from Spotify's concealed labels, and on Play's right save for someone else's playlist, download for
// one's own and for Liked Songs, which Spotify reports as neither owned nor unsaved (isOwnedBySelf NO,
// formatListType liked-songs).
static void showPlaylist(SGRHeaderInfo *info, UIView *block, UIView *root, id model) {
    NSString *title = modelString(model, @"playlistName") ?: firstText(block, nil);
    [info showTitle:title creator:creatorIn(block) length:lengthIn(block)
              about:plainText(modelString(model, @"playlistDescription"))];

    BOOL liked = [modelString(model, @"formatListType") isEqualToString:@"liked-songs"];
    BOOL own = modelFlag(model, @"isOwnedBySelf", YES) || liked;
    UIView *shuffle = SGRFindByIdentifier(block, @"Components.UI.ShuffleButton", &kShuffleKey);
    UIView *play = SGRFindByIdentifier(root, @"header-play-button", &kPlayKey);
    UIView *save = own ? nil : SGRFindByIdentifier(block, @"Components.UI.AddToButton", &kAddKey);
    UIView *download = save ? nil : SGRFindByIdentifier(block, @"DownloadButton.Granular*", &kDownloadKey);
    [info showShuffle:shuffle play:play trailing:save ?: download
     trailingFallback:[UIImage systemImageNamed:save ? @"plus" : @"arrow.down"] playColor:SGRPlaylistFieldColor(info)];
    // Only what the button draws goes: a concealed layer still sends the actions the capsule fires.
    conceal(play);

    // Whoever made the playlist, opened from the line that names them. Spotify's own button carries the
    // facepile and the name and takes the tap to a profile -- or, for a playlist several people are on, to
    // the picker it opens itself (issue #56).
    [info showCreatorLink:SGRFindByIdentifier(block, @"Components.PlaylistHeader.collaboratorsButton", &kCreatorKey)];

    // More, pinned over the page rather than left in the block, which is concealed and scrolls away; and
    // Spotify's own Sort, from the find-on-page toolbar this header conceals, for the ⋯ sheet to fire.
    UIView *page = SGRPlaylistPageOf(root);
    SGRPinnedMore(page, &kPinnedMoreKey, SGRFindByIdentifier(block, @"Components.UI.ContextMenuButton*", &kMoreKey));
    SGRPlaylistTakeSort(page, SGRFindByIdentifier(root, @"Components.Header.UI.Toolbar.Button", &kSortKey));

    static BOOL logged;
    if (!logged && info.window && (title || play)) {
        logged = YES;
        SGLog(@"redesign playlist: own block \"%@\" by %@, \"%@\"; shuffle %@, play %@, %@; model %@",
              title, creatorIn(block) ?: @"nobody", lengthIn(block) ?: @"no length", shuffle ? @"found" : @"missing",
              play ? @"found" : @"missing", save ? @"save" : (download ? @"download" : @"nothing on the right"),
              model ? NSStringFromClass([model class]) : @"missing");
    }
}

static SGRHeaderInfo *applyInfo(UIView *block, UIView *headerRoot, UIViewController *headerVC);

// `view`'s own pass puts the block together again, installed once under `key`.
static void reapplyOnPass(UIView *view, const void *key, UIView *block, UIView *headerRoot, UIViewController *headerVC) {
    if (!view || objc_getAssociatedObject(view, key)) return;
    objc_setAssociatedObject(view, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakBlock = block, *weakRoot = headerRoot;
    __weak UIViewController *weakVC = headerVC;
    SGRObserveLayout(view, ^(UIView *laidOut) {
        // A block the view has since left is Spotify's to lay out alone.
        if (!weakBlock || !weakRoot || !weakVC || [objc_getAssociatedObject(weakRoot, &kInfoKey) superview] != weakBlock) return;
        applyInfo(weakBlock, weakRoot, weakVC);
    });
}

// The block's own content goes, whole, and the redesign's takes its place. Spotify adds to the block as the page
// loads and shows parts of it again when Play is pressed, so everything of Spotify's in it is concealed on every
// pass and again from the block's own pass; concealing is idempotent and costs nothing once done.
static SGRHeaderInfo *applyInfo(UIView *block, UIView *headerRoot, UIViewController *headerVC) {
    // One per page, kept on the header's root: if Spotify ever hands over another block, the same view moves
    // into it rather than a second one being drawn beside the first.
    SGRHeaderInfo *info = objc_getAssociatedObject(headerRoot, &kInfoKey);
    if (!info) {
        info = [[SGRHeaderInfo alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(headerRoot, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (info.superview != block) {
        if (info.superview) SGLog(@"redesign playlist: the block moved, %@ -> %@", NSStringFromCGRect(info.superview.frame), NSStringFromCGRect(block.frame));
        [block addSubview:info];
    }
    else if (block.subviews.lastObject != info) [block bringSubviewToFront:info];
    for (UIView *sub in block.subviews) {
        if (sub != info) conceal(sub);
    }
    // The page's width, centred on the screen: Spotify's block is 16pt narrower than the page (386 of 402).
    CGFloat x = -[block convertPoint:CGPointZero toView:headerRoot].x;
    CGRect frame = CGRectMake(round(x), 0, headerRoot.bounds.size.width, block.bounds.size.height);
    if (!CGRectEqualToRect(info.frame, frame)) info.frame = frame;
    showPlaylist(info, block, headerRoot, viewModelOf(headerVC));

    reapplyOnPass(block, &kBlockWatchedKey, block, headerRoot, headerVC);
    // Save arrives after the header has laid out on a playlist opened for the first time, in a row that lays
    // nothing else out: Play's right drew download, or nothing, until the page was opened again (issue #19). The
    // row's own pass is watched too, a plain UIStackView, as the album's and the artist's are.
    reapplyOnPass(SGRFindByIdentifier(block, @"HeaderActionsRow", &kRowKey), &kRowWatchedKey, block, headerRoot, headerVC);
    return info;
}

#pragma mark - the header's pass

// Find on this page and Sort sit above the cover, shown as the page is pulled down. They stay Spotify's own
// controls, so the tap opens Spotify's find page; only the grey box becomes glass.
static void glassUp(UIView *box, const void *key) {
    CGSize size = box.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    if (box.backgroundColor != UIColor.clearColor) box.backgroundColor = UIColor.clearColor;
    if (box.layer.cornerRadius != size.height / 2) box.layer.cornerRadius = size.height / 2;
    SGRGlassCapsuleInside(box, key, size, NO);
}

static void applyToolbar(UIView *headerRoot) {
    static char kFieldKey, kSortBoxKey, kFieldGlassKey, kSortGlassKey;
    UIView *toolbar = SGRFindByIdentifier(headerRoot, @"Components.Header.UI.Toolbar.Content", &kToolbarKey);
    if (!toolbar) return;
    UIView *field = SGRFindByIdentifier(toolbar, @"Components.Header.UI.Toolbar.SearchField", &kFieldKey);
    glassUp(field, &kFieldGlassKey);
    glassUp(SGRFindByIdentifier(toolbar, @"Components.Header.UI.Toolbar.ButtonContainer", &kSortBoxKey), &kSortGlassKey);
    static BOOL logged;
    if (!logged && field.window) {
        logged = YES;
        SGLog(@"redesign playlist: find field %@ in glass, %.0fx%.0f", field.accessibilityLabel,
              field.bounds.size.width, field.bounds.size.height);
    }
}

// Two scrims Spotify fades in under the navigation bar as the page scrolls, each tinted with its own colour
// for the page rather than the field's: LiquidGlass.gradientContainer (124pt, a child of HeaderLayout) and
// the HeaderNavigationBar's GradientView. On Liked Songs the first is Spotify's blue, a band across the top
// of a black page (trees/continuous/2.txt, 2026-09-18). UIKit's own scroll edge effect is still there under
// the bar and keeps the back button legible, as on Home, Search and Library. Concealed rather than faded:
// Spotify writes their alpha on every step of the scroll, and the navigation bar's with -setHidden:.
static void applyScrims(UIView *headerRoot) {
    conceal(SGRFindByIdentifier(headerRoot, @"LiquidGlass.gradientContainer", &kScrimKey));
    // A concealed view stays concealed, so the bar is looked for until it is found and then never again:
    // the header lays out on every step of its collapse.
    if (objc_getAssociatedObject(headerRoot, &kBarScrimKey)) return;
    static Class bar;
    if (!bar) bar = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit19HeaderNavigationBar");
    UIView *navigation = firstOfClass(headerRoot, bar);
    for (UIView *sub in navigation.subviews) {
        if (![NSStringFromClass(sub.class) containsString:@"GradientView"]) continue;
        conceal(sub);
        objc_setAssociatedObject(headerRoot, &kBarScrimKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Spotify's colour wash goes, so the page's field shows through, and the plane it was drawn on is handed
// back: it is where the hero belongs (applyHero).
//
// The wash is a gradient on a plain view of its own, and that view is painted the base surface. Spotify
// keeps it at alpha 0 on an ordinary playlist, so concealing the gradient was enough; with the Mix feature
// turned on it raises the alpha and the view -- opaque black, drawn after the hero -- covered the picture
// whole (device, trees/continuous/1.txt 2026-09-20, issue #53). So the paint comes off everything on the
// plane as well, which is the same thing the field does to the rest of the page. The hero is left alone:
// the picture is drawn in it.
static UIView *applyBackground(UIView *layout) {
    UIView *container = nil;
    for (UIView *v = layout.superview; v && !container; v = v.superview) {
        for (UIView *sub in v.subviews) {
            if ([sub.accessibilityIdentifier isEqualToString:@"_backgroundViewContainer"]) container = sub;
        }
    }
    UIView *plane = container.subviews.firstObject;
    SGRPlaylistHero *hero = objc_getAssociatedObject(plane, &kHeroKey);
    SGForEachView(container, ^(UIView *v) {
        if (hero && (v == hero || [v isDescendantOfView:hero])) return;
        if ([NSStringFromClass(v.class) containsString:@"GradientView"]) {
            conceal(v);
            return;
        }
        CGColorRef color = v.layer.backgroundColor;
        if (color && SGIsBaseSurface(color)) v.backgroundColor = UIColor.clearColor;
    });
    return plane;
}

// The full bleed picture a mix is given instead of the artwork square: a child of the layout, as wide as the
// page and at the top of it.
static UIView *fullbleedIn(UIView *layout) {
    static Class fullbleed;
    if (!fullbleed) fullbleed = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit26HeaderFullbleedCentralView");
    for (UIView *sub in layout.subviews) {
        if ([sub isKindOfClass:fullbleed]) return sub;
    }
    return nil;
}

// The layout holds the cover square and, under it, the block of text and controls: the one child nearly as
// wide as the page. Taken by width, not by being lowest: Liked Songs' layout also holds a 45pt slot for its
// icon, which while the page loads sits below the block, and taken for it the header was drawn twice, once
// in the slot and once in the block (device, 2026-09-18).
//
// A mix's full bleed picture is as wide as the page too, and while the block is still unmeasured it is the
// only child wide enough to be taken for it -- which drew the redesign inside it and concealed the picture
// along with the rest of what it holds, leaving a black hero for good, since concealing does not come undone
// (trees/continuous/3.txt against 4.txt, 2026-09-20). It is never the block, so it is skipped like the cover.
static UIView *blockIn(UIView *layout, UIView *cover, UIView *fullbleed) {
    UIView *block = nil;
    CGFloat wide = layout.bounds.size.width * 0.6;
    for (UIView *sub in layout.subviews) {
        if (sub == cover || sub == fullbleed || [sub isKindOfClass:SGRPlaylistHero.class] || sub.bounds.size.width < wide) continue;
        if (!block || CGRectGetMinY(sub.frame) > CGRectGetMinY(block.frame)) block = sub;
    }
    return block;
}

static void applyHeader(UIView *layout) {
    UIViewController *headerVC = SGRPlaylistHeaderOf(layout);
    UIView *headerRoot = headerVC.viewIfLoaded;
    if (!headerRoot) return;

    // A playlist's artwork square, or a mix's full bleed picture where there is no square. Either way it is
    // the view the picture is read from and the view that is concealed once the hero is drawing it.
    UIView *fullbleed = fullbleedIn(layout);
    UIView *cover = SGRFindByIdentifier(layout, @"Components.Header.UI.ArtworkImage", &kCoverKey) ?: fullbleed;
    UIView *block = blockIn(layout, cover, fullbleed);
    if (!block) return;

    UIView *plane = applyBackground(layout);
    applyToolbar(headerRoot);
    applyScrims(headerRoot);
    SGRHeaderInfo *info = applyInfo(block, headerRoot, headerVC);

    // How far the page is pulled down past the top: the plane grows by that much and the block moves with it,
    // so nothing is measured then. Rest is the smallest the plane has been.
    CGFloat planeHeight = plane.bounds.size.height;
    CGFloat restPlane = [objc_getAssociatedObject(plane, &kRestPlaneKey) doubleValue];
    if (planeHeight > 0 && (restPlane <= 0 || planeHeight < restPlane - 0.5)) {
        restPlane = planeHeight;
        objc_setAssociatedObject(plane, &kRestPlaneKey, @(restPlane), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(objc_getAssociatedObject(plane, &kHeroKey), &kHeroHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(block, &kBlockHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat stretch = MAX(0, planeHeight - restPlane);

    // How far into the block the picture reaches: past the block's top by the title and the creator. The
    // block's height only grows (loading the description grows it, collapsing shrinks it).
    CGFloat rest = [objc_getAssociatedObject(block, &kBlockHeightKey) doubleValue];
    if (stretch < 0.5 && block.bounds.size.height > rest) {
        rest = block.bounds.size.height;
        objc_setAssociatedObject(block, &kBlockHeightKey, @(rest), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat reach = rest - SGRHeaderInfoBottom - [info contentHeightForWidth:info.bounds.size.width] + SGRHeaderInfoTitleRise;
    if (cover) applyHero(layout, cover, plane, block, reach, stretch);
}

// The content layout of the page `root` belongs to, kept weakly on it: the header lays out on every step of
// its collapse and a walk of its tree each time would be the redesign's own cost.
static UIView *layoutIn(UIView *root) {
    if (!root) return nil;
    SGRWeakView *box = objc_getAssociatedObject(root, &kLayoutKey);
    UIView *layout = box.view;
    if (layout && [layout isDescendantOfView:root]) return layout;
    static Class content;
    if (!content) content = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout");
    layout = firstOfClass(root, content);
    if (!layout) return nil;
    if (!box) {
        box = [SGRWeakView new];
        objc_setAssociatedObject(root, &kLayoutKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    box.view = layout;
    return layout;
}

%hook _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout
- (void)layoutSubviews {
    %orig;
    if (SGRPlaylistHeaderOf((UIView *)self)) applyHeader((UIView *)self);
}
%end

// The header's own pass catches the parts that fade in rather than being laid out: the find bar, and the
// action buttons as they arrive. The scroll's is where what Spotify fades back in is taken again.
// The play button arrives in the header's foreground plane after the row that replaces it has been laid
// out, so a page opening showed Spotify's green disc in the corner until something else laid the header out
// (device, 2026-09-17). Its own pass is where it goes, and the class is Spotify's own so nothing else pays
// for the check.
%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)self;
    if (button.layer.hidden || ![button.accessibilityIdentifier isEqualToString:@"header-play-button"]) return;
    if (SGRPlaylistHeaderOf(button)) conceal(button);
}
%end

%hook SPTFreeTierPlaylistEncoreHeaderViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *layout = layoutIn(((UIViewController *)self).viewIfLoaded);
    if (layout) applyHeader(layout);
}

// What the page's model says changes without a layout pass of the header's: the saves count comes in after the
// page opens (0, then 4647, device 2026-09-18), and a Save or an edit to the name updates it again.
- (void)update {
    %orig;
    UIView *layout = layoutIn(((UIViewController *)self).viewIfLoaded);
    if (layout) applyHeader(layout);
}

%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout",
        @"SPTFreeTierPlaylistEncoreHeaderViewController",
        @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView",
    ]);
}
