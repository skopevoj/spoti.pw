// The control's full travel represents 20 % vocals at the bottom, the original mix at four fifths of the way
// up, and vocals alone at the top, the instrumental fading out over the last fifth. As a level, 0.2...1 is
// the vocals' share with the instrumental whole, and 1...2 the instrumental going from whole (1) to silent
// (2) with the vocals whole. Shared by UI, controller and mixer so touch, accessibility and programmatic
// changes all use the same range.
#pragma once
#include <math.h>

#define SGSingMinimumVocalLevel 0.2f
#define SGSingVocalsOnlyLevel 2.0f
#define SGSingOriginalPosition 0.8f   // where on the travel the original mix is
static inline float SGSingClampLevel(float value) {
    return isfinite(value) ? fmaxf(SGSingMinimumVocalLevel, fminf(SGSingVocalsOnlyLevel, value)) : 1;
}
static inline float SGSingLevelFromPosition(float position) {
    float p = fmaxf(0, fminf(1, position));
    if (p <= SGSingOriginalPosition) return SGSingMinimumVocalLevel + (1 - SGSingMinimumVocalLevel) * p / SGSingOriginalPosition;
    return 1 + (SGSingVocalsOnlyLevel - 1) * (p - SGSingOriginalPosition) / (1 - SGSingOriginalPosition);
}
static inline float SGSingPositionFromLevel(float level) {
    float l = SGSingClampLevel(level);
    if (l <= 1) return (l - SGSingMinimumVocalLevel) / (1 - SGSingMinimumVocalLevel) * SGSingOriginalPosition;
    return SGSingOriginalPosition + (l - 1) / (SGSingVocalsOnlyLevel - 1) * (1 - SGSingOriginalPosition);
}
