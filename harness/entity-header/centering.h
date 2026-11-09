// Runs production album/artist hooks, not a duplicate of their frame calculation.
// Expected column comes independently from UIKit's page safe-area layout guide.
static void entityHeaderChecks(UIView *page, UIView *host, UIView *trigger) {
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
  UIWindow *window = page.window;
  CGRect original = window.frame, originalHost = host.frame;
  BOOL duo = window.safeAreaInsets.right > 60 || window.safeAreaInsets.left > 60;
  NSUInteger checks=0, failures=0;
  BOOL checkedHero=NO;
  NSArray *sizes = duo ? @[@466,@669,@951,@466] : @[@320,@402,@466,@320];
  for (NSNumber *width in sizes) {
   window.frame = CGRectMake(original.origin.x, original.origin.y, width.doubleValue, 678);
   window.rootViewController.view.frame = window.bounds;
   page.frame = window.bounds;
   for (UIView *ancestor=host.superview;ancestor && ancestor!=page;ancestor=ancestor.superview) {
    CGRect f=ancestor.frame; f.size.width=width.doubleValue; ancestor.frame=f;
   }
   [window layoutIfNeeded]; [page layoutIfNeeded];
   CGRect column = duo ? page.safeAreaLayoutGuide.layoutFrame : page.bounds;
   for (NSUInteger mode=0;mode<3;mode++) for (NSUInteger state=0;state<3;state++) {
    // A full-width host, a translated host, and one already inset to the rows.
    CGRect region = mode==2 ? column : page.bounds;
    if (mode==1) { region.origin.x += 13; region.size.width -= 13; }
    CGRect local = [host.superview convertRect:region fromView:page];
    host.frame = CGRectMake(local.origin.x, state==1 ? -200 : state==2 ? 30 : 0,
                            region.size.width, state==1 ? 220 : 568);
    for (NSUInteger pass=0;pass<4;pass++) {
     [page setNeedsLayout]; [page layoutIfNeeded];
     [trigger setNeedsLayout]; [trigger layoutIfNeeded];
     [host setNeedsLayout]; [host layoutIfNeeded];
    }
    UIView *info=nil;
    for (UIView *child in host.subviews) if ([NSStringFromClass(child.class) isEqualToString:@"SGRHeaderInfo"]) info=child;
    [info setNeedsLayout]; [info layoutIfNeeded];
    CGRect expected = duo ? CGRectIntersection(column,region) : region;
    CGRect actual = [page convertRect:info.bounds fromView:info];
    BOOL ok = info && fabs(actual.origin.x-expected.origin.x)<0.51 && fabs(actual.size.width-expected.size.width)<0.51;
    NSUInteger texts=0, buttons=0;
    CGRect controls=CGRectNull;
    for (UIView *child in info.subviews) {
     if (child.hidden) continue;
     CGRect f=[page convertRect:child.bounds fromView:child];
     BOOL text=[child isKindOfClass:UILabel.class] && ((UILabel *)child).textAlignment==NSTextAlignmentCenter;
     BOOL play=[NSStringFromClass(child.class) isEqualToString:@"SGRPlayCapsule"];
     BOOL button=play || [NSStringFromClass(child.class) isEqualToString:@"SGRMirrorButton"];
     if(text || play) ok &= fabs(CGRectGetMidX(f)-CGRectGetMidX(expected))<0.51;
     if(text) texts++;
     if(button) { buttons++; controls=CGRectUnion(controls,f); }
    }
    ok &= texts>=2 && buttons==3 && CGRectGetMinX(controls)>=CGRectGetMinX(expected) && CGRectGetMaxX(controls)<=CGRectGetMaxX(expected);
    if (!checkedHero) {
     checkedHero=YES;
     UIView *hero=nil; UILabel *title=nil;
     for (UIView *child in host.subviews) if ([NSStringFromClass(child.class) hasSuffix:@"Hero"]) hero=child;
     for (UIView *child in info.subviews) if ([child isKindOfClass:UILabel.class] && (child.accessibilityTraits & UIAccessibilityTraitHeader)) title=(UILabel *)child;
     CGFloat narrow=[title sizeThatFits:CGSizeMake(info.bounds.size.width-40,CGFLOAT_MAX)].height;
     CGFloat full=[title sizeThatFits:CGSizeMake(host.bounds.size.width-40,CGFLOAT_MAX)].height;
     BOOL heroOK=hero && title && fabs(hero.frame.size.width-host.bounds.size.width)<0.51
       && fabs(hero.frame.size.height-round(CGRectGetMinY(title.frame)+56))<0.51;
     if(duo) heroOK &= narrow > full;
     checks++; if(!heroOK) failures++;
     NSLog(@"[harness] wrapping hero narrow=%.1f full=%.1f hero=%.1f titleY=%.1f -- %@",narrow,full,hero.frame.size.height,title.frame.origin.y,heroOK?@"PASS":@"FAIL");
    }
    checks++; if(!ok) failures++;
    NSLog(@"[harness] entity centering width=%@ mode=%lu state=%lu info=%@ expected=%@ -- %@",width,(unsigned long)mode,(unsigned long)state,NSStringFromCGRect(actual),NSStringFromCGRect(expected),ok?@"PASS":@"FAIL");
   }
  }
  window.frame=original; host.frame=originalHost;
  NSLog(@"[harness] entity centering checks: %lu cases, %lu failures -- %@",(unsigned long)checks,(unsigned long)failures,failures?@"FAIL":@"PASS");
 });
}
