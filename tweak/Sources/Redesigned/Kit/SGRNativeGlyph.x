// Proven 9.1.94 control glyphs use UIImageView (not SPTEncoreIconView); AddTo uses Lottie.
// Only these semantic controls opt in. Never recolor cover art, avatar, colored glyphs or snapshots.
#import "Core/SGCore.h"
#import "SGRNativeGlyph.h"
#import "SGRNativeSurface.h"
#import "SGRRestyle.h"
#import "SGRDownload.h"
#import "SGRGlyph.h"
#import "SGRTokens.h"

static char kImage, kHighlighted, kWatching, kLayoutHooked, kAddGlyph, kAddHidden, kPendingAdd;
static _Thread_local NSUInteger changing;
static BOOL active(void) { return NSThread.isMainThread && SGRedesignedUI(); }

static BOOL identifiedControl(UIView *view) {
    NSString *identifier=view.accessibilityIdentifier;
    if ([identifier hasPrefix:@"YourLibraryHeader."] &&
        ![identifier hasSuffix:@"title"] && ![identifier hasSuffix:@"title-internal"]) return YES;
    if ([identifier hasPrefix:@"YourLibraryFolderHeader."] && ![identifier containsString:@"title"]) return YES;
    static NSSet *known;
    static dispatch_once_t once; dispatch_once(&once, ^{
        known=[NSSet setWithArray:@[@"YourLibraryContent.gridToggle", @"Components.UI.ShuffleButton",
            @"Nowplaying-RepeatButton", @"Components.ConnectButtonOutputSwitcher", @"SPTNowPlayingPlayButton", @"SPTNowPlayingSliderV2"]];
    });
    return [known containsObject:identifier];
}
static UIView *controlFor(UIView *image) {
    for (UIView *v=image.superview;v;v=v.superview) {
        NSString *name=NSStringFromClass(v.class);
        if ([name hasPrefix:@"SGR"] || [v.accessibilityIdentifier isEqualToString:@"Encore.ImageView"] ||
            [v.accessibilityIdentifier isEqualToString:@"Components.UI.SideDrawerButton"]) return nil;
        if (identifiedControl(v)) return v;
    }
    return nil;
}

// Classify only a small, known control's source bitmap. Do not process artwork or guess hue.
// White/black monochrome glyphs receive a semantic ink role; colored or multitone assets stay exact.
static UIColor *inkIn(UIImage *image, BOOL slider) {
    if (!image.CGImage || image.images.count || image.size.width>(slider?1400:90) || image.size.height>(slider?32:90)) return nil;
    size_t width=CGImageGetWidth(image.CGImage), height=CGImageGetHeight(image.CGImage);
    if (!width || !height || width>(slider?4200:300) || height>(slider?96:300)) return nil;
    size_t count=width*height;
    uint8_t *pixels=calloc(count,4); if (!pixels) return nil;
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,width,height,8,width*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) { free(pixels);return nil; }
    // UIImage may carry lazy tint/symbol configuration absent from CGImage. Inspect
    // what UIKit actually draws, so an active cyan asset is never mistaken for white.
    UIGraphicsPushContext(context);[image drawInRect:CGRectMake(0,0,width,height)];UIGraphicsPopContext();
    BOOL white=YES,black=YES;NSUInteger visible=0;
    for (size_t i=0;i<count;i++) {
        CGFloat a=pixels[i*4+3]/255.;if(a<.10)continue;
        CGFloat r=pixels[i*4]/(255.*a),g=pixels[i*4+1]/(255.*a),b=pixels[i*4+2]/(255.*a);
        visible++;
        if (MAX(r,MAX(g,b))-MIN(r,MIN(g,b))>.04) {white=NO;black=NO;break;}
        white &= MIN(r,MIN(g,b))>.92;
        black &= MAX(r,MAX(g,b))<.14;
        if (!white&&!black)break;
    }
    CGContextRelease(context);free(pixels);
    return visible && white ? UIColor.whiteColor : (visible && black ? [UIColor colorWithWhite:.08 alpha:1] : nil);
}
static UIImage *mappedImage(UIImageView *view, UIImage *current, const void *key) {
    NSMutableDictionary *record=objc_getAssociatedObject(view,key);
    UIImage *source=current;
    if (record && record[@"emitted"]==current) source=record[@"source"];
    else if (record) {objc_setAssociatedObject(view,key,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);record=nil;}
    UIView *owner=controlFor(view);
    if (!owner || !SGRNativeSurfaceManaged(owner)) {
        objc_setAssociatedObject(view,key,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return source;
    }
    if (!source) return nil;
    if (!record) {
        UIColor *ink=inkIn(source,[owner.accessibilityIdentifier isEqualToString:@"SPTNowPlayingSliderV2"]);
        record=[NSMutableDictionary dictionaryWithDictionary:@{@"source":source,@"emitted":source,@"ink":ink?:NSNull.null}];
        objc_setAssociatedObject(view,key,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *ink=record[@"ink"];
    if ((id)ink==NSNull.null) return source;
    UIColor *target=SGRNativeSurfaceForeground(owner,ink);
    if ([target isEqual:ink]) {record[@"emitted"]=source;record[@"color"]=ink;return source;}
    if ([record[@"color"] isEqual:target] && record[@"emitted"]) return record[@"emitted"];
    UIImage *result=[source imageWithTintColor:target renderingMode:UIImageRenderingModeAlwaysOriginal];
    record[@"emitted"]=result;record[@"color"]=target;
    return result;
}
static void refreshImages(UIView *root) {
    if ([root isKindOfClass:UIImageView.class]) SGRRefreshNativeGlyph(root);
    for (UIView *child in root.subviews) refreshImages(child);
}
static void refreshAdd(UIView *button) {
    BOOL added=NO;
    BOOL replace=SGRNativeSurfaceManaged(button) && SGRedesignLightAppearance() && SGRReadAddTo(button,&added) && !added;
    SGRGlyphView *glyph=objc_getAssociatedObject(button,&kAddGlyph);
    if (replace && !glyph) {
        glyph=[[SGRGlyphView alloc]initWithSymbol:@"plus.circle" pointSize:24 weight:UIImageSymbolWeightRegular];
        glyph.userInteractionEnabled=NO;glyph.accessibilityElementsHidden=YES;
        // Native AddTo buttons begin at zero size. The bitmap can arrive before their
        // first layout, and Swift may resize them without dispatching our layout thunk.
        // Flexible margins keep the glyph centered as those real bounds arrive.
        glyph.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|
            UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
        objc_setAssociatedObject(button,&kAddGlyph,glyph,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glyph) {
        if (replace && glyph.superview!=button) [button addSubview:glyph];
        glyph.alpha=replace?1:0;
        glyph.tintColor=SGRPrimary();
        glyph.center=CGPointMake(CGRectGetMidX(button.bounds),CGRectGetMidY(button.bounds));
    }
    // The model owner is proven in SGRReadAddTo. Leave the native saved/accent animation exact.
    for (UIView *child in button.subviews) {
        if (![NSStringFromClass(child.class) containsString:@"StateMicroInteractionView"]) continue;
        NSNumber *old=objc_getAssociatedObject(child,&kAddHidden);
        if (replace) {
            if(!old)objc_setAssociatedObject(child,&kAddHidden,@(child.alpha),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if(child.alpha!=0) {changing++;child.alpha=0;changing--;}
        } else if (old) {
            changing++;child.alpha=old.doubleValue;changing--;objc_setAssociatedObject(child,&kAddHidden,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}
static void watchedLayout(UIView *owner) {
    if (changing || !active() || !objc_getAssociatedObject(owner,&kWatching)) return;
    if([owner.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"])refreshAdd(owner);
    else refreshImages(owner);
}
// Swift view instances cannot safely change isa. Chain the actual class's proven UIKit
// layout method instead; no shared SGRObserveLayout callback is overwritten.
static BOOL watchLayout(UIView *view) {
    Class cls=object_getClass(view);
    if (!cls || [NSStringFromClass(cls) hasPrefix:@"NSKVONotifying_"]) return NO;
    if (!objc_getAssociatedObject(cls,&kLayoutHooked)) {
        SEL selector=@selector(layoutSubviews);
        Method inherited=class_getInstanceMethod(cls,selector);if(!inherited)return NO;
        IMP previous=class_getMethodImplementation(cls,selector);
        IMP wrapper=imp_implementationWithBlock(^(UIView *owner){
            ((void(*)(id,SEL))previous)(owner,selector);watchedLayout(owner);
        });
        Method own=NULL;unsigned count=0;Method *methods=class_copyMethodList(cls,&count);
        for(unsigned i=0;i<count;i++)if(method_getName(methods[i])==selector)own=methods[i];
        free(methods);
        BOOL installed=NO;
        if(own) {method_setImplementation(own,wrapper);installed=YES;}
        else installed=class_addMethod(cls,selector,wrapper,method_getTypeEncoding(inherited));
        if(!installed) {imp_removeBlock(wrapper);return NO;}
        objc_setAssociatedObject(cls,&kLayoutHooked,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(view,&kWatching,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}
static void addStateRendered(CALayer *layer) {
    if (!active() || changing) return;
    UIView *view=nil;
    for(CALayer *l=layer;l;l=l.superlayer)if([l.delegate isKindOfClass:UIView.class]) {view=(id)l.delegate;break;}
    UIView *button=nil;
    for(UIView *v=view;v;v=v.superview)if([v.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"]) {button=v;break;}
    if(!button || !SGRNativeSurfaceManaged(button) || !objc_getAssociatedObject(button,&kWatching) || objc_getAssociatedObject(button,&kPendingAdd))return;
    objc_setAssociatedObject(button,&kPendingAdd,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weak=button;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *owner=weak;if(!owner)return;
        objc_setAssociatedObject(owner,&kPendingAdd,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        refreshAdd(owner);
    });
}
void SGRRefreshNativeGlyph(UIView *view) {
    if (!active() || changing || !view) return;
    if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *image=(id)view;
        UIImage *normal=mappedImage(image,image.image,&kImage),*highlighted=mappedImage(image,image.highlightedImage,&kHighlighted);
        changing++;
        if(normal!=image.image)image.image=normal;
        if(highlighted!=image.highlightedImage)image.highlightedImage=highlighted;
        changing--;
    }
    BOOL add=[view.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"];
    if(add)refreshAdd(view);
    if ((identifiedControl(view)||add) && !objc_getAssociatedObject(view,&kWatching)) watchLayout(view);
}
%group SGRNativeGlyphHooks
%hook UIView
- (void)setAlpha:(CGFloat)alpha {
    if(changing || !active() || !objc_getAssociatedObject(self,&kAddHidden)) { %orig;return; }
    // Keep a native opacity change made while its unsaved glyph is replaced, so restoring
    // the native saved animation cannot replay an older enabled/disabled appearance.
    objc_setAssociatedObject(self,&kAddHidden,@(alpha),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL added=NO;
    BOOL replace=SGRNativeSurfaceManaged(self.superview) && SGRedesignLightAppearance() && SGRReadAddTo(self.superview,&added) && !added;
    changing++;%orig(replace?0:alpha);changing--;
}
%end
%hook UIImageView
- (void)setImage:(UIImage *)image {
    if(changing || !active()) { %orig;return; }
    changing++;%orig(mappedImage(self,image,&kImage));changing--;
}
- (void)setHighlightedImage:(UIImage *)image {
    if(changing || !active()) { %orig;return; }
    changing++;%orig(mappedImage(self,image,&kHighlighted));changing--;
}
%end
// Observe only rendering in the proven AddTo control. Lottie's state changes need not
// lay out its UIButton. Coalesce after its native transaction; never replace animations.
%hook CAShapeLayer
- (void)setFillColor:(CGColorRef)color { %orig;addStateRendered(self); }
- (void)setStrokeColor:(CGColorRef)color { %orig;addStateRendered(self); }
%end
%hook CALayer
- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key { %orig;addStateRendered(self); }
- (void)addSublayer:(CALayer *)layer { %orig;addStateRendered(layer); }
%end
%end
%ctor { if (!SGRedesignedUI())return; %init(SGRNativeGlyphHooks); }
