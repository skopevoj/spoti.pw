// Pure C inactivity policy. The adapter supplies a monotonic clock; no timers or UIKit here.
#pragma once
#include <stdbool.h>
#include <stdint.h>

enum {
    SGRImmersiveTouch = 1u << 0,
    SGRImmersiveBrowse = 1u << 1,
    SGRImmersiveMenu = 1u << 2,
    SGRImmersiveAccessibility = 1u << 3,
    SGRImmersiveControl = 1u << 4,
    SGRImmersiveSing = 1u << 5,
};
typedef struct {
    bool presented, active, immersive;
    uint32_t holds;
    double deadline;
} SGRImmersiveState;

void SGRImmersiveSetVisible(SGRImmersiveState *state, bool presented, bool active, double now);
// Returns true only when this interaction must be consumed to reveal chrome.
bool SGRImmersiveInteract(SGRImmersiveState *state, double now);
void SGRImmersiveHold(SGRImmersiveState *state, uint32_t reason, bool held, double now);
bool SGRImmersiveAdvance(SGRImmersiveState *state, double now);
