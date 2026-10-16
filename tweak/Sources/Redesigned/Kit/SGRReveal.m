// The curtain a redesigned page comes in behind. Laid over the page as its front subview, and drawn over
// whatever Spotify adds to the page afterwards by its zPosition, so no pass of Spotify's can put anything in
// front of it before the page's next pass brings it forward again.
//
// Lifting it fades the page in rather than fading a black sheet off it: the curtain goes at once, and in the
// same frame the page's own views start from nothing -- the field brightening out of the black into the
// page's colour, and over it the picture, the header and the list fading in where they are. Nothing moves:
// a rise into place read as the page scrolling on its own. The fades are additive and on the presentation
// layers only, so nothing Spotify sets on those views is fought over or changed, and a view Spotify fades
// meanwhile still ends where Spotify put it.
#import "Core/SGCore.h"
#import "SGRReveal.h"
#import "SGRField.h"
#import "SGRTokens.h"

const NSTimeInterval SGRRevealCap = 1.2;
// A curtain whose page has not said what it waits for by then is not one the redesign lays out.
static const NSTimeInterval kClaim = 0.25;
// The page fading in: the field's colour first, the rest a beat behind it.
static const NSTimeInterval kFieldFade = 0.4, kContentFade = 0.5, kContentDelay = 0.06;
// Above every layer Spotify puts on the page.
static const CGFloat kCurtainZ = 10000;

static char kRevealKey;

@interface SGRRevealState : NSObject
@property (nonatomic, weak) UIView *curtain;
@property (nonatomic) SGRRevealPart awaited, arrived;
@property (nonatomic) CFTimeInterval raised;
@property (nonatomic) BOOL lifted;
// When each part arrived, for the log line that says what the page waited on.
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, NSNumber *> *arrivals;
@end
@implementation SGRRevealState
- (instancetype)init {
    if ((self = [super init])) _arrivals = [NSMutableDictionary dictionary];
    return self;
}
@end

static SGRRevealState *stateOf(UIView *page, BOOL create) {
    if (!page) return nil;
    SGRRevealState *state = objc_getAssociatedObject(page, &kRevealKey);
    if (!state && create) {
        state = [SGRRevealState new];
        objc_setAssociatedObject(page, &kRevealKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static NSArray<NSNumber *> *allParts(void) {
    return @[@(SGRRevealPicture), @(SGRRevealColor), @(SGRRevealHeader), @(SGRRevealList)];
}

static NSString *partName(SGRRevealPart part) {
    switch (part) {
        case SGRRevealPicture: return @"picture";
        case SGRRevealColor: return @"colour";
        case SGRRevealHeader: return @"header";
        case SGRRevealList: return @"list";
        default: return @"?";
    }
}

static NSString *partNames(SGRRevealPart parts) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSNumber *part in allParts()) {
        if (parts & part.unsignedIntegerValue) [names addObject:partName(part.unsignedIntegerValue)];
    }
    return names.count ? [names componentsJoinedByString:@", "] : @"nothing";
}

// "picture 0.04, colour 0.06, header 0.05, list 0.31": when each part came in, from the curtain going up.
static NSString *arrivalTimes(SGRRevealState *state) {
    NSMutableArray<NSString *> *times = [NSMutableArray array];
    for (NSNumber *part in allParts()) {
        NSNumber *at = state.arrivals[part];
        if (at) [times addObject:[NSString stringWithFormat:@"%@ %.2f", partName(part.unsignedIntegerValue), MAX(0, at.doubleValue - state.raised)]];
    }
    return times.count ? [times componentsJoinedByString:@", "] : @"no part in";
}

// The page by what the log can tell apart: a view controller's view by the controller.
static NSString *pageName(UIView *page) {
    UIResponder *owner = page.nextResponder;
    return NSStringFromClass([owner isKindOfClass:UIViewController.class] ? owner.class : page.class);
}

// From nothing to what the layer's model says, added on top of it. An ease out: the page comes up fast and
// settles, rather than creeping in.
static void fadeIn(CALayer *layer, NSTimeInterval duration, NSTimeInterval delay) {
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.additive = YES;
    fade.fromValue = @(-layer.opacity);
    fade.toValue = @0;
    fade.duration = duration;
    fade.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] + delay;
    fade.fillMode = kCAFillModeBackwards;
    fade.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.16 :1 :0.3 :1];
    [layer addAnimation:fade forKey:@"spotifyglass.reveal.fade"];
}

// Every view of the page but the curtain, from nothing, in the frame the curtain goes: the first frame drawn
// without it already has them all at their start.
static void fadeInPage(UIView *page, UIView *curtain) {
    for (UIView *view in page.subviews) {
        if (view == curtain || view.hidden || view.layer.hidden || CGRectIsEmpty(view.bounds)) continue;
        BOOL field = [view isKindOfClass:SGRArtworkField.class];
        fadeIn(view.layer, field ? kFieldFade : kContentFade, field ? 0 : kContentDelay);
    }
}

static void lift(UIView *page, SGRRevealState *state, NSString *why) {
    if (state.lifted) return;
    state.lifted = YES;
    UIView *curtain = state.curtain;
    static NSUInteger logged;
    if (logged++ < 12) {
        SGLog(@"redesign reveal: %@ shown %.2f s after its first pass, %@ (%@)", pageName(page),
              CACurrentMediaTime() - state.raised, why, arrivalTimes(state));
    }
    if (!curtain) return;
    if (curtain.window) fadeInPage(page, curtain);
    [curtain removeFromSuperview];
}

static void liftIfComplete(UIView *page, SGRRevealState *state) {
    if (state.lifted || !state.curtain || !state.awaited) return;
    if ((state.arrived & state.awaited) == state.awaited) lift(page, state, @"everything in");
}

void SGRRevealHold(UIView *page, SGRRevealPart parts) {
    SGRRevealState *state = stateOf(page, YES);
    if (!state || state.lifted) return;
    state.awaited |= parts;

    UIView *curtain = state.curtain;
    if (!curtain) {
        curtain = [[UIView alloc] initWithFrame:page.bounds];
        curtain.backgroundColor = UIColor.blackColor;
        curtain.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        curtain.layer.zPosition = kCurtainZ;
        // Nothing under it is there to be touched yet.
        curtain.userInteractionEnabled = YES;
        curtain.accessibilityElementsHidden = YES;
        [page addSubview:curtain];
        state.curtain = curtain;
        state.raised = CACurrentMediaTime();

        __weak UIView *weakPage = page;
        __weak SGRRevealState *weakState = state;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kClaim * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weakPage && weakState && !weakState.awaited) lift(weakPage, weakState, @"claimed by nothing");
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SGRRevealCap * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGRRevealState *late = weakState;
            if (!weakPage || !late || late.lifted) return;
            lift(weakPage, late, [@"still without " stringByAppendingString:partNames(late.awaited & ~late.arrived)]);
        });
    }
    if (curtain.superview != page) [page addSubview:curtain];
    else if (page.subviews.lastObject != curtain) [page bringSubviewToFront:curtain];
    if (!CGRectEqualToRect(curtain.frame, page.bounds)) curtain.frame = page.bounds;
    liftIfComplete(page, state);
}

void SGRRevealMark(UIView *page, SGRRevealPart part) {
    SGRRevealState *state = stateOf(page, YES);
    if (!state || state.lifted || (state.arrived & part) == part) return;
    state.arrived |= part;
    state.arrivals[@(part)] = @(CACurrentMediaTime());
    liftIfComplete(page, state);
}

BOOL SGRRevealWaitsFor(UIView *page, SGRRevealPart part) {
    if (!page) return NO;
    SGRRevealState *state = stateOf(page, NO);
    return !state || (!state.lifted && (state.arrived & part) != part);
}

void SGRRevealBringToFront(UIView *page, UIView *view) {
    if (!page || view.superview != page) return;
    UIView *curtain = stateOf(page, NO).curtain;
    NSArray<UIView *> *subviews = page.subviews;
    if (curtain.superview != page) {
        if (subviews.lastObject != view) [page bringSubviewToFront:view];
        return;
    }
    NSUInteger count = subviews.count;
    if (count >= 2 && subviews[count - 1] == curtain && subviews[count - 2] == view) return;
    [page bringSubviewToFront:curtain];
    [page insertSubview:view belowSubview:curtain];
}

BOOL SGRRevealShowsText(UIView *root) {
    __block BOOL shows = NO;
    SGForEachView(root, ^(UIView *v) {
        if (shows || ![v isKindOfClass:UILabel.class] || v.hidden) return;
        NSString *text = ((UILabel *)v).text;
        shows = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    });
    return shows;
}
