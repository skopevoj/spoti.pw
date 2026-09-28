// Album redesign: the header the Music app gives an album (iOS 26.4), the same one the playlist redesign
// gives a playlist. The cover runs full bleed across the top of the page and dissolves into the page's
// colour; the title, the artist and the kind and date are centred on the bottom of that dissolve; and under
// them one row -- shuffle, a white Play capsule, and add.
//
// Tree (trees/clean/album/01.txt:39-152). The header is one element of the page's scrolling stack,
// id=CreativeWorkPlatform.Components.UI.CreativeWorkHeader, a plain UIView whose height the element framework
// measures from what it holds, down a chain of four stack views:
//
//     UIView {0, 78}                     the top inset, the status bar and the navigation bar's room
//       UIStackView                      the two groups
//         UIView 402x321                 the top group: the cover square, a spacer, and the title block --
//                                        TitleRow, and ParentRow, the artist with a facepile
//         UIView {0, 329} 402x71         the bottom group: Components.UI.MetadataRow (the kind and the date,
//                                        cells of a collection view) and the action row
//
// What the header shows is the redesign's own (the Kit's SGRHeaderInfo), not Spotify's rearranged: moving
// Spotify's stacks meant answering every pass of theirs, and the element framework measured the title for
// its own font. So Spotify's whole column is concealed and the Kit's view is drawn over the header in its
// place, reading its text off Spotify's concealed labels -- so it is in the app's language and follows
// whatever Spotify shows -- and drawing and firing Spotify's own controls. The header keeps its height, its
// fade as the page scrolls and its place in the stack.
//
// Play and shuffle are not in the header. The album page floats them over the page, pinned to the top
// trailing corner outside the scroll (01.txt:1431, :1436): they are concealed where they are, and the row
// draws them and fires them all the same.
#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/LockScreenArtwork/SGAppleArtwork.h"
#import "Shared/LockScreenArtwork/SGArtworkFile.h"
#import "Shared/LockScreenArtwork/SGCanvas.h"
#import "Album.h"

// How much of the cover's height the dissolve into the field covers, and the scrim over the top of it that
// keeps the status bar and the back button legible on a bright picture. The playlist's numbers: one page.
static const CGFloat kDissolve = 0.46, kTopScrim = 140, kTopScrimAlpha = 0.28;
// A header whose text begins nearer the top than this is one mid load, not one to measure the hero from;
// and an artwork view narrower than this is a placeholder glyph rather than the cover.
static const CGFloat kMinHero = 120, kMinCover = 80;

static char kHeaderKey, kCoverKey, kTitleKey, kParentKey, kMetaKey, kAddKey, kDownloadKey, kPlayKey, kShuffleKey;
static char kHeroKey, kHeroHeightKey, kHeaderHeightKey, kInfoKey, kHeaderWatchedKey, kRetryKey;
static char kExploreKey, kRowWatchedKey, kMoreKey, kPinnedMoreKey;

#pragma mark - moving Spotify's views

// Invisible for good. Spotify fades the header and the two floating controls by alpha as the page scrolls,
// so a redesign that answers with alpha is in a fight it loses a frame of on every scroll. `hidden` on the
// layer cannot be undone by a write to alpha, costs nothing per frame, and, unlike -[UIView setHidden:],
// tells neither KVO nor the stack views of it, which is what makes it safe on Spotify's Encore layouts; an
// empty mask holds when Spotify shows the view again with -setHidden:NO, which the playlist page does when
// Play is pressed (Playlist/PlaylistHeader.x).
static void conceal(UIView *view) {
    if (!view) return;
    if (!view.layer.hidden) view.layer.hidden = YES;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

// Drawn by nothing but not hidden: for Spotify's own column of the header, which the redesign still reads. A
// hidden collection view makes no cells, and the kind and the date are cells ("no metadata" in the harness
// with the column hidden, 2026-09-18), so the column keeps laying itself out and only its drawing goes.
static void blank(UIView *view) {
    if (!view) return;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

// The outermost view that still wraps the control exactly: the element view Spotify's layout places, so
// concealing it leaves the control itself alone to be read and fired.
static UIView *wrapperFor(UIView *control, UIView *stop) {
    UIView *wrapper = control;
    for (UIView *v = control.superview; v && v != stop; v = v.superview) {
        if (fabs(v.bounds.size.width - control.bounds.size.width) > 4) break;
        if (fabs(v.bounds.size.height - control.bounds.size.height) > 4) break;
        wrapper = v;
    }
    return wrapper;
}

// One of the two controls Spotify floats over the page. They are direct children of the page and 48pt
// across, so only the small children are searched: the wash, the tab and the navigation bar are the width
// of the page, and walking into the tab would be walking the whole list on every pass that missed.
static UIView *floatingIn(UIView *page, NSString *identifier, const void *cacheKey) {
    for (UIView *sub in page.subviews) {
        if (sub.bounds.size.width > 120) continue;
        UIView *found = SGRFindByIdentifier(sub, identifier, cacheKey);
        if (found) return found;
    }
    return nil;
}

static void setFrame(UIView *view, CGRect frame) {
    if (view && !CGRectIsEmpty(frame) && !CGRectEqualToRect(view.frame, frame)) view.frame = frame;
}

// The stack Spotify arranges the header's buttons in: the first one above `button`.
static UIView *rowOf(UIView *button, UIView *header) {
    for (UIView *v = button.superview; v && v != header; v = v.superview) {
        if ([v isKindOfClass:UIStackView.class]) return v;
    }
    return nil;
}

// Installs `laidOut` on the view's own pass once, under `key`.
static void watch(UIView *view, const void *key, void (^laidOut)(UIView *view)) {
    if (!view || objc_getAssociatedObject(view, key)) return;
    objc_setAssociatedObject(view, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRObserveLayout(view, laidOut);
}

#pragma mark - the cover, full bleed

// The picture across the top of the page with the field showing through the bottom of it. Two gradients
// rather than a mask or a blur: a scrim over the top for the status bar, and under it a fade from the
// picture to the very colour the page's field is drawing, so the two meet with nothing to see.
@interface SGRAlbumHero : UIView
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic, copy) UIColor *fieldColor;
// The cover in Spotify's artwork view, and every cover it puts there afterwards: the hero keeps itself
// right, rather than being handed a picture on each of the header's passes and staying empty between them.
- (void)followCover:(UIImageView *)source;
// Apple Music's square animated cover over the picture, where it has one. The same album again is a no-op.
- (void)findMotionOf:(NSString *)album by:(NSString *)artist;
@end

static char kReadyContext;

@implementation SGRAlbumHero {
    CAGradientLayer *_scrim, *_dissolve;
    __weak UIImageView *_cover;
    NSString *_motionFor;
    NSURLSessionTask *_fetch;
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    AVPlayerLayer *_motion;
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

    _scrim = [CAGradientLayer layer];
    _scrim.zPosition = 1;
    _scrim.colors = @[(id)[UIColor colorWithWhite:0 alpha:kTopScrimAlpha].CGColor, (id)UIColor.clearColor.CGColor];
    [self.layer addSublayer:_scrim];

    _dissolve = [CAGradientLayer layer];
    _dissolve.zPosition = 2;
    [self.layer addSublayer:_dissolve];
    self.fieldColor = SGRNeutralField();
    // The colour is read off the main thread, so it can land after the last layout pass of the page.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sgr_fieldColorDidChange)
                                               name:SGRFieldColorDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_fetch cancel];
    [_motion removeObserver:self forKeyPath:@"readyForDisplay" context:&kReadyContext];
    [_player pause];
}

- (void)sgr_fieldColorDidChange {
    if (self.superview) self.fieldColor = SGRAlbumFieldColor(self);
}

- (void)setFieldColor:(UIColor *)color {
    if (!color || [_fieldColor isEqual:color]) return;
    _fieldColor = [color copy];
    // The clear end is the same colour with no alpha rather than +clearColor, so the fade keeps its hue
    // instead of going through grey.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _dissolve.colors = @[(id)[color colorWithAlphaComponent:0].CGColor,
                         (id)[color colorWithAlphaComponent:0.72].CGColor,
                         (id)color.CGColor];
    _dissolve.locations = @[@0, @0.62, @1];
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrim.frame = CGRectMake(0, 0, bounds.size.width, MIN(kTopScrim, bounds.size.height));
    CGFloat fade = round(bounds.size.height * kDissolve);
    _dissolve.frame = CGRectMake(0, bounds.size.height - fade, bounds.size.width, fade);
    _motion.frame = bounds;
    [CATransaction commit];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateMotion];
}

- (void)findMotionOf:(NSString *)album by:(NSString *)artist {
    if (!album.length || !artist.length || !SGFlag(SGRKeyAnimatedCovers, YES)) return;
    // Not even looked up while it could not move: the clip is megabytes.
    if (SGRReduceMotion() || NSProcessInfo.processInfo.lowPowerModeEnabled) return;
    NSString *wanted = [NSString stringWithFormat:@"%@\n%@", artist, album];
    if ([_motionFor isEqualToString:wanted]) return;
    _motionFor = wanted;
    __weak SGRAlbumHero *weakSelf = self;
    SGAppleArtworkFind(artist, album, NO, ^(SGCanvas *canvas, NSString *note) {
        SGRAlbumHero *hero = weakSelf;
        if (!hero || ![hero->_motionFor isEqualToString:wanted]) return;
        if (!canvas) {
            SGLog(@"redesign album: no animated cover for \"%@\": %@", album, note);
            return;
        }
        hero->_fetch = SGArtworkFetchAside(canvas.identifier, canvas.address, ^(NSURL *file, NSString *fetched) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SGRAlbumHero *owner = weakSelf;
                if (!owner || ![owner->_motionFor isEqualToString:wanted]) return;
                owner->_fetch = nil;
                SGLog(@"redesign album: animated cover for \"%@\", %@", album, fetched);
                if (file) [owner playMotion:file];
            });
        });
    });
}

// Muted, never on AirPlay, and letting the screen lock: a picture, not a video.
- (void)playMotion:(NSURL *)file {
    if (_motion) return;
    AVQueuePlayer *player = [AVQueuePlayer new];
    player.muted = YES;
    player.allowsExternalPlayback = NO;
    player.preventsDisplaySleepDuringVideoPlayback = NO;
    _looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:[AVPlayerItem playerItemWithURL:file]];
    _player = player;
    _motion = [AVPlayerLayer playerLayerWithPlayer:player];
    _motion.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _motion.zPosition = 0.5;
    _motion.opacity = 0;
    _motion.frame = self.bounds;
    [self.layer addSublayer:_motion];
    [_motion addObserver:self forKeyPath:@"readyForDisplay" options:0 context:&kReadyContext];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(updateMotionSoon) name:name object:nil];
    }
    [self updateMotion];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kReadyContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_motion.readyForDisplay || self->_motion.opacity > 0) return;
        [CATransaction begin];
        [CATransaction setAnimationDuration:SGRCrossfade];
        self->_motion.opacity = 1;
        [CATransaction commit];
    });
}

// The power state is reported off the main thread.
- (void)updateMotionSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateMotion]; });
}

// Only while the page is on screen and in front: a page under another one, or a tab away, holds still.
- (void)updateMotion {
    if (!_player) return;
    BOOL front = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    BOOL moving = self.window && front && !SGRReduceMotion() && !NSProcessInfo.processInfo.lowPowerModeEnabled;
    if (moving && _player.rate == 0) [_player play];
    else if (!moving && _player.rate != 0) [_player pause];
}

- (void)followCover:(UIImageView *)source {
    if (!source) return;
    [self takeCover:source late:NO];
    if (_cover == source) return;
    _cover = source;
    __weak SGRAlbumHero *weakSelf = self;
    SGRObserveImage(source, ^(UIImageView *view) { [weakSelf takeCover:view late:YES]; });
}

// `late` is a cover that arrived after the header had laid out -- an album opened for the first time, whose
// artwork is still being fetched while the page is already on screen. The log line says once that the watch,
// and not one of the header's passes, is what filled the hero.
- (void)takeCover:(UIImageView *)source late:(BOOL)late {
    UIImage *image = source.image;
    if (!image || source.bounds.size.width < kMinCover || _picture.image == image) return;
    _picture.image = image;
    // The page's field takes its colour from the same picture.
    SGRAlbumSetArtwork(self, image);
    SGRRevealMark(SGRAlbumPageOf(self), SGRRevealPicture);
    static BOOL logged;
    if (late && !logged) {
        logged = YES;
        SGLog(@"redesign album: the cover landed after the header had laid out; the hero took it");
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

// The picture runs from the top of the header down past where its text begins, so the title and the artist
// sit on the bottom of its dissolve; below that the page's field is already drawing the very colour the
// picture dissolves into, so there is no seam to see.
//
// `bottom` is taken from the header at rest, never from where it is mid scroll, and only ever grows: a header
// still loading is shorter than it will end up, and once the cover and the artist are in it settles and the
// picture does not change size again.
static void applyHero(UIView *header, UIView *cover, CGFloat bottom) {
    SGRAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
    if (!hero) {
        hero = [[SGRAlbumHero alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(header, &kHeroKey, hero, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hero.superview != header) [header insertSubview:hero atIndex:0];
    else if (header.subviews.firstObject != hero) [header sendSubviewToBack:hero];

    CGFloat height = [objc_getAssociatedObject(hero, &kHeroHeightKey) doubleValue];
    if (bottom > height + 0.5) {
        height = round(bottom);
        objc_setAssociatedObject(hero, &kHeroHeightKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign album: hero %.0fpt across the top of the header", height);
    }
    if (height < kMinHero) return;
    setFrame(hero, CGRectMake(0, 0, header.bounds.size.width, height));
    hero.fieldColor = SGRAlbumFieldColor(header);

    [hero followCover:coverImageIn(cover)];
    conceal(cover);
}

#pragma mark - what the header shows

static NSString *trimmed(NSString *text) {
    NSString *clean = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return clean.length ? clean : nil;
}

// The first label under `root` with more than a letter in it: the facepile's initials are labels of their own.
static NSString *firstText(UIView *root) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (found || ![v isKindOfClass:UILabel.class]) return;
        NSString *text = trimmed(((UILabel *)v).text);
        if (text.length > 1) found = text;
    });
    return found;
}

// The kind and the date ("Album • 31. 1. 2025", "Single • 2024") are cells of a collection view, a label each;
// read in the order they are drawn in.
static NSString *metadataText(UIView *metadata) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(metadata, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && trimmed(((UILabel *)v).text) && v.window) [labels addObject:(UILabel *)v];
    });
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ax = [a convertPoint:CGPointZero toView:metadata].x, bx = [b convertPoint:CGPointZero toView:metadata].x;
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UILabel *label in labels) [parts addObject:trimmed(label.text)];
    return parts.count ? [parts componentsJoinedByString:@" "] : nil;
}

static void applyHeader(UIView *header, UIView *page);

// The Kit's view over the whole header, its content on the header's bottom edge; Spotify's own column goes.
static SGRHeaderInfo *applyInfo(UIView *header, UIView *page) {
    SGRHeaderInfo *info = objc_getAssociatedObject(header, &kInfoKey);
    if (!info) {
        info = [[SGRHeaderInfo alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(header, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (info.superview != header) [header addSubview:info];
    else if (header.subviews.lastObject != info) [header bringSubviewToFront:info];
    SGRAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
    for (UIView *sub in header.subviews) {
        if (sub != info && sub != hero) blank(sub);
    }
    setFrame(info, header.bounds);

    UIView *title = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.TitleRow", &kTitleKey);
    UIView *parent = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.ParentRow", &kParentKey);
    UIView *metadata = SGRFindByIdentifier(header, @"Components.UI.MetadataRow", &kMetaKey);
    NSString *name = firstText(title), *length = metadataText(metadata);
    NSString *artist = firstText(parent) ?: trimmed(parent.accessibilityLabel);
    SGRAlbumSetArtist(page, artist);
    [info showTitle:name creator:artist length:length about:nil];
    [(SGRAlbumHero *)objc_getAssociatedObject(header, &kHeroKey) findMotionOf:name by:artist];
    // The kind and the date are cells the metadata row's collection view makes on its own pass, after the
    // header's, and nothing lays the header out again when they arrive; the collection is Spotify's own Swift
    // class, which cannot be watched. So an empty row is read again a moment later, for as long as the page's
    // curtain waits at most (Kit/SGRReveal.h): the page is shown once they are in, so soon is better.
    NSInteger tries = [objc_getAssociatedObject(header, &kRetryKey) integerValue];
    if (!length && metadata && tries < 12) {
        objc_setAssociatedObject(header, &kRetryKey, @(tries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakHeader = header, *weakPage = page;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weakHeader && weakPage) applyHeader(weakHeader, weakPage);
        });
    }

    // The artist under the title, opened from the line that names them. ParentRow is one control for the
    // whole line however many artists are on the album, so several of them open Spotify's own picker
    // (issue #56). Its facepile's pictures go before the name (issue #149).
    [info showCreatorLink:parent];
    [info showFacesIn:parent];

    // More, pinned over the page rather than left in the header, which is blanked and scrolls away.
    SGRPinnedMore(page, &kPinnedMoreKey, SGRFindByIdentifier(header, @"Components.UI.ContextMenuButton*", &kMoreKey));

    UIView *play = floatingIn(page, @"header-play-button", &kPlayKey);
    UIView *shuffle = floatingIn(page, @"Components.UI.ShuffleButton", &kShuffleKey);
    UIView *add = SGRFindByIdentifier(header, @"Components.UI.AddToButton", &kAddKey);
    UIView *download = add ? nil : SGRFindByIdentifier(header, @"DownloadButton.Granular*", &kDownloadKey);
    [info showShuffle:shuffle play:play trailing:add ?: download
     trailingFallback:[UIImage systemImageNamed:add ? @"plus" : @"arrow.down"] playColor:SGRAlbumFieldColor(header)];
    // Only what the two floating buttons draw goes: a concealed layer still sends the actions the row fires.
    if (play) conceal(wrapperFor(play, page));
    if (shuffle) conceal(wrapperFor(shuffle, page));
    // The kind and the date are waited for too: arriving late they pushed the title up by a line.
    if (name && play && length) SGRRevealMark(page, SGRRevealHeader);

    // Add arrives after the header has laid out on an album opened for the first time (the next time its state
    // is cached and it is there from the start), in a row that lays nothing else out (Native/Album/Album.x): the
    // row drew download on Play's right, or nothing, until the page was opened again (issue #19). So the row's
    // own pass is watched, a plain UIStackView, as the artist page's is, found from whichever of Spotify's
    // buttons is in it already.
    UIView *inRow = add ?: download ?: SGRFindByIdentifier(header, @"Components.UI.WatchFeedEntityExplorerButton", &kExploreKey);
    __weak UIView *weakHeader = header, *weakPage = page;
    watch(rowOf(inRow, header), &kRowWatchedKey, ^(UIView *view) {
        if (weakHeader && weakPage) applyHeader(weakHeader, weakPage);
    });

    static BOOL logged;
    if (!logged && header.window && title) {
        logged = YES;
        SGLog(@"redesign album: own block \"%@\" by %@, \"%@\"; shuffle %@, play %@, %@", firstText(title),
              firstText(parent) ?: @"nobody", metadataText(metadata) ?: @"no metadata", shuffle ? @"found" : @"missing",
              play ? @"found" : @"missing", add ? @"add" : (download ? @"download" : @"nothing on the right"));
    }
    return info;
}

#pragma mark - the header's pass

// Drawn by nothing, whatever Spotify does to it: an empty mask. Spotify switches the navigation bar's
// gradient on and off with -setHidden:, which writes the layer's own hidden and so undoes conceal(); and
// it fades both gradients by alpha. Neither touches a mask.
static void maskOut(UIView *view) {
    if (!view || view.layer.mask) return;
    view.layer.mask = [CALayer layer];
    view.accessibilityElementsHidden = YES;
}

// Spotify's colour wash behind the header goes, so the page's field shows through.
//
// The navigation bar's gradient goes too. Hidden at rest, it is shown as the page scrolls under the
// title, and over the field it was a flat dark band across the top (device, 2026-09-18). What keeps the
// title legible over the list is the soft top edge every redesigned page has (SGREdgeEffect.x), as it is
// on Home, Search and Library.
static void applyWash(UIView *page) {
    for (UIView *sub in page.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if (![name containsString:@"HeaderView"] && ![name containsString:@"HeaderNavigationBar"]) continue;
        for (UIView *v in sub.subviews) {
            if ([NSStringFromClass(v.class) containsString:@"GradientView"]) maskOut(v);
        }
    }
}

static void applyHeader(UIView *header, UIView *page) {
    if (!SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.TitleRow", &kTitleKey)) return;
    // An album's page: its curtain waits for all of it (AlbumField.x put it up).
    SGRRevealHold(page, SGRRevealPage);
    applyWash(page);
    SGRHeaderInfo *info = applyInfo(header, page);

    // The picture reaches to where the content's top is at rest, plus the title and the artist. The header at
    // rest is the tallest it has been, so the picture does not change size as the header loads or scrolls.
    CGFloat rest = MAX([objc_getAssociatedObject(header, &kHeaderHeightKey) doubleValue], header.bounds.size.height);
    objc_setAssociatedObject(header, &kHeaderHeightKey, @(rest), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat bottom = rest - SGRHeaderInfoBottom - [info contentHeightForWidth:header.bounds.size.width] + SGRHeaderInfoTitleRise;
    UIView *cover = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.ArtWorkElement.WithCoverArt", &kCoverKey);
    if (cover) applyHero(header, cover, bottom);
}

static void applyPage(UIView *page) {
    UIView *header = SGRFindByIdentifier(page, @"CreativeWorkPlatform.Components.UI.CreativeWorkHeader", &kHeaderKey);
    if (!header) return;
    applyHeader(header, page);
    // The header lays itself out again whenever its cover, its artist or its buttons arrive, which the
    // page's own pass does not hear about. It is a plain UIView, so its pass can be watched.
    watch(header, &kHeaderWatchedKey, ^(UIView *view) {
        UIView *owner = SGRAlbumPageOf(view);
        if (owner) applyHeader(view, owner);
    });
}

%hook _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView
- (void)layoutSubviews {
    %orig;
    applyPage((UIView *)self);
}
%end

// The play button arrives in the page after the row that replaces it has been laid out, so a page opening
// showed Spotify's green disc in the corner until something else laid the page out. Its own pass is where
// it goes, and the class is Spotify's own so nothing else pays for the check.
%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)self;
    if (button.layer.hidden || ![button.accessibilityIdentifier isEqualToString:@"header-play-button"]) return;
    UIView *page = SGRAlbumPageOf(button);
    if (!page) return;
    conceal(wrapperFor(button, page));
    applyPage(page);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView",
        @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView",
    ]);
}
