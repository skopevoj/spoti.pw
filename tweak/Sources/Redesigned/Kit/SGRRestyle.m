#import <objc/message.h>
#import <CoreText/SFNTLayoutTypes.h>
#import "Core/SGCore.h"
#import "SGRRestyle.h"
#import "SGRTokens.h"

static char kPlateKey, kImageObserverKey, kLayoutObserverKey;

@interface SGRWeakBox : NSObject
@property (nonatomic, weak) id value;
@end

@implementation SGRWeakBox
@end

#pragma mark - instance subclasses

// A Swift class can lose its metadata when the runtime makes a subclass of it, and an instance KVO
// already swapped the class of would be swapped back when its last observer goes; neither is subclassed.
static BOOL subclassable(Class cls) {
    const char *name = class_getName(cls);
    return strncmp(name, "_Tt", 3) != 0 && !strchr(name, '.') && strncmp(name, "NSKVONotifying_", 15) != 0;
}

// The class `prefix` + the instance's class, made once, answering `class` with the original so
// isKindOfClass:, NSStringFromClass and the tree dumps see what Spotify made.
static Class instanceSubclass(Class original, const char *prefix, void (^install)(Class subclass, Class original)) {
    NSString *name = [NSString stringWithFormat:@"%s%s", prefix, class_getName(original)];
    Class subclass = objc_getClass(name.UTF8String);
    if (subclass) return subclass;
    subclass = objc_allocateClassPair(original, name.UTF8String, 0);
    if (!subclass) return Nil;
    install(subclass, original);
    class_addMethod(subclass, @selector(class), imp_implementationWithBlock(^Class(id self) { return original; }), "#@:");
    objc_registerClassPair(subclass);
    return subclass;
}

// Moves the view into the subclass unless it is already in it; NO when the view cannot be subclassed.
static BOOL adopt(UIView *view, const char *prefix, void (^install)(Class subclass, Class original)) {
    Class current = object_getClass(view);
    if (strncmp(class_getName(current), prefix, strlen(prefix)) == 0) return YES;
    if (!subclassable(current)) return NO;
    Class subclass = instanceSubclass(current, prefix, install);
    if (!subclass) return NO;
    object_setClass(view, subclass);
    return YES;
}

static void addOverride(Class subclass, Class original, SEL selector, id block) {
    Method method = class_getInstanceMethod(original, selector);
    if (method) class_addMethod(subclass, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method));
}

#pragma mark - the class itself

// What an instance of one of Spotify's own classes cannot have -- a subclass of its own -- the class every
// instance of it shares can: the override goes on the class, the way each of the tweak's %hooks does. The
// class is taken off the instance rather than named, since Encore's names carry a build hash that moves with
// every Spotify release, and it is given the override once; an instance that never asked to be watched pays
// one associated-object lookup for it.
//
// `make` is handed the implementation the override stands in front of and answers the block that replaces
// it; that block must call the one it was given first. The implementation replaced is the class's own where
// it has one -- so nothing above it in the hierarchy, UIKit's own classes included, is touched -- and the
// inherited one where it does not.
static BOOL overrideOnClass(Class cls, SEL selector, id (^make)(IMP replaced)) {
    if (!cls || !selector) return NO;
    // Never the class KVO made for one instance: it is swapped away again when the last observer goes, and
    // the override with it. Everything else here is a class Spotify itself wrote.
    if (strncmp(class_getName(cls), "NSKVONotifying_", 15) == 0) return NO;
    // Done already? A class is an object too, and a selector is a pointer unique to its name, so the class
    // carries its own mark per selector -- a plain lookup, since callers ask again on every pass they make.
    if (objc_getAssociatedObject(cls, (void *)selector)) return YES;

    Method inherited = class_getInstanceMethod(cls, selector);
    if (!inherited) return NO;
    Method own = nil;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) own = methods[i];
    }
    free(methods);
    IMP replaced = own ? method_getImplementation(own)
                       : class_getMethodImplementation(class_getSuperclass(cls), selector);
    if (!replaced) return NO;

    IMP override = imp_implementationWithBlock(make(replaced));
    if (own) method_setImplementation(own, override);
    else if (!class_addMethod(cls, selector, override, method_getTypeEncoding(inherited))) return NO;
    objc_setAssociatedObject(cls, (void *)selector, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

// Said once per class: what could not be watched at all, and what had to be watched through its class.
static void logWatch(UIView *view, SEL selector, BOOL kept, BOOL onClass) {
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *name = NSStringFromClass(object_getClass(view));
    NSString *mark = [NSString stringWithFormat:@"%@ %s", name, sel_getName(selector)];
    if ([logged containsObject:mark]) return;
    [logged addObject:mark];
    if (!kept) SGLog(@"redesign kit: %@ cannot be watched for %s", name, sel_getName(selector));
    else if (onClass) SGLog(@"redesign kit: %@ watched for %s through its class", name, sel_getName(selector));
}

#pragma mark - views

void SGRSuppress(UIView *view) {
    if (!view) return;
    BOOL kept = adopt(view, "SGRSuppressed_", ^(Class subclass, Class original) {
        addOverride(subclass, original, @selector(setAlpha:), ^(UIView *self, CGFloat alpha) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL, CGFloat))objc_msgSendSuper)(&parent, @selector(setAlpha:), 0);
        });
        addOverride(subclass, original, @selector(setUserInteractionEnabled:), ^(UIView *self, BOOL enabled) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&parent, @selector(setUserInteractionEnabled:), NO);
        });
    });
    if (!kept) {
        static NSMutableSet<NSString *> *logged;
        if (!logged) logged = [NSMutableSet set];
        NSString *name = NSStringFromClass(object_getClass(view));
        if (![logged containsObject:name]) {
            [logged addObject:name];
            SGLog(@"redesign kit: %@ cannot keep being suppressed, set once per call", name);
        }
    }
    view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static BOOL hasMonospacedDigits(UIFont *font) {
    for (NSDictionary *setting in font.fontDescriptor.fontAttributes[UIFontDescriptorFeatureSettingsAttribute]) {
        if ([setting[UIFontFeatureTypeIdentifierKey] integerValue] == kNumberSpacingType
            && [setting[UIFontFeatureSelectorIdentifierKey] integerValue] == kMonospacedNumbersSelector) return YES;
    }
    return NO;
}

static void applyMonospaced(UILabel *label, Class original) {
    NSAttributedString *text = label.attributedText;
    struct objc_super parent = {label, original};
    if (!text.length) {
        UIFont *font = label.font;
        if (font && !hasMonospacedDigits(font)) {
            ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setFont:), SGRMonospacedDigitsFont(font));
        }
        return;
    }
    __block NSMutableAttributedString *mapped = nil;
    [text enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(UIFont *font, NSRange range, BOOL *stop) {
        if (!font || hasMonospacedDigits(font)) return;
        if (!mapped) mapped = [text mutableCopy];
        [mapped addAttribute:NSFontAttributeName value:SGRMonospacedDigitsFont(font) range:range];
    }];
    if (mapped) ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setAttributedText:), mapped);
}

// Spotify's setters run first; what they left is then given the feature through the original class's
// own setters. UILabel may set one property through another, so a pass started inside a pass is
// skipped rather than trusted to settle.
static BOOL sg_keepingMonospaced = NO;

static void keepMonospaced(UILabel *label, Class original) {
    if (sg_keepingMonospaced) return;
    sg_keepingMonospaced = YES;
    applyMonospaced(label, original);
    sg_keepingMonospaced = NO;
}

void SGRMonospacedDigits(UILabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;
    BOOL kept = adopt(label, "SGRMonospaced_", ^(Class subclass, Class original) {
        for (NSString *name in @[@"setText:", @"setAttributedText:", @"setFont:"]) {
            SEL selector = NSSelectorFromString(name);
            addOverride(subclass, original, selector, ^(UILabel *self, id value) {
                struct objc_super parent = {self, original};
                ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, selector, value);
                keepMonospaced(self, original);
            });
        }
    });
    Class original = kept ? class_getSuperclass(object_getClass(label)) : object_getClass(label);
    keepMonospaced(label, original);
}

// Only the views that asked: everything else of the class carrying the override goes straight back out.
static void reportImage(UIImageView *view) {
    void (^block)(UIImageView *) = objc_getAssociatedObject(view, &kImageObserverKey);
    if (block) block(view);
}

BOOL SGRObserveImage(UIImageView *view, void (^changed)(UIImageView *view)) {
    if (![view isKindOfClass:UIImageView.class]) return NO;
    BOOL first = objc_getAssociatedObject(view, &kImageObserverKey) == nil;
    objc_setAssociatedObject(view, &kImageObserverKey, changed, OBJC_ASSOCIATION_COPY_NONATOMIC);
    BOOL kept = adopt(view, "SGRImageObserved_", ^(Class subclass, Class original) {
        addOverride(subclass, original, @selector(setImage:), ^(UIImageView *self, UIImage *image) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setImage:), image);
            reportImage(self);
        });
    });
    // Encore's image views, which is what every picture Spotify loads arrives in, are Swift classes: no
    // instance of one can be given a subclass of its own, so the class itself carries the override.
    BOOL onClass = !kept && overrideOnClass(object_getClass(view), @selector(setImage:), ^id(IMP replaced) {
        return ^(UIImageView *self, UIImage *image) {
            ((void (*)(id, SEL, id))replaced)(self, @selector(setImage:), image);
            reportImage(self);
        };
    });
    if (first) logWatch(view, @selector(setImage:), kept || onClass, onClass);
    return kept || onClass;
}

// A pass the block itself sets off (a frame it moves) reaches layoutSubviews again before the block has
// returned; one level is enough to settle, and re-entering would not end.
static BOOL sg_reportingLayout = NO;

BOOL SGRObserveLayout(UIView *view, void (^laidOut)(UIView *view)) {
    if (![view isKindOfClass:UIView.class]) return NO;
    objc_setAssociatedObject(view, &kLayoutObserverKey, laidOut, OBJC_ASSOCIATION_COPY_NONATOMIC);
    BOOL kept = adopt(view, "SGRLayoutObserved_", ^(Class subclass, Class original) {
        addOverride(subclass, original, @selector(layoutSubviews), ^(UIView *self) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&parent, @selector(layoutSubviews));
            if (sg_reportingLayout) return;
            void (^block)(UIView *) = objc_getAssociatedObject(self, &kLayoutObserverKey);
            if (!block) return;
            sg_reportingLayout = YES;
            block(self);
            sg_reportingLayout = NO;
        });
    });
    if (!kept) {
        static NSMutableSet<NSString *> *logged;
        if (!logged) logged = [NSMutableSet set];
        NSString *name = NSStringFromClass(object_getClass(view));
        if (![logged containsObject:name]) {
            [logged addObject:name];
            SGLog(@"redesign kit: %@ cannot be watched for its layout", name);
        }
    }
    return kept;
}

// An identifier ending in * matches by prefix, for Spotify's ids that carry an entity after a dash.
static BOOL identifierMatches(NSString *identifier, NSString *wanted) {
    if (!identifier) return NO;
    if ([wanted hasSuffix:@"*"]) return [identifier hasPrefix:[wanted substringToIndex:wanted.length - 1]];
    return [identifier isEqualToString:wanted];
}

static UIView *findIdentifier(UIView *view, NSString *identifier) {
    if (identifierMatches(view.accessibilityIdentifier, identifier)) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = findIdentifier(sub, identifier);
        if (found) return found;
    }
    return nil;
}

UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey) {
    if (!root || !identifier.length) return nil;
    SGRWeakBox *box = cacheKey ? objc_getAssociatedObject(root, cacheKey) : nil;
    UIView *cached = box.value;
    if (cached && identifierMatches(cached.accessibilityIdentifier, identifier) && [cached isDescendantOfView:root]) return cached;
    UIView *found = findIdentifier(root, identifier);
    if (found && cacheKey) {
        if (!box) {
            box = [SGRWeakBox new];
            objc_setAssociatedObject(root, cacheKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        box.value = found;
    }
    return found;
}

@implementation SGRShadowPlate {
    CGRect _pathBounds;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _cornerRadius = SGRRadiusArtwork;
    _pathBounds = CGRectNull;
    CALayer *layer = self.layer;
    layer.shadowColor = UIColor.blackColor.CGColor;
    layer.shadowOpacity = 0.45;
    layer.shadowRadius = 32;
    layer.shadowOffset = CGSizeMake(0, 12);
    return self;
}

- (void)setCornerRadius:(CGFloat)radius {
    _cornerRadius = radius;
    _pathBounds = CGRectNull;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (CGRectEqualToRect(bounds, _pathBounds)) return;
    _pathBounds = bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:_cornerRadius].CGPath;
    [CATransaction commit];
}

@end

SGRShadowPlate *SGRShadowPlateIn(UIView *host, const void *key) {
    if (!host) return nil;
    const void *slot = key ?: &kPlateKey;
    SGRShadowPlate *plate = objc_getAssociatedObject(host, slot);
    if (!plate) {
        plate = [[SGRShadowPlate alloc] initWithFrame:host.bounds];
        objc_setAssociatedObject(host, slot, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (plate.superview != host) [host insertSubview:plate atIndex:0];
    return plate;
}

#pragma mark - Spotify's controls and pages

// Nearly as wide as the cell. The bands are the width of the page -- a row's surface, a carousel's
// collection, a "see more" fade (artist, trees/continuous/3.txt 2026-09-18; episode page and the
// playlist's Recommended songs, trees/continuous/1.txt and 2.txt 2026-09-20) -- while a badge's black
// disc is 26pt and an avatar's ring the same.
static const CGFloat kPaintedShare = 0.75;

// The layer's colour, not the view's. -[UIView backgroundColor] answers only what was set through the
// view; a view painted straight on its layer reads back nil there, and the first pass of this left the
// playlist's Refresh band black while everything beside it cleared (device, trees/continuous/1.txt
// 2026-09-20). The layer is where the paint really is, and where the Kit's repaint hook watches for it.
//
// A cell nested inside the cell is walked into only while it is as wide as the band being looked for:
// a card in a carousel is its own and narrower, while the element framework wraps a cell's content in
// views of its own that are the full width, and stopping at one of those is stopping before the paint.
static void clearPaint(UIView *view, UIView *cell, CGFloat wide) {
    BOOL full = view.bounds.size.width >= wide;
    if (view != cell && !full && [view isKindOfClass:UICollectionViewCell.class]) return;
    if (full) {
        // Read off the layer, written through the view, so the two are left saying the same thing: the
        // clear colour lands on both, and reads back with an alpha the next pass does not take for paint.
        CGColorRef color = view.layer.backgroundColor;
        if (color && SGIsBaseSurface(color)) view.backgroundColor = UIColor.clearColor;
        if (!view.layer.mask && [NSStringFromClass(view.class) containsString:@"GradientView"]) view.layer.mask = [CALayer layer];
    }
    for (UIView *sub in view.subviews) clearPaint(sub, cell, wide);
}

void SGRClearCellPaint(UIView *cell) {
    if (!cell) return;
    clearPaint(cell, cell, cell.bounds.size.width * kPaintedShare);
}

// The way a tap on Spotify's own button would fire it: the first control under it, through the actions
// it registered, and through accessibility for an Encore control that reads its touches from a gesture
// recognizer instead -- which is every one of Spotify's own Swift controls.
void SGRActivate(UIView *source) {
    if (!source) return;
    __block UIControl *control = nil;
    SGForEachView(source, ^(UIView *v) {
        if (!control && [v isKindOfClass:UIControl.class]) control = (UIControl *)v;
    });
    if (control && SGRFire(control)) return;
    id target = control ?: source;
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *name = NSStringFromClass([target class]);
    if (![logged containsObject:name]) {
        [logged addObject:name];
        SGLog(@"redesign kit: %@ fired through accessibility", name);
    }
    [target accessibilityActivate];
}

BOOL SGRFire(UIControl *control) {
    if (![control isKindOfClass:UIControl.class]) return NO;
    __block UIControlEvents registered = control.allControlEvents;
    [control enumerateEventHandlers:^(UIAction *action, id target, SEL selector, UIControlEvents events, BOOL *stop) {
        registered |= events;
    }];
    UIControlEvents fire = (registered & UIControlEventPrimaryActionTriggered) ? UIControlEventPrimaryActionTriggered
                         : (registered & UIControlEventTouchUpInside) ? UIControlEventTouchUpInside : 0;
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *name = NSStringFromClass(control.class);
    if (![logged containsObject:name]) {
        [logged addObject:name];
        SGLog(@"redesign kit: %@ fires %@ (events 0x%lx)", name, fire == UIControlEventPrimaryActionTriggered ? @"its primary action" : fire ? @"touch up inside" : @"nothing", (unsigned long)registered);
    }
    if (!fire) return NO;
    [control sendActionsForControlEvents:fire];
    return YES;
}
