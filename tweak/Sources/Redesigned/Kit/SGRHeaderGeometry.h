// Text and actions share the rows' usable column; artwork remains full bleed.
#import "SGRBarGeometry.h"

static inline CGRect SGRHeaderContentBounds(UIView *header) {
    UIEdgeInsets inset = UIEdgeInsetsZero;
    if (!CGRectIsNull(SGRVerticalBarFrameIn(header, SGRVerticalBarExtent))) {
        inset = SGRVerticalBarContentInsets(header, SGRVerticalBarExtent);
        // Safe area and rail describe overlapping clearance, not two separate margins.
        // A header already inside the content column has neither overlap nor inherited inset.
        inset.left = MAX(inset.left, header.safeAreaInsets.left);
        inset.right = MAX(inset.right, header.safeAreaInsets.right);
    }
    CGRect content = UIEdgeInsetsInsetRect(header.bounds, inset);
    content.size.width = MAX(0, content.size.width);
    return content;
}

// Playlist's text block can be narrower or translated relative to the header. Resolve the
// column at the header, then convert once; retain the block's own vertical layout.
static inline CGRect SGRHeaderInfoFrame(UIView *header, UIView *host) {
    CGRect content = SGRHeaderContentBounds(header);
    CGFloat x = [host convertPoint:CGPointMake(CGRectGetMinX(content), 0) fromView:header].x;
    return CGRectMake(round(x), host == header ? host.bounds.origin.y : 0, content.size.width, host.bounds.size.height);
}
