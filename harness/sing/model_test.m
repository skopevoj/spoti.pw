// The production voice model download (Shared/Sing/SGSingModel.m) against a local server model_test.py
// runs: the real background URL session, the pinned sizes and hashes, the staging folder and the move
// into place. The server can corrupt a file, slow the weights down and count the requests it answers.
//   model-test all        a corrupted file rejected, a cancel resumed, the install, removal
//   model-test leave      starts a slow download and exits with it running
//   model-test reconnect  picks that download up the way a launch does, and waits for the install
#import <Foundation/Foundation.h>
#import "Shared/Sing/SGSingModel.h"
#import <assert.h>

static unsigned purges;
void SGStemWorkerPurge(void) { purges++; }

static NSString *serverBase(void) { return SGSingModelBase; }
static NSURL *folder(void) { return [NSURL fileURLWithPath:[SGSingModelRoot stringByAppendingPathComponent:@"spoti.pw/Sing"]]; }

// The server's control endpoint, asked outside the main queue so the main run loop can wait for it.
static NSDictionary *control(NSString *query) {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@control?%@", serverBase(), query]];
    __block NSDictionary *answer = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) answer = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    assert(answer);
    return answer;
}

static BOOL waitFor(NSTimeInterval seconds, BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition()) {
        if (deadline.timeIntervalSinceNow < 0) return NO;
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return YES;
}

static BOOL exists(NSURL *url) { return [NSFileManager.defaultManager fileExistsAtPath:url.path]; }
static NSURL *under(NSString *path) { return [folder() URLByAppendingPathComponent:path]; }

static void checkInstalled(void) {
    assert(SGSingModelCurrentState() == SGSingModelInstalled);
    NSString *model = SGSingModelPath();
    assert([model isEqualToString:under(@"separator.mlmodelc").path]);
    for (NSString *name in @[@"weights/weight.bin", @"model.mil", @"metadata.json", @"coremldata.bin", @"analytics/coremldata.bin"])
        assert(exists([NSURL fileURLWithPath:[model stringByAppendingPathComponent:name]]));
    assert(!exists(under(@"Download")));
    NSNumber *excluded = nil;
    [folder() getResourceValue:&excluded forKey:NSURLIsExcludedFromBackupKey error:nil];
    assert(excluded.boolValue);
    assert(SGSingModelReceived() == SGSingModelSize() && !SGSingModelFailure());
}

static void removeAll(void) {
    unsigned before = purges;
    SGSingModelRemove();
    assert(SGSingModelCurrentState() == SGSingModelMissing && !SGSingModelPath() && purges == before + 1);
    assert(waitFor(10, ^{ return (BOOL)!exists(folder()); }));
}

static void corrupted(void) {
    control(@"corrupt=1&throttle=0&reset=1");
    SGSingModelDownload(NO);
    assert(SGSingModelCurrentState() == SGSingModelDownloading);
    assert(waitFor(120, ^{ return (BOOL)(SGSingModelFailure() != nil); }));
    assert(SGSingModelCurrentState() == SGSingModelMissing && !SGSingModelPath());
    assert([SGSingModelFailure() containsString:@"didn't match"]);
    // The corrupted graph is gone; nothing was put in place.
    assert(!exists(under(@"Download/1.part")) && !exists(under(@"Download/separator.mlmodelc/model.mil")));
    assert(!exists(under(@"separator.mlmodelc")));
    printf("corrupted model.mil rejected and deleted: %s\n", SGSingModelFailure().UTF8String);
    removeAll();
}

static void cancelAndResume(void) {
    control(@"corrupt=0&throttle=40000000&reset=1");
    SGSingModelDownload(NO);
    assert(waitFor(60, ^{ return (BOOL)(SGSingModelReceived() > 100ll << 20); }));
    SGSingModelCancel();
    assert(SGSingModelCurrentState() == SGSingModelMissing && !SGSingModelFailure());
    // The weights keep what came in for the resume, written once the task hands it over.
    assert(waitFor(10, ^{ return (BOOL)exists(under(@"Download/0.resume")); }));
    int64_t kept = SGSingModelReceived();
    assert(kept > 100ll << 20 && kept < SGSingModelSize());
    printf("cancelled at %lld of %lld bytes, resume kept\n", kept, SGSingModelSize());

    control(@"throttle=0&reset=1");
    SGSingModelDownload(NO);
    assert(SGSingModelCurrentState() == SGSingModelDownloading);
    // The progress goes on from what was kept rather than starting from nothing again.
    __block int64_t lowest = INT64_MAX;
    assert(waitFor(300, ^{
        if (SGSingModelCurrentState() == SGSingModelDownloading) lowest = MIN(lowest, SGSingModelReceived());
        return (BOOL)(SGSingModelCurrentState() == SGSingModelInstalled || SGSingModelFailure());
    }));
    assert(lowest >= kept - (4ll << 20));
    if (SGSingModelFailure()) { fprintf(stderr, "failed: %s\n", SGSingModelFailure().UTF8String); abort(); }
    checkInstalled();
    NSDictionary *stats = control(@"stats=1");
    long long offset = [stats[@"weights/weight.bin"] longLongValue];
    printf("resumed the weights from byte %lld, installed\n", offset);
    assert(offset > 100ll << 20);
}

int main(int argc, char **argv) { @autoreleasepool {
    NSString *mode = argc > 1 ? @(argv[1]) : @"all";
    if ([mode isEqualToString:@"all"]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySingModelDownload];
        assert(SGSingModelCurrentState() == SGSingModelMissing && SGSingModelSize() == 489658578);
        assert([SGSingModelBytesText(SGSingModelSize()) isEqualToString:@"467 MB"]);
        corrupted();
        cancelAndResume();
        removeAll();
        printf("model download: corrupted file rejected, cancel and resume, install, removal passed\n");
    } else if ([mode isEqualToString:@"leave"]) {
        control(@"corrupt=0&throttle=40000000&reset=1");
        SGSingModelDownload(NO);
        assert(waitFor(60, ^{ return (BOOL)(SGSingModelReceived() > 50ll << 20); }));
        assert([NSUserDefaults.standardUserDefaults integerForKey:SGKeySingModelDownload] == 1);
        printf("left the download running at %lld bytes\n", SGSingModelReceived());
        exit(0);   // no cancel: the session's tasks outlive the process, as they outlive a suspended app
    } else if ([mode isEqualToString:@"reconnect"]) {
        control(@"throttle=0");
        assert(SGSingModelCurrentState() == SGSingModelMissing);
        SGSingModelReconnect();
        assert(SGSingModelCurrentState() != SGSingModelMissing);
        assert(waitFor(300, ^{ return (BOOL)(SGSingModelCurrentState() == SGSingModelInstalled || SGSingModelFailure()); }));
        if (SGSingModelFailure()) { fprintf(stderr, "failed: %s\n", SGSingModelFailure().UTF8String); abort(); }
        checkInstalled();
        assert(![NSUserDefaults.standardUserDefaults objectForKey:SGKeySingModelDownload]);
        NSDictionary *stats = control(@"stats=1");
        printf("reconnected at launch and installed; the weights were requested %lld time(s)\n", [stats[@"requests"] longLongValue]);
        removeAll();
    }
} return 0; }
