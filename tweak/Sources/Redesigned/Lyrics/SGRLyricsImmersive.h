#import <UIKit/UIKit.h>
#import "SGRImmersiveState.h"

#define SGRKeyLyricsImmersive @"spotifyglass.redesign.lyricsImmersive"
@class SGRKaraokeView;

// Main thread. The player owns geometry; this controller owns idle, interaction and chrome.
@interface SGRLyricsImmersiveController : NSObject
- (instancetype)initWithPage:(UIView *)page lyrics:(SGRKaraokeView *)lyrics chrome:(NSArray<UIView *> *)chrome;
- (void)setPresented:(BOOL)presented;
- (void)addChromeView:(UIView *)view;
- (void)interact;
- (void)hold:(uint32_t)reason active:(BOOL)active;
@property (nonatomic, copy) void (^layoutChanged)(BOOL expanded);
@property (nonatomic, readonly) BOOL immersive;
@end

// Resolves only a player that explicitly registered a controller, for its UIKit menus.
SGRLyricsImmersiveController *SGRLyricsImmersiveOwner(UIView *view);
