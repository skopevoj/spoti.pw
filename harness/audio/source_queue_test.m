// Exercise the actual guarded reader with owned memory; never execute a private function.
#import <mach/mach.h>
static unsigned reads;
static kern_return_t countedRead(vm_map_read_t task, vm_address_t at, vm_size_t size,
                                vm_address_t output, vm_size_t *count) {
    reads++;
    return vm_read_overwrite(task, at, size, output, count);
}
#define vm_read_overwrite countedRead
#import "Shared/Audio/SGAudioSourceQueue.m"
#undef vm_read_overwrite
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
static void put(void *at, size_t offset, uint64_t value) { memcpy((char *)at + offset, &value, sizeof value); }
int main(void) {
    sg_sourceImage = (uintptr_t)calloc(1, 0x1100000);
    assert(sg_sourceImage);
    put((void *)sg_sourceImage, 0x24dd98, UINT64_C(0xa9bc5ff8350005a3));
    put((void *)sg_sourceImage, 0x180f3c, UINT64_C(0xa9025ff8d10183ff));
    put((void *)sg_sourceImage, 0x10908b4, UINT64_C(0x17c2d2c2d1002000));
    put((void *)sg_sourceImage, 0x1453c0, UINT64_C(0xa9016ffcd101c3ff));
    put((void *)sg_sourceImage, 0x1454b4, UINT64_C(0x95ece96591006296));
    uint64_t context[32] = {0}, sink[16] = {0}, owner[32] = {0};
    uint64_t sinkTable[3] = {0}, delegateTable[3] = {0};
    uint64_t node[8] = {0}, block[8] = {0}, event[8] = {0}, later[8] = {0}, nextBlock[8] = {0};
    AURenderCallbackStruct callback = {(AURenderCallback)(sg_sourceImage + 0x24dd98), context};
    assert(!SGAudioSourceQueueSupported(callback)); // unknown executable UUID
    sg_sourceLayout = true;
    assert(SGAudioSourceQueueSupported(callback));
    sinkTable[2] = sg_sourceImage + 0x180f3c; delegateTable[2] = sg_sourceImage + 0x10908b4;
    sink[0] = (uintptr_t)sinkTable; sink[4] = (uintptr_t)owner + 8; owner[1] = (uintptr_t)delegateTable;
    put(context, 0x78, (uintptr_t)sink); put(context, 0x6c, 2);
    put(context, 0x80, 0x10000); put(context, 0x88, 0x18000);
    owner[3] = (uintptr_t)node; node[0] = (uintptr_t)block; block[4] = 88200;
    assert(SGAudioSourceQueueFrames(callback, UINT32_MAX) == 44100);
    node[4] = (uintptr_t)event; event[4] = (uintptr_t)later; later[0] = (uintptr_t)block;
    assert(SGAudioSourceQueueFrames(callback, UINT32_MAX) == 44100); // no PCM beyond the event
    SGAudioSourcePrefix prefix = SGAudioSourceQueuePrefix(callback, UINT32_MAX, true);
    assert(prefix.frames == 88200 && prefix.boundary == 44100);
    put(owner, 0xa0, UINT64_C(1) << 8); // the native end marker stops the source
    prefix = SGAudioSourceQueuePrefix(callback, UINT32_MAX, true);
    assert(prefix.frames == 44100 && prefix.boundary == UINT32_MAX);
    put(owner, 0xa0, (UINT64_C(1) << 8) | (UINT64_C(1) << 16)); // the reader can continue
    prefix = SGAudioSourceQueuePrefix(callback, UINT32_MAX, true);
    assert(prefix.frames == 88200 && prefix.boundary == 44100);
    put(owner, 0xa0, 0);
    prefix = SGAudioSourceQueuePrefix(callback, 44000, true);
    assert(prefix.frames == 44000 && prefix.boundary == UINT32_MAX);
    prefix = SGAudioSourceQueuePrefix(callback, 44101, true);
    assert(prefix.frames == 44101 && prefix.boundary == 44100);
    uint64_t secondEvent[8] = {0}, third[8] = {0};
    later[4] = (uintptr_t)secondEvent; secondEvent[4] = (uintptr_t)third; third[0] = (uintptr_t)block;
    prefix = SGAudioSourceQueuePrefix(callback, UINT32_MAX, true);
    assert(prefix.frames == 88200 && prefix.boundary == 44100); // only one following song
    later[4] = 0;
    put((void *)sg_sourceImage, 0x1454b4, 0);
    assert(!SGAudioSourceQueuePrefix(callback, UINT32_MAX, true).frames);
    assert(SGAudioSourceQueueFrames(callback, UINT32_MAX) == 44100); // strict reads remain fenced
    put((void *)sg_sourceImage, 0x1454b4, UINT64_C(0x95ece96591006296));
    owner[3] = (uintptr_t)event; assert(!SGAudioSourceQueueFrames(callback, UINT32_MAX));
    owner[3] = (uintptr_t)node; owner[0xb8 / 8] = 1;
    assert(!SGAudioSourceQueueFrames(callback, UINT32_MAX)); // queued seek/flush command
    owner[0xb8 / 8] = 0; block[4] = 88201;
    assert(!SGAudioSourceQueueFrames(callback, UINT32_MAX)); // invalid stereo count
    block[4] = 0; assert(!SGAudioSourceQueueFrames(callback, UINT32_MAX));
    // The native reader leaves an exactly consumed block at the head until its next
    // pull. It pops that non-null, zero-length block and reads the following PCM.
    // Treating it as an event starves Sing until its entire original reserve drains.
    node[4] = (uintptr_t)later; later[0] = (uintptr_t)nextBlock; nextBlock[4] = 176400;
    assert(SGAudioSourceQueueFrames(callback, 7340) == 7340);
    assert(SGAudioSourceQueueFrames(callback, UINT32_MAX) == 88200);
    later[4] = (uintptr_t)event; event[4] = 0;
    assert(SGAudioSourceQueueFrames(callback, UINT32_MAX) == 88200);
    nextBlock[4] = 0;
    assert(!SGAudioSourceQueueFrames(callback, UINT32_MAX)); // empty blocks cannot cross an event
    later[4] = (uintptr_t)node;
    assert(!SGAudioSourceQueueFrames(callback, UINT32_MAX)); // exhausted-block cycle is still invalid
    block[4] = 88200; node[4] = (uintptr_t)node;
    assert(!SGAudioSourceQueueFrames(callback, UINT32_MAX)); // malformed cycle
    node[4] = 0; sinkTable[2]++;
    assert(!SGAudioSourceQueueFrames(callback, UINT32_MAX)); // layout changed
    sinkTable[2]--; callback.inputProcRefCon = (void *)(UINTPTR_MAX - 4);
    assert(!SGAudioSourceQueueFrames(callback, UINT32_MAX));
    callback.inputProcRefCon = (void *)1; assert(!SGAudioSourceQueueFrames(callback, UINT32_MAX));
    callback.inputProc = NULL; assert(!SGAudioSourceQueueSupported(callback));
    // A long valid queue needs only the prefix covering the next pull and native reserve.
    uint64_t nodes[80][8] = {0}, blocks[80][8] = {0};
    callback.inputProc = (AURenderCallback)(sg_sourceImage + 0x24dd98);
    callback.inputProcRefCon = context;
    owner[3] = (uintptr_t)nodes;
    for (unsigned i = 0; i < 80; i++) {
        nodes[i][0] = (uintptr_t)blocks[i]; blocks[i][4] = 2048;
        nodes[i][4] = i == 79 ? 0 : (uintptr_t)nodes[i+1];
    }
    reads = 0;
    assert(SGAudioSourceQueueFrames(callback, UINT32_MAX) == 80 * 1024);
    unsigned fullReads = reads;
    reads = 0;
    assert(SGAudioSourceQueueFrames(callback, 7340) == 7340);
    unsigned prefixReads = reads;
    assert(prefixReads < fullReads / 4);
    reads = 0;
    assert(!SGAudioSourceQueueFrames(callback, 0) && !reads);
    nodes[3][0] = 0;
    assert(SGAudioSourceQueueFrames(callback, 7340) == 3 * 1024);
    nodes[0][4] = (uintptr_t)nodes;
    assert(!SGAudioSourceQueueFrames(callback, 1024)); // cycle at the requested boundary
    printf("source queue metadata reads: full=%u bounded=%u for a 7340-frame prefix\n", fullReads, prefixReads);
    free((void *)sg_sourceImage);
    puts("source queue: build and callback guards, event fences, pending commands, malformed and unreadable memory passed");
}
