#import <UIKit/UIKit.h>

// Explicit Spotify presentation owners only. Never applies to a window or arbitrary modal.
void SGRApplyNativeSheetAppearance(UIViewController *controller);
// Share payloads are content, not app chrome, including when inserted after the sheet loads.
BOOL SGRNativeSheetPreservesView(UIView *view);

BOOL SGRNativeSheetOwnsEffect(UIView *view);
void SGRRefreshNativeSheetNode(UIView *view);
