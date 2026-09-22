#import "GlobalIcons.h"
#import "Core/SGCore.h"
#import "Headers/SPTEncoreIconView.h"
#import <objc/runtime.h>

static char kSGGlobalIconOverlayKey;

static UIImageView *globalOverlay(UIView *view) {
    return objc_getAssociatedObject(view, &kSGGlobalIconOverlayKey);
}

static void installGlobalOverlay(SPTEncoreIconView *view, id icon) {
    if (SGAppIconStyleValue() != SGAppIconStyleSFSymbols || ![icon respondsToSelector:@selector(name)]) return;
    NSString *name = [icon name];
    if (![name isKindOfClass:NSString.class] || !name.length) return;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    UIImage *image = [UIImage systemImageNamed:SGAppIconSymbolForEncoreName(name) withConfiguration:configuration];
    if (!image) image = [UIImage systemImageNamed:@"questionmark.circle.fill" withConfiguration:configuration];
    if (!image) return;
    image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImageView *overlay = globalOverlay(view);
    if (!overlay) {
        overlay = [[UIImageView alloc] initWithImage:image];
        overlay.tintColor = UIColor.whiteColor;
        overlay.contentMode = UIViewContentModeScaleAspectFit;
        overlay.userInteractionEnabled = NO;
        overlay.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(view, &kSGGlobalIconOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view addSubview:overlay];
    } else {
        overlay.image = image;
    }
    overlay.frame = view.bounds;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

%hook SPTEncoreIconView
- (instancetype)initWithIcon:(id)icon {
    SPTEncoreIconView *view = %orig(icon);
    if (view) {
        installGlobalOverlay(view, icon);
        if (globalOverlay(view)) [view setForegroundColor:UIColor.whiteColor];
    }
    return view;
}

- (void)layoutSubviews {
    %orig;
    UIImageView *overlay = globalOverlay((UIView *)self);
    if (overlay) overlay.frame = self.bounds;
}

- (void)setForegroundColor:(UIColor *)color {
    UIImageView *overlay = globalOverlay((UIView *)self);
    if (overlay && SGAppIconStyleValue() == SGAppIconStyleSFSymbols) {
        %orig(UIColor.clearColor);
        overlay.tintColor = color ?: UIColor.whiteColor;
        return;
    }
    %orig(color);
}

- (void)setActiveForegroundColor:(UIColor *)color {
    UIImageView *overlay = globalOverlay((UIView *)self);
    if (overlay && SGAppIconStyleValue() == SGAppIconStyleSFSymbols) {
        %orig(UIColor.clearColor);
        overlay.tintColor = color ?: UIColor.whiteColor;
        return;
    }
    %orig(color);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"SPTEncoreIconView"]);
}
