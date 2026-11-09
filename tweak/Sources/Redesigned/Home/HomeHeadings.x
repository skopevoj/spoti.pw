// Home redesign: a shelf's heading at the Music app's size, the title 2 style in bold (22pt at the default
// text size) over Spotify's 17pt. The title is a label of the Kit's own on the same baseline, drawn over
// Spotify's, which goes transparent: Spotify's label measures the heading, so the shelf keeps its layout,
// and the heading button keeps its touch and its accessibility label. The larger title reaches a few
// points up into the gap above the shelf. A small line over the title ("For fans of") and the artist's
// picture beside it stay Spotify's.
//
// The label is held on Spotify's by constraints, not by a frame worked out here: a heading with a picture lays
// its labels out in a stack of its own, which is positioned after this hook has run, so a frame taken here put
// the title over the artist's picture at the leading edge, and a cell reused for a plain heading kept the
// place the picture had left (trees/continuous/1.txt:2533 and :2291, 2026-09-17). Spotify's label can also have
// no text yet when the button lays out, which left three of that tree's headings at Spotify's own size, so a
// heading with nothing to draw on is looked at again on the next turn of the run loop, a few times at most.
//
// Tree (trees/continuous/1.txt:2289-2312, 2026-09-17): Element_List.SupplementaryItemView 370x48 >
// ... > UIView id=Components.UI.SectionHeadingHome > AutoLayoutStackView > UIView > NoIntrinsicContentSizeButton
// (a11y "For fans of  Yzomandias"), under which an ImageViewHolder 48x48 and a stack of SPTEncoreLabels:
// "For fans of " 11pt #B3B3B3, "Yzomandias" 17pt #FFFFFF at {0, 19.3} 91x20.7, and a hidden one. A heading
// of a title alone is 20.7 tall (10.txt:2363). "Show all" is Components.UI.NavigationButtonHome, a sibling
// of the button's stack, 0 wide while it is not offered.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

static char kTitleKey, kShowAllKey, kHeldKey, kTriesKey;

// How often a heading with no title yet is looked at again.
static const NSUInteger kTries = 3;

// What the title is held on, so the constraints are made again only when it changes.
@interface SGRHeadingHold : NSObject
@property (nonatomic, weak) UILabel *label;
@property (nonatomic, weak) UIView *limit;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *constraints;
@end

@implementation SGRHeadingHold
@end

static UIView *headingAround(UIView *button) {
    NSUInteger depth = 0;
    for (UIView *v = button.superview; v && depth < 4; v = v.superview, depth++) {
        if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.SectionHeadingHome"]) return v;
    }
    return nil;
}

static BOOL shown(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) {
        if (v.hidden) return NO;
    }
    return YES;
}

// The label that is the title: the largest text showing under the button, its own label aside. A label the stack
// has not sized yet counts, since the constraints take its place from the layout rather than from its bounds.
static UILabel *titleLabelIn(UIView *button, UILabel *mine) {
    __block UILabel *title = nil;
    SGForEachView(button, ^(UIView *v) {
        if (v == mine || ![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (!label.text.length || !shown(label, button)) return;
        if (!title || label.font.pointSize > title.font.pointSize) title = label;
    });
    return title;
}

static void restyle(UIView *button) {
    UIView *heading = headingAround(button);
    if (!heading) return;
    UILabel *mine = objc_getAssociatedObject(button, &kTitleKey);
    UILabel *theirs = titleLabelIn(button, mine);
    SGRHeadingHold *held = objc_getAssociatedObject(button, &kHeldKey);
    if (!theirs) {
        // A heading between two shelves: nothing to hold the title on until its label has text again.
        mine.hidden = YES;
        if (held.constraints) [NSLayoutConstraint deactivateConstraints:held.constraints];
        objc_setAssociatedObject(button, &kHeldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!mine) {
        mine = [UILabel new];
        mine.userInteractionEnabled = NO;
        mine.accessibilityElementsHidden = YES;
        mine.lineBreakMode = NSLineBreakByTruncatingTail;
        mine.translatesAutoresizingMaskIntoConstraints = NO;
        objc_setAssociatedObject(button, &kTitleKey, mine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL added = mine.superview != button;
    if (added) [button addSubview:mine];
    mine.hidden = NO;

    UIFont *font = SGRFont(UIFontTextStyleTitle2, UIFontWeightBold, UIContentSizeCategoryLarge);
    if (![mine.font isEqual:font]) mine.font = font;
    if (![mine.text isEqualToString:theirs.text]) mine.text = theirs.text;
    UIColor *headingColor = SGAppearanceColor([UIColor colorWithWhite:0.08 alpha:1], theirs.textColor ?: UIColor.whiteColor);
    if (![mine.textColor isEqual:headingColor]) mine.textColor = headingColor;
    if (theirs.alpha != 0) theirs.alpha = 0;

    // The leading edge and the baseline are Spotify's label's; the title ends before "Show all", or before the
    // heading's trailing edge while there is none, and truncates rather than push anything.
    // Whether "Show all" is offered is read off the hidden flags, not off its width: it has none to go by until
    // the layout resolves, and a title held to the heading's own edge then ran under it.
    UIView *showAll = SGRFindByIdentifier(heading, @"Components.UI.NavigationButtonHome", &kShowAllKey);
    BOOL offered = showAll && shown(showAll, heading);
    UIView *limit = offered ? showAll : heading;
    if (added || held.label != theirs || held.limit != limit) {
        if (held.constraints) [NSLayoutConstraint deactivateConstraints:held.constraints];
        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
            [mine.leadingAnchor constraintEqualToAnchor:theirs.leadingAnchor],
            [mine.firstBaselineAnchor constraintEqualToAnchor:theirs.firstBaselineAnchor],
            [mine.trailingAnchor constraintLessThanOrEqualToAnchor:heading.trailingAnchor],
        ]];
        if (offered) [constraints addObject:[mine.trailingAnchor constraintLessThanOrEqualToAnchor:showAll.leadingAnchor constant:-SGRGrid]];
        [NSLayoutConstraint activateConstraints:constraints];
        held = [SGRHeadingHold new];
        held.label = theirs;
        held.limit = limit;
        held.constraints = constraints;
        objc_setAssociatedObject(button, &kHeldKey, held, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(button, &kTriesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign home: heading \"%@\" %.0fpt drawn at %.0fpt, held on Spotify's label", theirs.text, theirs.font.pointSize, font.pointSize); });
    }
}

// Looks again once the layout has settled, while the heading has no label with text to hold the title on.
static void restyleWhenReady(UIView *button) {
    if (objc_getAssociatedObject(button, &kHeldKey)) return;
    NSUInteger tries = [objc_getAssociatedObject(button, &kTriesKey) unsignedIntegerValue];
    if (tries >= kTries) return;
    objc_setAssociatedObject(button, &kTriesKey, @(tries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (button.window) restyle(button);
    });
}

%hook _TtCOOOE11Home_ECMKitO19LegacyUI_ECMCoreKit10Components18SectionHeadingHome2UI7Private28NoIntrinsicContentSizeButton
- (void)layoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    restyle((UIView *)self);
    restyleWhenReady((UIView *)self);
    SGRHomeProbeEnd(SGRHomeProbeHeadings, began);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtCOOOE11Home_ECMKitO19LegacyUI_ECMCoreKit10Components18SectionHeadingHome2UI7Private28NoIntrinsicContentSizeButton"]);
}
