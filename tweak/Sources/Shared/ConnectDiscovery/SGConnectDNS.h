#ifndef SG_CONNECT_DNS_H
#define SG_CONNECT_DNS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

static uint16_t SGDNSRead16(const uint8_t *bytes) {
    return ((uint16_t)bytes[0] << 8) | bytes[1];
}

// Decode a DNS name, including compression pointers, while advancing only past its wire form.
static bool SGDNSReadName(const uint8_t *packet, size_t length, size_t *offset,
                          char *name, size_t capacity) {
    size_t at = *offset, used = 0, end = 0;
    bool jumped = false;
    for (unsigned hops = 0; hops < 32; hops++) {
        if (at >= length) return false;
        uint8_t label = packet[at++];
        if ((label & 0xc0) == 0xc0) {
            if (at >= length) return false;
            size_t pointer = ((size_t)(label & 0x3f) << 8) | packet[at++];
            if (pointer >= length) return false;
            if (!jumped) end = at;
            jumped = true;
            at = pointer;
            continue;
        }
        if (label & 0xc0) return false;
        if (label == 0) {
            if (!used) { if (capacity < 2) return false; name[used++] = '.'; }
            name[used] = 0;
            *offset = jumped ? end : at;
            return true;
        }
        if (at + label > length || used + label + 2 > capacity) return false;
        for (uint8_t i = 0; i < label; i++) {
            uint8_t c = packet[at++];
            if (!c) return false;
            name[used++] = (char)(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c);
        }
        name[used++] = '.';
    }
    return false;
}

static bool SGDNSIsConnectName(const char *name) {
    static const char service[] = "_spotify-connect._tcp.local.";
    size_t nameLength = strlen(name), serviceLength = sizeof(service) - 1;
    return nameLength >= serviceLength &&
        strcmp(name + nameLength - serviceLength, service) == 0 &&
        (nameLength == serviceLength || name[nameLength - serviceLength - 1] == '.');
}

static bool SGDNSIsConnectQuery(const void *data, size_t length) {
    if (!data || length < 12 || length > 9000) return false;
    const uint8_t *packet = data;
    if (packet[2] & 0xf8) return false;
    uint16_t questions = SGDNSRead16(packet + 4);
    if (!questions || questions > 64) return false;
    size_t at = 12;
    bool relevant = false;
    for (uint16_t i = 0; i < questions; i++) {
        char name[256];
        if (!SGDNSReadName(packet, length, &at, name, sizeof(name)) || at + 4 > length) return false;
        at += 4;
        if (SGDNSIsConnectName(name)) relevant = true;
    }
    return relevant;
}

static bool SGDNSIsConnectResponse(const void *data, size_t length, const void *query, size_t queryLength) {
    if (!data || !query || length < 12 || length > 9000 || queryLength < 12) return false;
    const uint8_t *packet = data;
    if (!(packet[2] & 0x80) || (packet[2] & 0x7a) || (packet[3] & 0x0f) ||
        packet[0] != ((const uint8_t *)query)[0] || packet[1] != ((const uint8_t *)query)[1]) return false;
    uint16_t questions = SGDNSRead16(packet + 4);
    uint32_t records = (uint32_t)SGDNSRead16(packet + 6) + SGDNSRead16(packet + 8) + SGDNSRead16(packet + 10);
    if (questions > 64 || !records || records > 256) return false;
    size_t at = 12;
    for (uint16_t i = 0; i < questions; i++) {
        char name[256];
        if (!SGDNSReadName(packet, length, &at, name, sizeof(name)) || at + 4 > length) return false;
        at += 4;
    }
    bool relevant = false;
    for (uint32_t i = 0; i < records; i++) {
        char name[256];
        if (!SGDNSReadName(packet, length, &at, name, sizeof(name)) || at + 10 > length) return false;
        uint16_t type = SGDNSRead16(packet + at);
        uint16_t dnsClass = SGDNSRead16(packet + at + 2) & 0x7fff;
        size_t dataLength = SGDNSRead16(packet + at + 8);
        at += 10;
        if (dataLength > length - at) return false;
        if (dnsClass == 1 && SGDNSIsConnectName(name)) relevant = true;
        if (dnsClass == 1 && type == 12) { // PTR's owner may be a subtype; its target is the service instance.
            size_t ptrAt = at;
            char target[256];
            if (SGDNSReadName(packet, length, &ptrAt, target, sizeof(target)) &&
                ptrAt <= at + dataLength && SGDNSIsConnectName(target)) relevant = true;
        }
        at += dataLength;
    }
    return relevant;
}

#endif
