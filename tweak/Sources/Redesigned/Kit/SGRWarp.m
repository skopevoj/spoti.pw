#import <Metal/Metal.h>
#import "Core/SGCore.h"
#import "SGRWarp.h"
#import "SGRTokens.h"

const SGRWarpLook SGRWarpDefaultLook = {1, 1, 8, 1.5, 1};

static const NSUInteger kBlurSide = 128;
// Drawable pixels per point: the picture is a blur, so a small drawable scaled up by the compositor
// looks the same and costs a tenth.
static const CGFloat kPixelsPerPoint = 0.5;
static const CFTimeInterval kFade = 1.0;
static const float kTint[3] = {0.157f, 0.157f, 0.235f}, kTintAmount = 0.15f;
// The colour's linear luminance is held under this (0.07 with Increase Contrast), so white text keeps
// better than 5.5:1 at full brightness.
static const float kCeiling = 0.13f, kCeilingContrast = 0.07f;
// The shade under the controls: clear down to this share of the picture, then this much black at its bottom.
static const float kShadeFrom = 0.45f, kShadeBottom = 0.35f;
static const float kDither = 0.008f;

// The shaders are kawarp's (packages/core/src/index.ts), its simplex noise Ashima Arts' and its hash
// Dave Hoskins', all MIT; the passes are the same, the warp and the output are one pass here.
static NSString *const kSource = @R"(
#include <metal_stdlib>
using namespace metal;

struct Vertex { float4 position [[position]]; };

vertex Vertex cover(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return { float4(p * 2 - 1, 0, 1) };
}

constexpr sampler smooth(filter::linear, address::clamp_to_edge);

struct Tint { float r, g, b, amount; };

fragment half4 tint(Vertex in [[stage_in]], texture2d<float> source [[texture(0)]], constant Tint &t [[buffer(0)]]) {
    float4 c = source.sample(smooth, in.position.xy / float2(source.get_width(), source.get_height()));
    float luma = dot(c.rgb, float3(0.299, 0.587, 0.114));
    float dark = 1 - smoothstep(0.0, 0.5, luma);
    c.rgb = mix(c.rgb, float3(t.r, t.g, t.b), dark * t.amount);
    return half4(c);
}

fragment half4 kawase(Vertex in [[stage_in]], texture2d<float> t [[texture(0)]], constant float &offset [[buffer(0)]]) {
    float2 texel = 1.0 / float2(t.get_width(), t.get_height());
    float2 uv = in.position.xy * texel, o = offset * texel;
    float4 c = t.sample(smooth, uv + float2(-o.x, -o.y)) + t.sample(smooth, uv + float2(o.x, -o.y))
             + t.sample(smooth, uv + float2(-o.x, o.y)) + t.sample(smooth, uv + o);
    return half4(c * 0.25);
}

fragment half4 blend(Vertex in [[stage_in]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]], constant float &amount [[buffer(0)]]) {
    float2 uv = in.position.xy / float2(a.get_width(), a.get_height());
    return half4(mix(a.sample(smooth, uv), b.sample(smooth, uv), amount));
}

float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float2 mod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float3 permute(float3 x) { return mod289(((x * 34.0) + 1.0) * x); }

float snoise(float2 v) {
    const float4 C = float4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
    float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
    float3 x = 2.0 * fract(p * C.www) - 1.0;
    float3 h = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    float3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

float hash(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

struct Frame {
    float scaleX, scaleY, offsetX, offsetY;
    float time, blend, warp, saturation, brightness, ceiling, shadeFrom, shade, dither;
};

fragment half4 warp(Vertex in [[stage_in]], texture2d<float> from [[texture(0)]], texture2d<float> to [[texture(1)]], constant Frame &f [[buffer(0)]]) {
    // Where in the picture this pixel is; past its edges the edge carries on.
    float2 v = in.position.xy * float2(f.scaleX, f.scaleY) + float2(f.offsetX, f.offsetY);
    float2 uv = clamp(v, 0.0, 1.0);
    float t = f.time * 0.05;

    float2 centre = uv - 0.5;
    float weight = 1.0 - smoothstep(0.0, 0.7, length(centre));
    float n1 = snoise(uv * 0.35 + float2(t, t * 0.7));
    float n2 = snoise(uv * 0.35 + float2(-t * 0.8, t * 0.5) + float2(50.0, 50.0));
    float n3 = snoise(uv * 0.9 + float2(t * 1.2, -t) + float2(100.0, 0.0));
    float n4 = snoise(uv * 0.9 + float2(-t, t * 1.1) + float2(0.0, 100.0));
    float2 bend = float2(n1 * 0.65 + n3 * 0.35, n2 * 0.65 + n4 * 0.35) * weight;
    float2 p = clamp(uv + bend * f.warp, 0.0, 1.0);

    float3 c = mix(from.sample(smooth, p).rgb, to.sample(smooth, p).rgb, f.blend);
    c *= 1.0 - dot(centre, centre) * 0.3;
    float gray = dot(c, float3(0.299, 0.587, 0.114));
    c = max(mix(float3(gray), c, f.saturation), 0.0);

    // Held under the ceiling with a soft knee, in light rather than in code values (gamma 2 is near enough).
    float3 light = c * c;
    float lum = dot(light, float3(0.2126, 0.7152, 0.0722));
    float knee = f.ceiling * 0.6;
    if (lum > knee) {
        float held = knee + (f.ceiling - knee) * (1.0 - exp(-(lum - knee) / (f.ceiling - knee)));
        c *= sqrt(held / lum);
    }
    c *= f.brightness * (1.0 - f.shade * clamp((v.y - f.shadeFrom) / (1.0 - f.shadeFrom), 0.0, 1.0));
    c += (hash(float3(floor(in.position.xy), 0.0)) - 0.5) * f.dither;
    return half4(half3(c), 1.0h);
}
)";

// The same layout as the shader's Frame, all floats so the two agree without packing rules.
typedef struct {
    float scaleX, scaleY, offsetX, offsetY;
    float time, blend, warp, saturation, brightness, ceiling, shadeFrom, shade, dither;
} SGRWarpFrame;

typedef struct {
    float r, g, b, amount;
} SGRWarpTint;

#pragma mark - the device, the shaders and the blur's scratch, shared by every layer

@interface SGRWarpGPU : NSObject
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> queue;
@property (nonatomic, strong) id<MTLRenderPipelineState> tint, kawase, blend, warp;
@property (nonatomic, strong) id<MTLTexture> scratchA, scratchB;
@end

@implementation SGRWarpGPU
@end

static SGRWarpGPU *sg_gpu;
static BOOL sg_compiling, sg_failed;
static NSHashTable *sg_waiting;

static id<MTLDevice> sharedDevice(void) {
    static id<MTLDevice> device;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ device = MTLCreateSystemDefaultDevice(); });
    return device;
}

BOOL SGRWarpAvailable(void) {
    return sharedDevice() != nil && !sg_failed;
}

static id<MTLRenderPipelineState> pipeline(id<MTLDevice> device, id<MTLLibrary> library, NSString *fragment, MTLPixelFormat format, NSError **error) {
    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.label = fragment;
    descriptor.vertexFunction = [library newFunctionWithName:@"cover"];
    descriptor.fragmentFunction = [library newFunctionWithName:fragment];
    descriptor.colorAttachments[0].pixelFormat = format;
    return [device newRenderPipelineStateWithDescriptor:descriptor error:error];
}

static id<MTLTexture> blurTexture(id<MTLDevice> device) {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                          width:kBlurSide height:kBlurSide mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    descriptor.storageMode = MTLStorageModePrivate;
    return [device newTextureWithDescriptor:descriptor];
}

static void gpuReady(void);

void SGRWarpPrepare(void) {
    if (sg_gpu || sg_compiling || sg_failed) return;
    id<MTLDevice> device = sharedDevice();
    if (!device) {
        sg_failed = YES;
        SGLog(@"redesign warp: no Metal device, nothing drawn");
        return;
    }
    sg_compiling = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CFTimeInterval began = CACurrentMediaTime();
        NSError *error = nil;
        id<MTLLibrary> library = [device newLibraryWithSource:kSource options:nil error:&error];
        SGRWarpGPU *gpu = [SGRWarpGPU new];
        gpu.device = device;
        if (library) {
            gpu.tint = pipeline(device, library, @"tint", MTLPixelFormatRGBA16Float, &error);
            gpu.kawase = pipeline(device, library, @"kawase", MTLPixelFormatRGBA16Float, &error);
            gpu.blend = pipeline(device, library, @"blend", MTLPixelFormatRGBA16Float, &error);
            gpu.warp = pipeline(device, library, @"warp", MTLPixelFormatBGRA8Unorm, &error);
        }
        BOOL ok = gpu.tint && gpu.kawase && gpu.blend && gpu.warp;
        if (ok) {
            gpu.queue = [device newCommandQueue];
            gpu.scratchA = blurTexture(device);
            gpu.scratchB = blurTexture(device);
        }
        CFTimeInterval took = CACurrentMediaTime() - began;
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_compiling = NO;
            if (!ok) {
                sg_failed = YES;
                SGLog(@"redesign warp: shaders failed, nothing drawn: %@", error);
                return;
            }
            sg_gpu = gpu;
            SGLog(@"redesign warp: shaders ready in %.0f ms on %@", took * 1000, device.name);
            gpuReady();
        });
    });
}

#pragma mark - pictures

// The image in kBlurSide square RGBA bytes, top row first, the way a texture takes it.
static NSData *shrunk(UIImage *image) {
    CGImageRef picture = image.CGImage;
    if (!picture) return nil;
    NSMutableData *pixels = [NSMutableData dataWithLength:kBlurSide * kBlurSide * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, kBlurSide, kBlurSide, 8, kBlurSide * 4, space,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, kBlurSide, kBlurSide), picture);
    CGContextRelease(context);
    return pixels;
}

static dispatch_queue_t shrinkQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("spotifyglass.redesign.warp", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static id<MTLTexture> sourceTexture(id<MTLDevice> device, NSData *pixels) {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:kBlurSide height:kBlurSide mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    [texture replaceRegion:MTLRegionMake2D(0, 0, kBlurSide, kBlurSide) mipmapLevel:0 withBytes:pixels.bytes bytesPerRow:kBlurSide * 4];
    return texture;
}

UIImage *SGRWarpSampleArtwork(void) {
    static UIImage *sample;
    if (sample) return sample;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    CGFloat side = 256;
    sample = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGFloat ground[] = {0.13, 0.09, 0.42, 1, 0.72, 0.16, 0.50, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, ground, NULL, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(side, side), 0);
        CGGradientRelease(gradient);
        CGFloat spots[][5] = {{0.98, 0.56, 0.22, 0.70, 0.30}, {0.10, 0.66, 0.72, 0.25, 0.78}, {0.98, 0.84, 0.40, 0.85, 0.85}};
        for (int i = 0; i < 3; i++) {
            CGFloat stops[] = {spots[i][0], spots[i][1], spots[i][2], 1, spots[i][0], spots[i][1], spots[i][2], 0};
            CGGradientRef spot = CGGradientCreateWithColorComponents(space, stops, NULL, 2);
            CGPoint at = CGPointMake(side * spots[i][3], side * spots[i][4]);
            CGContextDrawRadialGradient(c, spot, at, 0, at, side * 0.42, 0);
            CGGradientRelease(spot);
        }
        CGColorSpaceRelease(space);
    }];
    return sample;
}

#pragma mark - passes

static void encodePass(id<MTLCommandBuffer> buffer, MTLRenderPassDescriptor *pass, id<MTLTexture> target, id<MTLRenderPipelineState> state,
                       id<MTLTexture> first, id<MTLTexture> second, const void *bytes, NSUInteger length) {
    pass.colorAttachments[0].texture = target;
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:state];
    [encoder setFragmentTexture:first atIndex:0];
    if (second) [encoder setFragmentTexture:second atIndex:1];
    [encoder setFragmentBytes:bytes length:length atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    pass.colorAttachments[0].texture = nil;
}

static MTLRenderPassDescriptor *newPass(void) {
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    return pass;
}

static BOOL inBackground(void) {
    return UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
}

static NSDictionary *noActions(void) {
    static NSDictionary *none;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNull *off = NSNull.null;
        none = @{@"bounds": off, @"position": off, @"frame": off, @"contents": off, @"hidden": off, @"opacity": off};
    });
    return none;
}

// The display link's target, so the link does not keep the layer.
@interface SGRWarpTicker : NSObject
@property (nonatomic, weak) SGRWarpLayer *layer;
@end

@interface SGRWarpLayer ()
- (void)tick:(CADisplayLink *)link;
- (void)catchUp;
@end

@implementation SGRWarpTicker
- (void)tick:(CADisplayLink *)link {
    [self.layer tick:link];
}
@end

static void gpuReady(void) {
    for (SGRWarpLayer *layer in sg_waiting.allObjects) [layer catchUp];
    [sg_waiting removeAllObjects];
}

// What one stretch of drawing cost, logged for the first few stretches.
typedef struct {
    NSUInteger frames, gpuFrames;
    double cpu, gpu;
    CFTimeInterval first, last;
} SGRWarpCost;

static const NSUInteger kCostFrames = 120;
static NSUInteger sg_costLogs;

#pragma mark - the layer

@implementation SGRWarpLayer {
    CADisplayLink *_link;
    MTLRenderPassDescriptor *_pass;
    // The cover as shrunk, and its blur crossfaded from and to; the spare holds a crossfade caught halfway.
    id<MTLTexture> _source, _from, _to, _spare;
    NSInteger _blurredWith;
    // A cover shrunk and waiting for the GPU, and when it was asked for.
    NSData *_pending;
    CFTimeInterval _pendingAt;
    BOOL _pendingAnimated;
    NSUInteger _generation;
    CFTimeInterval _fadeStart;   // 0 when no crossfade runs
    double _time;                // seconds of motion so far, at the look's speed
    CFTimeInterval _lastTick;
    BOOL _dirty, _drawQueued;
    SGRWarpCost _cost;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.device = sharedDevice();
    self.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.framebufferOnly = YES;
    self.opaque = YES;
    self.maximumDrawableCount = 2;
    self.actions = noActions();
    self.contentsGravity = kCAGravityResize;
    _look = SGRWarpDefaultLook;
    _pictureFrame = CGRectNull;
    _pace = SGRWarpPaceHidden;
    _pass = newPass();
    SGRWarpPrepare();
    return self;
}

- (void)dealloc {
    [_link invalidate];
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    CGSize size = CGSizeMake(MAX(1, ceil(bounds.size.width * kPixelsPerPoint)), MAX(1, ceil(bounds.size.height * kPixelsPerPoint)));
    if (CGSizeEqualToSize(size, self.drawableSize)) return;
    self.drawableSize = size;
    [self changed];
}

- (void)setPictureFrame:(CGRect)frame {
    if (CGRectEqualToRect(frame, _pictureFrame)) return;
    _pictureFrame = frame;
    [self changed];
}

- (void)setLook:(SGRWarpLook)look {
    if (!memcmp(&look, &_look, sizeof look)) return;
    _look = look;
    [self catchUp];
    [self changed];
}

- (void)setPace:(SGRWarpPace)pace {
    if (pace == _pace) return;
    _pace = pace;
    [self catchUp];
    [self updateLink];
}

- (BOOL)canDraw {
    return sg_gpu && _pace != SGRWarpPaceHidden && !inBackground();
}

#pragma mark - covers

- (void)setArtwork:(UIImage *)image animated:(BOOL)animated {
    if (!image) return;
    NSUInteger generation = ++_generation;
    CFTimeInterval asked = CACurrentMediaTime();
    __weak SGRWarpLayer *weakSelf = self;
    dispatch_async(shrinkQueue(), ^{
        NSData *pixels = shrunk(image);
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRWarpLayer *layer = weakSelf;
            if (!layer || !pixels || generation != layer->_generation) return;
            layer->_pending = pixels;
            layer->_pendingAt = asked;
            layer->_pendingAnimated = animated;
            [layer catchUp];
        });
    });
}

// Whatever waited for the GPU or for the layer to show: a cover to blur, a blur to redo, a frame.
- (void)catchUp {
    if (!sg_gpu) {
        if (!sg_waiting) sg_waiting = [NSHashTable weakObjectsHashTable];
        [sg_waiting addObject:self];
        return;
    }
    if (![self canDraw]) return;
    NSInteger passes = MAX(1, MIN(40, lround(_look.blur)));
    if (_pending) [self takePending];
    else if (_source && passes != _blurredWith) {
        id<MTLCommandBuffer> buffer = [sg_gpu.queue commandBuffer];
        [self encodeBlurInto:_to buffer:buffer];
        [buffer commit];
        _dirty = YES;
    }
    if (_dirty) [self drawSoon];
}

- (float)fadeAt:(CFTimeInterval)now {
    if (_fadeStart <= 0) return 1;
    double progress = (now - _fadeStart) / kFade;
    return progress >= 1 ? 1 : (float)(0.5 - 0.5 * cos(progress * M_PI));
}

- (void)takePending {
    SGRWarpGPU *gpu = sg_gpu;
    NSData *pixels = _pending;
    _pending = nil;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL fade = _pendingAnimated && _to && now - _pendingAt < kFade;
    id<MTLCommandBuffer> buffer = [gpu.queue commandBuffer];
    if (fade) {
        float shown = [self fadeAt:now];
        if (shown < 1) {
            // Caught halfway through a crossfade: what shows now is what the next one starts from.
            if (!_spare) _spare = blurTexture(gpu.device);
            MTLRenderPassDescriptor *pass = newPass();
            encodePass(buffer, pass, _spare, gpu.blend, _from ?: _to, _to, &shown, sizeof shown);
            id<MTLTexture> old = _from;
            _from = _spare;
            _spare = old;
        } else {
            id<MTLTexture> old = _from;
            _from = _to;
            _to = old;
        }
        _fadeStart = _pendingAt;
    } else {
        _fadeStart = 0;
    }
    if (!_to) _to = blurTexture(gpu.device);
    _source = sourceTexture(gpu.device, pixels);
    [self encodeBlurInto:_to buffer:buffer];
    [buffer commit];
    _dirty = YES;
    [self updateLink];
}

// kawarp's once-per-cover work: the dark parts tinted, then the Kawase passes, the last one into `target`.
- (void)encodeBlurInto:(id<MTLTexture>)target buffer:(id<MTLCommandBuffer>)buffer {
    SGRWarpGPU *gpu = sg_gpu;
    MTLRenderPassDescriptor *pass = newPass();
    SGRWarpTint tint = {kTint[0], kTint[1], kTint[2], kTintAmount};
    encodePass(buffer, pass, gpu.scratchA, gpu.tint, _source, nil, &tint, sizeof tint);
    NSInteger passes = MAX(1, MIN(40, lround(_look.blur)));
    id<MTLTexture> read = gpu.scratchA;
    for (NSInteger i = 0; i < passes; i++) {
        float offset = i + 0.5f;
        id<MTLTexture> into = i == passes - 1 ? target : (read == gpu.scratchA ? gpu.scratchB : gpu.scratchA);
        encodePass(buffer, pass, into, gpu.kawase, read, nil, &offset, sizeof offset);
        read = into;
    }
    _blurredWith = passes;
}

#pragma mark - drawing

- (void)changed {
    _dirty = YES;
    [self drawSoon];
}

// Changes made together draw once, and not at all while the link draws anyway.
- (void)drawSoon {
    if (_drawQueued || (_link && !_link.paused)) return;
    _drawQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_drawQueued = NO;
        if (self->_dirty) [self drawAt:CACurrentMediaTime()];
    });
}

- (BOOL)wantsLink {
    if (![self canDraw] || !_to || _pace < SGRWarpPaceStill) return NO;
    return _pace == SGRWarpPaceMoving || [self fadeAt:CACurrentMediaTime()] < 1;
}

- (void)updateLink {
    BOOL wants = [self wantsLink];
    if (wants && !_link) {
        SGRWarpTicker *ticker = [SGRWarpTicker new];
        ticker.layer = self;
        _link = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick:)];
        // Slow drift needs no more than 30 a second, and a range reaching 120 never holds the
        // player's 120 Hz transitions down.
        _link.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 30);
        _link.paused = YES;
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    if (!_link || _link.paused == !wants) return;
    _link.paused = !wants;
    _lastTick = 0;
    if (wants) _cost = (SGRWarpCost){0};
    static NSUInteger logged;
    if (logged++ < 12) SGLog(@"redesign warp: link %@ (pace %ld)", wants ? @"runs" : @"stops", (long)_pace);
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.targetTimestamp;
    if (_pace == SGRWarpPaceMoving) {
        if (_lastTick > 0) _time += MIN(now - _lastTick, 0.1) * _look.speed;
        _lastTick = now;
    }
    [self drawAt:now];
    if (![self wantsLink]) [self updateLink];
}

- (void)drawAt:(CFTimeInterval)now {
    SGRWarpGPU *gpu = sg_gpu;
    CGRect bounds = self.bounds;
    if (![self canDraw] || !_to || bounds.size.width < 1 || bounds.size.height < 1) return;
    CFTimeInterval began = CACurrentMediaTime();
    CGSize size = self.drawableSize;
    @autoreleasepool {
        id<CAMetalDrawable> drawable = [self nextDrawable];
        if (!drawable) return;
        CGRect picture = CGRectIsNull(_pictureFrame) || _pictureFrame.size.width < 1 || _pictureFrame.size.height < 1 ? bounds : _pictureFrame;
        float blend = [self fadeAt:now];
        if (blend >= 1) _fadeStart = 0;
        SGRWarpFrame frame = {
            .scaleX = (float)(bounds.size.width / size.width / picture.size.width),
            .scaleY = (float)(bounds.size.height / size.height / picture.size.height),
            .offsetX = (float)((bounds.origin.x - picture.origin.x) / picture.size.width),
            .offsetY = (float)((bounds.origin.y - picture.origin.y) / picture.size.height),
            .time = (float)_time,
            .blend = blend,
            .warp = MAX(0, MIN(1, _look.warp)),
            .saturation = MAX(0, _look.saturation),
            .brightness = MAX(0, _look.brightness),
            .ceiling = SGRIncreaseContrast() ? kCeilingContrast : kCeiling,
            .shadeFrom = kShadeFrom,
            .shade = kShadeBottom,
            .dither = kDither,
        };
        id<MTLCommandBuffer> buffer = [gpu.queue commandBuffer];
        encodePass(buffer, _pass, drawable.texture, gpu.warp, _from ?: _to, _to, &frame, sizeof frame);
        [buffer presentDrawable:drawable];
        if (_link && !_link.paused && sg_costLogs < 3) [self measure:buffer];
        [buffer commit];
    }
    _dirty = NO;
    if (_link && !_link.paused && sg_costLogs < 3) {
        _cost.cpu += CACurrentMediaTime() - began;
        if (!_cost.frames++) _cost.first = now;
        _cost.last = now;
    }
}

// GPU time comes back on Metal's thread; only the first few stretches are timed at all.
- (void)measure:(id<MTLCommandBuffer>)buffer {
    __weak SGRWarpLayer *weakSelf = self;
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> done) {
        double gpu = done.GPUEndTime - done.GPUStartTime;
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRWarpLayer *layer = weakSelf;
            if (layer) [layer counted:gpu];
        });
    }];
}

- (void)counted:(double)gpu {
    if (gpu > 0) {
        _cost.gpu += gpu;
        _cost.gpuFrames++;
    }
    if (_cost.frames < kCostFrames || sg_costLogs >= 3) return;
    sg_costLogs++;
    CGSize size = self.drawableSize;
    double fps = _cost.last > _cost.first ? (_cost.frames - 1) / (_cost.last - _cost.first) : 0;
    SGLog(@"redesign warp: %lu frames of %.0fx%.0f px at %.0f a second, cpu %.3f ms, gpu %.3f ms a frame",
          (unsigned long)_cost.frames, size.width, size.height, fps, _cost.cpu / _cost.frames * 1000,
          _cost.gpuFrames ? _cost.gpu / _cost.gpuFrames * 1000 : -1.0);
    _cost = (SGRWarpCost){0};
}

@end

#pragma mark - the preview's view

@implementation SGRWarpView

+ (Class)layerClass {
    return SGRWarpLayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      UIApplicationDidEnterBackgroundNotification, UIApplicationWillEnterForegroundNotification,
                                      UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(updatePace) name:name object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (SGRWarpLayer *)warpLayer {
    return (SGRWarpLayer *)self.layer;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updatePace];
}

- (void)updatePace {
    UIApplicationState state = UIApplication.sharedApplication.applicationState;
    SGRWarpPace pace = SGRWarpPaceMoving;
    if (!self.window || state == UIApplicationStateBackground) pace = SGRWarpPaceHidden;
    else if (state != UIApplicationStateActive) pace = SGRWarpPaceFrozen;
    else if (SGRReduceMotion()) pace = SGRWarpPaceStill;
    self.warpLayer.pace = pace;
}

@end
