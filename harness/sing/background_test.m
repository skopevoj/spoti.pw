// System scheduling boundaries are deterministic; the production grant owner remains real.
#import "Shared/Sing/SGSingBackground.m"
#import <objc/runtime.h>
#import <assert.h>

static BOOL permission = YES, supported = YES, permitted = YES, registration = YES;
static NSMutableDictionary<NSString *, id> *handlers;
static NSMutableArray<BGContinuedProcessingTaskRequest *> *requests;
static unsigned changes, expirations, cancellations;
static NSString *cancelledIdentifier;
static void (^completion)(NSError *);

SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator) { return (SecTaskRef)CFRetain(kCFBooleanTrue); }
CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef name, CFErrorRef *error) {
    return CFRetain(permission ? kCFBooleanTrue : kCFBooleanFalse);
}
@interface FakeTask : NSObject
@property (copy) void (^expirationHandler)(void);
@property NSProgress *progress;
@property BOOL success;
@property unsigned completions;
@end
@implementation FakeTask
- (instancetype)init { if ((self = [super init])) _progress = [NSProgress progressWithTotalUnitCount:100]; return self; }
- (BOOL)isKindOfClass:(Class)c { return c == BGContinuedProcessingTask.class || [super isKindOfClass:c]; }
- (void)setTaskCompletedWithSuccess:(BOOL)success { _success = success; _completions++; _expirationHandler = nil; }
@end
@interface FakeScheduler : NSObject
@end
@implementation FakeScheduler
- (BOOL)registerForTaskWithIdentifier:(NSString *)identifier usingQueue:(dispatch_queue_t)queue launchHandler:(void (^)(BGTask *))handler {
    if (!registration) return NO;
    assert(!handlers[identifier]); handlers[identifier] = [handler copy]; return YES;
}
- (void)submitTaskRequest:(BGContinuedProcessingTaskRequest *)request completionHandler:(void (^)(NSError *))done {
    assert(!NSThread.isMainThread);
    dispatch_async(dispatch_get_main_queue(), ^{ [requests addObject:request]; completion = [done copy]; });
}
- (void)cancelTaskRequestWithIdentifier:(NSString *)identifier { cancellations++; cancelledIdentifier = identifier; }
@end
static id scheduler(id self, SEL cmd) { static FakeScheduler *value; if (!value) value = [FakeScheduler new]; return value; }
static NSInteger resources(id self, SEL cmd) { return supported ? BGContinuedProcessingTaskRequestResourcesGPU : 0; }
static id info(id self, SEL cmd) { return permitted ? @{@"BGTaskSchedulerPermittedIdentifiers": @[@"pw.spoti.test.sing.*"]} : @{}; }
static id identifier(id self, SEL cmd) { return @"pw.spoti.test"; }
static void replace(Class cls, SEL sel, IMP imp) {
    Method m = class_getInstanceMethod(cls, sel); assert(m);
    class_replaceMethod(cls, sel, imp, method_getTypeEncoding(m));
}
static void flush(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]]; }
static FakeTask *grant(NSString *identifier) {
    FakeTask *task = [FakeTask new]; void (^handler)(id) = handlers[identifier]; assert(handler); handler(task); return task;
}
int main(void) { @autoreleasepool {
    handlers = [NSMutableDictionary dictionary]; requests = [NSMutableArray array];
    replace(object_getClass(BGTaskScheduler.class), @selector(sharedScheduler), (IMP)scheduler);
    replace(object_getClass(BGTaskScheduler.class), @selector(supportedResources), (IMP)resources);
    replace(object_getClass(NSBundle.mainBundle), @selector(infoDictionary), (IMP)info);
    replace(object_getClass(NSBundle.mainBundle), @selector(bundleIdentifier), (IMP)identifier);
    void (^changed)(BOOL) = ^(BOOL expired) { changes++; if (expired) expirations++; };
    permission = NO; SGSingBackgroundStart(changed); flush();
    assert(requests.count == 0 && !SGSingBackgroundAllowed() && [SGSingBackgroundExplanation() containsString:@"signing profile"]);
    permission = YES; supported = NO; SGSingBackgroundStart(changed); flush();
    assert(requests.count == 0 && !SGSingBackgroundAllowed());
    supported = YES; permitted = NO; SGSingBackgroundStart(changed); flush();
    assert(requests.count == 0 && !SGSingBackgroundAllowed() && [SGSingBackgroundExplanation() containsString:@"registration"]);
    permitted = YES; registration = NO; SGSingBackgroundStart(changed); flush();
    assert(requests.count == 0 && !SGSingBackgroundAllowed());
    registration = YES; SGSingBackgroundStart(changed); flush();
    assert(requests.count == 1 && !SGSingBackgroundAllowed());
    BGContinuedProcessingTaskRequest *first = requests[0];
    assert(first.requiredResources == BGContinuedProcessingTaskRequestResourcesGPU && first.strategy == BGContinuedProcessingTaskRequestSubmissionStrategyFail);
    completion(nil); flush();
    FakeTask *task = grant(first.identifier);
    assert(SGSingBackgroundAllowed() && changes == 1);
    SGSingBackgroundStart(changed); flush(); assert(requests.count == 1);
    SGSingBackgroundProgress(1, 66150, 441000);
    assert(task.progress.completedUnitCount == 66150 && task.progress.totalUnitCount == 441000);
    SGSingBackgroundProgress(2, 66150, 882000);
    assert(task.progress.completedUnitCount == 132300 && task.progress.totalUnitCount == 948150);
    void (^oldExpiry)(void) = [task.expirationHandler copy];
    void (^oldCompletion)(NSError *) = [completion copy];
    SGSingBackgroundEnd(); assert(task.success && task.completions == 1 && !SGSingBackgroundAllowed());
    SGSingBackgroundStart(changed); flush(); assert(requests.count == 2);
    assert(![requests[1].identifier isEqualToString:first.identifier]);
    oldCompletion(nil); flush();
    assert([cancelledIdentifier isEqualToString:first.identifier]);
    FakeTask *late = grant(first.identifier);
    assert(!late.success && late.completions == 1 && !SGSingBackgroundAllowed());
    FakeTask *second = grant(requests[1].identifier); oldExpiry(); flush();
    assert(SGSingBackgroundAllowed() && second.completions == 0);
    second.expirationHandler(); flush();
    assert(expirations == 1);
    assert(!SGSingBackgroundAllowed() && second.completions == 1 && !second.success);
    assert([SGSingBackgroundExplanation() containsString:@"iOS ended"]);
    SGSingBackgroundEnd(); SGSingBackgroundStart(changed); flush();
    unsigned previous = changes;
    completion([NSError errorWithDomain:@"fixture" code:1 userInfo:nil]); flush();
    assert(!SGSingBackgroundAllowed() && changes == previous + 1);
    SGSingBackgroundEnd(); assert(cancellations == 4);
    puts("Sing background: entitlement gating, GPU grant, progress, cancellation, late grant, stale expiry and submission failure passed");
} return 0; }
