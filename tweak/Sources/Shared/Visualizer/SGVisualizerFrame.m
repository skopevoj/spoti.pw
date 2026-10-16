// One still of the visualizer (Visualizer.h), for the lock screen's artwork: the cover blurred behind,
// the cover itself as a circle in the middle and the bars round it, as the ring in the player draws them
// (SGVisualizerView.m), in its style, colour (the cover's gradient included), width, height and mirror. The
// peaks and the rotation are the player's only: a still keeps no caps from frame to frame and has nothing to
// turn. With a line to show, the ring moves up and the line and the next one sit under it. Drawn with an image renderer, which any thread may use.
#import "Core/SGCore.h"
#import "SGCoverPalette.h"
#import "Visualizer.h"

static void drawText(NSString *text, UIFont *font, UIColor *color, CGRect box) {
    if (!text.length) return;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    [text drawWithRect:box options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: paragraph}
               context:nil];
}

UIImage *SGVisualizerDrawFrame(CGFloat side, UIImage *cover, UIImage *backdrop, const float *bars, NSInteger bands,
                               UIColor *accent, NSArray<UIColor *> *palette, NSString *line, NSString *next) {
    SGVisualizerStyle style = (SGVisualizerStyle)SGInt(SGKeyVisualizerStyle, SGVisualizerStyleBars);
    SGVisualizerColor colour = (SGVisualizerColor)SGInt(SGKeyVisualizerColor, SGVisualizerColorAccent);
    BOOL mirror = SGEnabled(SGKeyVisualizerMirror);
    CGFloat widthFactor = SGVisualizerWidthFactor();
    // A gradient colour's colours, as the player's ring has them (SGVisualizerView.m): Spectrum's hues, or the
    // cover's handed in (none yet, and the accent stands in, as there).
    NSArray<UIColor *> *colours = colour == SGVisualizerColorSpectrum ? SGVisualizerSpectrumColours()
                                : colour == SGVisualizerColorCover && palette.count ? palette : nil;
    SGVisualizerGradient shape = (SGVisualizerGradient)SGInt(SGKeyVisualizerGradient, SGVisualizerGradientAlong);
    if (colours.count < 2) colours = nil;
    NSArray<UIColor *> *stops = colours ? SGVisualizerGradientStops(colours, shape, mirror, colour == SGVisualizerColorSpectrum) : nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    CGSize size = CGSizeMake(side, side);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *renderer) {
        CGContextRef context = renderer.CGContext;
        CGRect bounds = (CGRect){CGPointZero, size};
        [UIColor.blackColor setFill];
        UIRectFill(bounds);
        if (backdrop) {
            [backdrop drawInRect:bounds];
            [[UIColor colorWithWhite:0 alpha:0.45] setFill];
            UIRectFillUsingBlendMode(bounds, kCGBlendModeNormal);
        }

        BOOL lyrics = line.length > 0;
        CGPoint centre = CGPointMake(side / 2, lyrics ? side * 0.39 : side / 2);
        CGFloat outer = side * (lyrics ? 0.33 : 0.45);
        CGFloat radius = outer * 0.62;   // the cover's, as the player's ring keeps it to 64 % of the square
        CGFloat inner = radius + side * 0.012;
        CGFloat reach = (outer - inner) * SGVisualizerHeightFactor();

        // The Backlight, as the player's ring lays it: solid to past the bars' middle, gone by the ring's edge.
        UIColor *glow = SGVisualizerBacklightColour(colours ?: @[colour == SGVisualizerColorWhite ? UIColor.whiteColor
                                                                                              : (accent ?: UIColor.whiteColor)]);
        if (glow) {
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGFloat solid = inner + reach * 0.6, edge = outer + side * 0.04;
            CGFloat locations[] = {0, solid / edge, 1};
            CFArrayRef glowColours = (__bridge CFArrayRef)@[(id)glow.CGColor, (id)glow.CGColor, (id)[glow colorWithAlphaComponent:0].CGColor];
            CGGradientRef gradient = CGGradientCreateWithColors(space, glowColours, locations);
            CGContextDrawRadialGradient(context, gradient, centre, 0, centre, edge, 0);
            CGGradientRelease(gradient);
            CGColorSpaceRelease(space);
        }

        // The cover, a circle.
        CGRect coverBox = CGRectMake(centre.x - radius, centre.y - radius, radius * 2, radius * 2);
        CGContextSaveGState(context);
        CGContextSetShadowWithColor(context, CGSizeMake(0, side * 0.01), side * 0.04, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
        [[UIColor colorWithWhite:0.12 alpha:1] setFill];
        CGContextFillEllipseInRect(context, coverBox);
        CGContextRestoreGState(context);
        if (cover) {
            CGContextSaveGState(context);
            CGContextAddEllipseInRect(context, coverBox);
            CGContextClip(context);
            [cover drawInRect:coverBox];
            CGContextRestoreGState(context);
        }

        // The bars round it, as one path: stroked in one colour, or turned into the outline of its strokes and
        // used as a clip for a radial gradient along every bar; a colour a bar round the ring, or bar by bar.
        NSInteger count = mirror ? bands * 2 : bands;
        if (count > 0 && reach > 0 && bars) {
            CGFloat step = 2 * M_PI / count;
            // As the ring in the player works its widths out (SGVisualizerView.m): a share of the room, never
            // more than the room, and a hairline at the least.
            CGFloat room = inner * step;
            CGFloat width = MIN(side * 0.014 * widthFactor, room * 0.55 * widthFactor);
            width = MIN(width, MAX(1, room * 0.95));
            width = MAX(width, MIN(2, room * 1.1));
            CGFloat waveWidth = MAX(2, side * 0.006 * MAX(1, widthFactor));
            UIColor *plain = colour == SGVisualizerColorWhite ? UIColor.whiteColor : (accent ?: UIColor.whiteColor);
            BOOL along = colours && shape == SGVisualizerGradientAlong;
            BOOL perBar = colours && !along;
            CGContextSetLineCap(context, kCGLineCapRound);
            CGContextSetLineJoin(context, kCGLineJoinRound);
            CGPoint *tips = malloc(sizeof(CGPoint) * (size_t)count);
            CGMutablePathRef path = CGPathCreateMutable();
            // The colour of bar `i`, for the gradients that colour bar by bar.
            UIColor *(^barColour)(NSInteger) = ^UIColor *(NSInteger i) {
                if (shape == SGVisualizerGradientAlternating) return stops[(NSUInteger)i % stops.count];
                return SGCoverGradientColor(stops, (CGFloat)(i + 0.5) / count);
            };
            for (NSInteger i = 0; i < count; i++) {
                NSInteger band = mirror ? (i < bands ? i : count - 1 - i) : i;
                CGFloat value = MAX(0, MIN(1, bars[band]));
                CGFloat angle = -M_PI_2 + (i + 0.5) * step;
                CGFloat dx = cos(angle), dy = sin(angle);
                CGFloat out = inner + MAX(width * 0.5, value * reach);
                CGPoint from = CGPointMake(centre.x + dx * inner, centre.y + dy * inner);
                CGPoint to = CGPointMake(centre.x + dx * out, centre.y + dy * out);
                tips[i] = to;
                if (style == SGVisualizerStyleWave) continue;
                if (perBar) {
                    // A colour of its own: drawn now.
                    if (style == SGVisualizerStyleBars) {
                        [barColour(i) setStroke];
                        CGContextSetLineWidth(context, width);
                        CGContextMoveToPoint(context, from.x, from.y);
                        CGContextAddLineToPoint(context, to.x, to.y);
                        CGContextStrokePath(context);
                    } else {
                        [barColour(i) setFill];
                        CGContextFillEllipseInRect(context, CGRectMake(to.x - width * 0.6, to.y - width * 0.6, width * 1.2, width * 1.2));
                    }
                    continue;
                }
                if (style == SGVisualizerStyleBars) {
                    CGPathMoveToPoint(path, NULL, from.x, from.y);
                    CGPathAddLineToPoint(path, NULL, to.x, to.y);
                } else {
                    CGPathAddEllipseInRect(path, NULL, CGRectMake(to.x - width * 0.6, to.y - width * 0.6, width * 1.2, width * 1.2));
                }
            }
            if (style == SGVisualizerStyleWave) {
                if (perBar) {
                    CGContextSetLineWidth(context, waveWidth);
                    for (NSInteger i = 0; i < count; i++) {
                        [barColour(i) setStroke];
                        CGContextMoveToPoint(context, tips[i].x, tips[i].y);
                        CGContextAddLineToPoint(context, tips[(i + 1) % count].x, tips[(i + 1) % count].y);
                        CGContextStrokePath(context);
                    }
                } else {
                    CGPathAddLines(path, NULL, tips, (size_t)count);
                    CGPathCloseSubpath(path);
                }
            }
            if (!perBar && !CGPathIsEmpty(path)) {
                CGFloat lineWidth = style == SGVisualizerStyleWave ? waveWidth : width;
                if (along) {
                    // The strokes' outline (a dot's own shape) as the clip, the gradient from inside to tip.
                    CGContextSaveGState(context);
                    CGContextAddPath(context, path);
                    if (style != SGVisualizerStyleDots) {
                        CGContextSetLineWidth(context, lineWidth);
                        CGContextReplacePathWithStrokedPath(context);
                    }
                    CGContextClip(context);
                    NSMutableArray *cgColours = [NSMutableArray array];
                    for (UIColor *stop in stops) [cgColours addObject:(id)stop.CGColor];
                    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
                    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)cgColours, NULL);
                    CGColorSpaceRelease(space);
                    if (gradient) {
                        CGContextDrawRadialGradient(context, gradient, centre, inner, centre, inner + reach,
                                                    kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
                        CGGradientRelease(gradient);
                    }
                    CGContextRestoreGState(context);
                } else {
                    CGContextAddPath(context, path);
                    if (style == SGVisualizerStyleDots) {
                        [plain setFill];
                        CGContextFillPath(context);
                    } else {
                        [plain setStroke];
                        CGContextSetLineWidth(context, lineWidth);
                        CGContextStrokePath(context);
                    }
                }
            }
            CGPathRelease(path);
            free(tips);
        }

        // The line being sung, and the next one dimmer, under the ring.
        if (lyrics) {
            CGFloat margin = side * 0.07, top = centre.y + outer + side * 0.04;
            CGFloat lineHeight = side * 0.17;
            drawText(line, [UIFont systemFontOfSize:side * 0.058 weight:UIFontWeightBold], UIColor.whiteColor,
                     CGRectMake(margin, top, side - 2 * margin, lineHeight));
            drawText(next, [UIFont systemFontOfSize:side * 0.04 weight:UIFontWeightBold], [UIColor colorWithWhite:1 alpha:0.45],
                     CGRectMake(margin, top + lineHeight + side * 0.01, side - 2 * margin, side - top - lineHeight - margin));
        }
    }];
}
