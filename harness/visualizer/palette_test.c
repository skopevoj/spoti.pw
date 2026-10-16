// The cover palette's two ways (tweak/Sources/Shared/Visualizer/SGPalette.h) on made-up covers.
// Spots: the colours are where they are on the cover, centre first and then the quarters; a small vivid detail
// on a dark cover does not become a colour; a purple and blue cover gives purples and blues; a grey cover greys.
// Main colours: two big colours come back as those two, a black border is no colour of its own, one colour is
// filled out with lighter and darker shades of it, a grey cover gets greys, and the main colour is first.
// Either way everything is light enough for a bar on black, unless dark colours are kept, when black stays black.
//   cc -std=c11 -I tweak/Sources -x c harness/visualizer/palette_test.c -x c tweak/Sources/Shared/Visualizer/SGPalette.m -lm
#include "Shared/Visualizer/SGPalette.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

enum { W = 32, H = 32 };
static uint8_t pixels[W * H * 4];

static void fill(int x0, int y0, int x1, int y1, int r, int g, int b) {
    for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) {
        uint8_t *p = pixels + (y * W + x) * 4;
        p[0] = (uint8_t)r; p[1] = (uint8_t)g; p[2] = (uint8_t)b; p[3] = 255;
    }
}

static float hueOf(const float *c) {
    float r = c[0], g = c[1], b = c[2];
    float most = fmaxf(r, fmaxf(g, b)), least = fminf(r, fminf(g, b)), d = most - least;
    if (d < 0.04f) return -1;
    float h = most == r ? fmodf((g - b) / d, 6) : most == g ? (b - r) / d + 2 : (r - g) / d + 4;
    h *= 60;
    return h < 0 ? h + 360 : h;
}

static float saturationOf(const float *c) {
    float most = fmaxf(c[0], fmaxf(c[1], c[2])), least = fminf(c[0], fminf(c[1], c[2]));
    return most > 0 ? (most - least) / most : 0;
}

static int byte(float c) { int v = (int)(c * 255 + 40); return v > 255 ? 255 : v; }

static int hasHue(const float *rgb, int n, float hue, float within) {
    for (int i = 0; i < n; i++) if (fabsf(hueOf(&rgb[i * 3]) - hue) <= within || 360 - fabsf(hueOf(&rgb[i * 3]) - hue) <= within) return 1;
    return 0;
}

static float valueOf(const float *c) { return fmaxf(c[0], fmaxf(c[1], c[2])); }

static float away(float a, float b) {
    float d = fabsf(a - b);
    return d > 180 ? 360 - d : d;
}

static void spots(void) {
    float rgb[SGPaletteMaxColors * 3];

    // Four quarters, four colours, a fifth in the middle: each comes back where it is. The first row is the
    // top, so red is top left, green top right, blue bottom right, yellow bottom left.
    fill(0, 0, 16, 16, 200, 30, 30);
    fill(16, 0, 32, 16, 30, 180, 60);
    fill(16, 16, 32, 32, 30, 60, 220);
    fill(0, 16, 16, 32, 220, 200, 30);
    fill(12, 12, 20, 20, 160, 40, 200);
    assert(SGPaletteSample(pixels, W, H, W * 4, 5, 0, rgb) == 5);
    for (int i = 0; i < 15; i++) assert(rgb[i] >= 0 && rgb[i] <= 1);
    assert(away(hueOf(&rgb[3]), 0) < 20);
    assert(away(hueOf(&rgb[6]), 135) < 25);
    assert(away(hueOf(&rgb[9]), 228) < 20);
    assert(away(hueOf(&rgb[12]), 55) < 20);
    for (int i = 0; i < 5; i++) assert(valueOf(&rgb[i * 3]) >= 0.55f);

    // A dark cover with white lettering across the middle and a few small cyan dots: greys and light greys,
    // the dots no colour of their own, and nothing red or orange.
    fill(0, 0, W, H, 12, 12, 14);
    fill(4, 12, 28, 20, 240, 240, 240);
    for (int x = 4; x < 28; x += 4) fill(x, 9, x + 1, 10, 40, 200, 220);
    assert(SGPaletteSample(pixels, W, H, W * 4, 5, 0, rgb) == 5);
    for (int i = 0; i < 5; i++) {
        float h = hueOf(&rgb[i * 3]);
        assert(h < 0 || (h > 150 && h < 260));             // grey, or a touch of the cyan
        assert(saturationOf(&rgb[i * 3]) < 0.35f);
        assert(valueOf(&rgb[i * 3]) >= 0.5f);
    }
    assert(valueOf(rgb) >= valueOf(&rgb[3]));             // the lettering makes the middle the lightest

    // Purple on top, blue below, a small hot yellow spot in a corner: purples and blues.
    fill(0, 0, W, 16, 90, 30, 140);
    fill(0, 16, W, H, 30, 40, 150);
    fill(29, 0, 32, 3, 255, 230, 0);
    assert(SGPaletteSample(pixels, W, H, W * 4, 5, 0, rgb) == 5);
    for (int i = 0; i < 5; i++) {
        float h = hueOf(&rgb[i * 3]);
        assert(h > 215 && h < 300);
        assert(saturationOf(&rgb[i * 3]) > 0.3f);
    }

    // A black and white cover with a faint blue cast, as a print or a JPEG has: greys, not blue.
    fill(0, 0, W, H, 18, 20, 26);
    fill(6, 6, 26, 26, 225, 228, 236);
    assert(SGPaletteSample(pixels, W, H, W * 4, 5, 0, rgb) == 5);
    for (int i = 0; i < 5; i++) assert(saturationOf(&rgb[i * 3]) < 0.12f);

    // A grey cover: greys, no hue anywhere.
    fill(0, 0, W, H, 120, 120, 120);
    assert(SGPaletteSample(pixels, W, H, W * 4, 4, 0, rgb) == 4);
    for (int i = 0; i < 4; i++) {
        assert(hueOf(&rgb[i * 3]) < 0);
        assert(rgb[i * 3] >= 0.5f && rgb[i * 3] <= 1);
    }

    // As many as asked for, up to eight.
    assert(SGPaletteSample(pixels, W, H, W * 4, 12, 0, rgb) == SGPaletteMaxColors);

    // Premultiplied pixels read the same as straight ones; transparent ones are not read.
    memset(pixels, 0, sizeof pixels);
    fill(0, 0, W, H, 200, 30, 30);
    for (int i = 0; i < W * H; i++) { pixels[i * 4] = (uint8_t)(pixels[i * 4] / 2); pixels[i * 4 + 1] /= 2; pixels[i * 4 + 2] /= 2; pixels[i * 4 + 3] = 128; }
    assert(SGPaletteSample(pixels, W, H, W * 4, 2, 0, rgb) == 2);
    assert(away(hueOf(rgb), 0) < 12);
    for (int i = 0; i < W * H; i++) pixels[i * 4 + 3] = 0;
    assert(SGPaletteSample(pixels, W, H, W * 4, 2, 0, rgb) == 0);

    // Bad arguments.
    assert(SGPaletteSample(NULL, W, H, W * 4, 4, 0, rgb) == 0);
    assert(SGPaletteSample(pixels, 0, H, W * 4, 4, 0, rgb) == 0);
    assert(SGPaletteSample(pixels, W, H, W * 4, 0, 0, rgb) == 0);
    assert(SGPaletteSample(pixels, W, H, 4, 4, 0, rgb) == 0);
}

static void mainColours(void) {
    float rgb[SGPaletteMaxColors * 3];

    // Two colours, a black border round them: red takes the most of the picture, blue less.
    memset(pixels, 0, sizeof pixels);
    for (int i = 0; i < W * H; i++) pixels[i * 4 + 3] = 255;
    fill(4, 4, 20, 28, 200, 30, 30);
    fill(20, 4, 28, 28, 30, 60, 220);
    assert(SGPaletteCluster(pixels, W, H, W * 4, 4, 0, rgb) == 4);
    for (int i = 0; i < 12; i++) assert(rgb[i] >= 0 && rgb[i] <= 1);
    assert(away(hueOf(rgb), 0) < 12);                 // the dominant colour first, and red
    assert(hasHue(rgb, 4, 230, 14));                   // blue is in
    for (int i = 0; i < 4; i++) assert(valueOf(&rgb[i * 3]) >= 0.5f);
    // Nothing black came out as a colour.
    for (int i = 0; i < 4; i++) assert(hueOf(&rgb[i * 3]) >= 0);
    // The two taken from the picture are light enough to show on black.
    assert(valueOf(rgb) >= 0.75f);

    // The same cover with the colours the other way round: blue first.
    memset(pixels, 0, sizeof pixels);
    for (int i = 0; i < W * H; i++) pixels[i * 4 + 3] = 255;
    fill(4, 4, 12, 28, 200, 30, 30);
    fill(12, 4, 28, 28, 30, 60, 220);
    assert(SGPaletteCluster(pixels, W, H, W * 4, 3, 0, rgb) == 3);
    assert(away(hueOf(rgb), 230) < 14);
    assert(hasHue(rgb, 3, 0, 12));

    // One colour: shades of it, of its hue, the colours not all the same.
    memset(pixels, 0, sizeof pixels);
    for (int i = 0; i < W * H; i++) pixels[i * 4 + 3] = 255;
    fill(0, 0, W, H, 30, 160, 60);
    assert(SGPaletteCluster(pixels, W, H, W * 4, 4, 0, rgb) == 4);
    assert(away(hueOf(rgb), 135) < 12);
    for (int i = 1; i < 4; i++) {
        assert(away(hueOf(&rgb[i * 3]), hueOf(rgb)) < 15);
        float d = fabsf(rgb[i * 3] - rgb[0]) + fabsf(rgb[i * 3 + 1] - rgb[1]) + fabsf(rgb[i * 3 + 2] - rgb[2]);
        assert(d > 0.08f);
    }

    // A grey cover: greys, no hue anywhere.
    fill(0, 0, W, H, 120, 120, 120);
    assert(SGPaletteCluster(pixels, W, H, W * 4, 4, 0, rgb) == 4);
    for (int i = 0; i < 4; i++) {
        assert(hueOf(&rgb[i * 3]) < 0);
        assert(rgb[i * 3] >= 0.4f && rgb[i * 3] <= 1);
    }

    // A rainbow: four far apart hues.
    for (int x = 0; x < W; x++) {
        float h = x * 360.0f / W, c = 0.85f, xx = c * (1 - fabsf(fmodf(h / 60, 2) - 1));
        float r, g, b;
        switch ((int)(h / 60)) { case 0: r = c; g = xx; b = 0; break; case 1: r = xx; g = c; b = 0; break;
            case 2: r = 0; g = c; b = xx; break; case 3: r = 0; g = xx; b = c; break;
            case 4: r = xx; g = 0; b = c; break; default: r = c; g = 0; b = xx; }
        fill(x, 0, x + 1, H, byte(r), byte(g), byte(b));
    }
    assert(SGPaletteCluster(pixels, W, H, W * 4, 4, 0, rgb) == 4);
    for (int i = 0; i < 4; i++) for (int j = i + 1; j < 4; j++) assert(away(hueOf(&rgb[i * 3]), hueOf(&rgb[j * 3])) >= 40);
    // In ring order: hue grows from the first, round.
    float last = 0;
    for (int i = 1; i < 4; i++) {
        float from = fmodf(hueOf(&rgb[i * 3]) - hueOf(rgb) + 360, 360);
        assert(from > last);
        last = from;
    }

    // Premultiplied pixels read the same as straight ones; transparent ones vote for nothing.
    memset(pixels, 0, sizeof pixels);
    fill(0, 0, W, H, 200, 30, 30);
    for (int i = 0; i < W * H; i++) { pixels[i * 4] = (uint8_t)(pixels[i * 4] / 2); pixels[i * 4 + 1] /= 2; pixels[i * 4 + 2] /= 2; pixels[i * 4 + 3] = 128; }
    assert(SGPaletteCluster(pixels, W, H, W * 4, 2, 0, rgb) == 2);
    assert(away(hueOf(rgb), 0) < 10);
    for (int i = 0; i < W * H; i++) pixels[i * 4 + 3] = 0;
    assert(SGPaletteCluster(pixels, W, H, W * 4, 2, 0, rgb) == 0);

    // Bad arguments.
    assert(SGPaletteCluster(NULL, W, H, W * 4, 4, 0, rgb) == 0);
    assert(SGPaletteCluster(pixels, 0, H, W * 4, 4, 0, rgb) == 0);
    assert(SGPaletteCluster(pixels, W, H, W * 4, 0, 0, rgb) == 0);
    assert(SGPaletteCluster(pixels, W, H, 4, 4, 0, rgb) == 0);
}

// Dark colours kept: a black cover with a red block gives black and dark colours as they are, and Main
// colours takes the black border as a colour of its own.
static void dark(void) {
    float rgb[SGPaletteMaxColors * 3];
    memset(pixels, 0, sizeof pixels);
    fill(0, 0, W, H, 5, 5, 5);
    fill(16, 16, 32, 32, 120, 10, 10);
    assert(SGPaletteSample(pixels, W, H, W * 4, 5, 1, rgb) == 5);
    assert(valueOf(&rgb[3]) < 0.12f);                   // top left is black, and stays black
    assert(away(hueOf(&rgb[9]), 0) < 20);               // bottom right is the red
    assert(valueOf(&rgb[9]) < 0.6f);                    // as dark as it is, not lifted
    // Without it, the same cover is lifted to show on black.
    assert(SGPaletteSample(pixels, W, H, W * 4, 5, 0, rgb) == 5);
    for (int i = 0; i < 5; i++) assert(valueOf(&rgb[i * 3]) >= 0.5f);

    assert(SGPaletteCluster(pixels, W, H, W * 4, 3, 1, rgb) == 3);
    int black = 0, red = 0;
    for (int i = 0; i < 3; i++) {
        if (valueOf(&rgb[i * 3]) < 0.12f) black = 1;
        if (away(hueOf(&rgb[i * 3]), 0) < 20 && valueOf(&rgb[i * 3]) < 0.6f) red = 1;
    }
    assert(black && red);
    // Without it, black is no colour.
    assert(SGPaletteCluster(pixels, W, H, W * 4, 3, 0, rgb) == 3);
    for (int i = 0; i < 3; i++) assert(valueOf(&rgb[i * 3]) >= 0.5f);
}

int main(void) {
    spots();
    mainColours();
    dark();
    puts("palette: spots (quarters in place, a dark cover with a detail, purple and blue, grey) and main colours (two colours, one hue, grey, a rainbow), dark colours kept, premultiplied and bad input passed");
    return 0;
}
