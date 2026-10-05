// Spotify's line under its lyrics ("Lyrics provided by …", LyricsFooterView) names the source the
// mod's lines came from, which LyricsHook writes into the reply. Where that source's terms want the
// people who made the lines linked, a tap on the line opens their pages.
#import "Core/SGCore.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import <objc/runtime.h>

static char kTapKey;

@interface SGLyricsCreditTap : NSObject <UIGestureRecognizerDelegate>
@end

@implementation SGLyricsCreditTap

+ (instancetype)shared {
    static SGLyricsCreditTap *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SGLyricsCreditTap new]; });
    return shared;
}

// Any other tap on the card or the page is left to Spotify.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)tap {
    return SGLyricsPageCreditFor(SGKaraokePlayingTrack()).links.count > 0;
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    SGLyricsCredit *credit = SGLyricsPageCreditFor(SGKaraokePlayingTrack());
    SGLog(@"lyrics: credit tapped, %lu links", (unsigned long)credit.links.count);
    SGLyricsOpenCredit(credit);
}

@end

static void addTap(UIView *footer) {
    if (objc_getAssociatedObject(footer, &kTapKey)) return;
    SGLyricsCreditTap *handler = SGLyricsCreditTap.shared;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:handler action:@selector(tapped:)];
    tap.delegate = handler;
    [footer addGestureRecognizer:tap];
    objc_setAssociatedObject(footer, &kTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook _TtC22Lyrics_TextElementImpl16LyricsFooterView
- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) addTap((UIView *)self);
}
%end

%hook _TtC24Lyrics_TextComponentImpl16LyricsFooterView
- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) addTap((UIView *)self);
}
%end

%ctor {
    if (!SGNativeUI() || !SGLyricsActive()) return;
    %init;
    SGRequireClasses(@[@"_TtC22Lyrics_TextElementImpl16LyricsFooterView", @"_TtC24Lyrics_TextComponentImpl16LyricsFooterView"]);
}
