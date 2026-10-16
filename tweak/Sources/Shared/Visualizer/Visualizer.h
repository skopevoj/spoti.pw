// The visualizer: a ring of bars that moves with what Spotify plays, NCS style, drawn around the cover
// (the redesign's player puts it there, Redesigned/Player/PlayerArtwork.x, and turns the cover into a
// circle inside it). Under either look the sound is read the same way:
//
//     VisualizerTap.x    the finished sound, after speed, pitch, audio effects and Sing, off the last of
//                        Audio/SGAudioPipeline's stages into SGSpectrum's ring, only while a ring shows
//     SGSpectrum.m       the bars out of the sound, plain C (harness/visualizer/)
//     SGVisualizerView.m the ring, drawn on a display link the way the lyrics are: 60 to 120 Hz, put down
//                        while the player animates and whenever the app or the view is not on screen
//     VisualizerSettings.m  its rows, set the same way as Music Haptics: a strength and what it follows
//
// Everything applies at once.
#import <UIKit/UIKit.h>

// How strongly the bars move, a percentage, and what they follow (an SGMusicFollows: everything, the beat
// or the bass), the same two settings as Music Haptics, and the switch that takes Music Haptics' own.
#define SGKeyVisualizerStrength @"spotifyglass.visualizer.strength"   // 20...200, 100 unset
#define SGKeyVisualizerFollows @"spotifyglass.visualizer.follows"
#define SGKeyVisualizerLikeHaptics @"spotifyglass.visualizer.likeHaptics"   // off until switched on
#define SGKeyVisualizerBars @"spotifyglass.visualizer.bars"           // an index into the counts below: 48 to 1024
#define SGKeyVisualizerWidth @"spotifyglass.visualizer.width"         // an SGVisualizerWidth
// How a gradient colour (Spectrum, Cover gradient) lies on the ring, an SGVisualizerGradient.
#define SGKeyVisualizerGradient @"spotifyglass.visualizer.gradient"
// How much of the ring the lowest notes get: an index into Even (one log scale, 40 Hz up), a fifth (unset), a
// quarter and a third of the bars for 20 to 100 Hz, the rest log spaced from 100 Hz up. Bass is all bass anyway.
#define SGKeyVisualizerBassShare @"spotifyglass.visualizer.bassShare"
// How far out the bars reach, an index into short, medium and full (unset).
#define SGKeyVisualizerHeight @"spotifyglass.visualizer.height"
// How the bars move, an index into snappy, normal (unset) and smooth.
#define SGKeyVisualizerResponse @"spotifyglass.visualizer.response"
// A cap left at each bar's peak, falling slowly back to it (the ring in the player only). Off until switched on.
#define SGKeyVisualizerPeaks @"spotifyglass.visualizer.peaks"
// The ring turning, an index into off (unset), slow and fast (the ring in the player only).
#define SGKeyVisualizerRotation @"spotifyglass.visualizer.rotation"
#define SGKeyVisualizerStyle @"spotifyglass.visualizer.style"         // an SGVisualizerStyle
#define SGKeyVisualizerColor @"spotifyglass.visualizer.color"         // an SGVisualizerColor
// How the Cover gradient reads the cover's colours, an SGVisualizerCoverColours.
#define SGKeyVisualizerCoverColours @"spotifyglass.visualizer.coverColours"
// The cover's dark colours, black included, kept as they are rather than lightened. Off until switched on.
#define SGKeyVisualizerCoverDark @"spotifyglass.visualizer.coverDark"
// A soft glow behind the bars, white behind dark bars and black behind light ones, so they never sink into
// what is behind them. Off until switched on.
#define SGKeyVisualizerBacklight @"spotifyglass.visualizer.backlight"
#define SGKeyVisualizerMirror @"spotifyglass.visualizer.mirror"       // on until switched off

typedef NS_ENUM(NSInteger, SGVisualizerStyle) {
    SGVisualizerStyleBars = 0,   // a bar out from the ring per band, rounded at the end
    SGVisualizerStyleWave,       // one closed line pushed out by the bands
    SGVisualizerStyleDots,       // a dot per band, riding out on its level
};

typedef NS_ENUM(NSInteger, SGVisualizerColor) {
    SGVisualizerColorAccent = 0,   // the look's accent, or what the host hands the view
    SGVisualizerColorWhite,
    SGVisualizerColorSpectrum,     // a hue all the way round
    SGVisualizerColorCover,        // a gradient through the playing cover's main colours (SGCoverPalette.h)
};

typedef NS_ENUM(NSInteger, SGVisualizerCoverColours) {
    SGVisualizerCoverColoursSpots = 0,   // the blurred cover read at its centre and quarters (SGPalette.h) (unset)
    SGVisualizerCoverColoursMain,        // the cover's main colours, clustered, vivid ones first
};

typedef NS_ENUM(NSInteger, SGVisualizerGradient) {
    SGVisualizerGradientAlong = 0,   // along every bar, from the inside out, the same on each (unset)
    SGVisualizerGradientAround,      // once round the ring
    SGVisualizerGradientRepeating,   // there and back round the ring, several times over
    SGVisualizerGradientAlternating, // each bar one colour, the next bar the next colour
};

typedef NS_ENUM(NSInteger, SGVisualizerWidth) {
    SGVisualizerWidthThin = 0,
    SGVisualizerWidthNormal,
    SGVisualizerWidthThick,
};

// Posted on the main queue when a setting changes, so every ring takes it at once.
extern NSNotificationName const SGVisualizerSettingsDidChangeNotification;

NSInteger SGVisualizerBarCount(void);
// How wide a bar is drawn against the room it has: 0.6, 1 (unset) or 1.4 times its share, never more than the
// room between bars, and never under what a 1024 bar ring needs to read as a line.
CGFloat SGVisualizerWidthFactor(void);
float SGVisualizerBassShare(void);               // 0, 0.2 (unset), 0.25 or 1/3
CGFloat SGVisualizerHeightFactor(void);          // how much of the room out to the edge the bars may take
void SGVisualizerResponse(float *rise, float *fall);
NSTimeInterval SGVisualizerRotationPeriod(void); // seconds a turn, 0 for none

// VisualizerTap.x: the tap reads the sound only while at least one ring is on screen, the lock screen draws
// frames or the Live Activity shows bars. Main thread.
void SGVisualizerSetListening(BOOL listening);
void SGVisualizerSetLockScreenListening(BOOL listening);
void SGVisualizerSetLiveActivityListening(BOOL listening);

// The visualizer on the lock screen (Shared/LockScreenLyrics/LockScreenLyrics.x): the now playing artwork
// becomes the cover in a ring of bars over the cover blurred, drawn again several times a second while
// Spotify is not on screen and the sound moves, with the line being sung under it when lock screen lyrics
// show the line as the artwork. Read at launch, like the lock screen lyrics' switch.
#define SGKeyLockScreenVisualizer @"spotifyglass.lockScreenVisualizer"            // off until switched on
#define SGKeyLockScreenVisualizerRate @"spotifyglass.lockScreenVisualizer.rate"   // an index into the rates below
NSInteger SGLockScreenVisualizerFramesPerSecond(void);   // 6, 10 (unset) or 15
// The same frames while CarPlay is connected, whether Spotify is on the iPhone's screen or not: CarPlay's Now
// Playing shows the now playing artwork, so the ring is drawn there. Off until switched on; read at launch.
// While it runs, the iPhone's lock screen and Control Center show the frames too, the artwork being one.
#define SGKeyVisualizerCarPlay @"spotifyglass.visualizer.carPlay"

// SGVisualizerFrame.m: one picture of the ring, `side` points square at scale 1, in the ring's own style,
// colour and mirror. Any thread; `cover` and `backdrop` may be nil, and `line`/`next` are drawn under it.
// `palette` is the cover's colours (SGCoverPalette.h) for the Cover gradient colour, nil for the accent.
UIImage *SGVisualizerDrawFrame(CGFloat side, UIImage *cover, UIImage *backdrop, const float *bars, NSInteger bands,
                               UIColor *accent, NSArray<UIColor *> *palette, NSString *line, NSString *next);
// The newest bars, `count` of them (up to SGSpectrumMaxBands), for a frame `elapsed` seconds after the last; NO when there is no sound
// to read yet (the bars then fall, which this does too).
BOOL SGVisualizerReadBars(float *bars, NSInteger count, float elapsed);

@class SGModRow, SGModSection, UIViewController;
// VisualizerSettings.m: the sections that set it up (Sound, Shape, Colour), greyed out while the switch under
// `waitsOnKey` (off until switched on) is off; nil for none.
NSArray<SGModSection *> *SGVisualizerSections(NSString *waitsOnKey);
// Its page, opened from the Player page under either look: `leading` (the redesign's switch for the ring in
// its player) first, then its sections, then the lock screen's.
UIViewController *SGVisualizerSettingsPage(NSArray<SGModSection *> *leading, NSString *waitsOnKey, NSString *intro);
// The lock screen's switch and how often it draws, under either look.
NSArray<SGModRow *> *SGLockScreenVisualizerRows(void);
