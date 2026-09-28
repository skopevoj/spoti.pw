#import "SGSingModel.h"
#import "SGStemWorker.h"
#import "Core/SGLog.h"
#import "Core/SGPrefs.h"
#import <CommonCrypto/CommonDigest.h>
#import <Network/Network.h>

NSNotificationName const SGSingModelDidChangeNotification = @"spotifyglass.singModelChanged";

// The model host: a Hugging Face repository holding the compiled model's files at the paths below. A test
// build serves them itself and keeps them somewhere of its own (harness/sing/model_test.m).
#ifndef SGSingModelBase
#define SGSingModelBase @"https://huggingface.co/Darkkos/spoti-sing/resolve/main/"
#endif
#ifndef SGSingModelRoot
#define SGSingModelRoot nil
#endif

// The compiled model, file by file, as harness/sing/stage_model.py prints it for an export. Only these
// files, at these sizes and with these hashes, ever become the model; the largest comes first.
static const struct { const char *path; int64_t size; const char *sha256; } kFiles[] = {
    {"weights/weight.bin", 488986336, "970a99fb4b15724bf76d2918ceb177df592c69265d3e2fabaab6e5ba72738e62"},
    {"model.mil", 669061, "966560ed5125174a98f19b94f5de04450a7112ade0e731f2236c202c0280a623"},
    {"metadata.json", 2431, "52a8d5e3f09e33236d495dbed5bbce1c75bac6f2a6b6097637cf214f37c1de53"},
    {"coremldata.bin", 507, "2090acaf7a6df72ec83857cb88d101654023a6baad222a25d0173827d3347e28"},
    {"analytics/coremldata.bin", 243, "f7ee4ec9b5cc1c97171bd5aad93af61e183aa0db1451ef3b775bd4e77f0b7cfd"},
};
enum { kFileCount = sizeof kFiles / sizeof *kFiles };

static NSString *const kSessionIdentifier = @"spotifyglass.sing.model";
static const int64_t kHeadroom = 64ll << 20;               // free space left over once the model is in
static const NSTimeInterval kProgressInterval = 0.25;      // between two progress notifications

// Main thread. A file is done once it is checked and in the staging folder under its own name, and
// checking while it waits for its hash; bytes are what arrived of one still coming, or a stopped
// download kept for its resume. The epoch goes up on removal, so work begun before it is let go.
static BOOL sg_loaded, sg_installed, sg_want, sg_metered;
static NSString *sg_failure;
static BOOL sg_done[kFileCount], sg_checking[kFileCount], sg_restarted[kFileCount], sg_fromResume[kFileCount];
static int64_t sg_bytes[kFileCount];
static NSString *sg_rejected[kFileCount];
static NSMutableDictionary<NSNumber *, NSURLSessionDownloadTask *> *sg_tasks;
static NSUInteger sg_epoch;
static NSURLSession *sg_session;
static void (^sg_sessionCompletion)(void);
static NSTimeInterval sg_lastPost;

#pragma mark - the files

static NSString *pathOf(int i) { return @(kFiles[i].path); }

static NSURL *singFolder(void) {
    static NSURL *folder;
    if (!folder) {
        NSString *root = SGSingModelRoot;
        NSURL *base = root ? [NSURL fileURLWithPath:root isDirectory:YES]
            : [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        folder = [base URLByAppendingPathComponent:@"spoti.pw/Sing" isDirectory:YES];
    }
    return folder;
}
static NSURL *installedModel(void) { return [singFolder() URLByAppendingPathComponent:@"separator.mlmodelc" isDirectory:YES]; }
static NSURL *staging(void) { return [singFolder() URLByAppendingPathComponent:@"Download" isDirectory:YES]; }
static NSURL *stagedModel(void) { return [staging() URLByAppendingPathComponent:@"separator.mlmodelc" isDirectory:YES]; }
static NSURL *stagedFile(int i) { return [stagedModel() URLByAppendingPathComponent:pathOf(i)]; }
// Where a file waits for its hash, and where a stopped download of it keeps what it needs to resume.
static NSURL *arrivedFile(int i) { return [staging() URLByAppendingPathComponent:[NSString stringWithFormat:@"%d.part", i]]; }
static NSURL *resumeFile(int i) { return [staging() URLByAppendingPathComponent:[NSString stringWithFormat:@"%d.resume", i]]; }

static int64_t sizeAt(NSURL *url) {
    NSNumber *size = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil][NSFileSize];
    return size ? size.longLongValue : -1;
}

static NSString *sha256(NSURL *url) {
    NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    if (!file) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    for (;;) {
        @autoreleasepool {
            NSData *chunk = [file readDataUpToLength:1 << 20 error:nil];
            if (!chunk.length) break;
            CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [file closeAndReturnError:nil];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int n = 0; n < CC_SHA256_DIGEST_LENGTH; n++) [hex appendFormat:@"%02x", digest[n]];
    return hex;
}

// Hashing, moving and removing go one after another, off the main thread.
static dispatch_queue_t disk(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.sing.model", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// The folder stays out of the iCloud backup, with what is in it: the model is large and can be had again.
static BOOL makeFolders(NSError **error) {
    if (![NSFileManager.defaultManager createDirectoryAtURL:stagedModel() withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSURL *folder = singFolder();
    [folder setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    return YES;
}

// What is on the disk, read once: the installed model when every file has its size, else the staged files
// (named only once checked) and what each resume kept.
static void load(void) {
    if (sg_loaded) return;
    sg_loaded = YES;
    sg_tasks = [NSMutableDictionary dictionary];
    sg_installed = YES;
    for (int i = 0; i < kFileCount; i++)
        sg_installed &= sizeAt([installedModel() URLByAppendingPathComponent:pathOf(i)]) == kFiles[i].size;
    if (sg_installed) return;
    for (int i = 0; i < kFileCount; i++) {
        sg_done[i] = sizeAt(stagedFile(i)) == kFiles[i].size;
        sg_bytes[i] = sg_done[i] ? 0 : [[NSDictionary dictionaryWithContentsOfURL:resumeFile(i)][@"bytes"] longLongValue];
    }
}

static void post(BOOL progress) {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (progress && now - sg_lastPost < kProgressInterval) return;
    sg_lastPost = now;
    [NSNotificationCenter.defaultCenter postNotificationName:SGSingModelDidChangeNotification object:nil];
}

#pragma mark - the download

@interface SGSingModelDelegate : NSObject <NSURLSessionDownloadDelegate>
@end

static NSURLSession *session(void) {
    if (!sg_session) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:kSessionIdentifier];
        configuration.sessionSendsLaunchEvents = YES;
        configuration.discretionary = NO;
        sg_session = [NSURLSession sessionWithConfiguration:configuration delegate:[SGSingModelDelegate new]
                                             delegateQueue:NSOperationQueue.mainQueue];
    }
    return sg_session;
}

static void keepResume(int i, NSData *data) {
    if (!data) { sg_bytes[i] = 0; return; }
    [@{@"data": data, @"bytes": @(sg_bytes[i]), @"metered": @(sg_metered)} writeToURL:resumeFile(i) error:nil];
}

// Stops every task: kept for a resume when `keep`, dropped otherwise.
static void stopTasks(BOOL keep) {
    sg_want = NO;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySingModelDownload];
    NSUInteger epoch = sg_epoch;
    [sg_tasks enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSURLSessionDownloadTask *task, BOOL *stop) {
        int i = key.intValue;
        if (!keep) { [task cancel]; return; }
        [task cancelByProducingResumeData:^(NSData *data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (epoch != sg_epoch || sg_want) return;
                keepResume(i, data);
                post(NO);
            });
        }];
    }];
    [sg_tasks removeAllObjects];
}

static void fail(NSString *failure) {
    SGLog(@"Sing voice model download stopped: %@", failure);
    sg_failure = failure;
    stopTasks(YES);
    post(NO);
}

static void startFile(int i) {
    NSDictionary *resume = [NSDictionary dictionaryWithContentsOfURL:resumeFile(i)];
    [NSFileManager.defaultManager removeItemAtURL:resumeFile(i) error:nil];
    NSURLSessionDownloadTask *task = nil;
    // A resume carries its request, and with it the networks it may use: one made for others than the
    // ones allowed now starts over, and so does one that has already failed once.
    if ([resume[@"data"] isKindOfClass:NSData.class] && [resume[@"metered"] boolValue] == sg_metered && !sg_restarted[i]) {
        task = [session() downloadTaskWithResumeData:resume[@"data"]];
        sg_bytes[i] = [resume[@"bytes"] longLongValue];
    }
    sg_fromResume[i] = task != nil;
    if (!task) {
        NSURL *url = [NSURL URLWithString:pathOf(i) relativeToURL:[NSURL URLWithString:SGSingModelBase]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.absoluteURL];
        request.allowsExpensiveNetworkAccess = sg_metered;
        request.allowsConstrainedNetworkAccess = sg_metered;
        task = [session() downloadTaskWithRequest:request];
        sg_bytes[i] = 0;
    }
    task.taskDescription = pathOf(i);
    task.countOfBytesClientExpectsToReceive = kFiles[i].size;
    sg_tasks[@(i)] = task;
    [task resume];
}

static void startMissing(void) {
    for (int i = 0; i < kFileCount; i++)
        if (!sg_done[i] && !sg_checking[i] && !sg_tasks[@(i)]) startFile(i);
}

// Every file checked: the staged model takes the installed one's place in one rename.
static void installIfComplete(void) {
    if (!sg_want) return;
    for (int i = 0; i < kFileCount; i++) if (!sg_done[i]) return;
    NSUInteger epoch = sg_epoch;
    NSURL *staged = stagedModel(), *installed = installedModel(), *folder = staging();
    dispatch_async(disk(), ^{
        NSFileManager *files = NSFileManager.defaultManager;
        NSError *error = nil;
        [files removeItemAtURL:installed error:nil];
        BOOL moved = [files moveItemAtURL:staged toURL:installed error:&error];
        if (moved) {
            [files removeItemAtURL:folder error:nil];
            [installed setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (epoch != sg_epoch || !sg_want) return;
            if (!moved) { fail([NSString stringWithFormat:@"The voice model could not be put in place: %@", error.localizedDescription]); return; }
            SGLog(@"Sing voice model installed");
            sg_want = NO;
            [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySingModelDownload];
            sg_installed = YES;
            memset(sg_done, 0, sizeof sg_done);
            memset(sg_bytes, 0, sizeof sg_bytes);
            post(NO);
        });
    });
}

// A file that arrived is hashed off the main thread and named in the staging folder only if it is the
// pinned one; anything else is deleted and stops the download.
static void check(int i) {
    sg_checking[i] = YES;
    NSUInteger epoch = sg_epoch;
    NSURL *arrived = arrivedFile(i), *staged = stagedFile(i);
    int64_t size = kFiles[i].size;
    NSString *expected = @(kFiles[i].sha256);
    dispatch_async(disk(), ^{
        NSFileManager *files = NSFileManager.defaultManager;
        BOOL right = sizeAt(arrived) == size && [sha256(arrived) isEqualToString:expected];
        if (right) {
            [files createDirectoryAtURL:staged.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [files removeItemAtURL:staged error:nil];
            right = [files moveItemAtURL:arrived toURL:staged error:nil];
        }
        if (!right) [files removeItemAtURL:arrived error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (epoch != sg_epoch) return;
            sg_checking[i] = NO;
            sg_done[i] = right;
            sg_bytes[i] = 0;
            if (!right) {
                SGLog(@"Sing voice model: %s did not match its pinned size and hash", kFiles[i].path);
                if (sg_want) fail(@"A downloaded file didn't match Sing's voice model, so it wasn't kept.");
                return;
            }
            installIfComplete();
            post(NO);
        });
    });
}

static int indexOf(NSURLSessionTask *task) {
    for (int i = 0; i < kFileCount; i++) if ([task.taskDescription isEqualToString:pathOf(i)]) return i;
    return -1;
}

@implementation SGSingModelDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)written
 totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    int i = indexOf(task);
    if (i < 0 || sg_tasks[@(i)] != task) return;
    sg_bytes[i] = total;
    post(YES);
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didResumeAtOffset:(int64_t)offset
 expectedTotalBytes:(int64_t)expected {
    int i = indexOf(task);
    if (i < 0 || sg_tasks[@(i)] != task) return;
    SGLog(@"Sing voice model: %s resumed at %lld bytes", kFiles[i].path, offset);
    sg_bytes[i] = offset;
    post(YES);
}

// The file has to be moved before this returns: the system deletes it afterwards.
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    int i = indexOf(task);
    if (i < 0 || !sg_want || sg_done[i] || sg_checking[i]) return;
    NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
    if (status != 200 && status != 206) {
        sg_rejected[i] = [NSString stringWithFormat:@"The voice model's host answered %ld.", (long)status];
        return;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    NSError *error = nil;
    [files removeItemAtURL:arrivedFile(i) error:nil];
    if (![files moveItemAtURL:location toURL:arrivedFile(i) error:&error]) {
        sg_rejected[i] = [NSString stringWithFormat:@"The downloaded file could not be kept: %@", error.localizedDescription];
        return;
    }
    check(i);
    // A launch may have started this file again while the task that finished was still reporting in.
    NSURLSessionDownloadTask *other = sg_tasks[@(i)];
    if (other && other != task) {
        [sg_tasks removeObjectForKey:@(i)];
        [other cancel];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    int i = indexOf(task);
    if (i < 0 || (sg_tasks[@(i)] && sg_tasks[@(i)] != task)) return;
    BOOL ours = sg_tasks[@(i)] == task;
    [sg_tasks removeObjectForKey:@(i)];
    NSString *rejected = sg_rejected[i];
    sg_rejected[i] = nil;
    if (!ours || !sg_want) { post(NO); return; }   // stopped here, which kept or dropped its resume itself
    if (error) {
        keepResume(i, error.userInfo[NSURLSessionDownloadTaskResumeData]);
        BOOL cancelled = [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled;
        // Cancelled without being asked (Spotify was quit while it ran): go on from what it kept. A resume
        // that failed some other way starts that file over, once.
        if (cancelled || (sg_fromResume[i] && !sg_restarted[i])) {
            if (!cancelled) sg_restarted[i] = YES;
            SGLog(@"Sing voice model: %s starting again after %@", kFiles[i].path, error.localizedDescription);
            startFile(i);
            post(NO);
            return;
        }
        fail([NSString stringWithFormat:@"The download stopped: %@", error.localizedDescription]);
        return;
    }
    if (rejected) fail(rejected);
    else post(NO);
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    void (^completion)(void) = sg_sessionCompletion;
    sg_sessionCompletion = nil;
    if (completion) completion();
}

@end

#pragma mark - the API

SGSingModelState SGSingModelCurrentState(void) {
    load();
    if (sg_installed) return SGSingModelInstalled;
    if (!sg_want) return SGSingModelMissing;
    return sg_tasks.count ? SGSingModelDownloading : SGSingModelChecking;
}

int64_t SGSingModelSize(void) {
    int64_t total = 0;
    for (int i = 0; i < kFileCount; i++) total += kFiles[i].size;
    return total;
}

int64_t SGSingModelReceived(void) {
    load();
    if (sg_installed) return SGSingModelSize();
    int64_t total = 0;
    for (int i = 0; i < kFileCount; i++)
        total += sg_done[i] || sg_checking[i] ? kFiles[i].size : MAX(0, MIN(sg_bytes[i], kFiles[i].size));
    return total;
}

NSString *SGSingModelFailure(void) { return sg_failure; }

NSString *SGSingModelPath(void) {
    load();
    return sg_installed ? installedModel().path : nil;
}

NSString *SGSingModelBytesText(int64_t bytes) {
    if (bytes >= 1ll << 30) return [NSString stringWithFormat:@"%.1f GB", bytes / (double)(1ll << 30)];
    return [NSString stringWithFormat:@"%lld MB", (bytes + (1ll << 19)) >> 20];
}

NSString *SGSingModelSpaceProblem(void) {
    int64_t needed = SGSingModelSize() - SGSingModelReceived() + kHeadroom;
    // The volume is asked through the nearest folder that already exists.
    NSURL *folder = singFolder();
    while (folder.path.length > 1 && ![NSFileManager.defaultManager fileExistsAtPath:folder.path])
        folder = folder.URLByDeletingLastPathComponent;
    NSNumber *free = nil;
    [folder getResourceValue:&free forKey:NSURLVolumeAvailableCapacityForImportantUsageKey error:nil];
    if (!free || free.longLongValue >= needed) return nil;
    return [NSString stringWithFormat:@"Sing's voice model needs %@ of free space, and this iPhone has %@.",
            SGSingModelBytesText(needed), SGSingModelBytesText(free.longLongValue)];
}

void SGSingModelCheckNetwork(void (^done)(SGSingModelNetwork network)) {
    nw_path_monitor_t monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(monitor, dispatch_get_main_queue());
    __block BOOL answered = NO;
    nw_path_monitor_set_update_handler(monitor, ^(nw_path_t path) {
        if (answered) return;
        answered = YES;
        SGSingModelNetwork network = nw_path_get_status(path) != nw_path_status_satisfied ? SGSingModelOffline
            : nw_path_is_expensive(path) || nw_path_is_constrained(path) ? SGSingModelMetered : SGSingModelUnmetered;
        nw_path_monitor_cancel(monitor);
        done(network);
    });
    nw_path_monitor_start(monitor);
}

void SGSingModelDownload(BOOL metered) {
    load();
    if (sg_installed || sg_want) return;
    NSError *error = nil;
    if (!makeFolders(&error)) {
        sg_failure = [NSString stringWithFormat:@"The voice model's folder could not be made: %@", error.localizedDescription];
        post(NO);
        return;
    }
    SGLog(@"Sing voice model download starting, %lld of %lld bytes here, %@", SGSingModelReceived(), SGSingModelSize(),
          metered ? @"on any network" : @"off metered networks");
    sg_want = YES;
    sg_metered = metered;
    sg_failure = nil;
    memset(sg_restarted, 0, sizeof sg_restarted);
    SGSetInt(SGKeySingModelDownload, metered ? 2 : 1);
    startMissing();
    installIfComplete();
    post(NO);
}

void SGSingModelCancel(void) {
    load();
    if (!sg_want) return;
    sg_failure = nil;
    stopTasks(YES);
    post(NO);
}

void SGSingModelRemove(void) {
    load();
    SGLog(@"Sing voice model removed");
    sg_epoch++;
    stopTasks(NO);
    sg_installed = NO;
    sg_failure = nil;
    memset(sg_done, 0, sizeof sg_done);
    memset(sg_checking, 0, sizeof sg_checking);
    memset(sg_bytes, 0, sizeof sg_bytes);
    // The warm model goes now; its files after anything already queued for them.
    SGStemWorkerPurge();
    NSURL *folder = singFolder();
    dispatch_async(disk(), ^{ [NSFileManager.defaultManager removeItemAtURL:folder error:nil]; });
    post(NO);
}

BOOL SGSingModelHandlesSession(NSString *identifier, void (^completion)(void)) {
    if (![identifier isEqualToString:kSessionIdentifier]) return NO;
    sg_sessionCompletion = [completion copy];
    load();
    session();   // the events come to the session once it exists again
    return YES;
}

// A download that was running when Spotify last quit: the session is made again, which hands back its
// tasks, and whatever is neither there nor already in is started again.
void SGSingModelReconnect(void) {
    load();
    NSInteger mode = SGInt(SGKeySingModelDownload, 0);
    if (!mode) return;
    if (sg_installed) { [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySingModelDownload]; return; }
    sg_want = YES;
    sg_metered = mode == 2;
    NSUInteger epoch = sg_epoch;
    [session() getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (epoch != sg_epoch || !sg_want) {
                for (NSURLSessionTask *task in tasks) [task cancel];
                return;
            }
            for (NSURLSessionTask *task in tasks) {
                int i = indexOf(task);
                if (i < 0 || sg_done[i] || sg_checking[i] || sg_tasks[@(i)] || ![task isKindOfClass:NSURLSessionDownloadTask.class]) {
                    [task cancel];
                    continue;
                }
                sg_tasks[@(i)] = (NSURLSessionDownloadTask *)task;
                sg_bytes[i] = task.countOfBytesReceived;
            }
            SGLog(@"Sing voice model download picked up with %lu running", (unsigned long)sg_tasks.count);
            startMissing();
            installIfComplete();
            post(NO);
        });
    }];
    post(NO);
}
