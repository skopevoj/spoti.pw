// Home redesign: a shortcut tile the way an Apple list row holds artwork. The cover sits inset from the tile's
// edges with its own corners, the title follows it in, and the tile is a dark surface tinted faintly towards the
// cover's dominant colour (Kit/SGRPalette.h, +tintForImage:), so the grid is not one grey and white text always
// reads. Until the cover has loaded, the tile is the untinted surface.
//
// The surface sits behind Spotify's stack, over the tile's own fill, so the title, the playing indicator and
// the button's touches stay Spotify's. The inset and the title's move are transforms, which Spotify's layout
// never reads, so its constraints are left as they are. The tint is worked out off the main thread once per
// picture and follows the cover as Spotify sets it (SGRObserveImage), since a cover lands after layout.
//
// Tree (trees/home 3 more scrolled.txt:36-50, 2026-09-17): InteractableLayoutBackingButton id=Shortcut.Card.Home
// 181x48 clips > UIView 181x48 bg=#FFFFFF@0.10 (the fill), then Encore.StackView > AutoLayoutStackView >
// UIView 173x48 (the row) > UIView {0, 0} 48x48 bg=#000000@0.90 r=4 (the cover's square) > Encore.ImageView >
// UIImageView 48x48 and the PlaceholderView; then the row's 8pt spacer and the title's stack at x 56.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

// How far the cover sits in from the tile's top, bottom and leading edges, and its corners there.
static const CGFloat kInset = 5, kCoverRadius = 4;

static char kSurfaceKey, kImageKey, kShownKey;

// Tints already worked out, by the image object while it lives (main thread only).
static NSMapTable<UIImage *, UIColor *> *tints(void) {
    static NSMapTable *table;
    if (!table) table = [NSMapTable weakToStrongObjectsMapTable];
    return table;
}

static UIColor *untinted(void) {
    static UIColor *color;
    if (!color) color = SGRElevated(UIColor.blackColor);
    return color;
}

@interface SGRTileParts : NSObject
@property (nonatomic, weak) UIView *fill;
@property (nonatomic, weak) UIView *square;
@property (nonatomic, weak) UIImageView *cover;
@end

@implementation SGRTileParts
@end

static SGRTileParts *partsOf(UIView *tile) {
    UIView *holder = SGRFindByIdentifier(tile, @"Encore.ImageView", &kImageKey);
    SGRTileParts *parts = [SGRTileParts new];
    for (UIView *sub in holder.subviews) {
        if ([sub isKindOfClass:UIImageView.class]) parts.cover = (UIImageView *)sub;
    }
    parts.square = holder.superview;
    UIView *first = tile.subviews.firstObject;
    if (object_getClass(first) == UIView.class && CGRectEqualToRect(first.frame, tile.bounds)) parts.fill = first;
    return parts;
}

static UIView *surfaceIn(UIView *tile, UIView *fill) {
    UIView *surface = objc_getAssociatedObject(tile, &kSurfaceKey);
    if (!surface) {
        surface = [UIView new];
        surface.userInteractionEnabled = NO;
        surface.accessibilityElementsHidden = YES;
        surface.backgroundColor = untinted();
        objc_setAssociatedObject(tile, &kSurfaceKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (surface.superview != tile) {
        if (fill) [tile insertSubview:surface aboveSubview:fill];
        else [tile insertSubview:surface atIndex:0];
    }
    if (!CGRectEqualToRect(surface.frame, tile.bounds)) surface.frame = tile.bounds;
    return surface;
}

// The square scaled about its centre so it clears the tile's edges by kInset, and everything after it in the
// row moved in by what that took off its trailing side.
static void inset(UIView *square) {
    CGFloat side = square.bounds.size.height;
    if (side <= kInset * 4) return;
    CGFloat scale = (side - kInset * 2) / side;
    CGAffineTransform shrink = CGAffineTransformMakeScale(scale, scale);
    if (!CGAffineTransformEqualToTransform(square.transform, shrink)) square.transform = shrink;
    CALayer *layer = square.layer;
    // The radius is drawn scaled with the square.
    CGFloat radius = kCoverRadius / scale;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
    if (!layer.masksToBounds) layer.masksToBounds = YES;

    CGAffineTransform follow = CGAffineTransformMakeTranslation(-square.bounds.size.width * (1 - scale) / 2, 0);
    BOOL after = NO;
    for (UIView *sibling in square.superview.subviews) {
        if (sibling == square) {
            after = YES;
            continue;
        }
        if (after && !CGAffineTransformEqualToTransform(sibling.transform, follow)) sibling.transform = follow;
    }
}

static void tint(UIView *tile, UIView *surface, UIColor *color, BOOL animated) {
    color = color ?: untinted();
    if ([surface.backgroundColor isEqual:color]) return;
    if (!animated || !tile.window) {
        surface.backgroundColor = color;
        return;
    }
    SGRAnimate(SGRMotionFade, ^{ surface.backgroundColor = color; }, nil);
}

static void refresh(UIView *tile) {
    SGRTileParts *parts = partsOf(tile);
    UIImageView *cover = parts.cover;
    UIView *square = parts.square;
    if (!cover || !square || square.bounds.size.width < 20 || tile.bounds.size.width <= square.bounds.size.width) return;
    UIView *surface = surfaceIn(tile, parts.fill);
    inset(square);

    UIImage *image = cover.image;
    if (!image) {
        objc_setAssociatedObject(tile, &kShownKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tint(tile, surface, nil, NO);
        return;
    }
    UIColor *known = [tints() objectForKey:image];
    if (known) {
        objc_setAssociatedObject(tile, &kShownKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tint(tile, surface, known, YES);
        return;
    }
    if (objc_getAssociatedObject(tile, &kShownKey) == image) return;
    objc_setAssociatedObject(tile, &kShownKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak UIView *weakTile = tile;
    [SGRPalette tintForImage:image surface:untinted() completion:^(UIColor *color) {
        UIView *strongTile = weakTile;
        if (color) [tints() setObject:color forKey:image];
        // A tile reused for another cover in the meantime has asked for that one.
        if (!strongTile || objc_getAssociatedObject(strongTile, &kShownKey) != image) return;
        tint(strongTile, surfaceIn(strongTile, partsOf(strongTile).fill), color, YES);
    }];
}

void SGRHomeStyleTile(UIView *tile) {
    SGRApplyNativeLightSurface(tile, NO);
    CFTimeInterval began = SGRHomeProbeBegin();
    UIImageView *cover = partsOf(tile).cover;
    if (!cover) return;
    __weak UIView *weakTile = tile;
    // The block is replaced on every pass, so a cover taken into another tile tells the tile it is in now.
    SGRObserveImage(cover, ^(UIImageView *view) {
        UIView *strongTile = weakTile;
        if (strongTile && [view isDescendantOfView:strongTile]) refresh(strongTile);
    });
    refresh(tile);
    SGRHomeProbeEnd(SGRHomeProbeTiles, began);
}
