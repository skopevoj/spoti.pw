// Compiled as C by the portable harness and Objective-C by Theos.
#include "SGRImmersiveState.h"
#include <math.h>

void SGRImmersiveSetVisible(SGRImmersiveState *s, bool presented, bool active, double now) {
    s->presented = presented;
    s->active = active;
    s->immersive = false;
    s->holds = 0;
    s->deadline = now + 2.0;
}

bool SGRImmersiveInteract(SGRImmersiveState *s, double now) {
    bool consume = s->immersive;
    s->immersive = false;
    s->deadline = now + 2.0;
    return consume;
}

void SGRImmersiveHold(SGRImmersiveState *s, uint32_t reason, bool held, double now) {
    if (held) s->holds |= reason;
    else s->holds &= ~reason;
    SGRImmersiveInteract(s, now);
}

bool SGRImmersiveAdvance(SGRImmersiveState *s, double now) {
    if (s->presented && s->active && !s->holds && isfinite(now) && now >= s->deadline)
        s->immersive = true;
    return s->immersive;
}
