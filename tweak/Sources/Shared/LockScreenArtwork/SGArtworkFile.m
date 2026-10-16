#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "SGArtworkFile.h"

static const unsigned long long kCap = 120 * 1024 * 1024;   // an Apple Music cover is about 8 MB
// A clip this close to the shape asked for is handed over untouched rather than re-encoded.
static const CGFloat kAspectSlack = 0.02;

static dispatch_queue_t queue(void) {
    static dispatch_queue_t shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = dispatch_queue_create("com.spotifyglass.lockartwork", DISPATCH_QUEUE_SERIAL); });
    return shared;
}

static NSURL *directory(void) {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSURL *url = [NSURL fileURLWithPath:[caches stringByAppendingPathComponent:@"spoti.pw/LockArtwork"]];
    [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

static NSURL *fileFor(NSString *name) {
    return [directory() URLByAppendingPathComponent:name];
}

// Kept alive by its use, so the file the lock screen is playing is the last one to go.
static void touch(NSURL *file) {
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: NSDate.date} ofItemAtPath:file.path error:nil];
}

static void prune(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSArray<NSURLResourceKey> *wanted = @[NSURLContentModificationDateKey, NSURLFileSizeKey];
    NSArray<NSURL *> *kept = [files contentsOfDirectoryAtURL:directory() includingPropertiesForKeys:wanted options:0 error:nil];
    unsigned long long total = 0;
    for (NSURL *file in kept) total += [[file resourceValuesForKeys:wanted error:nil][NSURLFileSizeKey] unsignedLongLongValue];
    if (total <= kCap) return;
    NSArray<NSURL *> *oldest = [kept sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *left = [a resourceValuesForKeys:wanted error:nil][NSURLContentModificationDateKey];
        NSDate *right = [b resourceValuesForKeys:wanted error:nil][NSURLContentModificationDateKey];
        return [left ?: NSDate.distantPast compare:right ?: NSDate.distantPast];
    }];
    for (NSURL *file in oldest) {
        if (total <= kCap) break;
        total -= [[file resourceValuesForKeys:wanted error:nil][NSURLFileSizeKey] unsignedLongLongValue];
        [files removeItemAtURL:file error:nil];
    }
    SGLog(@"lock artwork: cache pruned to %llu KB", total / 1024);
}

static NSURLSessionDownloadTask *sg_task;
// Everyone waiting on each download in flight, by file name: the lock screen and the player asking for
// one clip on the same track share one download.
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_coming;

static NSObject *comingLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [NSObject new];
        sg_coming = [NSMutableDictionary dictionary];
    });
    return lock;
}

// NO when `done` joined a download already coming.
static BOOL firstToAsk(NSString *name, void (^done)(NSURL *file, NSString *note)) {
    @synchronized (comingLock()) {
        NSMutableArray *waiting = sg_coming[name];
        if (waiting) {
            [waiting addObject:[done copy]];
            return NO;
        }
        sg_coming[name] = [NSMutableArray arrayWithObject:[done copy]];
        return YES;
    }
}

static void landed(NSString *name, NSURL *file, NSString *note) {
    NSArray *waiting;
    @synchronized (comingLock()) {
        waiting = sg_coming[name];
        [sg_coming removeObjectForKey:name];
    }
    for (void (^done)(NSURL *, NSString *) in waiting) done(file, note);
}

void SGArtworkCancelFetch(void) {
    NSURLSessionDownloadTask *task = sg_task;
    sg_task = nil;
    [task cancel];
}

void SGArtworkFetch(NSString *identifier, NSString *address, void (^done)(NSURL *file, NSString *note)) {
    SGArtworkCancelFetch();
    sg_task = (NSURLSessionDownloadTask *)SGArtworkFetchAside(identifier, address, done);
}

NSURLSessionTask *SGArtworkFetchAside(NSString *identifier, NSString *address, void (^done)(NSURL *file, NSString *note)) {
    NSURL *remote = address.length ? [NSURL URLWithString:address] : nil;
    if (!remote) {
        done(nil, @"no address");
        return nil;
    }
    NSURL *local = fileFor([identifier stringByAppendingPathExtension:@"mp4"]);
    if ([NSFileManager.defaultManager fileExistsAtPath:local.path]) {
        dispatch_async(queue(), ^{ touch(local); });
        done(local, @"cached");
        return nil;
    }
    NSString *name = local.lastPathComponent;
    if (!firstToAsk(name, done)) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:remote];
    // Low Data Mode marks the path constrained; the download then fails rather than spending the data.
    request.allowsConstrainedNetworkAccess = NO;
    NSURLSessionDownloadTask *task = [NSURLSession.sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL *temporary, NSURLResponse *response, NSError *error) {
        if (!temporary) {
            landed(name, nil, [NSString stringWithFormat:@"download failed: %@", error.localizedDescription]);
            return;
        }
        // Moved before the handler returns, which is when the system deletes the download.
        long long length = response.expectedContentLength;
        NSError *move = nil;
        [NSFileManager.defaultManager removeItemAtURL:local error:nil];
        BOOL moved = [NSFileManager.defaultManager moveItemAtURL:temporary toURL:local error:&move];
        NSString *note = moved ? [NSString stringWithFormat:@"downloaded %lld KB", length / 1024]
                               : [NSString stringWithFormat:@"not kept: %@", move.localizedDescription];
        dispatch_async(queue(), ^{
            if (moved) prune();
            landed(name, moved ? local : nil, note);
        });
    }];
    [task resume];
    return task;
}

// The size the clip is played at, its rotation applied, and the transform that puts its top left at
// the origin.
static CGSize shownSize(AVAssetTrack *track, CGAffineTransform *upright) {
    CGRect shown = CGRectApplyAffineTransform(CGRectMake(0, 0, track.naturalSize.width, track.naturalSize.height),
                                              track.preferredTransform);
    *upright = CGAffineTransformConcat(track.preferredTransform,
                                       CGAffineTransformMakeTranslation(-CGRectGetMinX(shown), -CGRectGetMinY(shown)));
    return CGSizeMake(fabs(shown.size.width), fabs(shown.size.height));
}

// H.264 wants even sides.
static CGFloat even(CGFloat value) {
    return 2 * floor(value / 2);
}

static void crop(AVURLAsset *asset, AVAssetTrack *track, NSURL *into, CGFloat aspect, void (^done)(NSURL *cropped, NSString *note)) {
    CGAffineTransform upright;
    CGSize shown = shownSize(track, &upright);
    if (shown.width < 2 || shown.height < 2) {
        done(nil, @"no picture");
        return;
    }
    if (fabs(shown.width / shown.height - aspect) < kAspectSlack) {
        done(asset.URL, @"already the right shape");
        return;
    }
    CGSize render = shown.width / shown.height > aspect ? CGSizeMake(even(shown.height * aspect), even(shown.height))
                                                        : CGSizeMake(even(shown.width), even(shown.width / aspect));
    AVMutableVideoCompositionLayerInstruction *layer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
    [layer setTransform:CGAffineTransformConcat(upright, CGAffineTransformMakeTranslation((render.width - shown.width) / 2,
                                                                                          (render.height - shown.height) / 2))
                 atTime:kCMTimeZero];
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = track.timeRange;
    instruction.layerInstructions = @[layer];
    AVMutableVideoComposition *composition = [AVMutableVideoComposition videoComposition];
    composition.renderSize = render;
    composition.frameDuration = CMTimeMake(1, track.nominalFrameRate > 1 ? (int32_t)lround(track.nominalFrameRate) : 30);
    composition.instructions = @[instruction];

    AVAssetExportSession *export = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
    if (!export) {
        done(nil, @"no exporter");
        return;
    }
    export.outputURL = into;
    export.outputFileType = AVFileTypeMPEG4;
    export.videoComposition = composition;
    [export exportAsynchronouslyWithCompletionHandler:^{
        BOOL ok = export.status == AVAssetExportSessionStatusCompleted;
        dispatch_async(queue(), ^{
            if (ok) prune();
            done(ok ? into : nil, ok ? [NSString stringWithFormat:@"cropped to %.0fx%.0f", render.width, render.height]
                                     : [NSString stringWithFormat:@"crop failed: %@", export.error.localizedDescription]);
        });
    }];
}

void SGArtworkCrop(NSURL *file, NSString *identifier, CGFloat aspect, void (^done)(NSURL *cropped, NSString *note)) {
    NSURL *into = fileFor([NSString stringWithFormat:@"%@-%.2f.mp4", identifier, aspect]);
    if ([NSFileManager.defaultManager fileExistsAtPath:into.path]) {
        dispatch_async(queue(), ^{ touch(into); });
        done(into, @"cropped already");
        return;
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        dispatch_async(queue(), ^{
            if (!tracks.count) {
                done(nil, [NSString stringWithFormat:@"no video track: %@", error.localizedDescription]);
                return;
            }
            crop(asset, tracks.firstObject, into, aspect, done);
        });
    }];
}

void SGArtworkFirstFrame(NSURL *file, void (^done)(CGImageRef frame)) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:file options:nil]];
    generator.appliesPreferredTrackTransform = YES;
    generator.requestedTimeToleranceBefore = kCMTimeZero;
    generator.requestedTimeToleranceAfter = kCMTimeZero;
    [generator generateCGImageAsynchronouslyForTime:kCMTimeZero completionHandler:^(CGImageRef frame, CMTime actual, NSError *error) {
        done(frame);
    }];
}
