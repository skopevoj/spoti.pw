// The engine side of AudioEffects.h (AudioEffects.x in the tweak) the harness does not compile: a made-up
// status and a few fake files in a temporary library. The curves are the engine's own (SGDSPFilters.m).
// The page draws what these answer, so they answer the way the engine is documented to.
#import "Core/SGCore.h"
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "SGDSPFilters.h"

void SGDSPApply(NSString *effect) {
    NSLog(@"[harness] apply %@", effect);
}

NSString *SGDSPStatus(void) {
    if (!SGDSPSwitch(SGKeyDSP)) return @"Off";
    // Alternates, so the page's once a second refresh can be seen working.
    return (long)NSDate.date.timeIntervalSince1970 % 6 < 3 ? @"Running · 44.1 kHz · 3% load" : @"Running · 44.1 kHz · 4% load";
}

// A chosen file whose name has "broken" in it did not take, the way a script that does not compile would not.
NSString *SGDSPError(NSString *switchKey) {
    NSDictionary<NSString *, NSString *> *files = @{
        SGKeyDSPLiveprog: SGKeyDSPLiveprogFile, SGKeyDSPConvolver: SGKeyDSPConvolverFile, SGKeyDSPDDC: SGKeyDSPDDCFile,
    };
    NSString *fileKey = files[switchKey];
    if (fileKey && [SGDSPString(fileKey) containsString:@"broken"]) {
        return @"Line 14: syntax error: 'spl0 =  <!> ;'";
    }
    if ([switchKey isEqualToString:SGKeyDSPGraphicEq] && ![SGDSPString(SGKeyDSPGraphicEqNodes) hasPrefix:@"GraphicEQ:"]) {
        return @"Not a GraphicEQ line: it starts with \"GraphicEQ:\"";
    }
    return nil;
}

#pragma mark - file libraries

static NSString *folderName(SGDSPFileKind kind) {
    return kind == SGDSPFileImpulseResponse ? @"Convolver" : kind == SGDSPFileDDC ? @"DDC" : @"Liveprog";
}

NSArray<NSString *> *SGDSPFileExtensions(SGDSPFileKind kind) {
    if (kind == SGDSPFileImpulseResponse) return @[@"wav", @"flac", @"irs"];
    return kind == SGDSPFileDDC ? @[@"vdc"] : @[@"eel"];
}

NSString *SGDSPLibraryDirectory(SGDSPFileKind kind) {
    NSString *path = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"AudioEffectsStandIn"] stringByAppendingPathComponent:folderName(kind)];
    NSFileManager *files = NSFileManager.defaultManager;
    if ([files fileExistsAtPath:path]) return path;
    [files createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray<NSString *> *shipped = kind == SGDSPFileImpulseResponse ? @[@"Concert hall.wav", @"Headphone crossfeed.irs", @"Small room.flac"]
                                 : kind == SGDSPFileDDC ? @[@"Beyerdynamic DT 770.vdc", @"Sennheiser HD 600.vdc"]
                                 : @[@"Bass enhancer.eel", @"Stereo panning.eel", @"Tape saturation broken.eel", @"Vinyl noise.eel"];
    for (NSString *name in shipped) {
        [[@"stand-in" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[path stringByAppendingPathComponent:name] atomically:YES];
    }
    return path;
}

NSArray<NSString *> *SGDSPLibraryFiles(SGDSPFileKind kind) {
    NSArray<NSString *> *extensions = SGDSPFileExtensions(kind);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:SGDSPLibraryDirectory(kind) error:nil]) {
        if ([extensions containsObject:name.pathExtension.lowercaseString]) [names addObject:name];
    }
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

NSString *SGDSPImportFile(SGDSPFileKind kind, NSURL *url, NSError **error) {
    NSString *name = url.lastPathComponent;
    if (![SGDSPFileExtensions(kind) containsObject:name.pathExtension.lowercaseString]) {
        if (error) *error = [NSError errorWithDomain:@"AudioEffects" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not a file of this kind."}];
        return nil;
    }
    NSString *target = [SGDSPLibraryDirectory(kind) stringByAppendingPathComponent:name];
    [NSFileManager.defaultManager removeItemAtPath:target error:nil];
    if (![NSFileManager.defaultManager copyItemAtPath:url.path toPath:target error:error]) return nil;
    return name;
}

BOOL SGDSPDeleteFile(SGDSPFileKind kind, NSString *name) {
    return [NSFileManager.defaultManager removeItemAtPath:[SGDSPLibraryDirectory(kind) stringByAppendingPathComponent:name] error:nil];
}

#pragma mark - curves

void SGDSPEqualizerResponse(NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *decibels) {
    double values[15] = {0};
    for (NSUInteger i = 0; i < 15 && i < gains.count; i++) values[i] = gains[i].doubleValue;
    SGBiquad bands[15];
    SGDSPDesignEqualizer(48000, SGDSPEqualizerFrequencies, values, bands);
    SGDSPLogFrequencies((int)count, frequencies);
    for (NSInteger i = 0; i < count; i++) decibels[i] = SGBiquadGainDB(bands, 15, 48000, frequencies[i]);
}

void SGDSPCompanderResponse(NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *values) {
    double amounts[7] = {0};
    for (NSUInteger i = 0; i < 7 && i < gains.count; i++) amounts[i] = gains[i].doubleValue;
    SGDSPLogFrequencies((int)count, frequencies);
    for (NSInteger i = 0; i < count; i++) values[i] = SGDSPSmoothCurve(SGDSPCompanderFrequencies, amounts, 7, frequencies[i]);
}
