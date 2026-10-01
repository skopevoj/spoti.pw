// Player declutter: hides parts of the full screen player, one switch each on the Player page. Cards
// under the player are Element_List cells; a hidden one reports zero height when the list sizes it,
// so the list closes up around it (the 24pt gap between cards stays). Player buttons go invisible but
// keep their place, so their row stays centred.
//
// Trees (trees/now-playing*.txt): every card is a CollectionViewCell whose content view names the
// page (NowPlaying_ScrollAPI) and whose subtree names the card. Player rows are the UIStackView of each NowPlaying_ModesImpl unit: playback controls
// hold shuffle, previous, play, next, repeat; the footer holds connect, a hidden button, share
// and the queue; track info ends with the add-to button.
#import "Core/SGCore.h"
#import "NowPlaying.h"

#pragma mark - cards and sections

static const struct { __unsafe_unretained NSString *marker, *key; } cards[] = {
    {@"Lyrics_CardElementImpl", SGHideLyricsCard},
    {@"CreatorBiography", SGHideAboutArtist},
    {@"VideoRecommendations", SGHideRelatedVideos},
    {@"SongDNA_", SGHideSongDNA},
    {@"LiveEvents_", SGHideLiveEvents},
    {@"WatchFeed_", SGHideExploreArtist},
    {@"Creator_Credits", SGHideCredits},
    {@"Merch_", SGHideMerch},
    {@"RelatedContentRecommendations", SGHideRecommendations},
};

// Class names of everything in the cell. Lists nested in the cell are laid out first so the
// cells that name the card (video cards) exist.
static NSString *classNamesIn(UIView *cell) {
    NSMutableString *names = [NSMutableString string];
    SGForEachView(cell, ^(UIView *v) {
        if (v != cell && [v isKindOfClass:UICollectionView.class]) [v layoutIfNeeded];
        [names appendString:NSStringFromClass(v.class)];
        [names appendString:@"\n"];
    });
    return names;
}

static NSString *hiddenKeyFor(UICollectionViewCell *cell) {
    // A cell inside another card's list: the outer card decides.
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell.class]) return nil;
    }
    NSString *names = nil;
    for (size_t i = 0; i < sizeof(cards) / sizeof(cards[0]); i++) {
        if (!SGHidden(cards[i].key)) continue;
        if (!names) names = classNamesIn(cell);
        if ([names containsString:@"NowPlaying_ScrollAPI"] && [names containsString:cards[i].marker]) return cards[i].key;
    }
    return nil;
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    NSString *key = hiddenKeyFor((UICollectionViewCell *)self);
    if (!key) return result;
    result.size = CGSizeMake(result.size.width, 0);
    ((UIView *)self).clipsToBounds = YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"collapsed the first card, %@", key); });
    return result;
}
%end

#pragma mark - player buttons, lyrics under the artwork

static BOOL vanish(UIView *view) {
    if (!view || view.alpha == 0) return NO;
    view.alpha = 0;
    view.userInteractionEnabled = NO;
    return YES;
}

// Re-layout once something went invisible, so the glass panes of Player.x follow.
static void finish(UIViewController *unit, BOOL changed) {
    if (changed) [unit.viewIfLoaded setNeedsLayout];
}

%hook _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    NSArray<UIView *> *items = SGRowIn(((UIViewController *)self).viewIfLoaded).arrangedSubviews;
    if (items.count != 5 || !SGHasClass(items[2], @"PlayButton")) return;
    BOOL changed = NO;
    if (SGHidden(SGHideShuffle)) changed |= vanish(items[0]);
    if (SGHidden(SGHideRepeat)) changed |= vanish(items[4]);
    finish((UIViewController *)self, changed);
}
%end

%hook _TtC20NowPlaying_ModesImpl18FooterElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    BOOL changed = NO;
    for (UIView *item in SGRowIn(((UIViewController *)self).viewIfLoaded).arrangedSubviews) {
        if (item.hidden || item.bounds.size.width < 20) continue;
        if (SGHasClass(item, @"Connect")) {
            if (SGHidden(SGHideConnect)) changed |= vanish(item);
        } else if (SGHasClass(item, @"QueueButton")) {
            if (SGHidden(SGHideQueue)) changed |= vanish(item);
        } else if (item.bounds.size.width <= 48 && SGHasClass(item, @"EncoreButton")) {
            if (SGHidden(SGHideShare)) changed |= vanish(item);
        }
    }
    finish((UIViewController *)self, changed);
}
%end

%hook _TtC20NowPlaying_ModesImpl23InformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    if (!SGHidden(SGHideAddTo)) return;
    BOOL changed = NO;
    for (UIView *item in SGRowIn(((UIViewController *)self).viewIfLoaded).arrangedSubviews) {
        if (SGHasClass(item, @"AddToButton")) changed |= vanish(item);
    }
    finish((UIViewController *)self, changed);
}
%end

%hook _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (void)setHidden:(BOOL)hidden {
    %orig(SGHidden(SGHideLyricsInline) ? YES : hidden);
}
- (void)didMoveToWindow {
    %orig;
    if (SGHidden(SGHideLyricsInline)) ((UIView *)self).hidden = YES;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC12Element_List18CollectionViewCell",
        @"_TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit",
        @"_TtC20NowPlaying_ModesImpl18FooterElementsUnit",
        @"_TtC20NowPlaying_ModesImpl23InformationElementsUnit",
        @"_TtC22Lyrics_NPVContainerKit19LyricsContainerView",
    ]);
}
