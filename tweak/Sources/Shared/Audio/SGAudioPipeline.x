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
static _Atomic(AudioUnit) sourceUnit, outputUnit;
static atomic_uint sourceBus, maximumFrames = 1024;
static Float64 sourceTime; // sole render consumer
static UInt32 sourceChannels;
static struct { AudioUnit unit; AURenderCallbackStruct callback; } sourceCallbacks[8]; // protected by gate
static OSStatus (*originalSet)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);
static OSStatus (*originalStart)(AudioUnit);
static OSStatus (*originalDispose)(AudioComponentInstance);
static atomic_bool available;

// Graph changes wait off the render thread. A render callback makes one attempt and never waits.
// This protects the source/bus pair and prevents disposing a source during a pull. Setters can
// invoke a property listener synchronously, hence the per-thread nesting count.
enum { rendering = 1, changing = 2 };
static atomic_uint gate;
static pthread_mutex_t controlLock = PTHREAD_MUTEX_INITIALIZER;
static _Thread_local unsigned controlDepth;
static _Thread_local bool pulling;
static _Thread_local bool inRender;
static void beginChange(void) {
    if (controlDepth++) return;
    pthread_mutex_lock(&controlLock);
    atomic_fetch_or(&gate, changing);
    while (atomic_load(&gate) & rendering) usleep(250);
}
static void endChange(void) {
    if (--controlDepth) return;
    atomic_store(&gate, 0);
    pthread_mutex_unlock(&controlLock);
}
static bool enterRender(void) {
    unsigned expected = 0;
    if (!atomic_compare_exchange_strong(&gate, &expected, rendering)) return false;
    inRender = true;
    return true;
}
static void leaveRender(void) { inRender = false; atomic_fetch_and(&gate, ~rendering); }
static void replaceSourceProcessor(SGAudioSourceProcessor processor, void *context) {
    sourceProcessor = processor; sourceContext = context;
    atomic_store(&attachedSourceContext, processor ? context : NULL);
}
bool SGAudioPipelineSourceProcessorAttached(void *context) {
    return context && context == atomic_load(&attachedSourceContext);
}

bool SGAudioPipelineAvailable(void) { return atomic_load(&available); }
bool SGAudioPipelineTapped(void) { return atomic_load(&sourceUnit) != NULL; }
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
OSStatus SGAudioPipelinePullOriginal(UInt32 frames, AudioBufferList *data, const AudioTimeStamp *outputTime) {
    AudioUnit source = atomic_load(&sourceUnit);
    if (!pulling || !source || !data) return kAudioUnitErr_NoConnection;
    if (!frames) return noErr;
    if (data->mNumberBuffers != sourceChannels || frames > UINT32_MAX / sizeof(float)) return kAudio_ParamError;
    UInt32 chunk = atomic_load_explicit(&maximumFrames, memory_order_relaxed);
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
        time.mSampleTime = sourceTime;
        time.mFlags |= kAudioTimeStampSampleTimeValid;
        AudioUnitRenderActionFlags flags = 0;
        OSStatus status = AudioUnitRender(source, &flags, &time, atomic_load(&sourceBus), count, &part.list);
        sourceTime += count;
        if (status != noErr) return status;
        if (flags & kAudioUnitRenderAction_OutputIsSilence)
            for (UInt32 b = 0; b < data->mNumberBuffers; b++) memset(part.list.mBuffers[b].mData, 0, count * sizeof(float));
        done += count;
    }
    return noErr;
}

static OSStatus feed(void *context, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time,
                     UInt32 bus, UInt32 frames, AudioBufferList *data) {
    bool entered = enterRender();
    if (!entered || (AudioUnit)context != atomic_load(&outputUnit) || !SGAudioPipelineTapped()) {
        if (entered) leaveRender();
        if (data) for (UInt32 b = 0; b < data->mNumberBuffers; b++)
            if (data->mBuffers[b].mData) memset(data->mBuffers[b].mData, 0, data->mBuffers[b].mDataByteSize);
        if (flags) *flags |= kAudioUnitRenderAction_OutputIsSilence;
        return noErr;
    }
    SGAudioPullProcessor processor = atomic_load(&pullProcessor);
    OSStatus status = noErr;
    pulling = true;
    if (!processor || !processor(frames, data, &status)) status = SGAudioPipelinePull(frames, data, time);
    pulling = false;
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
static void refreshSource(AudioUnit unit) {
    AudioUnit source = atomic_load(&sourceUnit);
    if (!source) return;
    UInt32 bus = atomic_load(&sourceBus), size = sizeof(AudioStreamBasicDescription);
    AudioStreamBasicDescription input = {0}, output = {0};
    OSStatus a = AudioUnitGetProperty(source, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, bus, &input, &size);
    size = sizeof output;
    OSStatus b = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &output, &size);
    BOOL supported = a == noErr && b == noErr && input.mFormatID == kAudioFormatLinearPCM &&
        input.mFormatID == output.mFormatID && input.mSampleRate > 0 && input.mSampleRate == output.mSampleRate &&
        input.mFormatFlags == output.mFormatFlags && input.mBitsPerChannel == 32 && output.mBitsPerChannel == 32 &&
        (input.mFormatFlags & kAudioFormatFlagIsFloat) && (input.mFormatFlags & kAudioFormatFlagIsNonInterleaved) &&
        input.mChannelsPerFrame >= 1 && input.mChannelsPerFrame <= 2 && input.mChannelsPerFrame == output.mChannelsPerFrame &&
        input.mBytesPerFrame == sizeof(float) && output.mBytesPerFrame == sizeof(float);
    if (!supported) {
        replaceSourceProcessor(NULL, NULL);
        atomic_store(&sourceUnit, NULL);
        AURenderCallbackStruct none = {0};
        AudioUnitConnection original = {source, bus, 0};
        originalSet(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &none, sizeof none);
        originalSet(unit, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &original, sizeof original);
        return;
    }
    sourceChannels = input.mChannelsPerFrame;
    if (input.mSampleRate != 44100 || input.mChannelsPerFrame != 2) replaceSourceProcessor(NULL, NULL);
    UInt32 limit = 1024;
    size = sizeof limit;
    if (AudioUnitGetProperty(source, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &limit, &size) != noErr || !limit)
        limit = 1024;
    atomic_store(&maximumFrames, limit);
}
static void formatChanged(void *context, AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element) {
    if (inRender) return; // refresh again before the next output start; never wait on our own callback
    beginChange();
    if (unit == atomic_load(&outputUnit) && property == kAudioUnitProperty_StreamFormat && element == 0) {
        replaceSourceProcessor(NULL, NULL); // old generation cannot cross a route/format change
        refreshSource(unit);
        prepare(unit);
    }
    endChange();
}
static OSStatus start(AudioUnit unit) {
    if (inRender) return kAudioUnitErr_CannotDoInCurrentContext;
    beginChange();
    if (remoteIO(unit)) {
        // A new RemoteIO can be driven by Spotify's own callback without MakeConnection.
        if (unit != atomic_load(&outputUnit)) {
            replaceSourceProcessor(NULL, NULL);
            atomic_store(&sourceUnit, NULL);
            sourceTime = 0;
        }
        atomic_store(&outputUnit, unit);
        refreshSource(unit);
        AudioUnitRemoveRenderNotify(unit, rendered, unit);
        AudioUnitRemovePropertyListenerWithUserData(unit, kAudioUnitProperty_StreamFormat, formatChanged, NULL);
        AudioUnitAddPropertyListener(unit, kAudioUnitProperty_StreamFormat, formatChanged, NULL);
        prepare(unit);
        OSStatus status = AudioUnitAddRenderNotify(unit, rendered, unit);
        if (status != noErr) SGLog(@"audio pipeline: cannot attach output processor (%d)", (int)status);
    }
    OSStatus status = originalStart(unit);
    endChange();
    return status;
}

static OSStatus setPropertyWhileStopped(AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element,
                            const void *data, UInt32 size) {
    if (unit == atomic_load(&outputUnit) && property == kAudioUnitProperty_SetRenderCallback &&
        scope == kAudioUnitScope_Input && element == 0) {
        replaceSourceProcessor(NULL, NULL);
        atomic_store(&sourceUnit, NULL);
    }
    if (unit == atomic_load(&sourceUnit) && property == kAudioUnitProperty_MaximumFramesPerSlice && data && size >= sizeof(UInt32)) {
        UInt32 count = *(const UInt32 *)data;
        if (count) atomic_store(&maximumFrames, count);
    }
    if (property != kAudioUnitProperty_MakeConnection || scope != kAudioUnitScope_Input || element != 0 ||
        !data || size < sizeof(AudioUnitConnection) || !remoteIO(unit))
        return originalSet(unit, property, scope, element, data, size);
    replaceSourceProcessor(NULL, NULL);
    const AudioUnitConnection *connection = data;
    if (!connection->sourceAudioUnit) {
        if (unit == atomic_load(&outputUnit)) atomic_store(&sourceUnit, NULL);
        AURenderCallbackStruct none = {0};
        originalSet(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &none, sizeof none);
        return originalSet(unit, property, scope, element, data, size);
    }
    // Unsupported formats keep Spotify's original connection. Output-domain pitch still works.
    AudioStreamBasicDescription format = {0};
    UInt32 formatSize = sizeof format;
    OSStatus read = AudioUnitGetProperty(connection->sourceAudioUnit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Output, connection->sourceOutputNumber, &format, &formatSize);
    if (!originalDispose || read != noErr || format.mFormatID != kAudioFormatLinearPCM || format.mSampleRate <= 0 ||
        !(format.mFormatFlags & kAudioFormatFlagIsFloat) || !(format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ||
        format.mBitsPerChannel != 32 || format.mBytesPerFrame != sizeof(float) || format.mChannelsPerFrame < 1 || format.mChannelsPerFrame > 2) {
        atomic_store(&sourceUnit, NULL);
        AURenderCallbackStruct none = {0};
        originalSet(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &none, sizeof none);
        return originalSet(unit, property, scope, element, data, size);
    }
    sourceTime = 0;
    sourceChannels = format.mChannelsPerFrame;
    UInt32 limit = 1024, limitSize = sizeof limit;
    if (AudioUnitGetProperty(connection->sourceAudioUnit, kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global, 0, &limit, &limitSize) != noErr || !limit) limit = 1024;
    atomic_store(&maximumFrames, limit);
    atomic_store(&sourceBus, connection->sourceOutputNumber);
    atomic_store(&outputUnit, unit);
    atomic_store(&sourceUnit, connection->sourceAudioUnit);
    AURenderCallbackStruct callback = {feed, unit};
    OSStatus status = originalSet(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof callback);
    if (status == noErr) return noErr;
    atomic_store(&sourceUnit, NULL);
    AURenderCallbackStruct none = {0};
    originalSet(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &none, sizeof none);
    return originalSet(unit, property, scope, element, data, size);
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
    if (unit == atomic_load(&outputUnit)) {
        replaceSourceProcessor(NULL, NULL);
        AudioUnitRemoveRenderNotify(unit, rendered, unit);
        AudioUnitRemovePropertyListenerWithUserData(unit, kAudioUnitProperty_StreamFormat, formatChanged, NULL);
        atomic_store(&outputUnit, NULL);
        atomic_store(&sourceUnit, NULL);
    } else if (unit == atomic_load(&sourceUnit)) {
        replaceSourceProcessor(NULL, NULL);
        atomic_store(&sourceUnit, NULL);
    }
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
