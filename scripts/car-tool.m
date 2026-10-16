// A Mac tool for Spotify's asset catalog (Assets.car), built by app-icons.sh on the fly. It reads and writes
// the catalog through CoreUI's own storage classes, the private ones actool writes with; there is no
// public way to edit a compiled catalog, and recompiling Spotify's would need sources nobody has.
//
//   car-tool svg <Assets.car> <name> <out.svg>    writes out the SVG of the vector named <name>
//   car-tool merge <into.car> <from.car>          copies from.car's names and renditions into into.car
//
// merge leaves out the flattened pictures of app icons (a 1024 px bitmap per appearance, the icon of an
// OS older than 26) and keeps their Liquid Glass stacks, about 10 KB against 3 MB an icon. Run
// `assetutil -U` on the result: the catalog's bitmap index is stale after a merge.
//
// Exit codes: 0 done, 1 failed, 2 usage, 3 a name of from.car hashes to an identifier into.car already
// uses (renditions are keyed by it, and an icon stack names its layers by it, so the two would clash);
// compile from.car again under other names.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <compression.h>

@interface CUICommonAssetStorage : NSObject
- (instancetype)initWithPath:(NSString *)path;
- (instancetype)initWithPath:(NSString *)path forWriting:(BOOL)writing;
- (NSData *)keyFormatData;
- (NSArray<NSString *> *)allRenditionNames;
- (const uint16_t *)renditionKeyForName:(const char *)name hotSpot:(CGPoint *)hotSpot;
- (NSDictionary<NSString *, NSNumber *> *)appearances;
// The block gets each rendition's key as attribute/value pairs ending in 0/0, and its CSI data.
- (BOOL)enumerateKeysAndObjectsUsingBlock:(void (^)(const uint16_t *tokens, NSData *csi))block;
@end

@interface CUIMutableCommonAssetStorage : CUICommonAssetStorage
- (BOOL)setAsset:(NSData *)asset forKey:(NSData *)key;
- (void)setRenditionKey:(const uint16_t *)tokens hotSpot:(CGPoint)hotSpot forName:(const char *)name;
- (void)setAppearanceIdentifier:(uint16_t)identifier forName:(NSString *)name;
- (BOOL)writeToDiskAndCompact:(BOOL)compact;
@end

// Key attributes (CoreUI's kCRTheme…) and the parts of an app icon's flattened pictures.
enum { kElement = 1, kPart = 2, kIdentifier = 17 };
enum { kPartMultiSizedImage = 218, kPartIconImage = 220 };

static uint16_t tokenValue(const uint16_t *tokens, uint16_t attribute) {
    for (int i = 0; tokens[i] || tokens[i + 1]; i += 2)
        if (tokens[i] == attribute) return tokens[i + 1];
    return 0;
}

static CUICommonAssetStorage *openCatalog(const char *path) {
    CUICommonAssetStorage *storage = [[NSClassFromString(@"CUICommonAssetStorage") alloc] initWithPath:@(path)];
    if (!storage) fprintf(stderr, "car-tool: cannot open %s\n", path);
    return storage;
}

// A vector's CSI ends in a DWAR block: the tag, a version, the length, then the SVG, lzfse'd or plain.
static int writeSVG(const char *car, const char *name, const char *out) {
    CUICommonAssetStorage *storage = openCatalog(car);
    if (!storage) return 1;
    CGPoint hot;
    const uint16_t *facet = [storage renditionKeyForName:name hotSpot:&hot];
    if (!facet) { fprintf(stderr, "car-tool: no %s in %s\n", name, car); return 1; }
    uint16_t identifier = tokenValue(facet, kIdentifier);
    __block NSData *svg = nil;
    [storage enumerateKeysAndObjectsUsingBlock:^(const uint16_t *tokens, NSData *csi) {
        if (svg || tokenValue(tokens, kIdentifier) != identifier) return;
        NSRange tag = [csi rangeOfData:[@"DWAR" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0, csi.length)];
        if (tag.location == NSNotFound || NSMaxRange(tag) + 8 > csi.length) return;
        uint32_t length;
        [csi getBytes:&length range:NSMakeRange(NSMaxRange(tag) + 4, 4)];
        NSUInteger start = NSMaxRange(tag) + 8;
        if (start + length > csi.length) return;
        NSData *body = [csi subdataWithRange:NSMakeRange(start, length)];
        if (length > 3 && !memcmp(body.bytes, "bvx", 3)) {
            size_t capacity = 1 << 22;
            uint8_t *buffer = malloc(capacity);
            size_t size = compression_decode_buffer(buffer, capacity, body.bytes, body.length, NULL, COMPRESSION_LZFSE);
            body = size ? [NSData dataWithBytesNoCopy:buffer length:size] : nil;
            if (!size) free(buffer);
        }
        if (body.length > 4 && strnstr(body.bytes, "<svg", MIN(body.length, 256))) svg = body;
    }];
    if (!svg) { fprintf(stderr, "car-tool: %s in %s is not an SVG\n", name, car); return 1; }
    return [svg writeToFile:@(out) atomically:YES] ? 0 : 1;
}

static NSArray<NSNumber *> *keyFormat(CUICommonAssetStorage *storage) {
    NSData *data = [storage keyFormatData];   // 'kfmt', a version, the count, then that many attributes
    const uint32_t *words = data.bytes;
    NSMutableArray *format = [NSMutableArray array];
    for (uint32_t i = 0; data.length >= 12 && i < words[2] && 12 + 4 * i < data.length; i++) [format addObject:@(words[3 + i])];
    return format;
}

static int merge(const char *intoPath, const char *fromPath) {
    // Read-only first: a storage opened for writing does not answer for its key format.
    NSArray<NSNumber *> *format = keyFormat(openCatalog(intoPath));
    CUIMutableCommonAssetStorage *into = [[NSClassFromString(@"CUIMutableCommonAssetStorage") alloc] initWithPath:@(intoPath) forWriting:YES];
    CUICommonAssetStorage *from = openCatalog(fromPath);
    if (!into || !from || !format.count) { fprintf(stderr, "car-tool: cannot open %s for writing\n", intoPath); return 1; }

    NSDictionary<NSString *, NSNumber *> *appearances = [into appearances];
    for (NSString *name in [from appearances]) {
        NSNumber *identifier = [from appearances][name];
        if (!appearances[name]) [into setAppearanceIdentifier:identifier.unsignedShortValue forName:name];
        else if (![appearances[name] isEqual:identifier]) {
            fprintf(stderr, "car-tool: appearance %s is %s in one catalog and %s in the other\n", name.UTF8String,
                    appearances[name].description.UTF8String, identifier.description.UTF8String);
            return 1;
        }
    }

    NSMutableSet<NSNumber *> *taken = [NSMutableSet set];
    for (NSString *name in [into allRenditionNames]) {
        CGPoint hot;
        const uint16_t *facet = [into renditionKeyForName:name.UTF8String hotSpot:&hot];
        if (facet) [taken addObject:@(tokenValue(facet, kIdentifier))];
    }
    NSArray<NSString *> *names = [from allRenditionNames];
    for (NSString *name in names) {
        CGPoint hot;
        const uint16_t *facet = [from renditionKeyForName:name.UTF8String hotSpot:&hot];
        if ([taken containsObject:@(tokenValue(facet, kIdentifier))]) {
            fprintf(stderr, "car-tool: %s hashes to identifier %u, which %s already uses\n", name.UTF8String, tokenValue(facet, kIdentifier), intoPath);
            return 3;
        }
    }
    for (NSString *name in names) {
        CGPoint hot;
        const uint16_t *facet = [from renditionKeyForName:name.UTF8String hotSpot:&hot];
        [into setRenditionKey:facet hotSpot:hot forName:name.UTF8String];
    }

    __block int copied = 0, failed = 0;
    [from enumerateKeysAndObjectsUsingBlock:^(const uint16_t *tokens, NSData *csi) {
        uint16_t part = tokenValue(tokens, kPart);
        if (part == kPartMultiSizedImage || part == kPartIconImage) return;
        // The catalogs may order their key attributes differently, and actool's leaves some of Spotify's out.
        NSMutableData *key = [NSMutableData dataWithLength:format.count * sizeof(uint16_t)];
        uint16_t *slots = key.mutableBytes;
        for (int i = 0; tokens[i] || tokens[i + 1]; i += 2) {
            NSUInteger slot = [format indexOfObject:@(tokens[i])];
            if (slot == NSNotFound) { fprintf(stderr, "car-tool: key attribute %u has no slot in %s\n", tokens[i], intoPath); failed++; return; }
            slots[slot] = tokens[i + 1];
        }
        if ([into setAsset:csi forKey:key]) copied++;
        else failed++;
    }];
    if (failed || ![into writeToDiskAndCompact:YES]) { fprintf(stderr, "car-tool: %d renditions could not be copied\n", failed); return 1; }
    printf("car-tool: merged %lu names, %d renditions\n", (unsigned long)names.count, copied);
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 5 && !strcmp(argv[1], "svg")) return writeSVG(argv[2], argv[3], argv[4]);
        if (argc == 4 && !strcmp(argv[1], "merge")) return merge(argv[2], argv[3]);
        fprintf(stderr, "usage: car-tool svg <Assets.car> <name> <out.svg> | car-tool merge <into.car> <from.car>\n");
        return 2;
    }
}
