// Spotify 9.1.94 has independent native Swift and Objective-C theme stores. Commit both,
// verify through original accessors, then publish to registered semantic/owned surfaces.
#import "Core/SGCore.h"
#import "SGRAppearance.h"
#import "SGRNativeTheme.h"
#import "SGRNativeSurface.h"

@interface SPTEncoreColorTheme : NSObject
+ (instancetype)main;
+ (void)setMain:(SPTEncoreColorTheme *)theme;
+ (instancetype)light;
+ (instancetype)dark;
@end

static id selectedTheme;
static BOOL available, apiReady, requestQueued;
static NSInteger appliedMode;
static id (*originalObjCMain)(id, SEL);
static void (*originalObjCSetMain)(id, SEL, id);
static NSString *lastFailure;
static NSHashTable<UIWindowScene *> *observedScenes;
static NSMutableArray<UIView *> *transitionCovers;

BOOL SGRAppearanceBridgeAvailable(void) { return available; }
BOOL SGRAppearanceNeedsRestart(void) {
    return SGInt(SGRKeyAppearance, SGRAppearanceSystem) != appliedMode;
}
NSString *SGRAppearanceStatus(void) {
    if (!available) return @"Unavailable · Dark fallback";
    if (lastFailure) return lastFailure;
    if (!SGRNativeThemeMatches(SGRedesignLightAppearance()) ||
        originalObjCMain(NSClassFromString(@"SPTEncoreColorTheme"), @selector(main)) != selectedTheme)
        return @"Theme changed · Retry appearance";
    return SGRedesignLightAppearance() ? @"Light" : @"Dark";
}

static UIUserInterfaceStyle systemStyle(void) {
    // Scene/screen traits are outside Spotify's forced-dark controllers and our registered
    // overrides. Never resolve System from a forced view or a window's effective style.
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
            UIUserInterfaceStyle style=((UIWindowScene *)scene).traitCollection.userInterfaceStyle;
            if (style != UIUserInterfaceStyleUnspecified) return style;
        }
    }
    return UIScreen.mainScreen.traitCollection.userInterfaceStyle;
}
static BOOL objectGetter(Class cls, SEL selector) {
    Method method=class_getClassMethod(cls,selector);
    if (!method || method_getNumberOfArguments(method)!=2) return NO;
    char type[16]={0}; method_getReturnType(method,type,sizeof(type));
    return type[0]=='@';
}
static BOOL setProviders(Class cls, id desired, BOOL light) {
    id previous=originalObjCMain(cls,@selector(main));
    __block BOOL objcChanged=NO;
    BOOL result=SGRSetNativeTheme(light,^BOOL{
        objcChanged=YES;
        originalObjCSetMain(cls,@selector(setMain:),desired);
        return originalObjCMain(cls,@selector(main))==desired && SGRNativeThemeMatches(light);
    });
    if (!result && objcChanged) originalObjCSetMain(cls,@selector(setMain:),previous);
    return result;
}
static void clearCovers(void) {
    for (UIView *cover in transitionCovers) { [cover.layer removeAllAnimations]; [cover removeFromSuperview]; }
    transitionCovers=nil;
}
static NSArray<UIView *> *captureCovers(BOOL animated) {
    clearCovers();
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) return @[];
    NSMutableArray<UIView *> *covers=[NSMutableArray new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha<=0 || window.windowLevel!=UIWindowLevelNormal) continue;
            UIView *cover=[window snapshotViewAfterScreenUpdates:NO];
            if (!cover) continue;
            cover.frame=window.bounds;
            cover.userInteractionEnabled=NO;
            cover.accessibilityElementsHidden=YES;
            [window addSubview:cover]; [covers addObject:cover];
        }
    }
    transitionCovers=covers;
    return covers;
}
BOOL SGRAppearanceApplyMode(NSInteger mode, BOOL animated) {
    if (!NSThread.isMainThread || !apiReady) return NO;
    BOOL light=mode==SGRAppearanceLight || (mode==SGRAppearanceSystem && systemStyle()==UIUserInterfaceStyleLight);
    Class cls=NSClassFromString(@"SPTEncoreColorTheme");
    id desired=light?[cls light]:[cls dark];
    if (!desired || ![desired isKindOfClass:cls]) { lastFailure=@"Could not apply · Previous theme kept"; return NO; }
    if (available && selectedTheme==desired && SGRNativeThemeMatches(light) && originalObjCMain(cls,@selector(main))==desired) {
        appliedMode=mode; lastFailure=nil; return YES;
    }
    NSArray<UIView *> *covers=captureCovers(animated);
    if (!setProviders(cls,desired,light)) {
        clearCovers(); lastFailure=@"Could not apply · Previous theme kept";
        SGLog(@"appearance: provider transaction rejected; previous rendered theme retained");
        return NO;
    }
    // No UI or global appearance is published until BOTH independent stores verify.
    selectedTheme=desired;
    available=YES;
    appliedMode=mode;
    lastFailure=nil;
    [UIView performWithoutAnimation:^{
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        SGConfigureRedesignAppearance(light?UIUserInterfaceStyleLight:UIUserInterfaceStyleDark);
        SGRefreshAppearanceOwners();
        SGRRefreshNativeSurfaces();
        [CATransaction commit];
    }];
    if (covers.count) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ for (UIView *cover in covers) cover.alpha=0; }
                         completion:^(BOOL done) { for (UIView *cover in covers) [cover removeFromSuperview]; if (transitionCovers==covers) transitionCovers=nil; }];
    }
    SGLog(@"appearance: %@ applied live%@",light?@"light":@"dark",mode==SGRAppearanceSystem?@" from system":@"");
    return YES;
}
void SGRAppearanceApplyPreference(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ SGRAppearanceApplyPreference(); }); return; }
    if (requestQueued) return;
    requestQueued=YES;
    dispatch_async(dispatch_get_main_queue(),^{
        requestQueued=NO;
        SGRAppearanceApplyMode(SGInt(SGRKeyAppearance,SGRAppearanceSystem),YES);
    });
}
static void observeScenes(void) {
    if (!observedScenes) observedScenes=[NSHashTable weakObjectsHashTable];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || [observedScenes containsObject:(id)scene]) continue;
        [observedScenes addObject:(id)scene];
        if (@available(iOS 17.0,*)) {
            [(UIWindowScene *)scene registerForTraitChanges:@[UITraitUserInterfaceStyle.class] withHandler:^(id<UITraitEnvironment> environment, UITraitCollection *previous) {
                if (SGInt(SGRKeyAppearance,SGRAppearanceSystem)==SGRAppearanceSystem) SGRAppearanceApplyPreference();
            }];
        }
    }
}
static void beginSystemObservation(void) {
    observeScenes();
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification,UISceneDidActivateNotification,UISceneWillConnectNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            observeScenes();
            if (SGInt(SGRKeyAppearance,SGRAppearanceSystem)==SGRAppearanceSystem) SGRAppearanceApplyPreference();
        }];
    }
}

%group SGRAppearanceBridge
%hook SPTEncoreColorTheme
+ (id)main { return selectedTheme ?: %orig; }
+ (void)setMain:(id)theme { %orig(selectedTheme ?: theme); }
%end
%end

%group SGRSystemAppearanceObservation
%hook UIScreen
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    %orig;
    if (SGInt(SGRKeyAppearance,SGRAppearanceSystem)==SGRAppearanceSystem &&
        previous.userInterfaceStyle!=self.traitCollection.userInterfaceStyle)
        SGRAppearanceApplyPreference();
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    appliedMode=SGInt(SGRKeyAppearance,SGRAppearanceSystem);
    Class cls=NSClassFromString(@"SPTEncoreColorTheme");
    Method setter=class_getClassMethod(cls,@selector(setMain:));
    char result[16]={0}, argument[16]={0};
    if (setter) { method_getReturnType(setter,result,sizeof(result)); method_getArgumentType(setter,2,argument,sizeof(argument)); }
    if (!objectGetter(cls,@selector(main)) || !objectGetter(cls,@selector(light)) || !objectGetter(cls,@selector(dark)) ||
        !setter || method_getNumberOfArguments(setter)!=3 || result[0]!='v' || argument[0]!='@') {
        SGLog(@"appearance: semantic theme API unavailable; keeping dark fallback"); return;
    }
    originalObjCMain=(id (*)(id,SEL))method_getImplementation(class_getClassMethod(cls,@selector(main)));
    originalObjCSetMain=(void (*)(id,SEL,id))method_getImplementation(setter);
    apiReady=YES;
    %init(SGRSystemAppearanceObservation);
    // Install the validated accessors even if the first transaction is rejected. With no
    // selected theme they pass through; a later successful retry becomes pinned correctly.
    %init(SGRAppearanceBridge, SPTEncoreColorTheme=cls);
    SGRAppearanceApplyMode(appliedMode,NO);
    dispatch_async(dispatch_get_main_queue(),^{ beginSystemObservation(); });
}
