// The production PlaylistHeader hooks and SGRHeaderInfo run here, not a copy of their layout.
// Live 9.1.94 Duo: the list spans 466pt but its rows span the 382pt safe column. The header's
// full-width root inherits 84pt on the right; its replacement info has no safe inset itself.
static void startHeaderCenteringChecks(UIViewController *page, UIView *header, UIView *layout,
                                       UIView *block, UIView *actions) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = page.view.window;
        CGRect initial = window.frame;
        CGRect initialPage = page.view.frame, initialHeader = header.frame, initialBlock = block.frame;
        NSMutableArray<UIView *> *ancestors = [NSMutableArray array];
        NSMutableArray<NSValue *> *frames = [NSMutableArray array];
        for (UIView *view = layout; view && view != header; view = view.superview) {
            [ancestors addObject:view]; [frames addObject:[NSValue valueWithCGRect:view.frame]];
        }
        NSUInteger failures = 0, checks = 0;
        BOOL vertical = !CGRectIsNull(SGRVerticalBarFrameIn(window, SGRVerticalBarExtent));
        NSArray<NSValue *> *sizes = vertical
            ? @[[NSValue valueWithCGSize:CGSizeMake(466, 678)], [NSValue valueWithCGSize:CGSizeMake(669, 951)],
                [NSValue valueWithCGSize:CGSizeMake(951, 669)], [NSValue valueWithCGSize:CGSizeMake(466, 678)]]
            : @[[NSValue valueWithCGSize:CGSizeMake(320, 667)], [NSValue valueWithCGSize:CGSizeMake(402, 874)],
                [NSValue valueWithCGSize:CGSizeMake(466, 678)], [NSValue valueWithCGSize:CGSizeMake(320, 667)]];
        for (NSValue *value in sizes) {
            CGSize size = value.CGSizeValue;
            window.frame = (CGRect){initial.origin, size};
            page.view.frame = window.bounds;
            [page.view setNeedsLayout];
            [page.view layoutIfNeeded];
            UIEdgeInsets safe = page.view.safeAreaInsets;
            CGRect rows = page.view.bounds;
            BOOL foundRows = NO;
            for (UIView *list in page.view.subviews) {
                if (![list.accessibilityIdentifier isEqualToString:@"SPTFreeTierPlaylistTableView"]) continue;
                for (UIView *cell in list.subviews) {
                    if (![cell.accessibilityIdentifier hasPrefix:@"Playlist.ItemCell"]) continue;
                    rows = [page.view convertRect:cell.bounds fromView:cell];
                    foundRows = YES;
                    break;
                }
            }
            // Full-width, a block with an inherited horizontal offset, and a header Spotify has
            // already constrained to the rows. The last must not lose the rail's width twice.
            for (NSUInteger mode = 0; mode < 3; mode++) {
                CGRect host = mode == 2 ? rows : page.view.bounds;
                for (NSUInteger state = 0; state < 3; state++) {
                    BOOL collapsed = state == 1, pulled = state == 2;
                    header.frame = CGRectMake(host.origin.x, collapsed ? -260 : pulled ? 30 : -72,
                                              host.size.width, collapsed ? 210 : 360);
                    for (UIView *ancestor = layout; ancestor && ancestor != header; ancestor = ancestor.superview) {
                        CGRect f = ancestor.frame;
                        f.size.width = host.size.width;
                        ancestor.frame = f;
                    }
                    CGFloat offset = mode == 1 ? 13 : 0;
                    block.frame = CGRectMake(offset, collapsed ? -26 : pulled ? 170 : 129,
                                             host.size.width - 16 - offset, collapsed ? 70 : pulled ? 150 : 115);
                    [header setNeedsLayout]; [header layoutIfNeeded];
                    [layout setNeedsLayout]; [layout layoutIfNeeded];
                    UIView *info = nil;
                    for (UIView *child in block.subviews) {
                        if ([NSStringFromClass(child.class) isEqualToString:@"SGRHeaderInfo"]) info = child;
                    }
                    for (NSUInteger pass = 0; pass < 4; pass++) {
                        // The row and block can lay out after the header. Their real observers must
                        // restore the same position without accumulating the inset on every pass.
                        [actions setNeedsLayout]; [actions layoutIfNeeded];
                        [block setNeedsLayout]; [block layoutIfNeeded];
                        [info setNeedsLayout]; [info layoutIfNeeded];
                    }
                    CGRect actual = [page.view convertRect:info.bounds fromView:info];
                    CGRect expected = vertical ? rows : host;
                    BOOL ok = info && foundRows && fabs(actual.origin.x - expected.origin.x) < 0.51
                        && fabs(actual.size.width - expected.size.width) < 0.51
                        && fabs(info.frame.origin.y) < 0.01
                        && fabs(info.bounds.size.height - block.bounds.size.height) < 0.01;
                    CGFloat midpoint = CGRectGetMidX(expected);
                    CGRect controls = CGRectNull;
                    NSUInteger textCount = 0, actionCount = 0;
                    for (UIView *child in info.subviews) {
                        if (child.hidden) continue;
                        CGRect f = [page.view convertRect:child.bounds fromView:child];
                        BOOL centeredText = [child isKindOfClass:UILabel.class]
                            && ((UILabel *)child).textAlignment == NSTextAlignmentCenter;
                        BOOL play = [NSStringFromClass(child.class) isEqualToString:@"SGRPlayCapsule"];
                        BOOL button = play || [NSStringFromClass(child.class) isEqualToString:@"SGRMirrorButton"];
                        if (centeredText || play) ok &= fabs(CGRectGetMidX(f) - midpoint) < 0.51;
                        if (centeredText) textCount++;
                        if (button) { controls = CGRectUnion(controls, f); actionCount++; }
                    }
                    ok &= textCount >= 2 && actionCount == 3
                        && fabs(CGRectGetMidX(controls) - midpoint) < 0.51
                        && CGRectGetMinX(controls) >= CGRectGetMinX(expected)
                        && CGRectGetMaxX(controls) <= CGRectGetMaxX(expected);
                    checks++; if (!ok) failures++;
                    NSLog(@"[harness] centering %.0fx%.0f mode=%lu state=%lu native=%d safe=%@ info=%@ rows=%@ actions=%@ -- %@",
                          size.width, size.height, (unsigned long)mode, (unsigned long)state, vertical,
                          NSStringFromUIEdgeInsets(safe), NSStringFromCGRect(actual), NSStringFromCGRect(expected),
                          NSStringFromCGRect(controls), ok ? @"PASS" : @"FAIL");
                }
            }
        }
        window.frame = initial;
        page.view.frame = initialPage;
        header.frame = initialHeader;
        for (NSUInteger i = 0; i < ancestors.count; i++) ancestors[i].frame = frames[i].CGRectValue;
        block.frame = initialBlock;
        [layout setNeedsLayout]; [layout layoutIfNeeded];
        NSLog(@"[harness] centering checks: %lu cases, %lu failures -- %@", (unsigned long)checks,
              (unsigned long)failures, failures ? @"FAIL" : @"PASS");
    });
}
