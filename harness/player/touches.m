// Real touches for the harness, delivered through UIApplication the way the screen's are, so hit testing,
// gesture recognizers and UIControl tracking all run as they do under a finger. The technique is KIF's:
// a UITouch filled in through its private setters and an IOHIDEvent behind it, sent in the app's own
// touches event.
#import <UIKit/UIKit.h>
#import <mach/mach_time.h>
#import <objc/message.h>
#import "touches.h"

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef double IOHIDFloat;
typedef uint32_t IOOptionBits;

IOHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef, uint64_t, uint32_t type, uint32_t index, uint32_t identity,
                                             uint32_t eventMask, uint32_t buttonMask, IOHIDFloat x, IOHIDFloat y, IOHIDFloat z,
                                             IOHIDFloat tipPressure, IOHIDFloat barrelPressure, Boolean range, Boolean touch,
                                             IOOptionBits options);
IOHIDEventRef IOHIDEventCreateDigitizerFingerEventWithQuality(CFAllocatorRef, uint64_t, uint32_t index, uint32_t identity,
                                                              uint32_t eventMask, IOHIDFloat x, IOHIDFloat y, IOHIDFloat z,
                                                              IOHIDFloat tipPressure, IOHIDFloat twist, IOHIDFloat minorRadius,
                                                              IOHIDFloat majorRadius, IOHIDFloat quality, IOHIDFloat density,
                                                              IOHIDFloat irregularity, Boolean range, Boolean touch, IOOptionBits options);
void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child, IOOptionBits options);
void IOHIDEventSetIntegerValue(IOHIDEventRef event, uint32_t field, long value);

enum { kHand = 3, kEventRange = 0x1, kEventTouch = 0x2, kEventPosition = 0x4 };
static const uint32_t kFieldDisplayIntegrated = (11 << 16) + 25;

@interface UITouch (SGRHarness)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setTapCount:(NSUInteger)count;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)phase;
- (void)setGestureView:(UIView *)view;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)reset;
- (void)_setHidEvent:(IOHIDEventRef)event;
@end

@interface UIEvent (SGRHarness)
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_clearTouches;
- (void)_setHIDEvent:(IOHIDEventRef)event;
@end

@interface UIApplication (SGRHarness)
- (UIEvent *)_touchesEvent;
@end

// Private setters move and get renamed between releases: each is tried by its known names and a missing
// one is logged once rather than thrown.
static BOOL tryBool(id target, NSArray<NSString *> *names, BOOL value) {
    for (NSString *name in names) {
        SEL sel = NSSelectorFromString(name);
        if (![target respondsToSelector:sel]) continue;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(target, sel, value);
        return YES;
    }
    static NSMutableSet *logged;
    if (!logged) logged = [NSMutableSet set];
    if (![logged containsObject:names.firstObject]) {
        [logged addObject:names.firstObject];
        NSLog(@"[harness] touches: %@ has none of %@", [target class], names);
    }
    return NO;
}

static IOHIDEventRef hidEvent(UITouch *touch) {
    uint64_t now = mach_absolute_time();
    IOHIDEventRef hand = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, now, kHand, 0, 0, kEventTouch, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    IOHIDEventSetIntegerValue(hand, kFieldDisplayIntegrated, 1);
    uint32_t mask = touch.phase == UITouchPhaseMoved ? kEventPosition : (kEventRange | kEventTouch);
    Boolean touching = touch.phase != UITouchPhaseEnded;
    CGPoint at = [touch locationInView:touch.window];
    IOHIDEventRef finger = IOHIDEventCreateDigitizerFingerEventWithQuality(kCFAllocatorDefault, now, 1, 2, mask, at.x, at.y, 0, 0, 0,
                                                                           5, 5, 1, 1, 1, touching, touching, 0);
    IOHIDEventSetIntegerValue(finger, kFieldDisplayIntegrated, 1);
    IOHIDEventAppendEvent(hand, finger, 0);
    CFRelease(finger);
    return hand;
}

static void send(UITouch *touch) {
    IOHIDEventRef hid = hidEvent(touch);
    [touch _setHidEvent:hid];
    UIEvent *event = [UIApplication.sharedApplication _touchesEvent];
    [event _clearTouches];
    [event _setHIDEvent:hid];
    [event _addTouch:touch forDelayedDelivery:NO];
    CFRelease(hid);
    [UIApplication.sharedApplication sendEvent:event];
}

// Every setter a touch cannot do without, checked once, so a runtime that lacks one fails the checks
// instead of throwing.
static BOOL ready(void) {
    static int answer;
    if (answer) return answer > 0;
    UITouch *touch = [UITouch new];
    UIEvent *event = [UIApplication.sharedApplication respondsToSelector:@selector(_touchesEvent)] ? [UIApplication.sharedApplication _touchesEvent] : nil;
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *name in @[@"setWindow:", @"setView:", @"setTapCount:", @"setTimestamp:", @"setPhase:",
                              @"_setLocationInWindow:resetPrevious:", @"_setHidEvent:"]) {
        if (![touch respondsToSelector:NSSelectorFromString(name)]) [missing addObject:name];
    }
    for (NSString *name in @[@"_addTouch:forDelayedDelivery:", @"_clearTouches", @"_setHIDEvent:"]) {
        if (![event respondsToSelector:NSSelectorFromString(name)]) [missing addObject:name];
    }
    answer = missing.count ? -1 : 1;
    if (missing.count) NSLog(@"[harness] touches: cannot be made here, missing %@", missing);
    return answer > 0;
}

static UITouch *touchDown(UIWindow *window, CGPoint point) {
    UITouch *touch = [UITouch new];
    [touch setWindow:window];
    [touch setTapCount:1];
    [touch _setLocationInWindow:point resetPrevious:YES];
    UIView *hit = [window hitTest:point withEvent:nil];
    [touch setView:hit];
    [touch setPhase:UITouchPhaseBegan];
    tryBool(touch, @[@"_setIsTapToClick:"], NO);
    tryBool(touch, @[@"_setIsFirstTouchForView:"], YES);
    tryBool(touch, @[@"setIsTap:", @"_setIsTap:"], YES);
    [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    if ([touch respondsToSelector:@selector(setGestureView:)]) [touch setGestureView:hit];
    send(touch);
    return touch;
}

static void moveTo(UITouch *touch, CGPoint point) {
    tryBool(touch, @[@"setIsTap:", @"_setIsTap:"], NO);
    [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    [touch _setLocationInWindow:point resetPrevious:NO];
    [touch setPhase:UITouchPhaseMoved];
    send(touch);
}

static void lift(UITouch *touch) {
    [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    [touch setPhase:UITouchPhaseEnded];
    send(touch);
}

static void later(NSTimeInterval seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

UIView *SGRHarnessPress(UIWindow *window, CGPoint point, NSTimeInterval hold, void (^done)(void)) {
    if (!ready()) return nil;
    UITouch *touch = touchDown(window, point);
    UIView *hit = touch.view;
    later(hold, ^{
        lift(touch);
        if (done) later(0.05, done);
    });
    return hit;
}

UIView *SGRHarnessTap(UIWindow *window, CGPoint point, void (^done)(void)) {
    return SGRHarnessPress(window, point, 0.08, done);
}

UIView *SGRHarnessDrag(UIWindow *window, CGPoint from, CGPoint to, NSTimeInterval duration, void (^done)(void)) {
    if (!ready()) return nil;
    UITouch *touch = touchDown(window, from);
    UIView *hit = touch.view;
    NSInteger steps = MAX(2, (NSInteger)(duration / 0.02));
    for (NSInteger i = 1; i <= steps; i++) {
        CGFloat t = (CGFloat)i / steps;
        CGPoint at = CGPointMake(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t);
        later(0.05 + duration * t, ^{ moveTo(touch, at); });
    }
    later(0.1 + duration, ^{
        lift(touch);
        if (done) later(0.05, done);
    });
    return hit;
}
