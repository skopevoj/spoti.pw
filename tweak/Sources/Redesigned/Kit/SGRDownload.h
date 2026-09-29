// What Spotify's download button says -- not downloaded, waiting, downloading and how far, downloaded, failed
// -- and the glyph the redesign draws for it, the Music app's: an arrow, a ring filling up with a stop square
// in it, and a filled arrow in a circle once everything is on the phone (issue #65).
//
// Spotify draws that button with Lottie, so there is no image to copy the way the action row copies the
// other glyphs. What it does have is a state in words: the button's accessibility identifier is
// `DownloadButton.Granular.<None|Waiting|Downloading|Downloaded|Error>` (every one of the five is a string
// in the 9.1.78 binary), and the Encore object that owns the button -- the button's own action target --
// keeps `currentState` and `progress` in stored properties the runtime lists by name (Swift field metadata:
// GranularDownloadButton { currentState: GranularDownloadButtonState, progress: Optional<8 bytes> }, the
// state being none, waiting, downloading, downloadingEndless, downloaded, error in that order).
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SGRDownloadState) {
    SGRDownloadNone,
    SGRDownloadWaiting,       // queued, or downloading with no progress to show: the ring turns
    SGRDownloadDownloading,
    SGRDownloadDownloaded,
    SGRDownloadError,
};

// YES when `source`, or something under it, is Spotify's download button, with what it says: `progress`
// is 0...1 while downloading, -1 when Spotify has none to give (an endless download, or not readable).
BOOL SGRReadDownload(UIView *source, SGRDownloadState *state, CGFloat *progress);

// YES when `source`, or something under it, is Spotify's add-to button (Components.UI.AddToButton, saving an
// album or a playlist), with whether it is saved. Lottie draws that one too, so the state is read off its
// Encore owner's `currentStatus` (AddToButtonState: notAdded, added); NO when that cannot be read.
BOOL SGRReadAddTo(UIView *source, BOOL *added);

// The glyph, 24pt square, drawn in the middle of a round action row button. A change of state is animated
// (symbol replaced in place, or the old shape shrinking away as the new one grows in), so the moment the
// download starts or ends reads as a moment; progress eases along between the reads.
@interface SGRDownloadGlyph : UIView
@property (nonatomic, readonly) SGRDownloadState state;
@property (nonatomic, readonly) BOOL showsState;   // NO until the first -showState:
- (void)showState:(SGRDownloadState)state progress:(CGFloat)progress animated:(BOOL)animated;
@end
