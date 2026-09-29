// Shared/LockScreenArtwork run on the Mac: a real 9:16 H.264 clip written here, cropped by the
// tweak's own SGArtworkCrop, handed to MPMediaItemAnimatedArtwork and put in the now playing info
// the way the hook does; and the pure parts, including the dictionary surviving the lock screen
// lyrics' rewrites of it.
#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Shared/LockScreenArtwork/SGArtworkFile.h"
#import "Shared/LockScreenArtwork/SGCanvas.h"

static int sg_failures;

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "  ok  " : "FAILED", what.UTF8String);
    if (!ok) sg_failures++;
}

#define CHECK(cond, ...) check((cond), [NSString stringWithFormat:__VA_ARGS__])

static NSURL *cacheDirectory(void) {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return [NSURL fileURLWithPath:[caches stringByAppendingPathComponent:@"spoti.pw/LockArtwork"]];
}

// A clip the shape a Canvas is, so the crop has something real to chew on.
static NSURL *writeClip(NSURL *into, int width, int height, int frames) {
    [NSFileManager.defaultManager removeItemAtURL:into error:nil];
    NSError *error = nil;
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:into fileType:AVFileTypeMPEG4 error:&error];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(width),
        AVVideoHeightKey: @(height),
    }];
    input.expectsMediaDataInRealTime = NO;
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [writer addInput:input];
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];
    for (int frame = 0; frame < frames; frame++) {
        CVPixelBufferRef buffer = NULL;
        CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
        if (!buffer) break;
        CVPixelBufferLockBaseAddress(buffer, 0);
        uint8_t *bytes = CVPixelBufferGetBaseAddress(buffer);
        size_t stride = CVPixelBufferGetBytesPerRow(buffer);
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                uint8_t *pixel = bytes + y * stride + x * 4;
                pixel[0] = (uint8_t)(x + frame * 8);
                pixel[1] = (uint8_t)(y + frame * 4);
                pixel[2] = (uint8_t)(frame * 16);
                pixel[3] = 0xff;
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        while (!input.readyForMoreMediaData) usleep(1000);
        [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(frame, 30)];
        CVPixelBufferRelease(buffer);
    }
    [input markAsFinished];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return writer.status == AVAssetWriterStatusCompleted ? into : nil;
}

// What the clip is played at, its rotation applied.
static CGSize shownSize(NSURL *file) {
    __block CGSize size = CGSizeZero;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[AVURLAsset URLAssetWithURL:file options:nil] loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        AVAssetTrack *track = tracks.firstObject;
        if (track) {
            CGRect shown = CGRectApplyAffineTransform(CGRectMake(0, 0, track.naturalSize.width, track.naturalSize.height), track.preferredTransform);
            size = CGSizeMake(fabs(shown.size.width), fabs(shown.size.height));
        }
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return size;
}

static void testCanvasFromMetadata(void) {
    SGCanvas *video = SGCanvasFromMetadata(@{@"canvas.id": @"abc", @"canvas.url": @"https://canvaz/x.mp4", @"canvas.type": @"VIDEO_LOOPING"});
    CHECK(video.video && [video.identifier isEqualToString:@"abc"] && [video.address hasSuffix:@"x.mp4"], @"a looping video canvas is taken from the metadata");
    CHECK(!SGCanvasFromMetadata(@{@"canvas.id": @"abc", @"canvas.url": @"https://canvaz/x.jpg", @"canvas.type": @"IMAGE"}).video, @"a still canvas is marked not video");
    CHECK(SGCanvasFromMetadata(@{@"artist_name": @"x"}) == nil, @"a track without canvas keys has no canvas");
    CHECK(SGCanvasFromMetadata(nil) == nil, @"no metadata at all has no canvas");
    SGCanvas *byFile = SGCanvasFromMetadata(@{@"canvas.fileId": @"f1", @"canvas.url": @"https://canvaz/y.mp4", @"canvas.type": @"VIDEO"});
    CHECK([byFile.identifier isEqualToString:@"f1"], @"the file id names a canvas that has no id");
}

static void testCanvaz(void) {
    NSData *body = SGCanvazRequestBody(@"spotify:track:4uLU6hMCjMI75M1A2tKUQC");
    // EntityCanvazRequest { entities = 1 { entity_uri = 1 } }: two tags, two lengths, the uri.
    CHECK(body.length == 2 + 2 + strlen("spotify:track:4uLU6hMCjMI75M1A2tKUQC"), @"the canvaz request wraps the uri twice");
    CHECK(SGCanvazRequestBody(nil) == nil, @"no uri asks for nothing");

    // EntityCanvazResponse { canvases = 1 { id = 1, url = 2, type = 4 } }, built by hand on the wire.
    NSMutableData *canvaz = [NSMutableData data];
    const uint8_t idField[] = {0x0a, 0x02, 'c', '1'};
    const uint8_t urlField[] = {0x12, 0x05, 'h', 't', 't', 'p', 's'};
    const uint8_t typeField[] = {0x20, 0x02};
    [canvaz appendBytes:idField length:sizeof(idField)];
    [canvaz appendBytes:urlField length:sizeof(urlField)];
    [canvaz appendBytes:typeField length:sizeof(typeField)];
    NSMutableData *answer = [NSMutableData data];
    uint8_t head[] = {0x0a, (uint8_t)canvaz.length};
    [answer appendBytes:head length:sizeof(head)];
    [answer appendData:canvaz];
    SGCanvas *canvas = SGCanvazFromBody(answer);
    CHECK(canvas.video && [canvas.identifier isEqualToString:@"c1"] && [canvas.address isEqualToString:@"https"], @"VIDEO_LOOPING comes back out of a canvaz answer");
    CHECK(SGCanvazFromBody([NSData data]) == nil, @"an empty answer carries no canvas");
    CHECK(SGCanvazFromBody([@"not protobuf at all" dataUsingEncoding:NSUTF8StringEncoding]) == nil, @"rubbish is not read as a canvas");
}

static void testMerging(MPMediaItemAnimatedArtwork *artwork, NSString *key) {
    NSDictionary *info = @{
        MPMediaItemPropertyTitle: @"Song",
        MPMediaItemPropertyArtist: @"Artist",
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @12.0,
        MPNowPlayingInfoPropertyPlaybackRate: @1.0,
    };
    NSDictionary *withArtwork = SGArtworkInInfo(info, artwork, key);
    CHECK(withArtwork[key] == artwork, @"the artwork goes in under the key");
    CHECK([withArtwork[MPMediaItemPropertyTitle] isEqual:@"Song"] && withArtwork.count == info.count + 1, @"nothing else in the dictionary moves");
    CHECK(SGArtworkInInfo(withArtwork, artwork, key) == withArtwork, @"the same artwork again leaves the dictionary alone");
    CHECK(SGArtworkInInfo(info, nil, key) == info, @"no artwork means no change");
    CHECK(SGArtworkInInfo(info, artwork, nil) == info, @"no key means no change");

    // LockScreenLyrics.x's rewrite: the artist swapped for the line and the position moved on.
    NSMutableDictionary *rewritten = [withArtwork mutableCopy];
    rewritten[MPMediaItemPropertyArtist] = @"the line being sung";
    rewritten[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @12.25;
    CHECK(rewritten[key] == artwork, @"the key survives the lyrics' rewrite");

    // And the other way round, which is the order the hooks run in when ours is installed first.
    NSMutableDictionary *lyricsFirst = [info mutableCopy];
    lyricsFirst[MPMediaItemPropertyArtist] = @"the line being sung";
    NSDictionary *both = SGArtworkInInfo(lyricsFirst, artwork, key);
    CHECK(both[key] == artwork && [both[MPMediaItemPropertyArtist] isEqual:@"the line being sung"], @"the key goes onto a dictionary the lyrics already wrote");
}

int main(void) {
    @autoreleasepool {
        NSURL *scratch = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"sg-lockart"]];
        [NSFileManager.defaultManager createDirectoryAtURL:scratch withIntermediateDirectories:YES attributes:nil error:nil];
        [NSFileManager.defaultManager removeItemAtURL:cacheDirectory() error:nil];

        printf("canvas\n");
        testCanvasFromMetadata();
        testCanvaz();

        printf("\nthe clip\n");
        NSURL *clip = writeClip([scratch URLByAppendingPathComponent:@"canvas.mp4"], 720, 1280, 45);
        CHECK(clip != nil, @"a 720x1280 H.264 clip is written");
        CGSize shown = shownSize(clip);
        CHECK(fabs(shown.width / shown.height - 9.0 / 16) < 0.01, @"it plays at 9:16 (%.0fx%.0f)", shown.width, shown.height);

        // The fetch with the file already there, which is what every play after the first one is.
        [NSFileManager.defaultManager createDirectoryAtURL:cacheDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
        [NSFileManager.defaultManager copyItemAtURL:clip toURL:[cacheDirectory() URLByAppendingPathComponent:@"cached.mp4"] error:nil];
        __block NSURL *fetched = nil;
        __block NSString *fetchNote = nil;
        dispatch_semaphore_t got = dispatch_semaphore_create(0);
        SGArtworkFetch(@"cached", @"https://example.invalid/never-asked.mp4", ^(NSURL *file, NSString *note) {
            fetched = file;
            fetchNote = note;
            dispatch_semaphore_signal(got);
        });
        dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        CHECK(fetched != nil && [fetchNote isEqualToString:@"cached"], @"a canvas already in the cache is handed straight back (%@)", fetchNote);

        printf("\nthe crop\n");
        __block NSURL *cropped = nil;
        __block NSString *cropNote = nil;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        SGArtworkCrop(clip, @"canvas", 3.0 / 4, ^(NSURL *file, NSString *note) {
            cropped = file;
            cropNote = note;
            dispatch_semaphore_signal(done);
        });
        CHECK(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) == 0, @"the crop answers");
        CHECK(cropped != nil, @"a 3:4 clip comes out (%@)", cropNote);
        CGSize croppedSize = shownSize(cropped);
        CHECK(fabs(croppedSize.width / croppedSize.height - 0.75) < 0.02, @"it plays at 3:4 (%.0fx%.0f)", croppedSize.width, croppedSize.height);
        CHECK(fabs(croppedSize.width - shown.width) < 2, @"the full width of the canvas is kept");
        unsigned long long bytes = [[NSFileManager.defaultManager attributesOfItemAtPath:cropped.path error:nil][NSFileSize] unsignedLongLongValue];
        CHECK(bytes > 1024, @"the cropped file has something in it (%llu KB)", bytes / 1024);

        __block NSURL *again = nil;
        __block NSString *againNote = nil;
        dispatch_semaphore_t twice = dispatch_semaphore_create(0);
        SGArtworkCrop(clip, @"canvas", 3.0 / 4, ^(NSURL *file, NSString *note) {
            again = file;
            againNote = note;
            dispatch_semaphore_signal(twice);
        });
        dispatch_semaphore_wait(twice, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        CHECK([againNote isEqualToString:@"cropped already"] && [again isEqual:cropped], @"the same canvas is not encoded twice (%@)", againNote);

        printf("\nthe animated artwork\n");
        NSArray<NSString *> *supported = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys;
        printf("  this Mac takes %s\n", supported.description.UTF8String);
        NSString *key = [supported containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork]
            ? MPNowPlayingInfoProperty3x4AnimatedArtwork : supported.firstObject ?: MPNowPlayingInfoProperty3x4AnimatedArtwork;
        NSImage *cover = [[NSImage alloc] initWithSize:NSMakeSize(300, 300)];
        __block int previews = 0, videos = 0;
        MPMediaItemAnimatedArtwork *artwork = [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:@"canvas|spotify:track:1"
            previewImageRequestHandler:^(CGSize size, void (^answer)(NSImage *image)) {
                previews++;
                answer(cover);
            }
            videoAssetFileURLRequestHandler:^(CGSize size, void (^answer)(NSURL *url)) {
                videos++;
                answer(cropped);
            }];
        CHECK(artwork != nil, @"MPMediaItemAnimatedArtwork takes the cropped local file and a still");

        printf("\nthe now playing info\n");
        testMerging(artwork, key);
        NSDictionary *out = SGArtworkInInfo(@{MPMediaItemPropertyTitle: @"Song"}, artwork, key);
        MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = out;
        NSDictionary *back = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
        CHECK(back[key] != nil, @"the info centre keeps the artwork under %@", key);
        printf("  the system asked for the still %d time(s) and the clip %d time(s)\n", previews, videos);

        [NSFileManager.defaultManager removeItemAtURL:scratch error:nil];
        [NSFileManager.defaultManager removeItemAtURL:cacheDirectory() error:nil];
        printf("\n%s\n", sg_failures ? [NSString stringWithFormat:@"%d failed", sg_failures].UTF8String : "all good");
        return sg_failures ? 1 : 0;
    }
}
