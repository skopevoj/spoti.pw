#import "SGAudioSourceQueue.h"
#import <mach/mach.h>
#import <mach-o/dyld.h>
#include <string.h>
#include <stdbool.h>

static uintptr_t sg_sourceImage;
static bool sg_sourceLayout;
static bool readMetadata(uintptr_t address, void *value, size_t size) {
    vm_size_t count = 0;
    return address && address <= UINTPTR_MAX - size &&
        vm_read_overwrite(mach_task_self(), address, size, (vm_address_t)value, &count) == KERN_SUCCESS && count == size;
}
static bool readWord(uintptr_t address, uint64_t *value) {
    *value = 0;
    return readMetadata(address, value, sizeof *value);
}
void SGAudioSourceQueueInitialize(void) {
    // Spotify 9.1.78 arm64. A version string alone cannot establish the private queue ABI.
    static const unsigned char uuid[16] = {0xc7,0x12,0x37,0x0b,0x44,0xcd,0x35,0xc8,0xa0,0x58,0x4f,0xbe,0xd1,0xad,0x07,0x58};
    const struct mach_header_64 *header = (const void *)_dyld_get_image_header(0);
    if (!header || header->magic != MH_MAGIC_64) return;
    const struct load_command *command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const void *)((const char *)command + command->cmdsize)) {
        if (command->cmd == LC_UUID && command->cmdsize == sizeof(struct uuid_command) &&
            !memcmp(((const struct uuid_command *)command)->uuid, uuid, sizeof uuid)) {
            sg_sourceImage = (uintptr_t)header;
            sg_sourceLayout = true;
            return;
        }
    }
}
bool SGAudioSourceQueueSupported(AURenderCallbackStruct callback) {
    uint64_t instruction;
    return sg_sourceLayout && (uintptr_t)callback.inputProc == sg_sourceImage + 0x24dd98 &&
        readWord((uintptr_t)callback.inputProc, &instruction) && instruction == UINT64_C(0xa9bc5ff8350005a3);
}
SGAudioSourcePrefix SGAudioSourceQueuePrefix(AURenderCallbackStruct callback, UInt32 maximumFrames, bool continuous) {
    const SGAudioSourcePrefix empty = {0, UINT32_MAX};
    if (!maximumFrames || !SGAudioSourceQueueSupported(callback)) return empty;
    uintptr_t context = (uintptr_t)callback.inputProcRefCon;
    uint64_t instruction, sink, table, function, delegate;
    uint64_t contextWords[5], sinkWords[5];
    // Adjacent metadata fields share one checked copy. Do not repeat kernel reads for
    // each word of the same source context, sink or queue node on every audio callback.
    if (!context || context > UINTPTR_MAX - 0x90 ||
        !readWord((uintptr_t)callback.inputProc, &instruction) || instruction != UINT64_C(0xa9bc5ff8350005a3) ||
        !readMetadata(context + 0x68, contextWords, sizeof contextWords)) return empty;
    sink = contextWords[2];
    if ((uint32_t)(contextWords[0] >> 32) != 2 || contextWords[4] <= contextWords[3] ||
        !readMetadata(sink, sinkWords, sizeof sinkWords)) return empty;
    table = sinkWords[0]; delegate = sinkWords[4];
    if (table > UINTPTR_MAX - 0x18 ||
        !readWord(table + 0x10, &function) || function != sg_sourceImage + 0x180f3c ||
        !readWord(function, &instruction) || instruction != UINT64_C(0xa9025ff8d10183ff) ||
        delegate < 8 || delegate > UINTPTR_MAX - 0xb8 ||
        !readWord(delegate, &table) || table > UINTPTR_MAX - 0x18 ||
        !readWord(table + 0x10, &function) || function != sg_sourceImage + 0x10908b4 ||
        !readWord(function, &instruction) || instruction != UINT64_C(0x17c2d2c2d1002000) ||
        !readWord(sg_sourceImage + 0x1453c0, &instruction) || instruction != UINT64_C(0xa9016ffcd101c3ff)) return empty;
    uintptr_t owner = delegate - 8;
    uint64_t head, tail, pending;
    // The reader at 0x1453c0 processes pending commands before consuming its queue.
    if (!readWord(owner + 0xb8, &pending) || pending ||
        !readWord(owner + 0x18, &head) || !readWord(owner + 0x20, &tail)) return empty;
    uint64_t cursor = head, samples = 0;
    uint64_t boundary = UINT64_MAX, flags = 0;
    uintptr_t visited[128];
    unsigned count = 0;
    while (cursor != tail) {
        if (count == 128 || !cursor || cursor > UINTPTR_MAX - 0x28) return empty;
        for (unsigned i = 0; i < count; i++) if (visited[i] == cursor) return empty;
        visited[count++] = cursor;
        uint64_t node[5], remaining;
        if (!readMetadata(cursor, node, sizeof node)) return empty;
        uint64_t block = node[0], next = node[4];
        if (next != tail) for (unsigned i = 0; i < count; i++) if (visited[i] == next) return empty;
        if (!block) {
            // 0x1454b4–0x1454fc pops a null block and continues unless byte a1 is 1
            // and byte a2 is 0 (the stop/wait path at 0x1456ac). Never read PCM directly
            // or invoke that private reader: the original AudioUnit remains the consumer.
            if (!continuous || boundary != UINT64_MAX) break;
            if (!readWord(sg_sourceImage + 0x1454b4, &instruction) || instruction != UINT64_C(0x95ece96591006296) ||
                !readWord(owner + 0xa0, &flags)) return empty;
            if (((flags >> 8) & 255) == 1 && !(flags & (UINT64_C(1) << 16))) break;
            boundary = samples / 2;
            cursor = next;
            continue;
        }
        if (block > UINTPTR_MAX - 0x28 || !readWord(block + 0x20, &remaining) ||
            remaining > 882000 || (remaining & 1)) return empty;
        // An exact-sized pull leaves the exhausted block at the head. The verified
        // reader (0x145550–0x1455c8) pops it on the next pull and continues with the
        // following block. Only a null block is an event fence; zero samples are not.
        samples += remaining;
        if (samples / 2 >= maximumFrames) break;
        cursor = next;
    }
    uint64_t headAfter, tailAfter;
    if (!readWord(owner + 0xb8, &pending) || pending ||
        !readWord(owner + 0x18, &headAfter) || !readWord(owner + 0x20, &tailAfter) ||
        head != headAfter || tail != tailAfter) return empty;
    if (boundary != UINT64_MAX) {
        uint64_t after;
        if (!readWord(owner + 0xa0, &after) || after != flags) return empty;
    }
    // Unvisited nodes cannot affect this prefix. Pending commands and an unstable queue
    // still invalidate the snapshot even when enough frames were found in its first node.
    UInt32 frames = (UInt32)MIN(samples / 2, maximumFrames);
    return (SGAudioSourcePrefix){frames, boundary < frames ? (UInt32)boundary : UINT32_MAX};
}
UInt32 SGAudioSourceQueueFrames(AURenderCallbackStruct callback, UInt32 maximumFrames) {
    return SGAudioSourceQueuePrefix(callback, maximumFrames, false).frames;
}
