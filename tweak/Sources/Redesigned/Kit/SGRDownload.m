// Reading Spotify's download and add-to buttons, and the glyph drawn for the download.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "SGRDownload.h"
#import "SGRTokens.h"

#pragma mark - reading Spotify's button

static NSString *const kIdentifierPrefix = @"DownloadButton.Granular.";

static UIView *identifiedIn(UIView *source, NSString *prefix) {
    __block UIView *found = nil;
    SGForEachView(source, ^(UIView *v) {
        if (!found && [v.accessibilityIdentifier hasPrefix:prefix]) found = v;
    });
    return found;
}

// The Encore object behind the button: the target of the button's own action (-performAction).
static id ownerOf(UIView *button, NSString *kind) {
    if (![button isKindOfClass:UIControl.class]) return nil;
    for (id target in ((UIControl *)button).allTargets) {
        if ([NSStringFromClass(object_getClass(target)) containsString:kind]) return target;
    }
    return nil;
}

// `length` bytes of the stored property `name`, NULL when the class has no such property or it would reach
// past the end of the instance.
static const uint8_t *propertyBytes(id object, const char *name, size_t length) {
    if (!object) return NULL;
    Class cls = object_getClass(object);
    Ivar ivar = class_getInstanceVariable(cls, name);
    if (!ivar) return NULL;
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (offset <= 0 || (size_t)offset + length > class_getInstanceSize(cls)) return NULL;
    return (const uint8_t *)(__bridge void *)object + offset;
}

static BOOL stateFromIdentifier(NSString *identifier, SGRDownloadState *state) {
    NSDictionary<NSString *, NSNumber *> *states = @{
        @"None": @(SGRDownloadNone), @"Waiting": @(SGRDownloadWaiting), @"Downloading": @(SGRDownloadDownloading),
        @"Downloaded": @(SGRDownloadDownloaded), @"Error": @(SGRDownloadError),
    };
    NSNumber *found = states[[identifier substringFromIndex:kIdentifierPrefix.length]];
    if (!found) return NO;
    *state = found.integerValue;
    return YES;
}

BOOL SGRReadDownload(UIView *source, SGRDownloadState *state, CGFloat *progress) {
    UIView *button = source ? identifiedIn(source, kIdentifierPrefix) : nil;
    if (!button) return NO;
    SGRDownloadState said = SGRDownloadNone;
    BOOL named = stateFromIdentifier(button.accessibilityIdentifier, &said);

    // What the button draws from. Its state is a Swift enum without payloads, one byte, its cases numbered
    // in the order they are declared; its progress an optional 8 byte number, the value then a byte that is
    // 1 when there is none. The identifier says the same state in words, and is what counts when the model
    // cannot be read.
    id owner = ownerOf(button, @"GranularDownloadButton");
    const uint8_t *current = propertyBytes(owner, "currentState", 1);
    const uint8_t *stored = propertyBytes(owner, "progress", 9);
    BOOL modelled = current && *current <= 5;
    static const SGRDownloadState fromModel[] = {
        SGRDownloadNone, SGRDownloadWaiting, SGRDownloadDownloading, SGRDownloadWaiting, SGRDownloadDownloaded, SGRDownloadError,
    };
    SGRDownloadState modelState = modelled ? fromModel[*current] : SGRDownloadNone;
    SGRDownloadState result = modelled ? modelState : said;
    if (!modelled && !named) return NO;

    CGFloat value = -1;
    if (result == SGRDownloadDownloading && stored && stored[8] == 0) {
        double raw;
        memcpy(&raw, stored, sizeof raw);
        // A fraction, or a percentage should it ever be one.
        if (isfinite(raw) && raw > 1.0001 && raw <= 100) raw /= 100;
        if (isfinite(raw) && raw >= 0 && raw <= 1.0001) value = MIN(1, raw);
    }
    // Downloading with nothing to show how far is the ring turning, as while waiting.
    if (result == SGRDownloadDownloading && value < 0) result = SGRDownloadWaiting;

    // Said once for each combination read, so the first device run shows which of the two signals moved.
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *mark = [NSString stringWithFormat:@"%@ %d %d", button.accessibilityIdentifier, current ? *current : -1, stored != NULL];
    if (![logged containsObject:mark]) {
        [logged addObject:mark];
        SGLog(@"redesign kit: download %@, model %@ state %d progress %@, label \"%@\" value \"%@\"",
              button.accessibilityIdentifier, owner ? NSStringFromClass(object_getClass(owner)) : @"missing",
              current ? *current : -1, stored ? (stored[8] == 0 ? @"set" : @"none") : @"unreadable",
              button.accessibilityLabel, button.accessibilityValue);
    }
    if (modelled && named && modelState != said && !(modelState == SGRDownloadWaiting && said == SGRDownloadDownloading)) {
        static NSMutableSet<NSString *> *disagreed;
        if (!disagreed) disagreed = [NSMutableSet set];
        if (![disagreed containsObject:mark]) {
            [disagreed addObject:mark];
            SGLog(@"redesign kit: download model says %d where the identifier says %@, the model wins", *current,
                  button.accessibilityIdentifier);
        }
    }
    if (state) *state = result;
    if (progress) *progress = value;
    return YES;
}

BOOL SGRReadAddTo(UIView *source, BOOL *added) {
    UIView *button = source ? identifiedIn(source, @"Components.UI.AddToButton") : nil;
    if (!button) return NO;
    // A Swift enum without payloads, one byte: notAdded, added.
    const uint8_t *status = propertyBytes(ownerOf(button, @"AddToButton"), "currentStatus", 1);
    int raw = status ? *status : -1;
    static int logged = -2;
    if (raw != logged) {
        logged = raw;
        SGLog(@"redesign kit: add-to state %d, label \"%@\"", raw, button.accessibilityLabel);
    }
    if (!status || *status > 1) return NO;
    if (added) *added = *status == 1;
    return YES;
}

#pragma mark - the glyph

// The ring inside the 24pt canvas, the width of the circle of a filled SF symbol at kSymbolSize.
static const CGFloat kCanvas = 24, kRingRadius = 9.75, kRingWidth = 2, kStopSide = 7, kSymbolSize = 17;
// How long the ring takes to catch up with a new reading: the time between two reads, so it never stops.
static const NSTimeInterval kProgressEase = 0.5;
// The ring closing before the downloaded glyph takes its place.
static const NSTimeInterval kRingCloses = 0.22;

static BOOL isRing(SGRDownloadState state) {
    return state == SGRDownloadWaiting || state == SGRDownloadDownloading;
}

static UIImage *symbolFor(SGRDownloadState state) {
    NSString *name = state == SGRDownloadDownloaded ? @"arrow.down.circle.fill"
                   : state == SGRDownloadError ? @"exclamationmark.circle" : @"arrow.down";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:kSymbolSize
                                                                                         weight:UIImageSymbolWeightSemibold];
    return [[UIImage systemImageNamed:name withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// Downloaded is the one state that is "on", so it takes the accent colour, as shuffle does while it is on.
static UIColor *tintFor(SGRDownloadState state) {
    return state == SGRDownloadDownloaded ? SGRAccent() : SGRPrimary();
}

@implementation SGRDownloadGlyph {
    UIImageView *_symbol;
    UIView *_ring;
    CAShapeLayer *_track, *_arc, *_stop;
    // Bumped on every change of state, so a swap still waiting for the ring to close knows it is stale.
    NSUInteger _generation;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;

    _symbol = [UIImageView new];
    _symbol.contentMode = UIViewContentModeCenter;
    [self addSubview:_symbol];

    _ring = [UIView new];
    _ring.hidden = YES;
    [self addSubview:_ring];
    _track = [CAShapeLayer layer];
    _arc = [CAShapeLayer layer];
    for (CAShapeLayer *layer in @[_track, _arc]) {
        layer.fillColor = UIColor.clearColor.CGColor;
        layer.lineWidth = kRingWidth;
        layer.lineCap = kCALineCapRound;
        [_ring.layer addSublayer:layer];
    }
    _stop = [CAShapeLayer layer];
    [_ring.layer addSublayer:_stop];
    [self sgr_paint];
    return self;
}

- (void)sgr_paint {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _track.strokeColor = [SGRPrimary() colorWithAlphaComponent:0.25].CGColor;
    _arc.strokeColor = SGRAccent().CGColor;
    _stop.fillColor = SGRAccent().CGColor;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _symbol.frame = bounds;
    _ring.bounds = CGRectMake(0, 0, kCanvas, kCanvas);
    _ring.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGRect canvas = CGRectMake(0, 0, kCanvas, kCanvas);
    CGPoint middle = CGPointMake(kCanvas / 2, kCanvas / 2);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CAShapeLayer *layer in @[_track, _arc, _stop]) layer.frame = canvas;
    // From twelve o'clock, clockwise, the way a download fills.
    UIBezierPath *circle = [UIBezierPath bezierPathWithArcCenter:middle radius:kRingRadius startAngle:-M_PI_2
                                                        endAngle:3 * M_PI_2 clockwise:YES];
    _track.path = circle.CGPath;
    _arc.path = circle.CGPath;
    CGRect stop = CGRectMake(middle.x - kStopSide / 2, middle.y - kStopSide / 2, kStopSide, kStopSide);
    _stop.path = [UIBezierPath bezierPathWithRoundedRect:stop cornerRadius:1.5].CGPath;
    [CATransaction commit];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self sgr_paint];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // Core Animation drops a repeating animation when the layer leaves the window; the turning ring is put
    // back on the way in.
    if (self.window && _showsState && _state == SGRDownloadWaiting) [self sgr_setProgress:-1 animated:NO];
}

// The ring: a known fraction fills it from the top; none turns a short arc round and round.
- (void)sgr_setProgress:(CGFloat)progress animated:(BOOL)animated {
    BOOL turning = progress < 0;
    [CATransaction begin];
    if (turning) {
        [CATransaction setDisableActions:YES];
        _arc.strokeEnd = 0.28;
        if (![_arc animationForKey:@"sgr.spin"]) {
            CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            spin.fromValue = @0;
            spin.toValue = @(2 * M_PI);
            spin.duration = 1;
            spin.repeatCount = HUGE_VALF;
            [_arc addAnimation:spin forKey:@"sgr.spin"];
        }
    } else {
        BOOL wasTurning = [_arc animationForKey:@"sgr.spin"] != nil;
        [_arc removeAnimationForKey:@"sgr.spin"];
        if (animated && !wasTurning) {
            [CATransaction setAnimationDuration:kProgressEase];
            [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
        } else {
            [CATransaction setDisableActions:YES];
        }
        _arc.strokeEnd = MAX(0, MIN(1, progress));
    }
    [CATransaction commit];
}

- (void)showState:(SGRDownloadState)state progress:(CGFloat)progress animated:(BOOL)animated {
    BOOL had = _showsState;
    SGRDownloadState old = _state;
    BOOL ring = isRing(state), wasRing = had && isRing(old);
    animated = animated && had && self.window != nil;

    if (had && state == old) {
        if (ring) [self sgr_setProgress:state == SGRDownloadDownloading ? progress : -1 animated:animated];
        return;
    }
    _state = state;
    _showsState = YES;
    NSUInteger generation = ++_generation;

    if (!animated) {
        _ring.hidden = !ring;
        _symbol.hidden = ring;
        _ring.alpha = _symbol.alpha = 1;
        _ring.transform = _symbol.transform = CGAffineTransformIdentity;
        if (ring) [self sgr_setProgress:state == SGRDownloadDownloading ? progress : -1 animated:NO];
        else {
            _symbol.image = symbolFor(state);
            _symbol.tintColor = tintFor(state);
        }
        return;
    }

    // One symbol for another (not downloaded to downloaded, say, when it happened while the page was away):
    // the symbol replaces itself in place.
    if (!ring && !wasRing) {
        UIImage *image = symbolFor(state);
        if (@available(iOS 17.0, *)) {
            if (!SGRReduceMotion()) [_symbol setSymbolImage:image withContentTransition:[NSSymbolReplaceContentTransition replaceDownUpTransition]];
            else _symbol.image = image;
        } else {
            _symbol.image = image;
        }
        SGRAnimate(SGRMotionFade, ^{ self->_symbol.tintColor = tintFor(state); }, nil);
        return;
    }
    // Waiting to downloading and back: the ring stays, only what it shows changes.
    if (ring && wasRing) {
        [self sgr_setProgress:state == SGRDownloadDownloading ? progress : -1 animated:YES];
        return;
    }

    // One shape for the other: the old one shrinks away as the new one grows in with a little bounce. A
    // download that ends closes its ring first, so the last moment of it is seen before the arrow lands.
    UIView *outgoing = wasRing ? _ring : _symbol, *incoming = ring ? _ring : _symbol;
    BOOL closeRing = wasRing && state == SGRDownloadDownloaded;
    if (closeRing) [self sgr_closeRing];
    __weak SGRDownloadGlyph *weakSelf = self;
    void (^swap)(void) = ^{
        SGRDownloadGlyph *glyph = weakSelf;
        if (!glyph || glyph->_generation != generation) return;
        BOOL still = SGRReduceMotion();
        CGAffineTransform small = still ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.55, 0.55);
        if (ring) [glyph sgr_setProgress:state == SGRDownloadDownloading ? progress : -1 animated:NO];
        else {
            glyph->_symbol.image = symbolFor(state);
            glyph->_symbol.tintColor = tintFor(state);
        }
        incoming.hidden = NO;
        incoming.alpha = 0;
        incoming.transform = small;
        [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            outgoing.alpha = 0;
            outgoing.transform = small;
        } completion:^(BOOL finished) {
            if (glyph->_generation != generation) return;
            outgoing.hidden = YES;
            outgoing.alpha = 1;
            outgoing.transform = CGAffineTransformIdentity;
        }];
        if (still) {
            SGRAnimate(SGRMotionFade, ^{ incoming.alpha = 1; }, nil);
        } else {
            [UIView animateWithDuration:0.5 delay:0.08 usingSpringWithDamping:0.58 initialSpringVelocity:0
                                options:UIViewAnimationOptionAllowUserInteraction animations:^{
                incoming.alpha = 1;
                incoming.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
    };
    if (closeRing) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRingCloses * NSEC_PER_SEC)), dispatch_get_main_queue(), swap);
    } else {
        swap();
    }
}

// The arc runs round to the top from wherever the last reading left it.
- (void)sgr_closeRing {
    CGFloat from = [(CAShapeLayer *)(_arc.presentationLayer ?: _arc) strokeEnd];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_arc removeAnimationForKey:@"sgr.spin"];
    _arc.strokeEnd = 1;
    [CATransaction commit];
    CABasicAnimation *close = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    close.fromValue = @(from);
    close.toValue = @1;
    close.duration = kRingCloses;
    close.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [_arc addAnimation:close forKey:@"sgr.close"];
}

@end
