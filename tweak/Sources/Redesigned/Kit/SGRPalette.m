#import <CoreImage/CoreImage.h>
#import "Core/SGCore.h"
#import "SGRPalette.h"
#import "SGRTokens.h"

static const size_t kSample = 64;      // the artwork shrunk to this square before its colours are read
static const size_t kEdgeRows = 10;    // the bottom rows of it averaged into the edge colour
// A field's OKLab lightness ceiling (0.30 with Increase Contrast), and its chroma lift and cap.
static const CGFloat kFieldLightness = 0.34, kFieldLightnessContrast = 0.30;
static const CGFloat kFieldChromaLift = 1.3, kFieldChroma = 0.14;
static const CGFloat kDissolveWidth = 96, kDissolveSigma = 5;
static const CGFloat kFadeFrom = 0.55, kDissolveOpaque = 0.85;
// A tint: the artwork's dominant colour brought down to this luminance, then this share of it mixed into
// the surface it tints.
static const CGFloat kTintLuminance = 0.05, kTintShare = 0.35;

@interface SGRPalette ()
@property (nonatomic, readwrite) UIColor *edgeColor;
@property (nonatomic, readwrite) UIColor *fieldColor;
@property (nonatomic, readwrite) UIImage *dissolve;
@end

static dispatch_queue_t paletteQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("spotifyglass.redesign.palette", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
    });
    return queue;
}

static CGColorSpaceRef sRGB(void) {
    static CGColorSpaceRef space;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB); });
    return space;
}

// One context for the whole launch; CIContext is safe to share and costly to make.
static CIContext *blurContext(void) {
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        context = [CIContext contextWithOptions:@{kCIContextCacheIntermediates: @NO, kCIContextWorkingColorSpace: (__bridge id)sRGB()}];
    });
    return context;
}

static CGContextRef newBitmap(size_t width, size_t height) {
    return CGBitmapContextCreate(NULL, width, height, 8, width * 4, sRGB(), (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
}

static void drawFilling(CGContextRef context, CGImageRef image, size_t width, size_t height) {
    CGFloat iw = CGImageGetWidth(image), ih = CGImageGetHeight(image);
    CGFloat scale = MAX(width / iw, height / ih);
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake((width - iw * scale) / 2, (height - ih * scale) / 2, iw * scale, ih * scale), image);
}

#pragma mark - colour

static CGFloat toLinear(CGFloat c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

static CGFloat toEncoded(CGFloat c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055;
}

static void toOklab(const CGFloat linear[3], CGFloat lab[3]) {
    CGFloat l = cbrt(0.4122214708 * linear[0] + 0.5363325363 * linear[1] + 0.0514459929 * linear[2]);
    CGFloat m = cbrt(0.2119034982 * linear[0] + 0.6806995451 * linear[1] + 0.1073969566 * linear[2]);
    CGFloat s = cbrt(0.0883024619 * linear[0] + 0.2817188376 * linear[1] + 0.6299787005 * linear[2]);
    lab[0] = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    lab[1] = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    lab[2] = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
}

// NO when the colour is outside sRGB.
static BOOL fromOklab(CGFloat lightness, CGFloat a, CGFloat b, CGFloat linear[3]) {
    CGFloat l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3);
    CGFloat m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3);
    CGFloat s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3);
    linear[0] = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    linear[1] = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    linear[2] = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
    for (int k = 0; k < 3; k++) {
        if (linear[k] < -1e-6 || linear[k] > 1 + 1e-6) return NO;
    }
    return YES;
}

// The colour's own hue, dark and a little more colourful, as the Music app draws a page: capping saturation
// in HSV instead turned every warm hue brown. Past the chroma sRGB holds at that lightness, chroma gives way.
static UIColor *fieldColorFor(UIColor *color, CGFloat ceiling) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if (![color getWhite:&white alpha:&a]) return SGRNeutralField();
        r = g = b = white;
    }
    CGFloat linear[3] = {toLinear(MIN(1, MAX(0, r))), toLinear(MIN(1, MAX(0, g))), toLinear(MIN(1, MAX(0, b)))}, lab[3];
    toOklab(linear, lab);
    CGFloat lightness = MIN(lab[0], ceiling), hue = atan2(lab[2], lab[1]);
    CGFloat chroma = MIN(hypot(lab[1], lab[2]) * kFieldChromaLift, kFieldChroma);
    while (!fromOklab(lightness, chroma * cos(hue), chroma * sin(hue), linear) && chroma > 0) {
        chroma = MAX(0, chroma - 0.004);
    }
    return [UIColor colorWithRed:toEncoded(MIN(1, MAX(0, linear[0]))) green:toEncoded(MIN(1, MAX(0, linear[1])))
                            blue:toEncoded(MIN(1, MAX(0, linear[2]))) alpha:1];
}

static CGFloat fieldCeiling(void) {
    return SGRIncreaseContrast() ? kFieldLightnessContrast : kFieldLightness;
}

UIColor *SGRFieldColorFor(UIColor *color) {
    return color ? fieldColorFor(color, fieldCeiling()) : SGRNeutralField();
}

// The artwork squeezed into a small square, whatever its aspect, and the bottom rows of that averaged
// by coverage. A bitmap context keeps its rows top to bottom, so the last rows are the bottom edge.
static UIColor *edgeColorOf(CGImageRef image) {
    CGContextRef context = newBitmap(kSample, kSample);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, kSample, kSample), image);
    const uint8_t *px = CGBitmapContextGetData(context);
    double r = 0, g = 0, b = 0, coverage = 0;
    for (size_t y = kSample - kEdgeRows; px && y < kSample; y++) {
        for (size_t x = 0; x < kSample; x++) {
            const uint8_t *p = px + (y * kSample + x) * 4;
            r += p[0], g += p[1], b += p[2], coverage += p[3];
        }
    }
    CGContextRelease(context);
    // Premultiplied, so the sums over the summed alpha are the average of what is actually there.
    if (coverage < 1) return nil;
    return [UIColor colorWithRed:r / coverage green:g / coverage blue:b / coverage alpha:1];
}

#pragma mark - bitmaps

// The artwork drawn to fill the size, then blurred with its edges clamped so the border does not
// darken. Returned retained.
static CGImageRef newBlurred(CGImageRef image, size_t width, size_t height, CGFloat sigma) {
    CGContextRef context = newBitmap(width, height);
    if (!context) return NULL;
    drawFilling(context, image, width, height);
    CGImageRef small = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!small) return NULL;
    CIImage *input = [CIImage imageWithCGImage:small];
    CGImageRelease(small);
    CIImage *output = [[input imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:sigma];
    return [blurContext() createCGImage:output fromRect:input.extent format:kCIFormatRGBA8 colorSpace:sRGB()];
}

// A black gradient from `a0` at `y0` to `a1` at `y1` (shares of the height, top down), extended
// past both ends; with kCGBlendModeDestinationIn it becomes an alpha ramp instead of a dim.
static void drawRamp(CGContextRef context, size_t height, CGFloat y0, CGFloat a0, CGFloat y1, CGFloat a1, CGBlendMode mode) {
    CGFloat components[] = {0, 0, 0, a0, 0, 0, 0, a1};
    CGFloat locations[] = {0, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(sRGB(), components, locations, 2);
    CGContextSetBlendMode(context, mode);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, y0 * height), CGPointMake(0, y1 * height),
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);
}

static UIImage *finished(CGImageRef blurred, CGFloat rampFrom, CGFloat alphaFrom, CGFloat rampTo, CGFloat alphaTo) {
    size_t width = CGImageGetWidth(blurred), height = CGImageGetHeight(blurred);
    CGContextRef context = newBitmap(width, height);
    if (!context) return nil;
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), blurred);
    // Top down from here on.
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1, -1);
    drawRamp(context, height, rampFrom, alphaFrom, rampTo, alphaTo, kCGBlendModeDestinationIn);
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    UIImage *image = result ? [UIImage imageWithCGImage:result scale:1 orientation:UIImageOrientationUp] : nil;
    CGImageRelease(result);
    return image;
}

#pragma mark - tint

// The artwork's dominant colour in linear light: its pixels binned 3 bits a channel, each bin scored by its
// count weighted towards colourful pixels, so a busy cover gives its main colour instead of the grey an
// average makes. Near-black and near-white count for little unless they are nearly all there is.
// The same over the rows y0..y1 and columns x0..x1 of a kSample square bitmap (rows top down).
static BOOL dominantIn(const uint8_t *px, size_t x0, size_t y0, size_t x1, size_t y1, CGFloat out[3]) {
    enum { kBins = 512 };
    double sums[kBins][3] = {{0}}, scores[kBins] = {0};
    size_t counts[kBins] = {0};
    for (size_t i = 0; px && i < kSample * kSample; i++) {
        size_t x = i % kSample, y = i / kSample;
        if (x < x0 || x >= x1 || y < y0 || y >= y1) continue;
        const uint8_t *p = px + i * 4;
        if (p[3] < 128) continue;
        int bin = (p[0] >> 5) << 6 | (p[1] >> 5) << 3 | (p[2] >> 5);
        CGFloat high = MAX(p[0], MAX(p[1], p[2])) / 255.0, low = MIN(p[0], MIN(p[1], p[2])) / 255.0;
        CGFloat saturation = high > 0 ? (high - low) / high : 0;
        scores[bin] += (0.25 + saturation) * (high < 0.12 ? 0.3 : 1) * (low > 0.88 ? 0.3 : 1);
        counts[bin]++;
        sums[bin][0] += toLinear(p[0] / 255.0), sums[bin][1] += toLinear(p[1] / 255.0), sums[bin][2] += toLinear(p[2] / 255.0);
    }
    int best = 0;
    for (int i = 1; i < kBins; i++) {
        if (scores[i] > scores[best]) best = i;
    }
    if (!counts[best]) return NO;
    for (int k = 0; k < 3; k++) out[k] = sums[best][k] / counts[best];
    return YES;
}

static BOOL dominantColorOf(CGImageRef image, CGFloat out[3]) {
    CGContextRef context = newBitmap(kSample, kSample);
    if (!context) return NO;
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, kSample, kSample), image);
    BOOL found = dominantIn(CGBitmapContextGetData(context), 0, 0, kSample, kSample, out);
    CGContextRelease(context);
    return found;
}

static UIColor *tintOf(CGImageRef image, UIColor *surface) {
    CGFloat linear[3];
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (!dominantColorOf(image, linear) || ![surface getRed:&r green:&g blue:&b alpha:&a]) return nil;
    CGFloat luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
    if (luminance > kTintLuminance) {
        for (int k = 0; k < 3; k++) linear[k] *= kTintLuminance / luminance;
    }
    CGFloat t = kTintShare;
    CGFloat mixed[3] = {r * (1 - t) + toEncoded(linear[0]) * t,
                        g * (1 - t) + toEncoded(linear[1]) * t,
                        b * (1 - t) + toEncoded(linear[2]) * t};

    // The colour mixed in is held under a luminance of 0.05 but has no floor, so a near-black cover mixes the
    // surface *down*: the tile ends up darker than the untinted surface it was meant to be a step above, and a
    // neutral one lands in the 1-10% grey band SGRAmoled.x turns pure black, which takes the whole card with
    // it -- a black square lost on a black page (The Weeknd's Trilogy, Bieber's SWAG; issue #36). So a mix
    // dimmer than the surface is lifted back to the surface's luminance, in linear light and by one factor
    // across the channels, which leaves its hue where the mix put it. Lifting cannot clip: the target
    // luminance is the surface's ~0.014, and the most one channel can carry of it is 0.014 / 0.0722.
    CGFloat want = 0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b);
    CGFloat lit[3] = {toLinear(mixed[0]), toLinear(mixed[1]), toLinear(mixed[2])};
    CGFloat have = 0.2126 * lit[0] + 0.7152 * lit[1] + 0.0722 * lit[2];
    if (have <= 0) return surface;
    if (have < want) {
        for (int k = 0; k < 3; k++) mixed[k] = toEncoded(MIN(1, lit[k] * want / have));
    }

    return [UIColor colorWithRed:mixed[0] green:mixed[1] blue:mixed[2] alpha:1];
}

@implementation SGRPalette

+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *palette))completion {
    if (!completion) return;
    CGFloat ceiling = fieldCeiling();
    dispatch_async(paletteQueue(), ^{
        SGRPalette *palette = nil;
        CGImageRef cg = image.CGImage;
        UIColor *edge = cg && CGImageGetWidth(cg) && CGImageGetHeight(cg) ? edgeColorOf(cg) : nil;
        if (edge) {
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            palette = [SGRPalette new];
            palette.edgeColor = edge;
            // The artwork's main colour, not its edge's: a scanned sleeve's edge is the scanner's grey, a
            // portrait's is skin.
            CGFloat main[3];
            UIColor *source = dominantColorOf(cg, main)
                ? [UIColor colorWithRed:toEncoded(main[0]) green:toEncoded(main[1]) blue:toEncoded(main[2]) alpha:1] : edge;
            palette.fieldColor = fieldColorFor(source, ceiling);
            if (request.dissolve) {
                CGFloat aspect = (CGFloat)CGImageGetHeight(cg) / CGImageGetWidth(cg);
                size_t height = (size_t)MIN(kDissolveWidth * 2, MAX(kDissolveWidth / 2, round(kDissolveWidth * aspect)));
                CGImageRef blurred = newBlurred(cg, (size_t)kDissolveWidth, height, kDissolveSigma);
                if (blurred) palette.dissolve = finished(blurred, kFadeFrom, 0, kDissolveOpaque, 1);
                CGImageRelease(blurred);
            }
            static dispatch_once_t once;
            double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
            dispatch_once(&once, ^{ SGLog(@"redesign kit: first palette %@ from %zux%zu in %.1f ms", palette.fieldColor, CGImageGetWidth(cg), CGImageGetHeight(cg), ms); });
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(palette); });
    });
}

+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface completion:(void (^)(UIColor *tint))completion {
    if (!completion) return;
    dispatch_async(paletteQueue(), ^{
        CGImageRef cg = image.CGImage;
        UIColor *tint = cg && CGImageGetWidth(cg) && CGImageGetHeight(cg) ? tintOf(cg, surface) : nil;
        static dispatch_once_t once;
        if (tint) dispatch_once(&once, ^{ SGLog(@"redesign kit: first tint %@", tint); });
        dispatch_async(dispatch_get_main_queue(), ^{ completion(tint); });
    });
}

@end
