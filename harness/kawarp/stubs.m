// What the settings harness does not compile: the Kit's accent and its now playing artwork, which answers
// the picture HARNESS_COVER names (a local file) or nothing, so the preview takes its sample.
#import <UIKit/UIKit.h>

UIColor *SGRAccentColor(void) { return nil; }

NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"spotifyglass.redesign.nowPlayingArtworkDidChange";

UIImage *SGRNowPlayingArtwork(NSString **trackURI, NSString **identity) {
    const char *path = getenv("HARNESS_COVER");
    return path ? [UIImage imageWithContentsOfFile:@(path)] : nil;
}
