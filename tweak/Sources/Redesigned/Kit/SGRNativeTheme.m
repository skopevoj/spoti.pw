#import "SGRNativeTheme.h"
#import <dlfcn.h>

// SpotifyShared 9.1.94: symbols-SpotifyShared.txt:43774-43778,44152-44154,44177-44179.
// Disassembly proves these static accessors take no metadata/context argument. A getter returns
// one owned Swift reference; the setter consumes it. Keep the pointer opaque: this is a native
// Swift class, NOT the Objective-C wrapper and not an NSObject to message or ARC-bridge.
typedef void * __attribute__((swiftcall)) (*SGRThemeGetter)(void);
typedef void __attribute__((swiftcall)) (*SGRThemeSetter)(void *);
typedef void __attribute__((swiftcall)) (*SGRSwiftRelease)(void *);

static SGRThemeGetter mainTheme, lightTheme, darkTheme;
static SGRThemeSetter setMainTheme;
static SGRSwiftRelease releaseTheme;
static BOOL resolve(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mainTheme = (SGRThemeGetter)dlsym(RTLD_DEFAULT, "$s16EncoreFoundation0A0O10ColorThemeC0A8_CoreKitE4mainAEvgZ");
        setMainTheme = (SGRThemeSetter)dlsym(RTLD_DEFAULT, "$s16EncoreFoundation0A0O10ColorThemeC0A8_CoreKitE4mainAEvsZ");
        lightTheme = (SGRThemeGetter)dlsym(RTLD_DEFAULT, "$s16EncoreFoundation0A0O10ColorThemeC5lightAEvgZ");
        darkTheme = (SGRThemeGetter)dlsym(RTLD_DEFAULT, "$s16EncoreFoundation0A0O10ColorThemeC4darkAEvgZ");
        releaseTheme = (SGRSwiftRelease)dlsym(RTLD_DEFAULT, "swift_release");
    });
    return mainTheme && setMainTheme && lightTheme && darkTheme && releaseTheme;
}

BOOL SGRNativeThemeMatches(BOOL light) {
    if (!resolve()) return NO;
    void *desired = (light ? lightTheme : darkTheme)();
    void *actual = mainTheme();
    BOOL matches = desired && actual == desired;
    if (desired) releaseTheme(desired);
    if (actual) releaseTheme(actual);
    return matches;
}

BOOL SGRSetNativeTheme(BOOL light, BOOL (^finish)(void)) {
    // Store transitions are main-thread transactions; rendered surfaces refresh only after success.
    if (!NSThread.isMainThread || !resolve()) return NO;
    void *previous = mainTheme();
    void *desired = (light ? lightTheme : darkTheme)();
    if (!previous || !desired) {
        if (previous) releaseTheme(previous);
        if (desired) releaseTheme(desired);
        return NO;
    }
    setMainTheme(desired); // Consumes the getter's +1; do not release it again.
    if (!SGRNativeThemeMatches(light) || (finish && !finish())) {
        setMainTheme(previous); // Restore, consuming the saved +1.
        return NO;
    }
    releaseTheme(previous);
    return YES;
}
