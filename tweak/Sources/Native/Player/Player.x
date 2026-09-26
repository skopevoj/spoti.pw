// Full screen player: glass where Liquid Glass belongs and nowhere else, and the album colour
// behind it traded for the cover art.
//
// Glass is the navigation layer floating over content, so only the header's two round buttons get
// a pane, the way the Music app keeps its chrome. The playlist name between them is a label, and
// shuffle, repeat, previous, next and the footer (connect, share, queue) are bare glyphs over the
// artwork next to Spotify's white play disc: a pane each turned both rows into a strip of glass
// discs sampling one another, which is the one thing the material cannot do. The cards below the
// player are surfaces rather than controls; the lyrics one is in LyricsCard.x.
//
// Tree (trees/now-playing.txt): NowPlaying_ModesImpl units, each a child controller whose view
// holds one UIStackView row; the header row is chevron 48x48, playlist name 110x48, more 48x48.
//
// The background is one plane the size of the screen painted the album colour, Spotify's gradients
// on top of it, and it is NPVBackgroundViewController's own view. Glass over a flat fill samples
// that same flat fill back, which is why the header panes cannot be made out on it; white text and
// Spotify's green both sit badly on saturated colour as well. SGKeyPlayerBackdrop strips the plane
// and puts the cover behind the player instead, shrunk until none of the picture is left in it,
// blurred, under a scrim ending near black so the cards scrolled up from below meet it. The switch
// covers what that field changes around it too: the artwork takes corners and a shadow so it sits
// on the field rather than being pasted onto it, the lyric under it drops behind the title in
// contrast, and the timestamps take monospaced digits so they stop twitching every second.
#import "Core/SGCore.h"
#import "Native/Appearance/Repaint.h"
#import "NowPlaying.h"
#import "Native/Appearance/Appearance.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import <MediaPlayer/MediaPlayer.h>

static const CGFloat kButtonMin = 36, kButtonMax = 48;
static const CGFloat kArtRadius = 12;

static BOOL backdropOn(void) {
    return SGFlag(SGKeyPlayerBackdrop, NO);
}

#pragma mark - glass behind the header buttons

// A glass circle per round button in the unit's row: children about as wide as they are tall.
// The playlist name is 110 wide against 48 tall, so it keeps no pane, and neither do the children
// PlayerDeclutter.x made invisible.
static void glassBehindRoundButtons(UIViewController *unit) {
    if (!SGFlag(SGKeyPlayer, NO)) return;
    UIView *host = unit.viewIfLoaded;
    UIStackView *row = SGRowIn(host);
    if (!row) return;
    [row layoutIfNeeded];
    NSUInteger index = 0;
    for (UIView *child in row.arrangedSubviews) {
        CGRect f = SGFrameIn(child, host);
        if (child.hidden || child.alpha == 0 || f.size.width < 20 || f.size.height < 20) continue;
        if (f.size.width > f.size.height * 1.4) continue;
        CGFloat side = MAX(kButtonMin, MIN(MAX(f.size.width, f.size.height), kButtonMax));
        UIVisualEffectView *glass = SGGlassAt(host, index++);
        // Dark whatever the system is set to: the player is presented outside the navigation stacks
        // Spotify makes dark itself, so its panes took the system's light glass on a phone in light mode.
        if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        glass.frame = CGRectMake(CGRectGetMidX(f) - side / 2, CGRectGetMidY(f) - side / 2, side, side);
        SGShapeGlass(glass, side / 2, YES);
    }
    SGHideGlassFrom(host, index);
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    glassBehindRoundButtons((UIViewController *)self);
}
%end

#pragma mark - the cover behind the player

static char kBackdropKey;

static UIImage *sg_cover;       // the cover the backdrop stands on, compared by pointer
static UIImage *sg_coverSmall;
static __weak UIImageView *sg_coverView;

static void showCover(UIImage *cover) {
    if (!cover || cover == sg_cover) return;
    sg_cover = cover;
    sg_coverSmall = SGBackdropSample(cover);
    UIImageView *view = sg_coverView;
    if (!view) return;
    [UIView transitionWithView:view duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        view.image = sg_coverSmall;
    } completion:nil];
}

// The covers are the cells of a list scrolled sideways, one per track in the queue; the cell under
// the middle of the list is the one playing.
static UIImage *coverInFront(UIScrollView *list) {
    CGFloat middle = list.contentOffset.x + list.bounds.size.width / 2;
    __block UIImage *cover = nil;
    // The cover is 354pt across, the glyph standing in for a missing one 64pt.
    __block CGFloat widest = 200;
    for (UIView *cell in list.subviews) {
        if (middle < CGRectGetMinX(cell.frame) || middle > CGRectGetMaxX(cell.frame)) continue;
        SGForEachView(cell, ^(UIView *view) {
            UIImageView *image = (UIImageView *)view;
            if (![view isKindOfClass:UIImageView.class] || !image.image || image.bounds.size.width <= widest) return;
            widest = image.bounds.size.width;
            cover = image.image;
        });
    }
    return cover;
}

// The local track's cover already reaches MPNowPlayingInfoCenter (the queue and lock screen use it),
// but the native full-screen player can leave its large image view on Spotify's placeholder. Prefer
// Spotify's cached local image path when the model exposes one, then use the matching system artwork.
static id objectResultForNoArgumentSelector(id object, SEL selector) {
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = object;
    invocation.selector = selector;
    [invocation invoke];
    __unsafe_unretained id result = nil;
    [invocation getReturnValue:&result];
    return result;
}

static UIImage *imageAtLocalValue(id value) {
    if ([value isKindOfClass:UIImage.class]) return value;
    NSMutableArray *candidates = [NSMutableArray array];
    if ([value isKindOfClass:NSURL.class]) [candidates addObject:value];
    if ([value isKindOfClass:NSString.class]) {
        NSURL *url = [NSURL URLWithString:value];
        if (url) [candidates addObject:url];
        [candidates addObject:value];
    }
    for (id candidate in candidates) {
        NSString *path = nil;
        if ([candidate isKindOfClass:NSURL.class] && [candidate isFileURL]) path = [candidate path];
        else if ([candidate isKindOfClass:NSString.class] && [candidate hasPrefix:@"/"]) path = candidate;
        SEL resolver = @selector(spt_localFileImagePath);
        if (!path && [candidate respondsToSelector:resolver]) {
            id resolved = objectResultForNoArgumentSelector(candidate, resolver);
            if ([resolved isKindOfClass:NSURL.class] && [resolved isFileURL]) path = [resolved path];
            else if ([resolved isKindOfClass:NSString.class] && [resolved hasPrefix:@"/"]) path = resolved;
        }
        if (path.length && [NSFileManager.defaultManager fileExistsAtPath:path]) {
            UIImage *image = [UIImage imageWithContentsOfFile:path];
            if (image) return image;
        }
    }
    return nil;
}

static BOOL sameTag(NSString *a, NSString *b) {
    if (!a.length || !b.length) return YES;
    return [a compare:b options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch] == NSOrderedSame;
}

static UIImage *localArtworkForTrack(SPTPlayerTrack *track) {
    NSString *trackKey = SGKaraokeTrackKeyFromURI(track.URI);
    if (!SGKaraokeTrackKeyIsLocal(trackKey)) return nil;

    static NSString *cachedTrack;
    static UIImage *cachedImage;
    if ([cachedTrack isEqualToString:trackKey] && cachedImage) return cachedImage;

    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url", @"image_small_url"]) {
        UIImage *image = imageAtLocalValue(metadata[field]);
        if (image) {
            cachedTrack = trackKey;
            cachedImage = image;
            return image;
        }
    }

    NSDictionary *nowPlaying = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    NSString *title = track.trackTitle;
    if (!title.length) {
        for (NSString *field in @[@"track_title", @"title", @"name"]) {
            if ([metadata[field] isKindOfClass:NSString.class] && [metadata[field] length]) { title = metadata[field]; break; }
        }
    }
    NSString *artist = track.artistName;
    if (!artist.length) {
        for (NSString *field in @[@"artist_name", @"artist"]) {
            if ([metadata[field] isKindOfClass:NSString.class] && [metadata[field] length]) { artist = metadata[field]; break; }
        }
    }
    NSString *systemTitle = nowPlaying[MPMediaItemPropertyTitle];
    NSString *systemArtist = nowPlaying[MPMediaItemPropertyArtist];
    // MediaPlayer sometimes omits one of these fields for a local item. Compare every field it does
    // provide, but don't reject its artwork just because Spotify's local model left a tag empty.
    if ((title.length && systemTitle.length && !sameTag(systemTitle, title)) ||
        (artist.length && systemArtist.length && !sameTag(systemArtist, artist))) return nil;

    id artwork = nowPlaying[MPMediaItemPropertyArtwork];
    UIImage *image = [artwork isKindOfClass:UIImage.class] ? artwork :
        [artwork isKindOfClass:MPMediaItemArtwork.class] ? [(MPMediaItemArtwork *)artwork imageWithSize:CGSizeMake(1200, 1200)] : nil;
    if (image) {
        cachedTrack = trackKey;
        cachedImage = image;
    }
    return image;
}

static UIImageView *coverViewInFront(UIScrollView *list) {
    CGFloat middle = list.contentOffset.x + list.bounds.size.width / 2;
    __block UIImageView *cover = nil;
    __block CGFloat widest = 200;
    for (UIView *cell in list.subviews) {
        if (middle < CGRectGetMinX(cell.frame) || middle > CGRectGetMaxX(cell.frame)) continue;
        SGForEachView(cell, ^(UIView *view) {
            if (![view isKindOfClass:UIImageView.class] || view.bounds.size.width <= widest) return;
            widest = view.bounds.size.width;
            cover = (UIImageView *)view;
        });
    }
    return cover;
}

static UIImageView *largeImageViewIn(UIView *root) {
    __block UIImageView *cover = nil;
    __block CGFloat widest = 200;
    SGForEachView(root, ^(UIView *view) {
        if (![view isKindOfClass:UIImageView.class] || view.bounds.size.width <= widest) return;
        widest = view.bounds.size.width;
        cover = (UIImageView *)view;
    });
    return cover;
}

static UIView *backdropIn(UIView *plane) {
    UIView *backdrop = objc_getAssociatedObject(plane, &kBackdropKey);
    if (backdrop) return backdrop;

    backdrop = SGBackdropMake(plane.bounds, SGFlag(SGKeyAmoled, NO) ? 1 : 0.94);
    UIImageView *cover = SGBackdropImageView(backdrop);
    cover.image = sg_coverSmall;
    sg_coverView = cover;

    objc_setAssociatedObject(plane, &kBackdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return backdrop;
}

%hook _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController
- (void)viewDidLayoutSubviews {
    %orig;
    if (!backdropOn()) return;
    UIView *plane = ((UIViewController *)self).viewIfLoaded;
    if (!plane || plane.bounds.size.height < 200) return;
    sg_npvBackdropRoot = plane;
    UIView *backdrop = backdropIn(plane);
    for (UIView *sub in plane.subviews) {
        if (sub != backdrop) SGStripBackgrounds(sub);
    }
    plane.layer.backgroundColor = NULL;
    if (backdrop.superview != plane) [plane insertSubview:backdrop atIndex:0];
}
%end

%hook _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView
- (void)layoutSubviews {
    %orig;
    SPTPlayerTrack *track = SGPlayerState().track;
    UIImage *local = track ? localArtworkForTrack(track) : nil;
    UIImageView *front = local ? coverViewInFront((UIScrollView *)self) : nil;
    if (front && front.image != local) {
        front.image = local;
        SGLog(@"player: local cached cover filled in the native player for %@", SGURIString(track.URI));
    }
    if (backdropOn()) showCover(coverInFront((UIScrollView *)self));
}
%end

#pragma mark - what the cover behind it changes around the player

%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)layoutSubviews {
    %orig;
    UIView *tilt = (UIView *)self;
    CGSize size = tilt.bounds.size;
    // The player's cover only; the bar downstairs carries a 40pt one of its own.
    if (size.width < 200) return;
    SPTPlayerTrack *track = SGPlayerState().track;
    UIImage *local = track ? localArtworkForTrack(track) : nil;
    UIImageView *cover = local ? largeImageViewIn(tilt) : nil;
    if (cover && cover.image != local) {
        cover.image = local;
        SGLog(@"player: local cached cover filled in CoverArtTiltView for %@", SGURIString(track.URI));
    }
    if (!backdropOn()) return;
    SGForEachView(tilt, ^(UIView *view) {
        if (view == tilt || !CGSizeEqualToSize(view.bounds.size, size)) return;
        view.layer.cornerRadius = kArtRadius;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.clipsToBounds = YES;
    });
    tilt.layer.shadowColor = UIColor.blackColor.CGColor;
    tilt.layer.shadowOpacity = 0.45;
    tilt.layer.shadowRadius = 32;
    tilt.layer.shadowOffset = CGSizeMake(0, 12);
    tilt.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:tilt.bounds cornerRadius:kArtRadius].CGPath;
}
%end

%hook _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (void)layoutSubviews {
    %orig;
    // White at full strength, and alone in the space under the artwork, the line reads louder than
    // the title it sits above. PlayerDeclutter.x hides the same view outright.
    if (backdropOn()) ((UIView *)self).alpha = 0.72;
}
%end

static UIFont *timeFont(void) {
    static UIFont *font;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    });
    return font;
}

%hook _TtC20NowPlaying_ModesImpl19DurationElementUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = backdropOn() ? ((UIViewController *)self).viewIfLoaded : nil;
    if (!host) return;
    SGForEachView(host, ^(UIView *view) {
        UILabel *label = (UILabel *)view;
        if (![view isKindOfClass:UILabel.class] || label.font.pointSize > 11 || label.font == timeFont()) return;
        label.font = timeFont();
    });
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit",
        @"_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController",
        @"_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView",
        @"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView",
        @"_TtC22Lyrics_NPVContainerKit19LyricsContainerView",
        @"_TtC20NowPlaying_ModesImpl19DurationElementUnit",
    ]);
}
