// Geometry-only harness boundary. Native semantic recoloring is deliberately not linked here;
// harness/appearance compiles and exercises the complete production adapter and its hooks.
#import "Core/SGAppearance.h"
#import "Redesigned/Kit/SGRNativeSurface.h"

void SGRApplyNativeLightSurface(UIView *root, BOOL fillsBase) {
    SGRegisterAppearanceView(root);
}
