// The mini player in the tab bar (SGRKeyInlinePlayer): the content of the UITabAccessory TabBar.x hands
// its UITabBarController. UIKit draws the glass around it, puts it above the bar, and moves it in
// between the selected tab and Search when the bar minimizes on scroll; the view only lays itself out
// for the space it is given, by the tabAccessoryEnvironment trait.
//
// The first cut: artwork, title and artist, play/pause, a swipe to skip and a tap to open the player.
// Title, artist and paused come from the player's state (Shared/Player/PlayerState.h). The artwork is the picture on
// Spotify's own bar, which is still there under the tab bar, invisible, and keeps loading it; a tap is
// passed on to that bar, so the player opens the way it always does.
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "NowPlayingBar.h"

// A swipe that goes this far across, or is let go of this fast, skips.
static const CGFloat kCommitFraction = 0.25;
static const CGFloat kCommitVelocity = 500;

static char kImageContext;

@interface SGRMiniPlayer : UIView <SGPlayerStateObserver, UIGestureRecognizerDelegate>
@property (nonatomic, readonly) UIView *artworkView;
@end

static __weak SGRMiniPlayer *sg_miniPlayer;

@implementation SGRMiniPlayer {
    UIView *_content;         // what a swipe moves
    UIImageView *_artwork;
    UILabel *_title, *_artist;
    UIButton *_play;
    __weak UIImageView *_source;   // the artwork on Spotify's bar, watched for its picture
    BOOL _swiping;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    _content = [UIView new];
    [self addSubview:_content];

    _artwork = [UIImageView new];
    _artwork.contentMode = UIViewContentModeScaleAspectFill;
    _artwork.clipsToBounds = YES;
    _artwork.layer.cornerCurve = kCACornerCurveContinuous;
    _artwork.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    [_content addSubview:_artwork];

    _title = [UILabel new];
    _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _title.textColor = UIColor.whiteColor;
    [_content addSubview:_title];

    _artist = [UILabel new];
    _artist.font = [UIFont systemFontOfSize:13];
    _artist.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    [_content addSubview:_artist];

    // Outside the part a swipe moves, so the button stays put while the track slides. A control in
    // UIKit's accessory never gets its touch up (simulator, iOS 26.5), so the card's own tap
    // recognizer works it and the button only draws.
    _play = [UIButton buttonWithType:UIButtonTypeSystem];
    _play.tintColor = UIColor.whiteColor;
    _play.userInteractionEnabled = NO;
    [self addSubview:_play];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    [self addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    pan.delegate = self;
    [self addGestureRecognizer:pan];

    if (@available(iOS 26.0, *)) {
        [self registerForTraitChanges:@[UITraitTabAccessoryEnvironment.class] withAction:@selector(environmentChanged)];
    }
    SGAddPlayerStateObserver(self);
    [self showState:SGPlayerState()];
    return self;
}

- (UIView *)artworkView {
    return _artwork;
}

- (void)dealloc {
    [self watchSource:nil];
}

- (void)environmentChanged {
    [self setNeedsLayout];
    static NSUInteger logged;
    if (logged++ < 60) SGLog(@"mini player: %@", [self isInline] ? @"inline (bar minimized)" : @"expanded");
}

// Between the selected tab and Search the accessory is a short capsule, and only the title fits.
- (BOOL)isInline {
    if (@available(iOS 26.0, *)) return self.traitCollection.tabAccessoryEnvironment == UITabAccessoryEnvironmentInline;
    return NO;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (!_swiping) {
        _content.transform = CGAffineTransformIdentity;
        _content.frame = bounds;
    }
    CGFloat height = bounds.size.height;
    BOOL compact = [self isInline];
    CGFloat side = MAX(0, MIN(height - (compact ? 10 : 12), 40));
    CGFloat inset = (height - side) / 2;
    // Concentric with the capsule's end: as far in from the side as from the top and bottom, and round,
    // which is the capsule's radius less that inset.
    _artwork.frame = CGRectMake(inset, inset, side, side);
    _artwork.layer.cornerRadius = side / 2;

    CGFloat button = MIN(height, 44);
    // Bounds and centre, not frame: the press animation scales it.
    _play.bounds = CGRectMake(0, 0, button, button);
    _play.center = CGPointMake(bounds.size.width - button / 2 - (compact ? 2 : 6), height / 2);
    UIImageSymbolConfiguration *symbol = [UIImageSymbolConfiguration configurationWithPointSize:compact ? 17 : 20 weight:UIImageSymbolWeightBold];
    if (![_play.currentPreferredSymbolConfiguration isEqual:symbol]) [_play setPreferredSymbolConfiguration:symbol forImageInState:UIControlStateNormal];

    CGFloat x = CGRectGetMaxX(_artwork.frame) + 10;
    CGFloat width = MAX(0, _play.center.x - button / 2 - x - 4);
    _artist.hidden = compact || !_artist.text.length;
    if (_artist.hidden) {
        _title.frame = CGRectMake(x, 0, width, height);
    } else {
        CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
        CGFloat top = floor((height - titleHeight - artistHeight - 1) / 2);
        _title.frame = CGRectMake(x, top, width, titleHeight);
        _artist.frame = CGRectMake(x, top + titleHeight + 1, width, artistHeight);
    }
}

#pragma mark - what it shows

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self showState:state];
}

- (void)showState:(SPTPlayerState *)state {
    SPTPlayerTrack *track = state.track;
    NSString *title = [track respondsToSelector:@selector(trackTitle)] ? track.trackTitle : nil;
    NSString *artist = [track respondsToSelector:@selector(artistName)] ? track.artistName : nil;
    BOOL paused = [state respondsToSelector:@selector(isPaused)] ? state.isPaused : NO;
    [self showPaused:paused];
    if (![_title.text isEqualToString:title] || ![_artist.text isEqualToString:artist]) {
        _title.text = title;
        _artist.text = artist;
        [self setNeedsLayout];
    }
    // Spotify's bar loads the new picture after the state arrives, and may have rebuilt the view that
    // shows it, so the view is looked for again and then watched.
    [self findArtwork];
    for (NSNumber *delay in @[@0.3, @1, @2.5]) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf findArtwork];
        });
    }
}

- (void)findArtwork {
    UIImageView *source = SGRNowPlayingArtworkView();
    if (source != _source) [self watchSource:source];
    UIImage *image = source.image;
    if (image && _artwork.image != image) _artwork.image = image;
}

- (void)watchSource:(UIImageView *)source {
    UIImageView *old = _source;
    if (old) [old removeObserver:self forKeyPath:@"image" context:&kImageContext];
    _source = source;
    if (source) [source addObserver:self forKeyPath:@"image" options:0 context:&kImageContext];
}

- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kImageContext) {
        [super observeValueForKeyPath:path ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self findArtwork];
    });
}

- (void)showPaused:(BOOL)paused {
    UIImage *image = [UIImage systemImageNamed:paused ? @"play.fill" : @"pause.fill"];
    if (![[_play imageForState:UIControlStateNormal] isEqual:image]) [_play setImage:image forState:UIControlStateNormal];
    _play.accessibilityLabel = paused ? @"Play" : @"Pause";
}

#pragma mark - touches

// Shown at once, and the state the player reports next sets it right if the command did not take.
- (void)togglePlay {
    id<SPTPlayer> player = SGKaraokePlayer();
    SPTPlayerState *state = SGPlayerState();
    BOOL paused = [state respondsToSelector:@selector(isPaused)] ? state.isPaused : NO;
    SEL command = paused ? @selector(resume:) : @selector(pause:);
    if (![player respondsToSelector:command]) {
        SGLog(@"mini player: the player (%@) cannot %@", player ? NSStringFromClass([(id)player class]) : @"nil", NSStringFromSelector(command));
        return;
    }
    [self showPaused:!paused];
    _play.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_play.transform = CGAffineTransformIdentity;
    } completion:nil];
    id result = paused ? [player resume:nil] : [player pause:nil];
    SGLog(@"mini player: %@ -> %@", paused ? @"resume" : @"pause", result);
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    // A tap near the button is the button's: it is a small target on a card that opens the player.
    CGPoint center = _play.center;
    CGFloat reach = _play.bounds.size.width / 2 + 6;
    CGPoint point = [tap locationInView:self];
    if (fabs(point.x - center.x) <= reach && fabs(point.y - center.y) <= reach) {
        [self togglePlay];
        return;
    }
    if (!SGROpenPlayerFromBar()) SGLog(@"mini player: nothing on Spotify's bar took the tap");
}

// Only a sideways drag is a swipe; anything else is left to the page and to UIKit's own gestures.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (![recognizer isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    CGPoint velocity = [(UIPanGestureRecognizer *)recognizer velocityInView:self];
    return fabs(velocity.x) > fabs(velocity.y);
}

- (void)panned:(UIPanGestureRecognizer *)pan {
    CGFloat width = self.bounds.size.width;
    CGFloat dx = [pan translationInView:self].x;
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            _swiping = YES;
            break;
        case UIGestureRecognizerStateChanged:
            _content.transform = CGAffineTransformMakeTranslation(dx, 0);
            _content.alpha = 1 - MIN(0.6, fabs(dx) / MAX(width, 1));
            break;
        case UIGestureRecognizerStateEnded: {
            CGFloat vx = [pan velocityInView:self].x;
            BOOL far = fabs(dx) > width * kCommitFraction, flung = fabs(vx) > kCommitVelocity && dx * vx > 0;
            if (dx != 0 && (far || flung)) [self skip:dx < 0];
            else [self settle];
            break;
        }
        default:
            [self settle];
    }
}

// Out the side it was swiped to, the player told, and in from the other side.
- (void)skip:(BOOL)next {
    CGFloat width = self.bounds.size.width;
    CGFloat out = next ? -width : width;
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self->_content.transform = CGAffineTransformMakeTranslation(out, 0);
        self->_content.alpha = 0;
    } completion:^(BOOL finished) {
        id<SPTPlayer> player = SGKaraokePlayer();
        SEL command = next ? @selector(skipToNextTrackWithOptions:) : @selector(skipToPreviousTrackWithOptions:);
        id result = [player respondsToSelector:command] ? (next ? [player skipToNextTrackWithOptions:nil] : [player skipToPreviousTrackWithOptions:nil]) : nil;
        SGLog(@"mini player: swipe %@ -> %@ (player %@)", next ? @"next" : @"previous", result, player ? NSStringFromClass([(id)player class]) : @"nil");
        self->_content.transform = CGAffineTransformMakeTranslation(-out * 0.4, 0);
        [self settle];
    }];
}

- (void)settle {
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_content.transform = CGAffineTransformIdentity;
        self->_content.alpha = 1;
    } completion:^(BOOL finished) {
        if (finished) self->_swiping = NO;
    }];
}

@end

UIView *SGRMakeMiniPlayer(void) {
    SGRMiniPlayer *player = [SGRMiniPlayer new];
    sg_miniPlayer = player;
    return player;
}

// The glass capsule UIKit draws around the accessory is the view's own frame, rounded to its height.
CGRect SGRMiniPlayerFrameIn(UIView *host, CGFloat *radius) {
    SGRMiniPlayer *player = sg_miniPlayer;
    if (!player.window || !host) return CGRectNull;
    if (radius) *radius = player.bounds.size.height / 2;
    return [host convertRect:player.bounds fromView:player];
}

CGRect SGRMiniPlayerArtworkFrameIn(UIView *host) {
    SGRMiniPlayer *player = sg_miniPlayer;
    UIView *artwork = player.artworkView;
    if (!artwork.window || !host) return CGRectNull;
    return [host convertRect:artwork.bounds fromView:artwork];
}
