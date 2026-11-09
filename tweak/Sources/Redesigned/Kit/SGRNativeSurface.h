#import <UIKit/UIKit.h>

// Explicit redesigned page/chrome roots only, never a UIWindow. The legacy function name
// remains for callers; registration now works in both appearances and stores weak roots.
void SGRApplyNativeLightSurface(UIView *root, BOOL fillsBase);
void SGRRefreshNativeSurfaces(void);
// Explicit modal sheet base: Light is coherent; Dark keeps its native backing/transparency.
void SGRApplyNativeSheetSurface(UIView *root);
void SGRPreserveNativeSurface(UIView *root);
BOOL SGRNativeSurfaceManaged(UIView *view);
// Resolve an explicit primary/subdued foreground role for a proven native glyph control.
// Arbitrary native text uses the per-property source-palette bindings inside the adapter.
UIColor *SGRNativeSurfaceForeground(UIView *view, UIColor *color);

// Exact one-way palette helpers retained for tests and legacy callers.
UIColor *SGRNativeLightText(UIColor *color);
UIColor *SGRNativeLightBackground(UIColor *color);

// One insertion/removal subtree, without acquiring an independent appearance root.
void SGRRefreshNativeSurfaceSubtree(UIView *view);
BOOL SGRNativeSurfaceHasRootWithin(UIView *view);
