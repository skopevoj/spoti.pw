#import "SGAppearance.h"
#import <stdatomic.h>

// Dark is the safe fallback until the bridge has verified Spotify's semantic theme provider.
static _Atomic(UIUserInterfaceStyle) appearance = UIUserInterfaceStyleDark;
static NSMapTable *refreshOwners;
static NSHashTable<UIView *> *appearanceViews;
static NSHashTable<UIViewController *> *appearanceControllers;
UIUserInterfaceStyle SGRedesignAppearanceStyle(void) { return appearance; }
void SGConfigureRedesignAppearance(UIUserInterfaceStyle style) {
    appearance = style == UIUserInterfaceStyleLight ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
}
BOOL SGRedesignLightAppearance(void) { return appearance == UIUserInterfaceStyleLight; }
UIColor *SGAppearanceColor(UIColor *light, UIColor *dark) {
    // Retained labels, attributed strings and control-state colors stay semantic. Registered roots
    // change traits when the selected mode changes; no view/window traversal is necessary.
    static NSCache *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ colors = [NSCache new]; colors.countLimit = 256; });
    NSArray *key = @[light, dark];
    UIColor *color = [colors objectForKey:key];
    if (!color) {
        color = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return [(SGRedesignLightAppearance() ? light : dark) resolvedColorWithTraitCollection:traits];
        }];
        [colors setObject:color forKey:key];
    }
    return color;
}
void SGRegisterAppearanceRefresh(id owner, void (^refresh)(id)) {
    NSCAssert(NSThread.isMainThread, @"Appearance owners are main-thread only");
    if (!owner || !refresh) return;
    if (!refreshOwners) refreshOwners = [NSMapTable weakToStrongObjectsMapTable];
    [refreshOwners setObject:[refresh copy] forKey:owner];
}
void SGRegisterAppearanceView(UIView *view) {
    NSCAssert(NSThread.isMainThread, @"Appearance views are main-thread only");
    if (!view) return;
    if (!appearanceViews) appearanceViews = [NSHashTable weakObjectsHashTable];
    [appearanceViews addObject:view];
    if (view.overrideUserInterfaceStyle != appearance) view.overrideUserInterfaceStyle = appearance;
}
void SGRegisterAppearanceController(UIViewController *controller) {
    NSCAssert(NSThread.isMainThread, @"Appearance controllers are main-thread only");
    if (!controller) return;
    if (!appearanceControllers) appearanceControllers = [NSHashTable weakObjectsHashTable];
    [appearanceControllers addObject:controller];
    if (controller.overrideUserInterfaceStyle != appearance) controller.overrideUserInterfaceStyle = appearance;
    SGRegisterAppearanceView(controller.viewIfLoaded);
}
void SGRefreshAppearanceOwners(void) {
    NSCAssert(NSThread.isMainThread, @"Appearance refresh is main-thread only");
    for (UIViewController *controller in appearanceControllers.allObjects) {
        if (controller.overrideUserInterfaceStyle != appearance) controller.overrideUserInterfaceStyle = appearance;
    }
    for (UIView *view in appearanceViews.allObjects) {
        if (view.overrideUserInterfaceStyle != appearance) view.overrideUserInterfaceStyle = appearance;
        [view setNeedsDisplay];
    }
    // Snapshot owners: callbacks may register newly constructed owned controls.
    for (id owner in refreshOwners.keyEnumerator.allObjects) {
        void (^refresh)(id) = [refreshOwners objectForKey:owner];
        if (refresh) refresh(owner);
    }
}

void SGUnregisterAppearanceView(UIView *view) {
    NSCAssert(NSThread.isMainThread, @"Appearance views are main-thread only");
    [appearanceViews removeObject:view];
}
void SGUnregisterAppearanceRefresh(id owner) {
    NSCAssert(NSThread.isMainThread, @"Appearance owners are main-thread only");
    [refreshOwners removeObjectForKey:owner];
}
