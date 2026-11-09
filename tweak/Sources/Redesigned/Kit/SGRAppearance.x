// Spotify 9.1.94 has TWO independent stores: native Swift Encore.ColorTheme.main at
// 0x445500 and SPTEncoreColorTheme.main at 0x445508. The ObjC wrapper is initialized from
// the Swift store once, but its setter never updates that store. Both must be selected before
// views are built. Preserve overMedia/inverted semantics and artwork. No live color guessing.
#import "Core/SGCore.h"
#import "SGRAppearance.h"
#import "SGRNativeTheme.h"

@interface SPTEncoreColorTheme : NSObject
+ (instancetype)main;
+ (void)setMain:(SPTEncoreColorTheme *)theme;
+ (instancetype)light;
+ (instancetype)dark;
@end

static id selectedTheme;
static BOOL available;
static NSInteger launchMode;
static id (*originalObjCMain)(id, SEL);
BOOL SGRAppearanceBridgeAvailable(void) { return available; }
BOOL SGRAppearanceNeedsRestart(void) {
    return SGInt(SGRKeyAppearance, SGRAppearanceSystem) != launchMode;
}
NSString *SGRAppearanceStatus(void) {
    if (!available) return @"Unavailable · Dark fallback";
    if (!SGRNativeThemeMatches(SGRedesignLightAppearance()) ||
        (originalObjCMain && originalObjCMain(NSClassFromString(@"SPTEncoreColorTheme"), @selector(main)) != selectedTheme)) return @"Theme changed · Restart required";
    return SGRedesignLightAppearance() ? @"Light" : @"Dark";
}

static BOOL objectGetter(Class cls, SEL selector) {
    Method method = class_getClassMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char type[16] = {0};
    method_getReturnType(method, type, sizeof(type));
    return type[0] == '@';
}

%group SGRAppearanceBridge
%hook SPTEncoreColorTheme
+ (id)main {
    return selectedTheme ?: %orig;
}
+ (void)setMain:(id)theme {
    // ObjC clients cannot put the app back in dark while our own controls remain light.
    // Swift direct setters cannot be intercepted by this hook; device verification remains required.
    %orig(selectedTheme ?: theme);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    launchMode = SGInt(SGRKeyAppearance, SGRAppearanceSystem);
    Class cls = NSClassFromString(@"SPTEncoreColorTheme");
    Method setter = class_getClassMethod(cls, @selector(setMain:));
    char result[16] = {0}, argument[16] = {0};
    if (setter) {
        method_getReturnType(setter, result, sizeof(result));
        method_getArgumentType(setter, 2, argument, sizeof(argument));
    }
    if (!objectGetter(cls, @selector(main)) || !objectGetter(cls, @selector(light)) ||
        !objectGetter(cls, @selector(dark)) || !setter || method_getNumberOfArguments(setter) != 3 ||
        result[0] != 'v' || argument[0] != '@') {
        SGLog(@"appearance: semantic theme API missing; keeping the existing dark policy");
        return;
    }
    NSInteger mode = launchMode;
    // UIScreen's traits are outside Spotify's forced-dark navigation hierarchy. System is intentionally
    // captured once, before building any pages, rather than mixing new glass with cached native text.
    UIUserInterfaceStyle system = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    BOOL light = mode == SGRAppearanceLight || (mode == SGRAppearanceSystem && system == UIUserInterfaceStyleLight);
    id desired = light ? [cls light] : [cls dark];
    if (!desired || ![desired isKindOfClass:cls]) return;
    id previous = [cls main];
    if (!SGRSetNativeTheme(light, ^BOOL{
        [cls setMain:desired];
        if ([cls main] == desired) return YES;
        [cls setMain:previous];
        return NO;
    })) {
        SGLog(@"appearance: native Swift/ObjC theme transaction unavailable or rejected; keeping dark");
        return;
    }
    originalObjCMain = (id (*)(id, SEL))method_getImplementation(class_getClassMethod(cls, @selector(main)));
    selectedTheme = desired;
    available = YES;
    SGConfigureRedesignAppearance(light ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark);
    %init(SGRAppearanceBridge, SPTEncoreColorTheme = cls);
    SGLog(@"appearance: %@, native Swift and ObjC themes verified at launch%@", light ? @"light" : @"dark", mode == SGRAppearanceSystem ? @" from system" : @"");
}
