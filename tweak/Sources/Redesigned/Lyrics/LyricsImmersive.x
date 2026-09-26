// UIKit menu callbacks scoped to the immersive lyrics controller in Now Playing.
#import "Core/SGCore.h"
#import "SGRLyricsImmersive.h"

// UIButton is the public context-menu delegate for Spotify's More and route controls. Scope both
// callbacks to the player; a menu anywhere else in Spotify is unaffected.
%hook UIButton
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    [SGRLyricsImmersiveOwner((UIView *)self) hold:SGRImmersiveMenu active:YES];
    %orig;
}
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    %orig;
    __weak SGRLyricsImmersiveController *owner = SGRLyricsImmersiveOwner((UIView *)self);
    if (animator) [animator addCompletion:^{ [owner hold:SGRImmersiveMenu active:NO]; }];
    else [owner hold:SGRImmersiveMenu active:NO];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGFlag(SGRKeyLyricsImmersive, YES)) return;
    %init;
}
