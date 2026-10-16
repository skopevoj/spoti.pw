// Encore's facepile as the album and playlist harnesses mock it (issue #149), under the 9.1.78 class names:
// FacepileView > UIView > FacepileStackView > AvatarView > [initial label, AvatarView.ImageView > UIImageView]
// (trees/clean/album/01.txt:69-77, playlist/01.txt:694-702). An own playlist's pile starts with a
// FacepileIconView, a glyph on a disc (own-playlist/01.txt:757-766). Faces overlap by Spotify's 20.4 of 24.
//
// The pictures are drawn here, placeholders of no one.
#import <UIKit/UIKit.h>

@interface _TtCE14Encore_FaceKitO16EncoreFoundation6Encore12FacepileView : UIView @end
@implementation _TtCE14Encore_FaceKitO16EncoreFoundation6Encore12FacepileView @end
@interface _TtCE14Encore_FaceKitO16EncoreFoundation6Encore17FacepileStackView : UIView @end
@implementation _TtCE14Encore_FaceKitO16EncoreFoundation6Encore17FacepileStackView @end
@interface _TtCE14Encore_FaceKitO16EncoreFoundation6Encore16FacepileIconView : UIView @end
@implementation _TtCE14Encore_FaceKitO16EncoreFoundation6Encore16FacepileIconView @end
@interface _TtCE14Encore_FaceKitO16EncoreFoundation6Encore10AvatarView : UIView @end
@implementation _TtCE14Encore_FaceKitO16EncoreFoundation6Encore10AvatarView @end
@interface _TtCCE14Encore_FaceKitO16EncoreFoundation6Encore10AvatarView9ImageView : UIView @end
@implementation _TtCCE14Encore_FaceKitO16EncoreFoundation6Encore10AvatarView9ImageView @end

// A head and shoulders on a coloured disc.
static UIImage *mockFace(CGFloat hue) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(72, 72)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithHue:hue saturation:0.55 brightness:0.62 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, 72, 72));
        [[UIColor colorWithHue:hue saturation:0.25 brightness:0.95 alpha:1] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(24, 12, 24, 26)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(10, 44, 52, 44)] fill];
    }];
}

// The pile under `parent` at `origin`, one AvatarView per initial, a glyph disc first when `icon`. The
// returned image views are the faces', empty until the caller sets a picture.
static NSArray<UIImageView *> *mockFacepile(UIView *parent, CGPoint origin, NSArray<NSString *> *initials, BOOL icon) {
    NSUInteger count = initials.count + (icon ? 1 : 0);
    CGFloat width = 24 + (count - 1) * 20.4;
    UIView *pile = [[_TtCE14Encore_FaceKitO16EncoreFoundation6Encore12FacepileView alloc] initWithFrame:CGRectMake(origin.x, origin.y, width, 24)];
    [parent addSubview:pile];
    UIView *inner = [[UIView alloc] initWithFrame:pile.bounds];
    [pile addSubview:inner];
    UIView *stack = [[_TtCE14Encore_FaceKitO16EncoreFoundation6Encore17FacepileStackView alloc] initWithFrame:pile.bounds];
    [inner addSubview:stack];
    CGFloat x = 0;
    if (icon) {
        UIView *disc = [[_TtCE14Encore_FaceKitO16EncoreFoundation6Encore16FacepileIconView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
        disc.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        disc.layer.cornerRadius = 12;
        UIImageView *glyph = [[UIImageView alloc] initWithFrame:CGRectMake(6, 6, 12, 12)];
        glyph.image = [UIImage systemImageNamed:@"lock.fill"];
        [disc addSubview:glyph];
        [stack addSubview:disc];
        x += 20.4;
    }
    NSMutableArray<UIImageView *> *faces = [NSMutableArray array];
    for (NSString *initial in initials) {
        UIView *avatar = [[_TtCE14Encore_FaceKitO16EncoreFoundation6Encore10AvatarView alloc] initWithFrame:CGRectMake(x, 0, 24, 24)];
        avatar.backgroundColor = [UIColor colorWithRed:0.95 green:0.45 blue:0.6 alpha:1];
        avatar.layer.cornerRadius = 12;
        UILabel *letter = [[UILabel alloc] initWithFrame:CGRectMake(6.5, 1, 11, 22)];
        letter.text = initial;
        letter.font = [UIFont boldSystemFontOfSize:16];
        letter.textColor = UIColor.blackColor;
        letter.accessibilityIdentifier = @"Encore.Label-internal";
        [avatar addSubview:letter];
        UIView *holder = [[_TtCCE14Encore_FaceKitO16EncoreFoundation6Encore10AvatarView9ImageView alloc] initWithFrame:avatar.bounds];
        holder.accessibilityIdentifier = @"Encore.ImageView";
        holder.layer.cornerRadius = 12;
        holder.clipsToBounds = YES;
        [avatar addSubview:holder];
        UIImageView *picture = [[UIImageView alloc] initWithFrame:holder.bounds];
        picture.contentMode = UIViewContentModeScaleAspectFill;
        [holder addSubview:picture];
        [stack addSubview:avatar];
        [faces addObject:picture];
        x += 20.4;
    }
    return faces;
}

// What the redesign drew before the creator's name, for the log: each face's frame in the header view, the
// name's, and what a touch on the first face reaches.
static NSString *facesReport(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    UIView *info = nil;
    while (stack.count && !info) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) info = v;
        [stack addObjectsFromArray:v.subviews];
    }
    if (!info) return @"no header";
    UIView *faces = nil;
    UILabel *creator = nil;
    for (UIView *sub in info.subviews) {
        if ([sub isMemberOfClass:UIView.class] && [sub.subviews.firstObject isKindOfClass:UIImageView.class]) faces = sub;
        if ([sub isKindOfClass:UILabel.class] && ((UILabel *)sub).userInteractionEnabled) creator = (UILabel *)sub;
    }
    if (!faces) return [NSString stringWithFormat:@"no faces; name \"%@\" %@ (centre %.1f, page centre %.1f)", creator.text,
                               NSStringFromCGRect(creator.frame), CGRectGetMidX(creator.frame), CGRectGetMidX(info.bounds)];
    NSMutableArray<NSString *> *drawn = [NSMutableArray array];
    for (UIImageView *face in faces.subviews.reverseObjectEnumerator) {
        if (!face.hidden && face.image) [drawn addObject:NSStringFromCGRect([faces convertRect:face.frame toView:info])];
    }
    NSString *touch = @"-";
    if (drawn.count && !faces.hidden) {
        CGPoint centre = [faces convertPoint:CGPointMake(CGRectGetMidX(faces.subviews.lastObject.frame), CGRectGetMidY(faces.bounds)) toView:info];
        UIView *hit = [info hitTest:centre withEvent:nil];
        touch = hit == creator ? @"the creator line" : (hit ? NSStringFromClass(hit.class) : @"through");
    }
    CALayer *shown = faces.layer.presentationLayer ?: faces.layer, *name = creator.layer.presentationLayer ?: creator.layer;
    return [NSString stringWithFormat:@"%lu face(s) %@ a=%.2f (on screen %.2f) hidden=%d animating %@; name \"%@\" %@ (on screen at x %.1f); line centre %.1f, page centre %.1f; a touch on the first face reaches %@",
            (unsigned long)drawn.count, [drawn componentsJoinedByString:@" "], faces.alpha, shown.opacity, faces.hidden,
            [faces.layer.animationKeys componentsJoinedByString:@","] ?: @"nothing", creator.text,
            NSStringFromCGRect(creator.frame), name.position.x - creator.bounds.size.width / 2,
            faces.hidden ? CGRectGetMidX(creator.frame) : (CGRectGetMinX(CGRectUnion(creator.frame, faces.frame)) + CGRectGetMaxX(CGRectUnion(creator.frame, faces.frame))) / 2,
            CGRectGetMidX(info.bounds), touch];
}
