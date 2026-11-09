// Player redesign: glass circles behind the header's close and more buttons.
//
// Glass is the control layer floating over the field, so it goes behind the round buttons only: the
// playlist name between them stays a label, and the row of playback controls stays bare glyphs
// (PlayerControls.x). Each circle is a subview of the button it sits behind (SGRGlassInside), below
// what the button draws and taking no touches, so the buttons stay Spotify's, with their actions, state
// and accessibility, and the circle follows the button wherever Spotify's row puts it. Circles placed
// from the unit's layout pass instead (a backing across the unit's view) were read before the row had
// laid the buttons out and sat 24pt up and to the side until a tap laid the unit out again
// (trees/continuous/1.txt, 2026-09-17: shapes at {-10, -22} and {320, -22}; the close button is at {12, 0}
// in the unit's view, so its circle belonged at {14, 2}).
//
// The add button keeps no circle: its glyph is a circle of its own, green and filled once the track is
// saved, and on glass it read as a disc on a disc (device test, 2026-09-17).
//
// Tree (trees/clean/player/01.txt): HeaderElementsUnit's view is a 402x48 row holding
// id=now-playing-minimize-button 48x48 (:103) and id=Context menu 48x48 (:122), the playlist name
// between them.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"
#import "Redesigned/Kit/SGRBarGeometry.h"

static char kGlassKey, kCloseKey, kMoreKey;

// The real Spotify control moves, not a glyph that tries to synthesize its action. A proxy's
// accessibility activation did not open the physical device's menu. Keeping the same view keeps
// every target, UIAction, gesture recognizer, interaction and accessibility implementation intact.
@interface SGRPlayerMorePlaceholder : UIView
@property (nonatomic) CGSize reservedSize;
@end
@implementation SGRPlayerMorePlaceholder
- (CGSize)intrinsicContentSize { return self.reservedSize; }
@end

@interface SGRPlayerSidebarMore : UIView
@property (nonatomic, strong) UIView *source;
@property (nonatomic, weak) UIView *originalParent;
@property (nonatomic, weak) UIView *ownerHost;
@property (nonatomic, strong) SGRPlayerMorePlaceholder *placeholder;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *originalConstraints;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *placeholderConstraints;
@property (nonatomic) NSUInteger originalIndex;
@property (nonatomic) NSUInteger arrangedIndex;
@property (nonatomic) BOOL originalTranslates;
@property (nonatomic) UIViewAutoresizing originalAutoresizing;
@property (nonatomic) CGAffineTransform originalTransform;
- (void)takeSource:(UIView *)source;
- (void)restoreSource;
@end

@implementation SGRPlayerSidebarMore
// Explicit targets and recognizers remain on source. Nil-target actions and menu-presenter
// lookups must also keep following the original header/controller responder chain.
- (UIResponder *)nextResponder { return self.originalParent ?: [super nextResponder]; }

- (void)takeSource:(UIView *)source {
    UIView *parent = source.superview;
    if (!parent) return;
    self.source = source;
    self.originalParent = parent;
    self.originalIndex = [parent.subviews indexOfObjectIdenticalTo:source];
    self.arrangedIndex = [parent isKindOfClass:UIStackView.class]
        ? [((UIStackView *)parent).arrangedSubviews indexOfObjectIdenticalTo:source] : NSNotFound;
    self.originalTranslates = source.translatesAutoresizingMaskIntoConstraints;
    self.originalAutoresizing = source.autoresizingMask;
    self.originalTransform = source.transform;

    SGRPlayerMorePlaceholder *placeholder = [[SGRPlayerMorePlaceholder alloc] initWithFrame:source.frame];
    placeholder.bounds = source.bounds;
    placeholder.center = source.center;
    placeholder.transform = source.transform;
    placeholder.reservedSize = source.bounds.size;
    placeholder.translatesAutoresizingMaskIntoConstraints = source.translatesAutoresizingMaskIntoConstraints;
    placeholder.autoresizingMask = source.autoresizingMask;
    placeholder.userInteractionEnabled = NO;
    placeholder.accessibilityElementsHidden = YES;
    for (NSNumber *axis in @[@(UILayoutConstraintAxisHorizontal), @(UILayoutConstraintAxisVertical)]) {
        [placeholder setContentHuggingPriority:[source contentHuggingPriorityForAxis:axis.integerValue] forAxis:axis.integerValue];
        [placeholder setContentCompressionResistancePriority:[source contentCompressionResistancePriorityForAxis:axis.integerValue] forAxis:axis.integerValue];
    }
    self.placeholder = placeholder;

    NSMutableArray *originals = [NSMutableArray array], *replacements = [NSMutableArray array];
    // Constraints owned above the button would be removed by UIKit on reparenting. Save the exact
    // objects for restoration and give their old endpoints to an inert, same-size placeholder.
    // UIStackView's generated constraints belong to its arranged-subview machinery, not to us.
    for (UIView *ancestor = parent; ancestor; ancestor = ancestor.superview) {
        for (NSLayoutConstraint *constraint in ancestor.constraints) {
            if (constraint.firstItem != source && constraint.secondItem != source) continue;
            if ([constraint.identifier hasPrefix:@"UISV-"] ||
                [NSStringFromClass(constraint.class) isEqualToString:@"NSAutoresizingMaskLayoutConstraint"]) continue;
            [originals addObject:constraint];
            NSLayoutConstraint *replacement = [NSLayoutConstraint constraintWithItem:constraint.firstItem == source ? placeholder : constraint.firstItem
                attribute:constraint.firstAttribute relatedBy:constraint.relation
                toItem:constraint.secondItem == source ? placeholder : constraint.secondItem attribute:constraint.secondAttribute
                multiplier:constraint.multiplier constant:constraint.constant];
            replacement.priority = constraint.priority;
            replacement.identifier = constraint.identifier;
            [replacements addObject:replacement];
        }
    }
    // The original retains its own size constraints. Copy button-only dimensions to reserve the
    // same space in the stack; never copy constraints to the original's glyphs or internal guides.
    for (NSLayoutConstraint *constraint in source.constraints) {
        if (constraint.firstItem != source || (constraint.secondItem && constraint.secondItem != source)) continue;
        NSLayoutConstraint *replacement = [NSLayoutConstraint constraintWithItem:placeholder attribute:constraint.firstAttribute
            relatedBy:constraint.relation toItem:constraint.secondItem ? placeholder : nil attribute:constraint.secondAttribute
            multiplier:constraint.multiplier constant:constraint.constant];
        replacement.priority = constraint.priority;
        [replacements addObject:replacement];
    }
    self.originalConstraints = originals;
    self.placeholderConstraints = replacements;
    [NSLayoutConstraint deactivateConstraints:originals];
    if (self.arrangedIndex != NSNotFound) {
        UIStackView *stack = (UIStackView *)parent;
        [stack removeArrangedSubview:source];
        [stack insertArrangedSubview:placeholder atIndex:MIN(self.arrangedIndex, stack.arrangedSubviews.count)];
    } else {
        [parent insertSubview:placeholder atIndex:MIN(self.originalIndex, parent.subviews.count)];
    }
    [source removeFromSuperview];
    [NSLayoutConstraint activateConstraints:replacements];
    source.translatesAutoresizingMaskIntoConstraints = YES;
    source.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    source.transform = CGAffineTransformIdentity;
    [self addSubview:source];
    source.frame = self.bounds;
}

- (void)restoreSource {
    UIView *source = self.source, *parent = self.originalParent;
    if (!source) return;
    [NSLayoutConstraint deactivateConstraints:self.placeholderConstraints];
    CGRect originalBounds = self.placeholder.bounds;
    CGPoint originalCenter = self.placeholder.center;
    NSUInteger index = self.placeholder.superview == parent ? [parent.subviews indexOfObjectIdenticalTo:self.placeholder] : self.originalIndex;
    if (self.arrangedIndex != NSNotFound && [parent isKindOfClass:UIStackView.class]) {
        UIStackView *stack = (UIStackView *)parent;
        [stack removeArrangedSubview:self.placeholder];
        [self.placeholder removeFromSuperview];
        [stack insertArrangedSubview:source atIndex:MIN(self.arrangedIndex, stack.arrangedSubviews.count)];
    } else if (parent) {
        [parent insertSubview:source atIndex:MIN(index, parent.subviews.count)];
    } else {
        [source removeFromSuperview];
    }
    [self.placeholder removeFromSuperview];
    source.translatesAutoresizingMaskIntoConstraints = self.originalTranslates;
    source.autoresizingMask = self.originalAutoresizing;
    source.bounds = originalBounds;
    source.center = originalCenter;
    source.transform = self.originalTransform;
    // Spotify can replace part of the header while the source is in the rail. A saved
    // relationship to a detached sibling must not be reactivated (UIKit would throw).
    if (parent) for (NSLayoutConstraint *constraint in self.originalConstraints) {
        id first = constraint.firstItem, second = constraint.secondItem;
        UIView *a = [first isKindOfClass:UILayoutGuide.class] ? [first owningView] : first;
        UIView *b = [second isKindOfClass:UILayoutGuide.class] ? [second owningView] : second;
        BOOL shared = !second;
        if ([a isKindOfClass:UIView.class] && [b isKindOfClass:UIView.class]) {
            for (UIView *ancestor = a; ancestor && !shared; ancestor = ancestor.superview)
                shared = b == ancestor || [b isDescendantOfView:ancestor];
        }
        if (shared) constraint.active = YES;
    }
    self.originalConstraints = nil;
    self.placeholderConstraints = nil;
    self.placeholder = nil;
    self.source = nil;
    self.originalParent = nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.source.frame = self.bounds;
}
@end

static char kSidebarMoreKey;

static UIView *headerMoreOutsideSidebar(UIView *view, UIView *sidebar) {
    if (view == sidebar) return nil;
    if ([view.accessibilityIdentifier isEqualToString:@"Context menu"]) return view;
    for (UIView *child in view.subviews) {
        UIView *found = headerMoreOutsideSidebar(child, sidebar);
        if (found) return found;
    }
    return nil;
}

static void removeSidebarMore(UIView *host) {
    SGRPlayerSidebarMore *sidebar = objc_getAssociatedObject(host, &kSidebarMoreKey);
    [sidebar restoreSource];
    [sidebar removeFromSuperview];
    objc_setAssociatedObject(host, &kSidebarMoreKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// A presented sheet must remain above the player. Only repair interception inside the player's
// existing presentation branch; never add the control to UIWindow or above another presentation.
static BOOL playerHasPresentedOverlay(UIView *host) {
    for (UIResponder *responder = host; responder; responder = responder.nextResponder) {
        if (![responder isKindOfClass:UIViewController.class]) continue;
        UIViewController *presented = ((UIViewController *)responder).presentedViewController;
        if (presented && ![host isDescendantOfView:presented.viewIfLoaded]) return YES;
    }
    return NO;
}

static void placeRealMoreAboveInterception(SGRPlayerSidebarMore *sidebar, UIView *host, CGRect frame) {
    UIView *container = host;
    for (;;) {
        if (sidebar.superview != container) [container addSubview:sidebar];
        sidebar.frame = [container convertRect:frame fromView:host];
        sidebar.source.frame = sidebar.bounds;
        [container bringSubviewToFront:sidebar];
        BOOL receivesHits = YES;
        for (NSValue *sample in @[[NSValue valueWithCGPoint:CGPointMake(24, 24)],
            [NSValue valueWithCGPoint:CGPointMake(2, 2)], [NSValue valueWithCGPoint:CGPointMake(46, 2)],
            [NSValue valueWithCGPoint:CGPointMake(2, 46)], [NSValue valueWithCGPoint:CGPointMake(46, 46)]]) {
            CGPoint point = [sidebar convertPoint:sample.CGPointValue toView:host.window];
            UIView *hit = [host.window hitTest:point withEvent:nil];
            if (hit != sidebar && ![hit isDescendantOfView:sidebar]) { receivesHits = NO; break; }
        }
        if (receivesHits) break;
        // Transparent siblings can cover a nested player. Move the small, player-owned holder up
        // one common presentation branch at a time, keeping its window position unchanged.
        UIView *parent = container.superview;
        if (!parent || [parent isKindOfClass:UIWindow.class]) break;
        container = parent;
    }
}

static void placeSidebarMore(UIView *host) {
    if (!host) return;
    BOOL visible = host.window != nil;
    for (UIView *ancestor = host; ancestor && visible; ancestor = ancestor.superview)
        visible = !ancestor.hidden && ancestor.alpha > 0.01;
    if (!visible || playerHasPresentedOverlay(host)) { removeSidebarMore(host); return; }
    SGRPlayerSidebarMore *sidebar = objc_getAssociatedObject(host, &kSidebarMoreKey);
    CGRect rail = SGRVerticalBarFrameIn(host, SGRVerticalBarExtent);
    CGRect visibleRail = CGRectIntersection(rail, host.bounds);
    BOOL fits = !CGRectIsNull(rail) && !CGRectIsNull(visibleRail) &&
        visibleRail.size.width >= 48 && visibleRail.size.height >= 56;
    UIView *source = headerMoreOutsideSidebar(host, sidebar);
    if (!source && [sidebar.originalParent isDescendantOfView:host]) source = sidebar.source;
    if (!fits || !source) { removeSidebarMore(host); return; }
    if (sidebar && sidebar.source != source) { removeSidebarMore(host); sidebar = nil; }
    if (!sidebar) {
        sidebar = [[SGRPlayerSidebarMore alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
        sidebar.accessibilityIdentifier = @"spotifyglass.player.sidebar-more";
        sidebar.ownerHost = host;
        sidebar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [sidebar takeSource:source];
        objc_setAssociatedObject(host, &kSidebarMoreKey, sidebar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect frame = CGRectMake(CGRectGetMidX(visibleRail) - 24, CGRectGetMinY(visibleRail) + 8, 48, 48);
    placeRealMoreAboveInterception(sidebar, host, frame);
    SGRGlassInside(source, &kGlassKey, SGRGlassCircleSize);
    SGPlayerMenuWatchMoreButton(source);
}

static void glassInside(UIViewController *unit, NSArray<NSString *> *identifiers, const void **findKeys) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    NSUInteger found = 0;
    for (NSUInteger i = 0; i < identifiers.count; i++) {
        UIView *button = SGRFindByIdentifier(host, identifiers[i], findKeys[i]);
        if (!button && [identifiers[i] isEqualToString:@"Context menu"]) {
            for (UIView *ancestor = host; ancestor && !button; ancestor = ancestor.superview) {
                SGRPlayerSidebarMore *sidebar = objc_getAssociatedObject(ancestor, &kSidebarMoreKey);
                if (sidebar.originalParent == host || [sidebar.originalParent isDescendantOfView:host]) {
                    button = sidebar.source;
                    button.frame = sidebar.bounds;
                }
            }
        }
        if (!button) {
            static NSMutableSet<NSString *> *missing;
            if (!missing) missing = [NSMutableSet set];
            if (![missing containsObject:identifiers[i]]) {
                [missing addObject:identifiers[i]];
                SGLog(@"redesign player: %@ not found in %@, left as Spotify's", identifiers[i], NSStringFromClass(host.class));
            }
            continue;
        }
        SGRGlassInside(button, &kGlassKey, SGRGlassCircleSize);
        if ([identifiers[i] isEqualToString:@"Context menu"]) SGPlayerMenuWatchMoreButton(button);
        found++;
    }

    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *unitName = NSStringFromClass(unit.class);
    if (![logged containsObject:unitName]) {
        [logged addObject:unitName];
        SGLog(@"redesign player: glass inside %lu of %lu buttons in %@", (unsigned long)found, (unsigned long)identifiers.count, unitName);
    }
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    static const void *keys[] = {&kCloseKey, &kMoreKey};
    glassInside((UIViewController *)self, @[@"now-playing-minimize-button", @"Context menu"], keys);
}
%end

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController
- (void)viewDidLayoutSubviews {
    %orig;
    placeSidebarMore(((UIViewController *)self).viewIfLoaded);
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    removeSidebarMore(host);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit", @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController"]);
}
