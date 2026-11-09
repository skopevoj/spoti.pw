// Spicetify's useful lesson: native UIKit assignments survive a semantic-theme change.
// Unlike its window sweeps / broad luminance guesses, this adapter is opt-in per redesigned
// surface, maps only known neutral roles, and handles insertion/reuse and assignment events.
// One coalesced pass per transition/insertion, no display link, frame sweep or preference writes.
#import "Core/SGCore.h"
#import "SGRNativeSurface.h"
#import "SGRNativeGlyph.h"
#import "SGRSheetAppearance.h"
#import "SGRTokens.h"
#import "Headers/SPTEncoreIconView.h"

@interface SPTEncoreIconView (SGRAppearanceReadback)
- (UIColor *)foregroundColor;
- (UIColor *)activeForegroundColor;
@end

static char kRoot, kSheetBase, kPreserve, kOriginal, kRoles, kVisited, kIconEmitted;
static NSHashTable<UIView *> *roots;
static BOOL transitioning, replaying;
static _Thread_local NSUInteger applying;
static NSAttributedStringKey const originalInk = @"SGRNativeOriginalForeground";
static NSAttributedStringKey const originalRole = @"SGRNativeForegroundRole";
static NSAttributedStringKey const emittedInk = @"SGRNativeEmittedForeground";
static BOOL enabled(void) { return SGRedesignedUI() && NSThread.isMainThread; }
// Native base/text pairs are verified against SpotifyShared 9.1.94; the existing adapter
// aliases use the redesign's primary/elevated roles. The high bit records the source palette.
// A transition re-evaluates the ROLE, never a generic inverse of its brightness.
// Unknown colors, chromatic accents, artwork and inverted/media regions are never inverted.
typedef NS_ENUM(NSUInteger, SGRSurfaceRole) {
    SGRRoleNone, SGRRolePrimary, SGRRoleSecondary, SGRRoleTertiary, SGRRoleBase, SGRRoleElevated,
    SGRRoleLightSource = 0x100,
};
static NSMutableDictionary *roles(UIView *view, BOOL create) {
    NSMutableDictionary *values=objc_getAssociatedObject(view,&kRoles);
    if (!values && create) { values=[NSMutableDictionary new]; objc_setAssociatedObject(view,&kRoles,values,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return values;
}

static BOOL neutral(UIColor *color, CGFloat *white, CGFloat *alpha) {
    CGFloat r, g, b, a;
    if (!color || ![color getRed:&r green:&g blue:&b alpha:&a] || a <= 0 ||
        fabs(r-g) > 0.002 || fabs(g-b) > 0.002) return NO;
    *white = r; *alpha = a; return YES;
}
static BOOL at(CGFloat value, NSUInteger byte) { return fabs(value - byte / 255.0) < 0.002; }
UIColor *SGRNativeLightText(UIColor *color) {
    CGFloat w, a;
    if (!neutral(color, &w, &a)) return color;
    if (at(w,255) || at(w,250) || at(w,242)) return [UIColor colorWithWhite:0.08 alpha:a];
    if (at(w,179) || at(w,178) || at(w,167) || at(w,166)) return [UIColor colorWithWhite:101.0/255 alpha:a];
    if (at(w,153) || at(w,128)) return [UIColor colorWithWhite:0.40 alpha:a];
    return color;
}
UIColor *SGRNativeLightBackground(UIColor *color) {
    CGFloat w, a;
    if (!neutral(color, &w, &a)) return color;
    if (at(w,18) || at(w,24)) return [UIColor colorWithWhite:0.97 alpha:a];
    if (at(w,31) || at(w,40) || at(w,41)) return [UIColor colorWithWhite:0.92 alpha:a];
    // Black may be an artwork scrim, an inverted button, or a shadow. Never infer its role.
    return color;
}
static NSUInteger textRole(UIColor *color) {
    CGFloat w,a;
    if (!neutral(color,&w,&a)) return SGRRoleNone;
    if (at(w,255) || at(w,250) || at(w,242)) return SGRRolePrimary;
    if (at(w,179) || at(w,178) || at(w,167) || at(w,166)) return SGRRoleSecondary;
    if (at(w,153) || at(w,128)) return SGRRoleTertiary;
    if (SGRedesignLightAppearance()) {
        if (at(w,0) || fabs(w-0.08)<0.002) return SGRRolePrimary | SGRRoleLightSource;
        if (at(w,101)) return SGRRoleSecondary | SGRRoleLightSource;
        if (fabs(w-0.40)<0.002) return SGRRoleTertiary | SGRRoleLightSource;
    }
    return SGRRoleNone;
}
static NSUInteger backgroundRole(UIView *view, UIColor *color) {
    CGFloat w,a;
    if (!neutral(color,&w,&a)) return SGRRoleNone;
    BOOL base=[view isKindOfClass:UIScrollView.class] || [objc_getAssociatedObject(view,&kRoot) boolValue];
    if (at(w,18) || at(w,24) || (base && at(w,0))) return SGRRoleBase;
    if (at(w,31) || at(w,40) || at(w,41)) return SGRRoleElevated;
    if (SGRedesignLightAppearance()) {
        // White controls may be deliberate inverted buttons. Only native content surfaces
        // are eligible for the white base role; controls and media keep their own paint.
        if (fabs(w-.97)<.002 || (at(w,255) && ![view isKindOfClass:UIControl.class]))
            return SGRRoleBase | SGRRoleLightSource;
        if (fabs(w-.92)<.002) return SGRRoleElevated | SGRRoleLightSource;
    }
    return SGRRoleNone;
}
static UIColor *roleColor(UIColor *source, NSUInteger role) {
    if (!source || !role) return source;
    BOOL light=SGRedesignLightAppearance();
    if (light==((role & SGRRoleLightSource)!=0)) return source;
    CGFloat alpha=CGColorGetAlpha(source.CGColor), value;
    switch (role & ~SGRRoleLightSource) {
        case SGRRolePrimary: value=light?.08:1; break;
        case SGRRoleSecondary: value=light?101./255:179./255; break;
        case SGRRoleTertiary: value=light?.40:153./255; break;
        case SGRRoleBase: value=light?.97:18./255; break;
        case SGRRoleElevated: value=light?.92:31./255; break;
        default: return source;
    }
    return [UIColor colorWithWhite:value alpha:alpha];
}
static UIColor *background(UIView *view, UIColor *color, NSString *key) {
    if (objc_getAssociatedObject(view,&kSheetBase)) {
        if (SGRedesignLightAppearance()) return SGRNeutralField();
        // Sheet roots have an explicit base role, but Dark retains native transparency,
        // material backing, and exact opaque shades. Light-provider values use their role.
        return roleColor(color,[roles(view,NO)[key] unsignedIntegerValue]);
    }
    if ([objc_getAssociatedObject(view,&kRoot) boolValue]) return SGRNeutralField();
    return roleColor(color,[roles(view,NO)[key] unsignedIntegerValue]);
}
static BOOL boundary(UIView *view) {
    if (SGRNativeSheetPreservesView(view)) return YES;
    if (objc_getAssociatedObject(view, &kPreserve)) return YES;
    if ([view isKindOfClass:UIVisualEffectView.class] && !SGRNativeSheetOwnsEffect(view)) return YES;
    NSString *name = NSStringFromClass(view.class);
    if ([name hasPrefix:@"SGR"] && ![name hasPrefix:@"SGRSuppressed_"]) return YES;
    if ([view.accessibilityIdentifier isEqualToString:@"Encore.ImageView"]) return YES;
    if ([view isKindOfClass:UIImageView.class]) {
        return ((UIImageView *)view).image.renderingMode != UIImageRenderingModeAlwaysTemplate;
    }
    return NO;
}
BOOL SGRNativeSurfaceManaged(UIView *view) {
    if (!enabled() || !view) return NO;
    for (UIView *v = view; v; v = v.superview) {
        if (boundary(v)) return NO;
        if (objc_getAssociatedObject(v, &kRoot)) return YES;
    }
    return NO;
}
// A deliberate dark/inverted control or colored media card keeps white ink. This is
// a contrast guard, not a color-role guess: its opaque background was not converted.
static BOOL paleSurface(UIView *view) {
    for (UIView *v=view; v; v=v.superview) {
        BOOL directLayer = [objc_getAssociatedObject(v,&kOriginal) objectForKey:@"layerBackground"] != nil;
        UIColor *color = directLayer ? nil : v.backgroundColor;
        if ((directLayer || !color) && v.layer.backgroundColor) color=[UIColor colorWithCGColor:v.layer.backgroundColor];
        CGFloat r,g,b,a;
        if ([color getRed:&r green:&g blue:&b alpha:&a] && a>0.9) {
            CGFloat level=0.2126*r+0.7152*g+0.0722*b;
            return level>0.55;
        }
        if (objc_getAssociatedObject(v,&kRoot)) return SGRedesignLightAppearance();
    }
    return SGRedesignLightAppearance();
}
UIColor *SGRNativeSurfaceForeground(UIView *view, UIColor *color) {
    if (!SGRNativeSurfaceManaged(view) || paleSurface(view)!=SGRedesignLightAppearance()) return color;
    NSUInteger role=textRole(color);
    // This public entry is used only by explicitly identified semantic glyph controls.
    // Their stored Light-origin image ink must retain its role after the provider changes.
    CGFloat white,alpha;
    if (!role && neutral(color,&white,&alpha)) {
        if (at(white,0) || fabs(white-.08)<.002) role=SGRRolePrimary|SGRRoleLightSource;
        else if (at(white,101)) role=SGRRoleSecondary|SGRRoleLightSource;
    }
    return roleColor(color,role);
}
static UIColor *foreground(UIView *view, UIColor *color, NSString *key) {
    return paleSurface(view)==SGRedesignLightAppearance() ? roleColor(color,[roles(view,NO)[key] unsignedIntegerValue]) : color;
}
static NSMutableDictionary *originals(UIView *view, BOOL create) {
    NSMutableDictionary *values = objc_getAssociatedObject(view, &kOriginal);
    if (!values && create) {
        values = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(view, &kOriginal, values, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return values;
}
static void remember(UIView *view, NSString *key, id value) {
    if (replaying && originals(view,NO)[key]) return;
    originals(view, YES)[key] = value ?: NSNull.null;
    if ([value isKindOfClass:UIColor.class])
        roles(view,YES)[key]=@(([key isEqual:@"background"] || [key isEqual:@"layerBackground"]) ? backgroundRole(view,value) : textRole(value));
    else [roles(view,NO) removeObjectForKey:key];
}
static void iconEmitted(UIView *view, NSString *key, UIColor *value) {
    NSMutableDictionary *values=objc_getAssociatedObject(view,&kIconEmitted);
    if (!values) { values=[NSMutableDictionary new];objc_setAssociatedObject(view,&kIconEmitted,values,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    values[key]=value ?: NSNull.null;
}
static void captureIconDrift(UIView *view, NSString *key, UIColor *actual) {
    id last=[objc_getAssociatedObject(view,&kIconEmitted) objectForKey:key];
    id value=actual ?: NSNull.null;
    if (last && ![last isEqual:value]) { remember(view,key,actual);iconEmitted(view,key,actual); }
}
// Keep only color provenance in the CURRENT value, never an old copy of a song/title.
// Native reuse can replace text through UIKit internals; replaying a cached string would
// resurrect stale content. Private attributes survive a copy and disappear with replacement.
static NSAttributedString *text(UIView *view, NSAttributedString *input, BOOL restoreOnly) {
    if (!input.length) return input;
    BOOL adapts = !restoreOnly && paleSurface(view)==SGRedesignLightAppearance();
    __block NSMutableAttributedString *result;
    [input enumerateAttributesInRange:NSMakeRange(0,input.length) options:0
                          usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
        UIColor *saved=attrs[originalInk], *actual=attrs[NSForegroundColorAttributeName];
        BOOL validSaved=[saved isKindOfClass:UIColor.class] && [actual isEqual:attrs[emittedInk]];
        UIColor *source=validSaved?saved:actual;
        if (![source isKindOfClass:UIColor.class]) return;
        NSUInteger role=validSaved?[attrs[originalRole] unsignedIntegerValue]:textRole(source);
        UIColor *mapped=adapts?roleColor(source,role):source;
        if (!result) result=[input mutableCopy];
        [result addAttribute:NSForegroundColorAttributeName value:mapped range:range];
        if (!restoreOnly && role) {
            [result addAttribute:originalInk value:source range:range];
            [result addAttribute:originalRole value:@(role) range:range];
            [result addAttribute:emittedInk value:mapped range:range];
        } else {
            [result removeAttribute:originalInk range:range];
            [result removeAttribute:originalRole range:range];
            [result removeAttribute:emittedInk range:range];
        }
    }];
    return result ?: input;
}
static void clearButtonLabelRecord(UIButton *button) {
    // UIButton updates titleLabel internally while our parent setter is guarded. Its
    // current state is authoritative, not an earlier scalar value recorded on the label.
    [originals(button.titleLabel,NO) removeObjectForKey:@"text"];
}
static void refresh(UIView *view);
static void refreshInk(UIView *view);
static void refreshTree(UIView *view) {
    if (!view) return;
    SGRRefreshNativeSheetNode(view);
    refresh(view);
    SGRRefreshNativeGlyph(view);
    // Walk only when opting in, moving, or inserting a subtree. Boundary descendants may
    // have old marks from reuse, so refresh them to restore the original values as needed.
    for (UIView *child in view.subviews) refreshTree(child);
}
static id restored(id value) { return value == NSNull.null ? nil : value; }
static void refresh(UIView *view) {
    Class iconClass=NSClassFromString(@"SPTEncoreIconView");
    if (iconClass && [view isKindOfClass:iconClass]) {
        captureIconDrift(view,@"icon",[(SPTEncoreIconView *)view foregroundColor]);
        captureIconDrift(view,@"activeIcon",[(SPTEncoreIconView *)view activeForegroundColor]);
    }
    BOOL use = SGRNativeSurfaceManaged(view);
    NSMutableDictionary *old = originals(view, NO);
    if (use) objc_setAssociatedObject(view,&kVisited,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSAttributedString *currentText = [view isKindOfClass:UILabel.class] ? [(UILabel *)view attributedText] : nil;
    NSAttributedString *restoredText = !use ? text(view,currentText,YES) : nil;
    if (!use && !old.count && restoredText == currentText) return;
    if (!use) {
        applying++;
        // A direct layer assignment is later than the saved UIView assignment. Restore
        // in that order, including an explicit nil layer override, never dictionary order.
        if (old[@"background"]) view.backgroundColor = restored(old[@"background"]);
        if (old[@"layerBackground"]) view.layer.backgroundColor = [restored(old[@"layerBackground"]) CGColor];
        for (NSString *key in old) {
            id value = restored(old[key]);
            if ([key isEqual:@"tint"]) view.tintColor = value;
            else if ([key isEqual:@"text"]) ((UILabel *)view).textColor = value;
            else if ([key isEqual:@"icon"]) [(SPTEncoreIconView *)view setForegroundColor:value];
            else if ([key isEqual:@"activeIcon"]) [(SPTEncoreIconView *)view setActiveForegroundColor:value];
            else if ([key hasPrefix:@"button:"]) [(UIButton *)view setTitleColor:value forState:[[key substringFromIndex:7] integerValue]];

        }
        if (restoredText) ((UILabel *)view).attributedText = restoredText;
        for (NSString *key in old) if ([key hasPrefix:@"buttonText:"]) {
            UIControlState state=[[key substringFromIndex:11] integerValue];
            NSAttributedString *current=old[key]==NSNull.null?nil:[(UIButton *)view attributedTitleForState:state];
            [(UIButton *)view setAttributedTitle:text(view,current,YES) forState:state];
        }
        applying--;
        objc_setAssociatedObject(view,&kOriginal,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view,&kIconEmitted,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view,&kRoles,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    // Re-submit saved role bindings; do not reinterpret a Light-origin value after switching.
    BOOL wasReplaying=replaying; replaying=YES;
    id layerSource = old[@"layerBackground"];
    if (old[@"background"] || view.backgroundColor)
        view.backgroundColor = old[@"background"] ? restored(old[@"background"]) : view.backgroundColor;
    if (layerSource) view.layer.backgroundColor = [restored(layerSource) CGColor];
    else if (!view.backgroundColor && view.layer.backgroundColor &&
             ![view isKindOfClass:UILabel.class] && ![view isKindOfClass:UIImageView.class])
        view.layer.backgroundColor = view.layer.backgroundColor;
    refreshInk(view);
    replaying=wasReplaying;
}
static void refreshInk(UIView *view) {
    NSMutableDictionary *old=originals(view,NO);
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        NSAttributedString *sourceText = label.attributedText;
        if (label.textColor) label.textColor = restored(old[@"text"]) ?: label.textColor;
        if (sourceText.length) label.attributedText = sourceText;
    }
    // Do not read/write inherited tint values: that would freeze UIKit inheritance.
    // Only explicit setter inputs are recorded. Owned roots supply the default tint.
    if (old[@"tint"]) view.tintColor=restored(old[@"tint"]);
    Class iconClass=NSClassFromString(@"SPTEncoreIconView");
    if (iconClass && [view isKindOfClass:iconClass]) {
        SPTEncoreIconView *icon=(id)view;
        captureIconDrift(view,@"icon",icon.foregroundColor);
        captureIconDrift(view,@"activeIcon",icon.activeForegroundColor);
        old=originals(view,NO);
        UIColor *base=restored(old[@"icon"]) ?: icon.foregroundColor;
        UIColor *active=restored(old[@"activeIcon"]) ?: icon.activeForegroundColor;
        if (base) [icon setForegroundColor:base];
        if (active) [icon setActiveForegroundColor:active];
    }
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button=(id)view;
        // Reapply only explicit inputs previously seen by our hooks. UIKit's getters return
        // fallback values for unset states; copying them would silently create new overrides.
        for (NSString *key in [old.allKeys copy]) if ([key hasPrefix:@"button:"])
            [button setTitleColor:restored(old[key]) forState:[[key substringFromIndex:7] integerValue]];
        for (NSString *key in [old.allKeys copy]) if ([key hasPrefix:@"buttonText:"]) {
            UIControlState state=[[key substringFromIndex:11] integerValue];
            NSAttributedString *current=old[key]==NSNull.null?nil:[button attributedTitleForState:state];
            [button setAttributedTitle:current forState:state];
        }
    }
}
void SGRApplyNativeLightSurface(UIView *root, BOOL fillsBase) {
    if (!enabled() || !root || [root isKindOfClass:UIWindow.class]) return;
    if (objc_getAssociatedObject(root,&kRoot)) return;
    if (!roots) roots=[NSHashTable weakObjectsHashTable];
    [roots addObject:root];
    objc_setAssociatedObject(root,&kRoot,@(fillsBase),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRegisterAppearanceView(root);
    applying++;
    root.tintColor=SGRPrimary();
    if (fillsBase) root.backgroundColor=SGRNeutralField();
    applying--;
    refreshTree(root);
}
void SGRApplyNativeSheetSurface(UIView *root) {
    if (!enabled() || !root || [root isKindOfClass:UIWindow.class] || objc_getAssociatedObject(root,&kSheetBase)) return;
    UIColor *source=root.backgroundColor;
    objc_setAssociatedObject(root,&kSheetBase,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRApplyNativeLightSurface(root,NO);
    // Record even nil/clear: those native sheet backings must return exactly in Dark.
    root.backgroundColor=source;
}
void SGRRefreshNativeSurfaces(void) {
    if (!enabled()) return;
    NSArray<UIView *> *registered=roots.allObjects;
    transitioning=YES;
    for (UIView *root in registered) {
        applying++;
        root.overrideUserInterfaceStyle=SGRedesignAppearanceStyle();
        if (!originals(root,NO)[@"tint"]) root.tintColor=SGRPrimary();
        if ([objc_getAssociatedObject(root,&kRoot) boolValue]) root.backgroundColor=SGRNeutralField();
        applying--;
    }
    // Weak roots also include detached retained pages. Skip nested roots here: their entire
    // subtree is visited once from the highest registered ancestor, including boundaries.
    for (UIView *root in registered) {
        BOOL nested=NO;
        for (UIView *parent=root.superview;parent;parent=parent.superview)
            if (objc_getAssociatedObject(parent,&kRoot)) { nested=YES;break; }
        if (!nested) refreshTree(root);
    }
    transitioning=NO;
}
void SGRPreserveNativeSurface(UIView *root) {
    if (!enabled() || !root || objc_getAssociatedObject(root,&kPreserve)) return;
    objc_setAssociatedObject(root,&kPreserve,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    refreshTree(root);
}

%group SGRNativeSurfaceHooks
%hook UIView
- (void)didMoveToSuperview {
    %orig;
    if (!applying && enabled() && (SGRNativeSurfaceManaged(self) || objc_getAssociatedObject(self,&kVisited))) refreshTree(self);
}
- (void)setBackgroundColor:(UIColor *)color {
    if (applying || !SGRNativeSurfaceManaged(self)) { %orig; return; }
    BOOL wasPale=paleSurface(self);
    remember(self,@"background",color);
    // A new native UIView assignment supersedes the layer override. A transition replay
    // must retain BOTH the saved layer input and its source-palette role until replayed.
    if (!replaying) {
        [originals(self,NO) removeObjectForKey:@"layerBackground"];
        [roles(self,NO) removeObjectForKey:@"layerBackground"];
    }
    applying++; %orig(background(self,color,@"background")); applying--;
    if (!transitioning && wasPale != paleSurface(self)) { refreshInk(self); for (UIView *child in self.subviews) refreshTree(child); }
}
- (void)setTintColor:(UIColor *)color {
    if (applying || !SGRNativeSurfaceManaged(self)) { %orig; return; }
    remember(self,@"tint",color);
    applying++; %orig(foreground(self,color,@"tint")); applying--;
}
%end
%hook UILabel
- (void)setTextColor:(UIColor *)color {
    if (applying || !SGRNativeSurfaceManaged(self)) { %orig; return; }
    remember(self,@"text",color);
    applying++;
    %orig(foreground(self,color,@"text"));
    // UIKit's explicit textColor assignment supersedes all foreground runs. Update only
    // the current content so its old provenance cannot override that native decision.
    if (self.attributedText.length && color) {
        NSMutableAttributedString *current = [self.attributedText mutableCopy];
        NSRange all=NSMakeRange(0,current.length);
        [current removeAttribute:originalInk range:all];
        [current removeAttribute:originalRole range:all];
        [current removeAttribute:emittedInk range:all];
        [current addAttribute:NSForegroundColorAttributeName value:color range:all];
        self.attributedText = text(self,current,NO);
    }
    applying--;
}
- (void)setAttributedText:(NSAttributedString *)value {
    if (applying || !SGRNativeSurfaceManaged(self)) { %orig; return; }
    applying++; %orig(text(self,value,NO)); applying--;
}
%end
%hook UIButton
- (void)setTitle:(NSString *)value forState:(UIControlState)state {
    if (applying || !SGRNativeSurfaceManaged(self)) { %orig; return; }
    [originals(self,NO) removeObjectForKey:[NSString stringWithFormat:@"buttonText:%lu",(unsigned long)state]];
    clearButtonLabelRecord(self);
    applying++; %orig; applying--;
}
- (void)setTitleColor:(UIColor *)color forState:(UIControlState)state {
    if (applying || !SGRNativeSurfaceManaged(self)) { %orig; return; }
    remember(self,[NSString stringWithFormat:@"button:%lu",(unsigned long)state],color);
    clearButtonLabelRecord(self);
    applying++; %orig(foreground(self,color,[NSString stringWithFormat:@"button:%lu",(unsigned long)state]),state); applying--;
}
- (void)setAttributedTitle:(NSAttributedString *)value forState:(UIControlState)state {
    if (applying || !SGRNativeSurfaceManaged(self)) { %orig; return; }
    // Record only that this state was explicitly assigned. Color roles travel in the CURRENT
    // attributed title, just as for UILabel; never retain/replay an old song or button string.
    remember(self,[NSString stringWithFormat:@"buttonText:%lu",(unsigned long)state],value?@YES:nil);
    clearButtonLabelRecord(self);
    applying++; %orig(text(self,value,NO),state); applying--;
}
%end
// SpotifyShared's glyphs bake their foreground into their drawing. tintColor is not enough.
// These two setters/getters are present in its 9.1.94 Objective-C method/property table.
%hook SPTEncoreIconView
- (void)layoutSubviews {
    %orig;
    if (!applying && SGRNativeSurfaceManaged(self)) {
        // Native Swift callers can bypass an ObjC setter hook. Read back just this glyph,
        // and redraw only when its two proven properties actually drifted. No subtree walk.
        SPTEncoreIconView *icon=(id)self;
        UIColor *base=icon.foregroundColor, *active=icon.activeForegroundColor;
        captureIconDrift(self,@"icon",base);
        captureIconDrift(self,@"activeIcon",active);
        if (base && ![foreground(self,base,@"icon") isEqual:base]) [icon setForegroundColor:base];
        if (active && ![foreground(self,active,@"activeIcon") isEqual:active]) [icon setActiveForegroundColor:active];
    }
}
- (void)setForegroundColor:(UIColor *)color {
    if (applying || !SGRNativeSurfaceManaged(self)) { %orig; return; }
    remember(self,@"icon",color);
    UIColor *mapped=foreground(self,color,@"icon");
    applying++; %orig(mapped); applying--;
    iconEmitted(self,@"icon",mapped);
}
- (void)setActiveForegroundColor:(UIColor *)color {
    if (applying || !SGRNativeSurfaceManaged(self)) { %orig; return; }
    remember(self,@"activeIcon",color);
    UIColor *mapped=foreground(self,color,@"activeIcon");
    applying++; %orig(mapped); applying--;
    iconEmitted(self,@"activeIcon",mapped);
}
%end
%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    UIView *view = (id)self.delegate;
    if (applying || !enabled() || ![view isKindOfClass:UIView.class] || view.layer != self ||
        [view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] || !SGRNativeSurfaceManaged(view)) { %orig; return; }
    UIColor *source=color ? [UIColor colorWithCGColor:color] : nil;
    BOOL wasPale=paleSurface(view);
    remember(view,@"layerBackground",source);
    applying++; %orig(background(view,source,@"layerBackground").CGColor); applying--;
    if (!transitioning && wasPale != paleSurface(view)) { refreshInk(view); for (UIView *child in view.subviews) refreshTree(child); }
}
%end
%end
%ctor {
    if (!SGRedesignedUI()) return;
    %init(SGRNativeSurfaceHooks);
}

void SGRRefreshNativeSurfaceSubtree(UIView *view) {
    if (enabled()) refreshTree(view);
}
BOOL SGRNativeSurfaceHasRootWithin(UIView *view) {
    if (!enabled() || !view) return NO;
    for (UIView *root in roots.allObjects)
        if (root==view || [root isDescendantOfView:view]) return YES;
    return NO;
}
