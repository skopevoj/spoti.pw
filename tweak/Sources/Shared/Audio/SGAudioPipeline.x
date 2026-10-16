#import "Shared/Audio/SGAudioPipeline.h"
#import "Shared/Audio/SGAudioSourceQueue.h"
#import "Core/SGLog.h"
#import "Core/SGRebind.h"
#import <pthread.h>
#import <stdatomic.h>
#import <unistd.h>

static _Atomic(const SGAudioProcessor *) processors[SGAudioStageCount];
static _Atomic(SGAudioPullProcessor) pullProcessor;
static SGAudioSourceProcessor sourceProcessor; // protected by gate
static void *sourceContext;
static _Atomic(void *) attachedSourceContext;
static _Atomic(AudioUnit) sourceUnit, outputUnit; // outputUnit's route, published for readers outside the gate
static atomic_uint sourceBus, maximumFrames = 1024;
// Every RemoteIO input taken over, with the unit Spotify connected to it. Spotify keeps an output chain
// per sample rate, so two can be alive and running at once: each pulls only its own source.
typedef struct {
    AudioUnit output, source; // no source: Spotify's own connection was kept
    UInt32 bus, channels, limit;
    Float64 time; // that output's render thread only
} Route;
static Route routes[8], *active; // protected by gate; active is outputUnit's
static struct { AudioUnit unit; AURenderCallbackStruct callback; } sourceCallbacks[8]; // protected by gate
static OSStatus (*originalSet)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);
static OSStatus (*originalStart)(AudioUnit);
static OSStatus (*originalDispose)(AudioComponentInstance);
static atomic_bool available;

// Graph changes wait off the render thread. A render callback makes one attempt and never waits.
// This protects the routes and prevents disposing a source during a pull. Setters can invoke a
// property listener synchronously, hence the per-thread nesting count. Outputs render at once.
enum { changing = 1u << 31 };
static atomic_uint gate; // changing, plus the renders inside
static pthread_mutex_t controlLock = PTHREAD_MUTEX_INITIALIZER;
static _Thread_local unsigned controlDepth;
static _Thread_local bool pulling;
static _Thread_local bool inRender;
static void beginChange(void) {
    if (controlDepth++) return;
    pthread_mutex_lock(&controlLock);
    atomic_fetch_or(&gate, changing);
    while (atomic_load(&gate) & ~changing) usleep(250);
}
static void endChange(void) {
    if (--controlDepth) return;
    atomic_fetch_and(&gate, ~changing);
    pthread_mutex_unlock(&controlLock);
}
static bool enterRender(void) {
    unsigned value = atomic_load(&gate);
    do if (value & changing) return false;
    while (!atomic_compare_exchange_weak(&gate, &value, value + 1));
    inRender = true;
    return true;
}
static void leaveRender(void) { inRender = false; atomic_fetch_sub(&gate, 1); }
static void replaceSourceProcessor(SGAudioSourceProcessor processor, void *context) {
    sourceProcessor = processor; sourceContext = context;
    atomic_store(&attachedSourceContext, processor ? context : NULL);
}
bool SGAudioPipelineSourceProcessorAttached(void *context) {
    return context && context == atomic_load(&attachedSourceContext);
}
static Route *routeFor(AudioUnit output) {
    if (output) for (unsigned i = 0; i < 8; i++) if (routes[i].output == output) return &routes[i];
    return NULL;
}
static void publish(void) {
    atomic_store(&sourceBus, active ? active->bus : 0);
    atomic_store(&maximumFrames, active && active->limit ? active->limit : 1024);
    atomic_store(&sourceUnit, active ? active->source : NULL);
}
// The processors follow one output; the others play their own chain untouched.
static void activate(AudioUnit output) {
    replaceSourceProcessor(NULL, NULL);
    atomic_store(&outputUnit, output);
    active = routeFor(output);
    publish();
}
static void forget(Route *route) {
    if (!route) return;
    if (route == active) { replaceSourceProcessor(NULL, NULL); active = NULL; }
    memset(route, 0, sizeof *route);
    publish();
}

bool SGAudioPipelineAvailable(void) { return atomic_load(&available); }
bool SGAudioPipelineTapped(void) { return atomic_load(&sourceUnit) != NULL; }
AudioUnit SGAudioPipelineOutputUnit(void) { return atomic_load(&outputUnit); }
UInt32 SGAudioPipelineMaximumFrames(void) { return atomic_load(&maximumFrames); }
void SGAudioPipelineSetPullProcessor(SGAudioPullProcessor processor) { atomic_store(&pullProcessor, processor); }
bool SGAudioPipelineSetSourceProcessor(SGAudioSourceProcessor processor, void *context) {
    if (inRender) return false;
    beginChange();
    if (processor) {
        AudioUnit source = atomic_load(&sourceUnit);
        AudioStreamBasicDescription format = {0};
        UInt32 size = sizeof format;
        bool supported = source && AudioUnitGetProperty(source, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
            atomic_load(&sourceBus), &format, &size) == noErr && format.mSampleRate == 44100 && format.mChannelsPerFrame == 2;
        if (!supported) { endChange(); return false; }
    }
    replaceSourceProcessor(processor, context);
    endChange();
    return true;
}
bool SGAudioPipelineClearSourceProcessor(void *context) {
    if (inRender) return false;
    beginChange();
    bool matches = sourceContext == context;
    if (matches) replaceSourceProcessor(NULL, NULL);
    endChange();
    return matches;
}
bool SGAudioPipelineSourceFormat(AudioStreamBasicDescription *format) {
    if (inRender || !format) return false;
    beginChange();
    AudioUnit source = atomic_load(&sourceUnit);
    UInt32 size = sizeof *format;
    bool valid = source && AudioUnitGetProperty(source, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
        atomic_load(&sourceBus), format, &size) == noErr;
    endChange();
    return valid;
}

static BOOL remoteIO(AudioUnit unit) {
    AudioComponentDescription desc = {0};
    return unit && AudioComponentGetDescription(AudioComponentInstanceGetComponent(unit), &desc) == noErr &&
        desc.componentType == kAudioUnitType_Output && desc.componentSubType == kAudioUnitSubType_RemoteIO;
}

SGAudioSourcePrefix SGAudioPipelineSourcePrefix(UInt32 maximumFrames, bool continuous) {
    const SGAudioSourcePrefix empty = {0, UINT32_MAX};
    if (!pulling || !sourceProcessor) return empty;
    AudioUnit source = atomic_load(&sourceUnit);
    for (unsigned i = 0; i < 8; i++)
        if (sourceCallbacks[i].unit == source) return SGAudioSourceQueuePrefix(sourceCallbacks[i].callback, maximumFrames, continuous);
    return empty;
}
UInt32 SGAudioPipelineSourceAheadFrames(UInt32 maximumFrames) {
    return SGAudioPipelineSourcePrefix(maximumFrames, false).frames;
}
bool SGAudioPipelineSourceCanReadAhead(void) {
    if (inRender) return false;
    beginChange();
    AudioUnit source = atomic_load(&sourceUnit);
    bool supported = false;
    for (unsigned i = 0; i < 8; i++)
        if (sourceCallbacks[i].unit == source && source) supported = SGAudioSourceQueueSupported(sourceCallbacks[i].callback);
    endChange();
    return supported;
}

OSStatus SGAudioPipelinePull(UInt32 frames, AudioBufferList *data, const AudioTimeStamp *outputTime) {
    if (!pulling) return kAudioUnitErr_NoConnection;
    if (sourceProcessor) return sourceProcessor(sourceContext, frames, data, outputTime);
    return SGAudioPipelinePullOriginal(frames, data, outputTime);
}
static OSStatus pull(Route *route, UInt32 frames, AudioBufferList *data, const AudioTimeStamp *outputTime) {
    AudioUnit source = route ? route->source : NULL;
    if (!source || !data) return kAudioUnitErr_NoConnection;
    if (!frames) return noErr;
    if (data->mNumberBuffers != route->channels || frames > UINT32_MAX / sizeof(float)) return kAudio_ParamError;
    UInt32 chunk = route->limit ? route->limit : 1024;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mNumberChannels != 1 ||
            data->mBuffers[b].mDataByteSize < frames * sizeof(float)) return kAudio_ParamError;
    }
    for (UInt32 done = 0; done < frames;) {
        UInt32 count = MIN(chunk, frames - done);
        struct { AudioBufferList list; AudioBuffer more; } part;
        part.list.mNumberBuffers = data->mNumberBuffers;
        for (UInt32 b = 0; b < data->mNumberBuffers; b++)
            part.list.mBuffers[b] = (AudioBuffer){1, count * sizeof(float), (float *)data->mBuffers[b].mData + done};
        AudioTimeStamp time = outputTime ? *outputTime : (AudioTimeStamp){0};
        time.mSampleTime = route->time;
        time.mFlags |= kAudioTimeStampSampleTimeValid;
        AudioUnitRenderActionFlags flags = 0;
        OSStatus status = AudioUnitRender(source, &flags, &time, route->bus, count, &part.list);
        route->time += count;
        if (status != noErr) return status;
        if (flags & kAudioUnitRenderAction_OutputIsSilence)
            for (UInt32 b = 0; b < data->mNumberBuffers; b++) memset(part.list.mBuffers[b].mData, 0, count * sizeof(float));
        done += count;
    }
    return noErr;
}
OSStatus SGAudioPipelinePullOriginal(UInt32 frames, AudioBufferList *data, const AudioTimeStamp *outputTime) {
    return pulling ? pull(active, frames, data, outputTime) : kAudioUnitErr_NoConnection;
}

static OSStatus feed(void *context, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time,
                     UInt32 bus, UInt32 frames, AudioBufferList *data) {
    bool entered = enterRender();
    Route *route = entered ? routeFor((AudioUnit)context) : NULL;
    if (!route || !route->source) {
        if (entered) leaveRender();
        if (data) for (UInt32 b = 0; b < data->mNumberBuffers; b++)
            if (data->mBuffers[b].mData) memset(data->mBuffers[b].mData, 0, data->mBuffers[b].mDataByteSize);
        if (flags) *flags |= kAudioUnitRenderAction_OutputIsSilence;
        return noErr;
    }
    OSStatus status = noErr;
    if (route != active) status = pull(route, frames, data, time);
    else {
        SGAudioPullProcessor processor = atomic_load(&pullProcessor);
        pulling = true;
        if (!processor || !processor(frames, data, &status)) status = SGAudioPipelinePull(frames, data, time);
        pulling = false;
    }
    leaveRender();
    return status;
}

static OSStatus rendered(void *context, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time,
                         UInt32 bus, UInt32 frames, AudioBufferList *data) {
    if ((AudioUnit)context != atomic_load(&outputUnit) || !flags || !data || !frames || bus != 0 ||
        !(*flags & kAudioUnitRenderAction_PostRender) || (*flags & kAudioUnitRenderAction_PostRenderError) || !enterRender()) return noErr;
    if ((AudioUnit)context == atomic_load(&outputUnit)) for (unsigned i = 0; i < SGAudioStageCount; i++) {
        const SGAudioProcessor *processor = atomic_load_explicit(&processors[i], memory_order_acquire);
        if (processor && processor->output) processor->output(context, flags, time, bus, frames, data);
    }
    leaveRender();
    return noErr;
}

static void prepare(AudioUnit unit) {
    for (unsigned i = 0; i < SGAudioStageCount; i++) {
        const SGAudioProcessor *processor = atomic_load(&processors[i]);
        if (processor && processor->prepare) processor->prepare(unit);
    }
}
// Spotify's own connection back, for formats the pull does not take.
static OSStatus restore(Route *route) {
    AURenderCallbackStruct none = {0};
    AudioUnitConnection original = {route->source, route->bus, 0};
    route->source = NULL;
    if (route == active) { replaceSourceProcessor(NULL, NULL); publish(); }
    originalSet(route->output, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &none, sizeof none);
    return originalSet(route->output, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &original, sizeof original);
}
static void refreshSource(Route *route) {
    if (!route || !route->source) return;
    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioStreamBasicDescription input = {0}, output = {0};
    OSStatus a = AudioUnitGetProperty(route->source, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, route->bus, &input, &size);
    size = sizeof output;
    OSStatus b = AudioUnitGetProperty(route->output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &output, &size);
    BOOL supported = a == noErr && b == noErr && input.mFormatID == kAudioFormatLinearPCM &&
        input.mFormatID == output.mFormatID && input.mSampleRate > 0 && input.mSampleRate == output.mSampleRate &&
        input.mFormatFlags == output.mFormatFlags && input.mBitsPerChannel == 32 && output.mBitsPerChannel == 32 &&
        (input.mFormatFlags & kAudioFormatFlagIsFloat) && (input.mFormatFlags & kAudioFormatFlagIsNonInterleaved) &&
        input.mChannelsPerFrame >= 1 && input.mChannelsPerFrame <= 2 && input.mChannelsPerFrame == output.mChannelsPerFrame &&
        input.mBytesPerFrame == sizeof(float) && output.mBytesPerFrame == sizeof(float);
    if (!supported) {
        restore(route);
        return;
    }
    route->channels = input.mChannelsPerFrame;
    if (route == active && (input.mSampleRate != 44100 || input.mChannelsPerFrame != 2)) replaceSourceProcessor(NULL, NULL);
    UInt32 limit = 1024;
    size = sizeof limit;
    if (AudioUnitGetProperty(route->source, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &limit, &size) != noErr || !limit)
        limit = 1024;
    route->limit = limit;
    if (route == active) publish();
}
static void formatChanged(void *context, AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element) {
    if (inRender) return; // refresh again before the next output start; never wait on our own callback
    beginChange();
    if (property == kAudioUnitProperty_StreamFormat && element == 0) {
        if (unit == atomic_load(&outputUnit)) {
            replaceSourceProcessor(NULL, NULL); // old generation cannot cross a route/format change
            refreshSource(active);
            prepare(unit);
        } else refreshSource(routeFor(unit));
    }
    endChange();
}
static OSStatus start(AudioUnit unit) {
    if (inRender) return kAudioUnitErr_CannotDoInCurrentContext;
    beginChange();
    if (remoteIO(unit)) {
        // A kept chain starts again without a new MakeConnection. A RemoteIO Spotify never connected
        // (driven by its own callback, or voice search's) takes the processors only from another such.
        if (unit != atomic_load(&outputUnit) && (routeFor(unit) || !active)) activate(unit);
        AudioUnitRemoveRenderNotify(unit, rendered, unit);
        AudioUnitRemovePropertyListenerWithUserData(unit, kAudioUnitProperty_StreamFormat, formatChanged, NULL);
        AudioUnitAddPropertyListener(unit, kAudioUnitProperty_StreamFormat, formatChanged, NULL);
        refreshSource(routeFor(unit));
        if (unit == atomic_load(&outputUnit)) prepare(unit);
        OSStatus status = AudioUnitAddRenderNotify(unit, rendered, unit);
        if (status != noErr) SGLog(@"audio pipeline: cannot attach output processor (%d)", (int)status);
    }
    OSStatus status = originalStart(unit);
    endChange();
    return status;
}

static OSStatus setPropertyWhileStopped(AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element,
                            const void *data, UInt32 size) {
    if (property == kAudioUnitProperty_SetRenderCallback && scope == kAudioUnitScope_Input && element == 0) {
        if (unit == atomic_load(&outputUnit)) replaceSourceProcessor(NULL, NULL);
        forget(routeFor(unit)); // Spotify feeds that output itself now
    }
    if (property == kAudioUnitProperty_MaximumFramesPerSlice && data && size >= sizeof(UInt32) && *(const UInt32 *)data) {
        for (unsigned i = 0; i < 8; i++) if (routes[i].source && routes[i].source == unit) routes[i].limit = *(const UInt32 *)data;
        publish();
    }
    if (property != kAudioUnitProperty_MakeConnection || scope != kAudioUnitScope_Input || element != 0 ||
        !data || size < sizeof(AudioUnitConnection) || !remoteIO(unit))
        return originalSet(unit, property, scope, element, data, size);
    replaceSourceProcessor(NULL, NULL);
    const AudioUnitConnection *connection = data;
    forget(routeFor(unit));
    if (!connection->sourceAudioUnit) {
        AURenderCallbackStruct none = {0};
        originalSet(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &none, sizeof none);
        return originalSet(unit, property, scope, element, data, size);
    }
    Route *route = NULL;
    for (unsigned i = 0; !route && i < 8; i++) if (!routes[i].output) route = &routes[i];
    if (!route) return originalSet(unit, property, scope, element, data, size);
    *route = (Route){unit, NULL, connection->sourceOutputNumber, 0, 0, 0};
    activate(unit);
    // Unsupported formats keep Spotify's original connection. Output-domain pitch still works.
    AudioStreamBasicDescription format = {0};
    UInt32 formatSize = sizeof format;
    OSStatus read = AudioUnitGetProperty(connection->sourceAudioUnit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Output, connection->sourceOutputNumber, &format, &formatSize);
    if (!originalDispose || read != noErr || format.mFormatID != kAudioFormatLinearPCM || format.mSampleRate <= 0 ||
        !(format.mFormatFlags & kAudioFormatFlagIsFloat) || !(format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ||
        format.mBitsPerChannel != 32 || format.mBytesPerFrame != sizeof(float) || format.mChannelsPerFrame < 1 || format.mChannelsPerFrame > 2) {
        AURenderCallbackStruct none = {0};
        originalSet(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &none, sizeof none);
        return originalSet(unit, property, scope, element, data, size);
    }
    UInt32 limit = 1024, limitSize = sizeof limit;
    if (AudioUnitGetProperty(connection->sourceAudioUnit, kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global, 0, &limit, &limitSize) != noErr || !limit) limit = 1024;
    route->source = connection->sourceAudioUnit;
    route->channels = format.mChannelsPerFrame;
    route->limit = limit;
    publish();
    AURenderCallbackStruct callback = {feed, unit};
    OSStatus status = originalSet(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof callback);
    return status == noErr ? noErr : restore(route);
}

static OSStatus setProperty(AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element,
                            const void *data, UInt32 size) {
    if (inRender) return kAudioUnitErr_CannotDoInCurrentContext;
    beginChange();
    OSStatus status = setPropertyWhileStopped(unit, property, scope, element, data, size);
    if (!status && property == kAudioUnitProperty_SetRenderCallback && scope == kAudioUnitScope_Input &&
        element == 0 && data && size >= sizeof(AURenderCallbackStruct)) {
        AURenderCallbackStruct callback = *(const AURenderCallbackStruct *)data;
        bool supported = SGAudioSourceQueueSupported(callback);
        if (unit == atomic_load(&sourceUnit)) replaceSourceProcessor(NULL, NULL);
        unsigned slot = 8;
        for (unsigned i = 0; i < 8; i++) if (sourceCallbacks[i].unit == unit) { slot = i; break; }
        if (supported && slot == 8) for (unsigned i = 0; i < 8; i++) if (!sourceCallbacks[i].unit) { slot = i; break; }
        if (slot != 8) {
            sourceCallbacks[slot].callback = callback;
            sourceCallbacks[slot].unit = supported ? unit : NULL;
        }
    }
    endChange();
    return status;
}

static OSStatus dispose(AudioComponentInstance unit) {
    if (inRender) return kAudioUnitErr_CannotDoInCurrentContext;
    beginChange();
    for (unsigned i = 0; i < 8; i++) if (sourceCallbacks[i].unit == unit) memset(&sourceCallbacks[i], 0, sizeof sourceCallbacks[i]);
    if (unit == atomic_load(&sourceUnit)) replaceSourceProcessor(NULL, NULL);
    for (unsigned i = 0; i < 8; i++) if (routes[i].source == unit) routes[i].source = NULL;
    forget(routeFor(unit));
    if (unit == atomic_load(&outputUnit)) {
        replaceSourceProcessor(NULL, NULL);
        AudioUnitRemoveRenderNotify(unit, rendered, unit);
        AudioUnitRemovePropertyListenerWithUserData(unit, kAudioUnitProperty_StreamFormat, formatChanged, NULL);
        atomic_store(&outputUnit, NULL);
    }
    publish();
    OSStatus status = originalDispose(unit);
    endChange();
    return status;
}

static void install(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGAudioSourceQueueInitialize();
        if (!SGRebindImport("AudioOutputUnitStart", start, (void **)&originalStart) || !originalStart) {
            originalStart = NULL;
            SGLog(@"audio pipeline: Spotify output import unavailable");
            return;
        }
        atomic_store(&available, true);
        if (!SGRebindImport("AudioComponentInstanceDispose", dispose, (void **)&originalDispose)) originalDispose = NULL;
        if (!SGRebindImport("AudioUnitSetProperty", setProperty, (void **)&originalSet) || !originalSet) {
            originalSet = NULL;
            SGLog(@"audio pipeline: mixer import unavailable; output processing only");
        }
    });
}
bool SGAudioPipelineRegister(SGAudioStage stage, const SGAudioProcessor *processor) {
    if (stage >= SGAudioStageCount || stage < 0 || !processor) return false;
    atomic_store(&processors[stage], processor);
    install();
    return SGAudioPipelineAvailable();
}
