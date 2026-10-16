// The colours of a picture, for the visualizer's Cover gradient (Visualizer.h), read one of two ways the
// Visualizer page picks between. Plain C so it is tested on the Mac or Linux against
// harness/visualizer/palette_test.c, like SGSpectrum.
//
// Spots (SGPaletteSample): the picture is blurred and read at a few points, its centre, then the middle of
// each quarter going round (top left, top right, bottom right, bottom left), then the middle of each edge.
// Each point is the average of the picture round it, weighted by distance, so a small vivid detail or thin
// text barely moves it and the colours are the ones the cover is mostly made of where it is. They come back
// in the order of the points.
//
// Main colours (SGPaletteCluster): k-means in OKLab over the whole picture, each pixel weighted by how vivid
// it is, so a cover's vivid parts stand out even when small; clusters too dark for a bar on black are left
// out, colours too close to one taken are skipped, and a cover with fewer colours than asked for is filled
// out with lighter and darker shades of its main one. They come back in a ring order: the main colour first,
// then the others by how far their hue is round from it.
//
// Either way each colour is lifted to be light enough to show as a bar on black, keeping its hue, unless
// `dark` is set: then the colours are as dark as they are on the cover, black included, and Main colours
// takes dark clusters as well as light ones.
#pragma once
#include <stdint.h>

enum { SGPaletteMaxColors = 8 };

// `rgba` is width x height pixels of 8 bit channels, premultiplied or not, rows `stride` bytes apart, the
// first row the top. Each writes `count` (1...SGPaletteMaxColors) colours as three floats each, 0...1, into
// `rgb` and returns how many it wrote: `count`, or 0 for an empty picture or bad arguments.
int SGPaletteSample(const uint8_t *rgba, int width, int height, int stride, int count, int dark, float *rgb);
int SGPaletteCluster(const uint8_t *rgba, int width, int height, int stride, int count, int dark, float *rgb);
