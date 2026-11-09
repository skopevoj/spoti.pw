#import <Foundation/Foundation.h>

// Spotify keeps the native Swift Encore.ColorTheme.main separately from SPTEncoreColorTheme.main.
// Apply through the exported Swift ABI, never by writing a guessed static address.
// finish commits the ObjC provider. Returning NO restores the prior native provider.
BOOL SGRSetNativeTheme(BOOL light, BOOL (^finish)(void));
BOOL SGRNativeThemeMatches(BOOL light);
