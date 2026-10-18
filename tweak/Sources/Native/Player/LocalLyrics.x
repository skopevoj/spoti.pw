// Spotify 9.1.74 disables its native lyrics entry point for local files before the lyrics service
// is consulted. Put a working entry point over that disabled glyph when this local track has an
// assigned LRC, and show the tweak's cached lines directly.
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LRCFiles.h"

static const void *kLocalLyricsButtonKey = &kLocalLyricsButtonKey;

@interface SGNativeLocalLyricsController : UIViewController
- (instancetype)initWithTrackID:(NSString *)trackID;
@end

@implementation SGNativeLocalLyricsController {
    NSString *_trackID;
    NSArray<SGKaraokeLine *> *_lines;
    NSMutableArray<UILabel *> *_lineLabels;
    UIStackView *_lineStack;
    UIScrollView *_scroll;
    UILabel *_status;
    NSTimer *_refreshTimer;
    NSInteger _activeLine;
}

- (instancetype)initWithTrackID:(NSString *)trackID {
    if ((self = [super init])) {
        _trackID = [trackID copy];
        _activeLine = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = UIColor.whiteColor;
    close.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1];
    close.layer.cornerRadius = 22;
    [close addTarget:self action:@selector(closePage) forControlEvents:UIControlEventTouchUpInside];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:close];

    SPTPlayerTrack *track = SGKaraokeTrackFor(_trackID);
    UILabel *title = [UILabel new];
    title.text = track.trackTitle.length ? track.trackTitle : @"Local track";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    title.numberOfLines = 2;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    UILabel *artist = [UILabel new];
    artist.text = track.artistName ?: @"";
    artist.font = [UIFont systemFontOfSize:16];
    artist.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    artist.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:artist];

    _status = [UILabel new];
    _status.text = @"Loading imported lyrics…";
    _status.textColor = [UIColor colorWithWhite:0.65 alpha:1];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.numberOfLines = 2;
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_status];

    _scroll = [UIScrollView new];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scroll];
    _lineStack = [UIStackView new];
    _lineStack.axis = UILayoutConstraintAxisVertical;
    _lineStack.alignment = UIStackViewAlignmentFill;
    _lineStack.spacing = 22;
    _lineStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_lineStack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [close.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18],
        [close.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [close.widthAnchor constraintEqualToConstant:44], [close.heightAnchor constraintEqualToConstant:44],
        [title.leadingAnchor constraintEqualToAnchor:close.trailingAnchor constant:14],
        [title.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18],
        [title.topAnchor constraintEqualToAnchor:close.topAnchor],
        [artist.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [artist.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [artist.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3],
        [_scroll.topAnchor constraintEqualToAnchor:artist.bottomAnchor constant:28],
        [_scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:26],
        [_scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-26],
        [_scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-22],
        [_lineStack.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
        [_lineStack.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
        [_lineStack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:18],
        [_lineStack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-18],
        [_lineStack.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor],
        [_status.centerXAnchor constraintEqualToAnchor:_scroll.centerXAnchor],
        [_status.centerYAnchor constraintEqualToAnchor:_scroll.centerYAnchor],
    ]];
    [self refreshLyrics];
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(refreshLyrics)
                                                    userInfo:nil repeats:YES];
}

- (void)closePage {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)refreshLyrics {
    NSArray<SGKaraokeLine *> *current = SGKaraokeLinesForTrack(_trackID);
    if (current.count && current != _lines) {
        _lines = current;
        [_lineStack.arrangedSubviews.copy enumerateObjectsUsingBlock:^(UIView *view, NSUInteger idx, BOOL *stop) {
            [_lineStack removeArrangedSubview:view];
            [view removeFromSuperview];
        }];
        _lineLabels = [NSMutableArray arrayWithCapacity:current.count];
        for (SGKaraokeLine *line in current) {
            UILabel *label = [UILabel new];
            label.text = SGKaraokeLineText(line);
            label.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
            label.textColor = [UIColor colorWithWhite:0.52 alpha:1];
            label.numberOfLines = 0;
            [_lineStack addArrangedSubview:label];
            [_lineLabels addObject:label];
        }
        _status.hidden = YES;
    } else if (!_lines.count) {
        _status.hidden = NO;
        _status.text = @"No readable lines were found in the assigned LRC file.";
        SGKaraokeRequestLyrics(_trackID);
        return;
    }

    NSInteger active = SGKaraokeLeadLine(_lines, SGKaraokePositionMs());
    if (active == _activeLine || active < 0 || active >= (NSInteger)_lineLabels.count) return;
    _activeLine = active;
    for (NSUInteger i = 0; i < _lineLabels.count; i++) {
        UILabel *label = _lineLabels[i];
        label.textColor = i == (NSUInteger)active ? UIColor.whiteColor : [UIColor colorWithWhite:0.48 alpha:1];
        label.transform = i == (NSUInteger)active ? CGAffineTransformMakeScale(1.02, 1.02) : CGAffineTransformIdentity;
    }
    UILabel *label = _lineLabels[(NSUInteger)active];
    CGRect visible = [_scroll convertRect:label.bounds fromView:label];
    [_scroll scrollRectToVisible:CGRectInset(visible, 0, -50) animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

@end

static UIViewController *presenterFor(UIViewController *controller) {
    UIViewController *top = controller;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

static void openAssignedLyrics(UIViewController *owner, NSString *trackID) {
    if (!owner || !SGLRCHasAssignedLyrics(trackID)) return;
    SGKaraokeRequestLyrics(trackID);
    SGNativeLocalLyricsController *page = [[SGNativeLocalLyricsController alloc] initWithTrackID:trackID];
    page.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenterFor(owner) presentViewController:page animated:YES completion:nil];
}

static UIButton *localLyricsButton(UIView *host, UIViewController *owner) {
    UIButton *button = objc_getAssociatedObject(host, kLocalLyricsButtonKey);
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.accessibilityLabel = @"Lyrics";
        button.accessibilityIdentifier = @"spoti.pw.localLyricsButton";
        [button setImage:[UIImage systemImageNamed:@"quote.bubble"] forState:UIControlStateNormal];
        button.tintColor = UIColor.whiteColor;
        button.backgroundColor = UIColor.clearColor;
        button.bounds = CGRectMake(0, 0, 44, 44);
        __weak UIViewController *weakOwner = owner;
        [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            openAssignedLyrics(weakOwner, SGKaraokePlayingTrack());
        }] forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(host, kLocalLyricsButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addSubview:button];
    }
    return button;
}

%hook _TtC20NowPlaying_ModesImpl18FooterElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *owner = (UIViewController *)self;
    UIView *host = owner.viewIfLoaded;
    if (!host || host.bounds.size.width < 100) return;
    NSString *trackID = SGKaraokePlayingTrack();
    BOOL assigned = SGKaraokeTrackKeyIsLocal(trackID) && SGLRCHasAssignedLyrics(trackID);
    UIButton *button = objc_getAssociatedObject(host, kLocalLyricsButtonKey);
    if (!assigned) {
        button.hidden = YES;
        return;
    }
    button = localLyricsButton(host, owner);
    button.hidden = NO;
    button.enabled = YES;
    BOOL rtl = host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    button.center = CGPointMake(round(host.bounds.size.width * (rtl ? 0.8 : 0.2)), CGRectGetMidY(host.bounds));
    [host bringSubviewToFront:button];
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18FooterElementsUnit"]);
}
