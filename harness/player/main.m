// A mock of Spotify's full screen player under its own class names and accessibility identifiers, built
// from trees/clean/player/01.txt, so Redesigned/Player's lyrics state can be laid out, animated and
// looked at on the Mac. Tapping the lyrics glyph in the footer works exactly as it does on the phone;
// the harness also toggles it once by itself so a screenshot catches each state.
//
// HARNESS_SCENARIO (simctl launch passes it as SIMCTL_CHILD_HARNESS_SCENARIO) picks what it does:
//     lyrics   (default) the lyrics opened at 2 s, closed at 6, opened again at 10
//     look     one track playing, a second one from another album at 8 s, nothing opened
//     scroll   the list moved up and down in code; the log says whether it stayed at its top
//     artwork  issue #58: tracks change while the covers on screen and the picture server lag behind,
//              checked by colour at the end of each step; the log says PASS or FAIL
// HARNESS_VOLUME=0 leaves out the volume row the phone has (trees/clean/player/01.txt has none).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Shared/Lyrics/Lyrics.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Redesigned/Kit/SGRField.h"

void SGRHarnessPlayFrom(NSInteger ms);
void SGRHarnessSetTrack(NSString *uri, NSString *imageURI, BOOL paused);

static NSString *scenario(void) {
    const char *value = getenv("HARNESS_SCENARIO");
    return value ? @(value) : @"lyrics";
}

#pragma mark - the picture server

// i.scdn.co as the harness wants it: each picture by the last 24 digits of its id, served after a delay
// of its own, or failed as if the phone were offline.
@interface SGRHarnessPicture : NSObject
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) NSTimeInterval delay;
@property (nonatomic) BOOL fails;
@end
@implementation SGRHarnessPicture
@end

static NSMutableDictionary<NSString *, SGRHarnessPicture *> *sg_pictures;
static NSUInteger sg_served;

static void serve(NSString *imageURI, UIImage *image, NSTimeInterval delay, BOOL fails) {
    if (!sg_pictures) sg_pictures = [NSMutableDictionary dictionary];
    SGRHarnessPicture *picture = [SGRHarnessPicture new];
    picture.image = image;
    picture.delay = delay;
    picture.fails = fails;
    sg_pictures[[imageURI substringFromIndex:imageURI.length - 24]] = picture;
}

@interface SGRHarnessPictureServer : NSURLProtocol
@end

@implementation SGRHarnessPictureServer {
    BOOL _stopped;
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return [request.URL.host isEqualToString:@"i.scdn.co"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSString *name = self.request.URL.lastPathComponent;
    SGRHarnessPicture *picture = name.length >= 24 ? sg_pictures[[name substringFromIndex:name.length - 24]] : nil;
    NSThread *thread = NSThread.currentThread;
    NSLog(@"[harness] picture server: %@ asked for, %@", name, picture ? (picture.fails ? @"will fail" : [NSString stringWithFormat:@"answers in %.1f s", picture.delay]) : @"unknown");
    NSData *data = picture.fails ? nil : UIImagePNGRepresentation(picture.image);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(picture.delay * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
        [self performSelector:@selector(answer:) onThread:thread withObject:data waitUntilDone:NO];
    });
}

- (void)answer:(NSData *)data {
    if (_stopped) return;
    if (!data) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
        return;
    }
    sg_served++;
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{@"Content-Type": @"image/png"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
    _stopped = YES;
}

@end

// Every session the mod makes is handed the server first.
@implementation NSURLSessionConfiguration (SGRHarness)
+ (NSURLSessionConfiguration *)sgr_harnessDefault {
    NSURLSessionConfiguration *configuration = [self sgr_harnessDefault];
    configuration.protocolClasses = [@[SGRHarnessPictureServer.class] arrayByAddingObjectsFromArray:configuration.protocolClasses ?: @[]];
    return configuration;
}
@end

#pragma mark - pictures

static UIImage *solid(UIColor *color) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300) format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        UIRectFill(CGRectMake(0, 0, 300, 300));
    }];
}

// The colour a picture is, by the pixel in its middle, named the way the checks name them.
static NSString *colorName(UIImage *image) {
    if (!image.CGImage) return @"none";
    uint8_t px[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(px, 1, 1, 8, 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGFloat w = CGImageGetWidth(image.CGImage), h = CGImageGetHeight(image.CGImage);
    CGContextDrawImage(context, CGRectMake(-w / 2, -h / 2, w, h), image.CGImage);
    CGContextRelease(context);
    int r = px[0] > 128, g = px[1] > 128, b = px[2] > 128;
    NSArray *names = @[@"black", @"blue", @"green", @"cyan", @"red", @"magenta", @"yellow", @"white"];
    return names[r << 2 | g << 1 | b];
}

#pragma mark - Spotify's classes, by name

@interface _TtC19NowPlaying_ViewImpl24NowPlayingViewController : UIViewController @end
@implementation _TtC19NowPlaying_ViewImpl24NowPlayingViewController @end

@interface _TtC20NowPlaying_ModesImpl23InformationElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl23InformationElementsUnit @end

@interface _TtC20NowPlaying_ModesImpl19DurationElementUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl19DurationElementUnit @end

@interface _TtC20NowPlaying_ModesImpl20FloatingElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl20FloatingElementsUnit @end

@interface _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit @end

@interface _TtC20NowPlaying_ModesImpl18FooterElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl18FooterElementsUnit @end

@interface _TtC21NowPlaying_ScrollImpl23NPVScrollViewController : UIViewController <UIScrollViewDelegate> @end
@implementation _TtC21NowPlaying_ScrollImpl23NPVScrollViewController
- (void)scrollViewDidScroll:(UIScrollView *)list {}
@end

@interface _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView : UICollectionView @end
@implementation _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView @end

@interface _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl : UICollectionViewCell @end
@implementation _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl @end

@interface _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController : UIViewController @end
@implementation _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController @end

@interface _TtC18NowPlaying_BarImpl27NowPlayingBarViewController : UIViewController @end
@implementation _TtC18NowPlaying_BarImpl27NowPlayingBarViewController @end

@interface _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView : UIView
- (void)handleTap;
@end
@implementation _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)handleTap {}
@end

@interface _TtC22Lyrics_NPVContainerKit19LyricsContainerView : UIView @end
@implementation _TtC22Lyrics_NPVContainerKit19LyricsContainerView @end

@interface MockEncoreButton : UIControl @end
@implementation MockEncoreButton @end

#pragma mark - building the tree

static UIView *box(UIView *parent, Class cls, CGRect frame, NSString *identifier) {
    UIView *view = [[cls alloc] initWithFrame:frame];
    view.accessibilityIdentifier = identifier;
    [parent addSubview:view];
    return view;
}

static UILabel *marquee(UIView *parent, CGRect frame, NSString *text, CGFloat size, UIColor *color, NSString *identifier) {
    UIView *clip = box(parent, UIView.class, frame, identifier);
    clip.clipsToBounds = YES;
    UILabel *inner = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 900, frame.size.height)];
    inner.text = text;
    inner.font = [UIFont systemFontOfSize:size weight:UIFontWeightBold];
    inner.textColor = color;
    [inner sizeToFit];
    [clip addSubview:inner];
    return inner;
}

static UIView *glyphButton(UIView *parent, CGRect frame, NSString *symbol, NSString *identifier) {
    UIView *button = box(parent, MockEncoreButton.class, frame, identifier);
    UIImageView *glyph = [[UIImageView alloc] initWithFrame:CGRectInset(button.bounds, 10, 10)];
    glyph.image = [UIImage systemImageNamed:symbol];
    glyph.contentMode = UIViewContentModeScaleAspectFit;
    glyph.tintColor = UIColor.whiteColor;
    [button addSubview:glyph];
    return button;
}

static UIImage *artwork(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(354, 354)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat components[] = {0.11, 0.06, 0.35, 1, 0.83, 0.15, 0.62, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
        CGContextDrawLinearGradient(ctx.CGContext, gradient, CGPointZero, CGPointMake(354, 354), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithWhite:1 alpha:0.9] set];
        [@"LOOSE\nCANON" drawAtPoint:CGPointMake(28, 28) withAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:44 weight:UIFontWeightHeavy],
            NSForegroundColorAttributeName: [UIColor colorWithRed:1 green:0.92 blue:0.2 alpha:1],
        }];
    }];
}

// A second album, busier: a warm sky over teal water with a sun in it, for the track change.
static UIImage *secondArtwork(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(354, 354)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat sky[] = {0.98, 0.55, 0.20, 1, 0.85, 0.22, 0.30, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, sky, NULL, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(0, 200), 0);
        CGGradientRelease(gradient);
        CGFloat sea[] = {0.05, 0.45, 0.50, 1, 0.02, 0.12, 0.22, 1};
        gradient = CGGradientCreateWithColorComponents(space, sea, NULL, 2);
        CGContextSaveGState(c);
        CGContextClipToRect(c, CGRectMake(0, 200, 354, 154));
        CGContextDrawLinearGradient(c, gradient, CGPointMake(0, 200), CGPointMake(0, 354), 0);
        CGContextRestoreGState(c);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithRed:1 green:0.9 blue:0.55 alpha:1] setFill];
        CGContextFillEllipseInRect(c, CGRectMake(210, 110, 90, 90));
        [@"LOW\nTIDE" drawAtPoint:CGPointMake(26, 230) withAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:40 weight:UIFontWeightHeavy],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.9],
        }];
    }];
}

// A song with words timed inside each line, the shape SGRKaraokeView draws.
static void loadLyrics(void) {
    NSArray<NSString *> *texts = @[
        @"Who got the 808 under the 809",
        @"Making everybody jump?",
        @"Easy, I'm motivated",
        @"I got the feeling this is overrated",
        @"Give me the respect or give me nothing",
        @"Running up the hill with a heavy load",
        @"Tell them that the kid never folded",
        @"Every single verse was a promise kept",
        @"Nobody was there when it started",
        @"Now everybody wanna say they knew",
    ];
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    NSInteger at = 0;
    for (NSString *text in texts) {
        NSArray<NSString *> *words = [text componentsSeparatedByString:@" "];
        NSMutableArray<SGKaraokeWord *> *built = [NSMutableArray array];
        NSInteger cursor = at;
        for (NSString *word in words) {
            SGKaraokeWord *w = [SGKaraokeWord new];
            w.text = word;
            w.start = cursor;
            cursor += 260 + word.length * 40;
            w.end = cursor;
            [built addObject:w];
        }
        SGKaraokeLine *line = [SGKaraokeLine new];
        line.words = built;
        line.start = at;
        line.end = cursor;
        [lines addObject:line];
        at = cursor + 400;
    }
    SGKaraokeKeepLines(@"harness", lines);
}

#pragma mark - the harness

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGRHarnessDelegate {
    NSArray<UIViewController *> *_units;
    UIImageView *_cover, *_barCover;
    UIViewController *_bar;
    UICollectionView *_covers;
    UIScrollView *_list;
    NSUInteger _failures, _checks;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    loadLyrics();
    SGRHarnessPlayFrom(2400);
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithRed:0.09 green:0.07 blue:0.17 alpha:1];
    self.window.rootViewController = root;

    CGFloat W = root.view.bounds.size.width, H = root.view.bounds.size.height;
    // The player's own numbers are the tree's 402x874; the simulator's screen is whatever it is, so the
    // rows are placed as shares of it, the way Spotify's layout puts them.
    CGFloat headerTop = 62, headerHeight = 48;
    CGFloat bandTop = headerTop + headerHeight;
    const char *volumeEnv = getenv("HARNESS_VOLUME");
    BOOL hasVolume = !(volumeEnv && volumeEnv[0] == '0');
    CGFloat bottomHeight = 236 + (hasVolume ? 44 : 0);   // the tree's rows plus a volume row, as the phone has it
    CGFloat bottomTop = H - bottomHeight - 61.33;
    CGFloat bandHeight = bottomTop - bandTop;
    CGFloat coverSide = MIN(354, W - 48);

    // NPVScrollViewController: the list the player is the header of.
    UIView *page = box(root.view, UIView.class, root.view.bounds, nil);
    UIScrollView *list = [[UIScrollView alloc] initWithFrame:page.bounds];
    list.accessibilityIdentifier = @"scrolling_npv_collection_view_accessibility_identifier";
    list.contentSize = CGSizeMake(W, H + 326);       // the player and a card's worth of cards under it
    [page addSubview:list];
    UIViewController *scrollUnit = [_TtC21NowPlaying_ScrollImpl23NPVScrollViewController new];
    scrollUnit.view = page;
    list.delegate = (id<UIScrollViewDelegate>)scrollUnit;
    _list = list;

    // NPVBackgroundViewController's plane, the field's home (trees/clean/player/01.txt:449), under the player.
    UIView *plane = box(list, UIView.class, CGRectMake(0, 0, W, H), nil);
    plane.backgroundColor = [UIColor colorWithRed:0.3 green:0.1 blue:0.3 alpha:1];
    UIViewController *background = [_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController new];
    background.view = plane;

    UIView *host = box(list, UIView.class, CGRectMake(0, 0, W, H), @"SPTNowPlayingView");

    // the content layers: the sideways list of covers
    UIView *layers = box(host, UIView.class, host.bounds, nil);
    UICollectionViewFlowLayout *flow = [UICollectionViewFlowLayout new];
    UICollectionView *covers = [[_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView alloc]
                                initWithFrame:layers.bounds collectionViewLayout:flow];
    covers.accessibilityIdentifier = @"nowplaying-contentlayer-collectionview";
    covers.backgroundColor = UIColor.clearColor;
    [layers addSubview:covers];
    UIView *cell = box(covers, _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl.class, covers.bounds, @"nowplaying-contentlayer-cell-0");
    UIView *band = box(cell, UIView.class, CGRectMake(0, bandTop, W, bandHeight), nil);
    UIView *inner = box(band, UIView.class, CGRectMake(24, 8, W - 48, bandHeight - 16), nil);
    UIView *tilt = box(inner, _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView.class,
                       CGRectMake(0, round((inner.bounds.size.height - coverSide) / 2), coverSide, coverSide), nil);
    tilt.accessibilityLabel = @"Inspect cover art";
    // The Encore.ImageView holding the picture (01.txt:40), which PlayerField.x reads the cover from.
    UIView *coverElement = box(tilt, UIView.class, tilt.bounds, @"Encore.ImageView");
    UIImage *picture = artwork();
    UIImageView *cover = [[UIImageView alloc] initWithFrame:coverElement.bounds];
    cover.image = picture;
    _cover = cover;
    cover.contentMode = UIViewContentModeScaleAspectFill;
    [coverElement addSubview:cover];
    box(inner, _TtC22Lyrics_NPVContainerKit19LyricsContainerView.class, CGRectMake(0, inner.bounds.size.height, coverSide, 0), nil);

    // the header row
    UIView *header = box(host, UIStackView.class, CGRectMake(0, headerTop, W, headerHeight), nil);
    glyphButton(header, CGRectMake(12, 0, 48, 48), @"chevron.down", @"now-playing-minimize-button");
    glyphButton(header, CGRectMake(W - 60, 0, 48, 48), @"ellipsis", @"Context menu");

    // the bottom stack: information, duration, controls, volume, footer
    UIView *bottom = box(host, UIStackView.class, CGRectMake(0, bottomTop, W, bottomHeight), @"npv.bottomStackView");

    UIView *floatingView = box(bottom, UIView.class, CGRectMake(0, -32, W, 32), nil);
    UIView *chip = box(floatingView, UIView.class, CGRectMake(24, 0, 148, 32), nil);
    chip.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    chip.layer.cornerRadius = 16;
    UILabel *chipLabel = [[UILabel alloc] initWithFrame:chip.bounds];
    chipLabel.text = @"  \u25B6  Switch to video";
    chipLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    chipLabel.textColor = UIColor.whiteColor;
    [chip addSubview:chipLabel];

    UIView *infoView = box(bottom, UIView.class, CGRectMake(0, 0, W, 64), nil);
    UIView *infoRow = box(infoView, UIStackView.class, CGRectMake(12, 8, W - 24, 48), nil);
    UIView *infoInner = box(infoRow, UIStackView.class, infoRow.bounds, nil);
    box(infoInner, UIView.class, CGRectMake(0, 24, 0, 0), nil);          // Spotify's own mini cover, unused
    box(infoInner, UIView.class, CGRectMake(0, 24, 12, 0), nil);         // the spacer after it
    CGFloat titleWidth = infoInner.bounds.size.width - 12 - 60;
    UIView *titleElement = box(infoInner, UIView.class, CGRectMake(12, 2.33, titleWidth, 43.33), nil);
    UIView *titleContainer = box(titleElement, UIView.class, titleElement.bounds, nil);
    marquee(titleContainer, CGRectMake(0, 0, titleWidth, 25.33), @"We Are The People - southstar Remix (Extended)", 21,
            UIColor.whiteColor, @"now-playing-title-label");
    marquee(titleContainer, CGRectMake(0, 25.33, titleWidth, 18), @"Canon", 13,
            [UIColor colorWithWhite:1 alpha:0.7], @"now-playing-subtitle-label");
    glyphButton(infoInner, CGRectMake(infoInner.bounds.size.width - 48, 0, 48, 48), @"star", @"Components.UI.AddToButton");

    UIView *durationView = box(bottom, UIView.class, CGRectMake(0, 64, W, 40), nil);
    UIView *track = box(durationView, UIView.class, CGRectMake(24, 8, W - 48, 6), nil);
    track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
    track.layer.cornerRadius = 3;
    UIView *played = box(track, UIView.class, CGRectMake(0, 0, (W - 48) * 0.22, 6), nil);
    played.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
    played.layer.cornerRadius = 3;

    UIView *controls = box(bottom, UIView.class, CGRectMake(0, 104, W, 88), nil);
    glyphButton(controls, CGRectMake(W / 2 - 130, 20, 48, 48), @"backward.fill", nil);
    glyphButton(controls, CGRectMake(W / 2 - 24, 14, 48, 60), @"pause.fill", nil);
    glyphButton(controls, CGRectMake(W / 2 + 82, 20, 48, 48), @"forward.fill", nil);

    if (hasVolume) {
        UIView *volume = box(bottom, UIView.class, CGRectMake(0, 192, W, 44), nil);
        UIView *volumeTrack = box(volume, UIView.class, CGRectMake(44, 19, W - 88, 6), nil);
        volumeTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
        volumeTrack.layer.cornerRadius = 3;
    }

    UIView *footerView = box(bottom, UIView.class, CGRectMake(0, hasVolume ? 236 : 192, W, 44), nil);
    UIView *footerRow = box(footerView, UIStackView.class, CGRectMake(12, 0, W - 24, 44), nil);
    UIView *connect = box(footerRow, UIView.class, CGRectMake(0, 4, 153.67, 36), nil);
    UIView *connectHolder = box(connect, UIView.class, connect.bounds, @"Components.ConnectButtonOutputSwitcher");
    UIImageView *connectGlyph = [[UIImageView alloc] initWithFrame:CGRectMake(0, 8, 19, 19)];
    connectGlyph.image = [UIImage systemImageNamed:@"airpods.pro"];
    connectGlyph.tintColor = UIColor.whiteColor;
    [connectHolder addSubview:connectGlyph];
    glyphButton(footerRow, CGRectMake(279, 0, 44, 44), @"square.and.arrow.up", @"ShareButtonNowPlayingView");
    glyphButton(footerRow, CGRectMake(323, 6, 47, 32), @"list.bullet", @"QueueButtonNowPlaying");

    // The now playing bar, off screen: the Kit reads its 40pt cover (SPTNowPlayingBar > Encore.ImageView >
    // UIImageView, trees/clean/artist/01.txt).
    UIView *barView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 64)];
    UIView *barCard = box(barView, UIView.class, CGRectMake(8, 8, W - 16, 48), @"SPTNowPlayingBar");
    UIView *barHolder = box(barCard, UIView.class, CGRectMake(8, 4, 40, 40), @"Encore.ImageView");
    UIImageView *barCover = [[UIImageView alloc] initWithFrame:barHolder.bounds];
    barCover.image = picture;
    [barHolder addSubview:barCover];
    _barCover = barCover;
    _bar = [_TtC18NowPlaying_BarImpl27NowPlayingBarViewController new];
    _bar.view = barView;

    [self.window makeKeyAndVisible];

    UIViewController *info = [_TtC20NowPlaying_ModesImpl23InformationElementsUnit new];
    info.view = infoView;
    UIViewController *duration = [_TtC20NowPlaying_ModesImpl19DurationElementUnit new];
    duration.view = durationView;
    UIViewController *floating = [_TtC20NowPlaying_ModesImpl20FloatingElementsUnit new];
    floating.view = floatingView;
    UIViewController *footer = [_TtC20NowPlaying_ModesImpl18FooterElementsUnit new];
    footer.view = footerView;
    UIViewController *playback = [_TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit new];
    playback.view = controls;
    UIViewController *player = [_TtC19NowPlaying_ViewImpl24NowPlayingViewController new];
    player.view = host;
    _units = @[info, duration, floating, playback, footer, scrollUnit, background, player];
    _covers = covers;
    [self start];
    [self layOut];
    // Spotify lays its units out again as a track's elements arrive, which is what the redesign's
    // transforms and narrowed labels have to survive.
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { [self layOut]; }];

    NSLog(@"[harness] lyrics available: %d", SGRPlayerLyricsAvailable());
    // With the lines up, the row that rose into them must still be Spotify's to touch, and the lines
    // themselves must take the tap that seeks.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *star = nil;
        for (UIView *v in infoInner.subviews) if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"]) star = v;
        CGPoint onStar = [self.window convertPoint:CGPointMake(CGRectGetMidX(star.bounds), CGRectGetMidY(star.bounds)) fromView:star];
        CGPoint onTitle = [self.window convertPoint:CGPointMake(40, 12) fromView:titleElement];
        CGPoint onLines = CGPointMake(W / 2, H * 0.45);
        NSLog(@"[harness] hit on the star: %@", NSStringFromClass([self.window hitTest:onStar withEvent:nil].class));
        NSLog(@"[harness] hit on the title: %@", NSStringFromClass([self.window hitTest:onTitle withEvent:nil].class));
        NSLog(@"[harness] hit on the lines: %@", NSStringFromClass([self.window hitTest:onLines withEvent:nil].class));
    });
    if ([scenario() isEqualToString:@"artwork"]) [self runArtworkChecks];
    else if ([scenario() isEqualToString:@"look"]) [self runLook];
    else if ([scenario() isEqualToString:@"scroll"]) [self runScrollChecks];
    // Opened, closed and opened again, so a screenshot can be taken of each state and of the move itself.
    else for (NSNumber *at in @[@2, @6, @10]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(at.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@ the lyrics", SGRPlayerLyricsOpen() ? @"closing" : @"opening");
            SGRPlayerToggleLyrics();
        });
    }
    return YES;
}

- (void)layOut {
    for (UIViewController *unit in _units) [unit viewDidLayoutSubviews];
}

#pragma mark - tracks

static NSString *imageURI(NSString *digits) {
    // 16 digits of size, then the picture's own 24 (padded here from a short name).
    NSString *hash = [[digits stringByPaddingToLength:24 withString:@"0" startingAtIndex:0] substringToIndex:24];
    return [@"spotify:image:ab67616d0000b273" stringByAppendingString:hash];
}

static UIViewController *unitOf(UIView *view) {
    UIResponder *next = view.nextResponder;
    return [next isKindOfClass:UIViewController.class] ? (UIViewController *)next : nil;
}

static void after(NSTimeInterval seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

// What Spotify's screens do when a track changes: the list of covers moves to the new cell and lays out,
// still showing whatever picture that cell had, and the bar's cover stays what it was, until the
// pictures load and are set on the image views -- which lays nothing out.
- (void)playTrack:(NSString *)uri image:(NSString *)image {
    NSLog(@"[harness] track %@ (picture %@)", uri, [image substringFromIndex:image.length - 24]);
    SGRHarnessSetTrack(uri, image, NO);
    [_covers setNeedsLayout];
    [_covers layoutIfNeeded];
}

- (void)showOnScreen:(UIImage *)picture {
    _cover.image = picture;
    _barCover.image = picture;
}

- (void)start {
    BOOL checks = [scenario() isEqualToString:@"artwork"];
    UIImage *first = checks ? solid(UIColor.redColor) : _cover.image;
    [self showOnScreen:first];
    serve(imageURI(@"aaaa"), first, 0.2, NO);
    [self playTrack:@"spotify:track:harnessA" image:imageURI(@"aaaa")];
    // The bar lays out once as the app comes up.
    [_bar viewDidLayoutSubviews];
}

- (void)check:(NSString *)step want:(NSString *)want {
    NSString *uri = nil;
    UIImage *artwork = SGRNowPlayingArtwork(&uri, NULL);
    UIImage *drawn = [SGRPlayerField() valueForKey:@"image"];
    NSString *kit = colorName(artwork), *field = colorName(drawn);
    BOOL ok = [kit isEqualToString:want] && [field isEqualToString:want];
    _checks++;
    if (!ok) _failures++;
    NSLog(@"[harness] check %@: want %@, the Kit has %@ (for %@), the field draws %@ -- %@", step, want, kit, uri, field, ok ? @"ok" : @"WRONG");
}

// Issue #58: after a switch to another album the field kept the last one's picture until the next track.
- (void)runArtworkChecks {
    UIImage *green = solid(UIColor.greenColor), *blue = solid(UIColor.blueColor), *yellow = solid(UIColor.yellowColor),
            *magenta = solid(UIColor.magentaColor);
    after(1.5, ^{ [self check:@"1 first track" want:@"red"]; });

    // Another album: the screens go on showing the last picture for 3.5 s, well past the Kit's last look
    // at them, and the picture server answers in 1 s.
    after(2, ^{
        serve(imageURI(@"bbbb"), green, 1.0, NO);
        [self playTrack:@"spotify:track:harnessB" image:imageURI(@"bbbb")];
    });
    after(5.5, ^{ [self showOnScreen:green]; });
    after(7, ^{ [self check:@"2 album switch, the screens late" want:@"green"]; });

    // Two tracks in quick succession, the first one's picture answering last.
    after(7.5, ^{
        serve(imageURI(@"cccc"), blue, 2.0, NO);
        [self playTrack:@"spotify:track:harnessC" image:imageURI(@"cccc")];
    });
    after(7.7, ^{ [self showOnScreen:blue]; });
    after(7.8, ^{
        serve(imageURI(@"dddd"), yellow, 0.3, NO);
        [self playTrack:@"spotify:track:harnessD" image:imageURI(@"dddd")];
    });
    after(8.1, ^{ [self showOnScreen:yellow]; });
    after(11, ^{ [self check:@"3 skip twice, the older answer last" want:@"yellow"]; });

    // Offline: the server fails, and the screens show the new picture 0.8 s after the change.
    after(11.5, ^{
        serve(imageURI(@"eeee"), magenta, 0.1, YES);
        [self playTrack:@"spotify:track:harnessE" image:imageURI(@"eeee")];
    });
    after(12.3, ^{ [self showOnScreen:magenta]; });
    after(14.5, ^{ [self check:@"4 offline, the screens only" want:@"magenta"]; });

    after(15, ^{
        NSLog(@"[harness] artwork checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
              self->_failures ? @"FAIL" : @"PASS");
    });
}

// Up must be taken back to the top, down (the dismissal's pull) left where it went.
- (void)runScrollChecks {
    after(2, ^{
        UIScrollView *list = self->_list;
        CGFloat top = -list.adjustedContentInset.top;
        list.contentOffset = CGPointMake(0, top + 120);
        BOOL up = list.contentOffset.y == top;
        list.contentOffset = CGPointMake(0, top - 80);
        BOOL down = list.contentOffset.y == top - 80;
        [list setContentOffset:CGPointMake(0, top + 300) animated:NO];
        BOOL again = list.contentOffset.y == top;
        list.contentOffset = CGPointMake(0, top);
        NSLog(@"[harness] scroll checks: up %@, down %@, again %@ -- %@", up ? @"held" : @"moved", down ? @"kept" : @"lost",
              again ? @"held" : @"moved", up && down && again ? @"PASS" : @"FAIL");
    });
}

// One track, then another album's at 8 s, its picture on the screens 0.4 s later.
- (void)runLook {
    UIImage *second = secondArtwork();
    // Issue #54: the footer row moved down past the bottom stack's bounds must still take its touches,
    // at the bottom edge of each glyph as well as the middle.
    after(3, ^{
        CGFloat bottom = 0;
        for (NSString *symbol in @[@"list.bullet", @"airpods.pro"]) {
            __block UIView *found = nil;
            NSMutableArray *queue = [NSMutableArray arrayWithObject:self.window];
            while (queue.count && !found) {
                UIView *v = queue.firstObject;
                [queue removeObjectAtIndex:0];
                if ([v isKindOfClass:UIImageView.class] && [((UIImageView *)v).image isEqual:[UIImage systemImageNamed:symbol]]) found = v;
                [queue addObjectsFromArray:v.subviews];
            }
            CGRect drawn = [found convertRect:found.bounds toView:self.window];
            bottom = CGRectGetMaxY(drawn);
            for (NSNumber *dy in @[@0, @8]) {
                CGPoint at = CGPointMake(CGRectGetMidX(drawn), CGRectGetMidY(drawn) + dy.doubleValue);
                UIView *hit = [self.window hitTest:at withEvent:nil];
                BOOL inRow = NO;
                for (UIView *v = hit; v; v = v.superview) inRow = inRow || [NSStringFromClass(unitOf(v).class) containsString:@"FooterElementsUnit"] || [v.accessibilityIdentifier isEqualToString:@"QueueButtonNowPlaying"];
                NSLog(@"[harness] touch on %@ at y %.0f (+%.0f): %@ -- %@", symbol, at.y, dy.doubleValue, NSStringFromClass(hit.class), inRow ? @"the footer's" : @"MISSED");
            }
        }
        NSLog(@"[harness] footer glyphs end at %.0f of %.0f", bottom, self.window.bounds.size.height);
    });
    after(8, ^{
        serve(imageURI(@"ffff"), second, 0.25, NO);
        [self playTrack:@"spotify:track:harnessF" image:imageURI(@"ffff")];
    });
    after(8.4, ^{ [self showOnScreen:second]; });
}

@end

// Before every %ctor, so the redesign's gate reads on, and every session gets the picture server.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
    Method original = class_getClassMethod(NSURLSessionConfiguration.class, @selector(defaultSessionConfiguration));
    Method harness = class_getClassMethod(NSURLSessionConfiguration.class, @selector(sgr_harnessDefault));
    method_exchangeImplementations(original, harness);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRHarnessDelegate.class));
    }
}
