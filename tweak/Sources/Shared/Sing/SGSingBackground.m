#import "SGSingBackground.h"
#import "Core/SGLog.h"
#import <BackgroundTasks/BackgroundTasks.h>

// The profile must authorize this entitlement; adding it to an unsigned plist cannot grant it.
// These Security entry points are also used by extension/AppGroups/AppGroups.m.
typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

static BGTask *sg_task;
static NSString *sg_identifier, *sg_explanation;
static BOOL sg_requested;
static uint64_t sg_ticket, sg_generation, sg_completed, sg_offset;
static void (^sg_changed)(BOOL);

static BOOL entitled(void) {
    SecTaskRef task = SecTaskCreateFromSelf(NULL);
    if (!task) return NO;
    id value = CFBridgingRelease(SecTaskCopyValueForEntitlement(task,
        CFSTR("com.apple.developer.background-tasks.continued-processing.gpu"), NULL));
    CFRelease(task);
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}
BOOL SGSingBackgroundAllowed(void) { return sg_task != nil; }
NSString *SGSingBackgroundExplanation(void) {
    return sg_explanation ?: @"Sing is waiting for permission to keep processing in the background.";
}
void SGSingBackgroundEnd(void) {
    sg_ticket++;
    sg_changed = nil;
    if (@available(iOS 26.0, *)) {
        if (sg_requested) [BGTaskScheduler.sharedScheduler cancelTaskRequestWithIdentifier:sg_identifier];
        [sg_task setTaskCompletedWithSuccess:YES];
    }
    sg_task = nil; sg_requested = NO;
    sg_generation = sg_completed = sg_offset = 0;
}
void SGSingBackgroundStart(void (^changed)(BOOL)) {
    sg_changed = [changed copy];
    if (sg_requested) return;
    sg_explanation = nil;
    if (@available(iOS 27.0, *)) {
        if (!entitled()) {
            sg_explanation = @"This build needs Background GPU Access in its signing profile to keep Sing on when Spotify is in the background.";
            return;
        }
        if (!(BGTaskScheduler.supportedResources & BGContinuedProcessingTaskRequestResourcesGPU)) {
            sg_explanation = @"Background GPU processing is unavailable on this device.";
            return;
        }
        NSString *prefix = [NSBundle.mainBundle.bundleIdentifier stringByAppendingString:@".sing."];
        NSArray *permitted = NSBundle.mainBundle.infoDictionary[@"BGTaskSchedulerPermittedIdentifiers"];
        if (![permitted containsObject:[prefix stringByAppendingString:@"*"]]) {
            sg_explanation = @"This build is missing Sing's background task registration.";
            return;
        }
        // A unique identifier makes a grant from a cancelled request distinguishable from
        // the next activation; rapid Off/On must never adopt the old request's GPU lifetime.
        sg_identifier = [prefix stringByAppendingString:NSUUID.UUID.UUIDString];
        uint64_t ticket = ++sg_ticket;
        BOOL registered = [BGTaskScheduler.sharedScheduler registerForTaskWithIdentifier:sg_identifier
                usingQueue:dispatch_get_main_queue() launchHandler:^(__kindof BGTask *task) {
                    if (ticket != sg_ticket || !sg_requested || ![task isKindOfClass:BGContinuedProcessingTask.class]) {
                        [task setTaskCompletedWithSuccess:NO]; return;
                    }
                    sg_task = task;
                    __weak BGContinuedProcessingTask *weakTask = (id)sg_task;
                    task.expirationHandler = ^{
                        dispatch_async(dispatch_get_main_queue(), ^{
                            BGContinuedProcessingTask *expired = weakTask;
                            if (!expired || expired != sg_task) return;
                            sg_task = nil;
                            sg_explanation = @"iOS ended Sing's background processing. The original audio will continue.";
                            // Stop the worker before acknowledging that its GPU grant has ended.
                            if (sg_changed) sg_changed(YES);
                            [expired setTaskCompletedWithSuccess:NO];
                        });
                    };
                    ((BGContinuedProcessingTask *)sg_task).progress.totalUnitCount = -1;
                    sg_explanation = nil;
                    if (sg_changed) sg_changed(NO);
                }];
        if (!registered) {
            sg_explanation = @"iOS could not register Sing's background processing.";
            return;
        }
        sg_requested = YES;
        BGContinuedProcessingTaskRequest *request = [[BGContinuedProcessingTaskRequest alloc]
            initWithIdentifier:sg_identifier title:@"Sing" subtitle:@"Separating vocals during playback"];
        request.requiredResources = BGContinuedProcessingTaskRequestResourcesGPU;
        request.strategy = BGContinuedProcessingTaskRequestSubmissionStrategyFail;
        // The asynchronous submission API must not run on the main/audio thread.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [BGTaskScheduler.sharedScheduler submitTaskRequest:request completionHandler:^(NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (ticket != sg_ticket) {
                        // End may have cancelled before the utility queue submitted this
                        // request. Cancel again after submission, without touching the new one.
                        [BGTaskScheduler.sharedScheduler cancelTaskRequestWithIdentifier:request.identifier];
                        return;
                    }
                    if (!error) return;
                    SGLog(@"Sing background request failed: %@", error);
                    sg_explanation = @"iOS could not start Sing's background processing. Keep Spotify open or try Sing again.";
                    if (sg_changed) sg_changed(NO);
                });
            }];
        });
    }
}
void SGSingBackgroundProgress(uint64_t generation, uint64_t completed, uint64_t total) {
    if (!sg_task) return;
    if (@available(iOS 26.0, *)) {
        BGContinuedProcessingTask *task = (id)sg_task;
        if (generation != sg_generation) {
            sg_offset += sg_completed;
            sg_generation = generation; sg_completed = 0;
        }
        sg_completed = MAX(sg_completed, completed);
        // Count actual processed source samples, including changes of track/seek generation.
        task.progress.totalUnitCount = total ? (int64_t)(sg_offset + MAX(total, sg_completed + 1)) : -1;
        task.progress.completedUnitCount = (int64_t)(sg_offset + sg_completed);
    }
}
