// The control's full travel represents 20–100% vocals. Shared by UI, controller and mixer so
// touch, accessibility and programmatic changes all use the same range.
#pragma once
#include <math.h>

#define SGSingMinimumVocalLevel 0.2f
static inline float SGSingClampLevel(float value) {
    return isfinite(value) ? fmaxf(SGSingMinimumVocalLevel, fminf(1, value)) : 1;
}
static inline float SGSingLevelFromPosition(float position) {
    return SGSingMinimumVocalLevel + (1 - SGSingMinimumVocalLevel) * fmaxf(0, fminf(1, position));
}
static inline float SGSingPositionFromLevel(float level) {
    return (SGSingClampLevel(level) - SGSingMinimumVocalLevel) / (1 - SGSingMinimumVocalLevel);
}
