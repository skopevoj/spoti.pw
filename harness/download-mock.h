// Spotify's download button and shuffle's "on" dot as the playlist and album harnesses mock them (issue #65).
//
// The download button is a UIButton drawn by Lottie -- no image view to copy -- whose accessibility
// identifier names its state (`DownloadButton.Granular.<None|Waiting|Downloading|Downloaded|Error>`, all five
// strings in the 9.1.78 binary), and whose action target is Encore's GranularDownloadButton, keeping
// `currentState` (a one byte enum: none, waiting, downloading, downloadingEndless, downloaded, error) and
// `progress` (an optional 8 byte number: the value, then a byte that is 1 when there is none) as stored
// properties the runtime lists by name. The mock has the same names and the same layout.
//
// Shuffle marks "on" with a 4pt round view under its glyph that it hides while off (trees/continuous/1.txt),
// and draws its glyph grey while off, green while on.
//
// `download` on the launch line runs downloadScript(): none, waiting, downloading 0 to 100%, downloaded,
// shuffle on, removed and shuffle off, error -- each held a few seconds and logged, for screenshots.
#import <UIKit/UIKit.h>

typedef struct {
    double value;
    uint8_t none;
} MockOptionalDouble;

@interface _TtCOOOE32EncoreConsumerMobile_ElementsKitO19LegacyUI_ECMCoreKit10Components22GranularDownloadButton2UI7Private22GranularDownloadButton : NSObject {
@public
    __unsafe_unretained UIView *uiView;
    __unsafe_unretained UIButton *uiButton;
    uint8_t currentState;
    MockOptionalDouble progress;
    BOOL isEnabled;
}
- (void)performAction;
@end

@implementation _TtCOOOE32EncoreConsumerMobile_ElementsKitO19LegacyUI_ECMCoreKit10Components22GranularDownloadButton2UI7Private22GranularDownloadButton
- (void)performAction {
    NSLog(@"[harness] Spotify's download button fired (state %d)", currentState);
}
@end

typedef _TtCOOOE32EncoreConsumerMobile_ElementsKitO19LegacyUI_ECMCoreKit10Components22GranularDownloadButton2UI7Private22GranularDownloadButton MockDownloadOwner;

// Lottie's view, which draws the glyph without an image view.
@interface MockLottieView : UIView @end
@implementation MockLottieView @end

static MockDownloadOwner *sgh_downloadOwner;
static UIButton *sgh_downloadButton;
static UIView *sgh_shuffleDot;
static UIImageView *sgh_shuffleGlyph;

static void setDownload(uint8_t state, double progress) {
    NSArray<NSString *> *names = @[@"None", @"Waiting", @"Downloading", @"Downloading", @"Downloaded", @"Error"];
    MockDownloadOwner *owner = sgh_downloadOwner;
    owner->currentState = state;
    owner->progress.value = progress < 0 ? 0 : progress;
    owner->progress.none = progress < 0;
    sgh_downloadButton.accessibilityIdentifier = [@"DownloadButton.Granular." stringByAppendingString:names[state]];
    sgh_downloadButton.accessibilityLabel = state == 4 ? @"Remove download" : @"Download";
}

// The download button as Spotify builds it, inside `host` (48x48).
static UIButton *mockDownloadButton(UIView *host) {
    UIButton *button = [[UIButton alloc] initWithFrame:host.bounds];
    button.accessibilityIdentifier = @"DownloadButton.Granular.None";
    button.accessibilityLabel = @"Download";
    [host addSubview:button];
    UIView *micro = [[UIView alloc] initWithFrame:CGRectMake(12, 12, 24, 24)];
    [micro addSubview:[[MockLottieView alloc] initWithFrame:micro.bounds]];
    [button addSubview:micro];
    MockDownloadOwner *owner = [MockDownloadOwner new];
    owner->uiButton = button;
    owner->uiView = button;
    owner->progress.none = 1;
    [button addTarget:owner action:@selector(performAction) forControlEvents:UIControlEventTouchUpInside];
    // Held by the button, as Encore's element holds it.
    static char kOwnerKey;
    objc_setAssociatedObject(button, &kOwnerKey, owner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sgh_downloadOwner = owner;
    sgh_downloadButton = button;
    return button;
}

static UIImage *shuffleImage(BOOL on) {
    UIImage *symbol = [UIImage systemImageNamed:@"shuffle"];
    UIColor *color = on ? [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1] : [UIColor colorWithWhite:0.70 alpha:1];
    return [[symbol imageWithTintColor:color] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// Shuffle's glyph and dot as Spotify draws them, inside `button` (48x48), off.
static void mockShuffleGlyph(UIView *button) {
    UIImageView *glyph = [[UIImageView alloc] initWithFrame:CGRectInset(button.bounds, 12, 12)];
    glyph.image = shuffleImage(NO);
    [button addSubview:glyph];
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(22, 38, 4, 4)];
    dot.backgroundColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
    dot.layer.cornerRadius = 2;
    dot.hidden = YES;
    [button addSubview:dot];
    sgh_shuffleGlyph = glyph;
    sgh_shuffleDot = dot;
}

static void setShuffle(BOOL on) {
    // As Spotify does it: the dot first, then the glyph (which is what the redesign hears).
    sgh_shuffleDot.hidden = !on;
    sgh_shuffleGlyph.image = shuffleImage(on);
}

// The add-to button (Components.UI.AddToButton, 9.1.78 binary): a UIButton drawn by Lottie whose action target
// is Encore's private AddToButton, keeping `currentStatus` (one byte: notAdded, added). Spotify's own
// -performAction saves or removes; the mock's flips the byte, as the saved state would come back.
@interface _TtC28EncoreConsumerMobile_BaseKitP33_23B9F07423DE1078C0EAAD54E8754BE611AddToButton : NSObject {
@public
    __unsafe_unretained UIView *microInteractionView;
    __unsafe_unretained UIView *uiView;
    __unsafe_unretained UIButton *uiButton;
    uint8_t configuration;
    uint8_t currentStatus;
}
- (void)performAction;
@end

static void setAddTo(uint8_t status);

@implementation _TtC28EncoreConsumerMobile_BaseKitP33_23B9F07423DE1078C0EAAD54E8754BE611AddToButton
- (void)performAction {
    setAddTo(!currentStatus);
    NSLog(@"[harness] Spotify's add-to button fired, now %d", currentStatus);
}
@end

typedef _TtC28EncoreConsumerMobile_BaseKitP33_23B9F07423DE1078C0EAAD54E8754BE611AddToButton MockAddToOwner;

static MockAddToOwner *sgh_addToOwner;

static void setAddTo(uint8_t status) {
    sgh_addToOwner->currentStatus = status;
    sgh_addToOwner->uiButton.accessibilityLabel = status ? @"Remove from Your Library" : @"Save to Your Library";
}

// The add-to button as Spotify builds it, inside `host` (48x48), not saved.
static UIButton *mockAddToButton(UIView *host) {
    UIButton *button = [[UIButton alloc] initWithFrame:host.bounds];
    button.accessibilityIdentifier = @"Components.UI.AddToButton";
    [host addSubview:button];
    UIView *micro = [[UIView alloc] initWithFrame:CGRectInset(button.bounds, -4, -4)];
    [micro addSubview:[[MockLottieView alloc] initWithFrame:micro.bounds]];
    [button addSubview:micro];
    MockAddToOwner *owner = [MockAddToOwner new];
    owner->uiButton = button;
    owner->uiView = button;
    owner->microInteractionView = micro;
    [button addTarget:owner action:@selector(performAction) forControlEvents:UIControlEventTouchUpInside];
    static char kOwnerKey;
    objc_setAssociatedObject(button, &kOwnerKey, owner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sgh_addToOwner = owner;
    setAddTo(0);
    return button;
}

static void at(NSTimeInterval seconds, void (^block)(void)) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

// Nothing is laid out by any of it, as on the phone: the redesign has to hear it by itself. Each state is
// held for a few seconds and announced with a "[harness] state:" line, which is what screenshots wait for.
static void downloadScript(void) {
    at(1, ^{ NSLog(@"[harness] state: none"); });
    at(6, ^{ setDownload(1, -1); NSLog(@"[harness] state: waiting"); });
    for (int i = 0; i <= 12; i++) {
        // To half way, a pause there, then the rest.
        NSTimeInterval when = 12 + i * 0.4 + (i > 6 ? 6 : 0);
        at(when, ^{
            setDownload(2, i / 12.0);
            if (i == 6) NSLog(@"[harness] state: downloading 50%%");
        });
    }
    at(23.5, ^{ setDownload(4, -1); NSLog(@"[harness] state: downloaded"); });
    at(30, ^{ setShuffle(YES); NSLog(@"[harness] state: shuffle on"); });
    at(36, ^{ setDownload(0, -1); setShuffle(NO); NSLog(@"[harness] state: removed, shuffle off"); });
    at(42, ^{ setDownload(5, -1); NSLog(@"[harness] state: error"); });
    at(48, ^{ NSLog(@"[harness] state: end"); });
}
