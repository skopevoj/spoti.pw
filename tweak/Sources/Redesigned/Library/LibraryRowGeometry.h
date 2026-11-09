// Live 9.1.94 row: Playlist.Row.Library owns one AutoLayoutStackView constrained
// top/bottom +/-8, leading/trailing +/-16. Keep cells and separators full width;
// apply the system/rail exclusion only to this verified inner content container.
static void SGRLibraryInsetRowContent(UIView *cell) {
    static char rowKey, constraintsKey, observedKey;
    __block UIView *row = objc_getAssociatedObject(cell, &rowKey);
    if (!row || ![row isDescendantOfView:cell]) {
        row = nil;
        SGForEachView(cell, ^(UIView *view) {
            if (!row && [@[@"Playlist.Row.Library", @"Album.Row.Library", @"Podcast.Row.Library"] containsObject:view.accessibilityIdentifier ?: @""])
                row = view;
        });
        if (row) objc_setAssociatedObject(cell, &rowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!row) return;
    if (!objc_getAssociatedObject(row, &observedKey)) {
        objc_setAssociatedObject(row, &observedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakCell = cell;
        SGRObserveLayout(row, ^(UIView *view) {
            UIView *owner = weakCell;
            if (owner && [view isDescendantOfView:owner]) SGRLibraryInsetRowContent(owner);
        });
    }
    BOOL vertical = !CGRectIsNull(SGRVerticalBarFrameIn(row, SGRVerticalBarExtent));
    NSArray *records = objc_getAssociatedObject(row, &constraintsKey);
    if (!records && vertical) {
        for (UIView *stack in row.subviews) {
            if (![NSStringFromClass(stack.class) containsString:@"AutoLayoutStackView"]) continue;
            NSMutableArray *found = [NSMutableArray array];
            NSUInteger verifiedEdges = 0;
            for (NSLayoutConstraint *constraint in row.constraints) {
                if (constraint.firstItem != stack || constraint.secondItem != row
                    || constraint.firstAttribute != constraint.secondAttribute || !constraint.active
                    || constraint.relation != NSLayoutRelationEqual || constraint.multiplier != 1) continue;
                NSLayoutAttribute edge = constraint.firstAttribute;
                CGFloat expected = edge == NSLayoutAttributeTop ? 8 : edge == NSLayoutAttributeBottom ? -8
                    : edge == NSLayoutAttributeLeading ? 16 : edge == NSLayoutAttributeTrailing ? -16 : NAN;
                if (fabs(constraint.constant - expected) > 0.01 || isnan(expected)) continue;
                verifiedEdges++;
                if (edge == NSLayoutAttributeLeading || edge == NSLayoutAttributeTrailing)
                    [found addObject:@[constraint, @(constraint.constant)]];
            }
            if (verifiedEdges == 4 && found.count == 2) { records = found; break; }
        }
        if (records) objc_setAssociatedObject(row, &constraintsKey, records, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIEdgeInsets clearance = UIEdgeInsetsZero;
    if (vertical) {
        clearance = SGRVerticalBarContentInsets(row, SGRVerticalBarExtent);
        clearance.left = MAX(clearance.left, row.safeAreaInsets.left);
        clearance.right = MAX(clearance.right, row.safeAreaInsets.right);
    }
    BOOL rtl = row.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    for (NSArray *record in records) {
        NSLayoutConstraint *constraint = record[0];
        BOOL leading = constraint.firstAttribute == NSLayoutAttributeLeading;
        CGFloat inset = (leading != rtl) ? clearance.left : clearance.right;
        CGFloat desired = [record[1] doubleValue] + (leading ? inset : -inset);
        if (fabs(constraint.constant - desired) > 0.01) constraint.constant = desired;
    }
}
