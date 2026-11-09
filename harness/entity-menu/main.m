// Real UINavigationController / Back, production SGRPinnedMore and source forwarding.
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRActionRow.h"
#import "Redesigned/Kit/SGRBarGeometry.h"
static int checks, failures;
static void check(BOOL ok, NSString *label) { checks++; if (!ok) failures++; NSLog(@"CHECK %@ %@",ok?@"PASS":@"FAIL",label); }
static char key;
@interface Page : UIViewController
@property(nonatomic,strong) UIButton *source;
@property(nonatomic,strong) SGRMirrorButton *more;
@property(nonatomic) NSUInteger taps;
@property(nonatomic) BOOL stopFeeding;
@end
@implementation Page
- (void)viewDidLoad {
 [super viewDidLoad]; self.view.backgroundColor=[UIColor colorWithWhite:.08 alpha:1];
 self.source=[UIButton buttonWithType:UIButtonTypeSystem]; self.source.accessibilityLabel=@"More options";
 self.source.frame=CGRectMake(30,300,60,44); self.source.alpha=0; [self.view addSubview:self.source];
 [self.source addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
 UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(30,100,300,60)]; label.text=self.title; label.textColor=UIColor.whiteColor; label.font=[UIFont boldSystemFontOfSize:28]; [self.view addSubview:label];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; if(!self.stopFeeding) self.more=SGRPinnedMore(self.view,&key,self.source); }
- (void)tapped { self.taps++; check(SGRPinnedMoreRecentPage()==self.view,@"recorder identifies tapped page before source fires"); }
@end
static void verify(Page *p, NSString *phase) {
 UIWindow *w=p.view.window; CGRect f=[p.more convertRect:p.more.bounds toView:w]; CGRect rail=SGRVerticalBarFrameIn(w,52);
 check(p.more.superview==p.view,[phase stringByAppendingString:@" remains page owned"]);
 check(f.size.width>=44 && f.size.height>=44,[phase stringByAppendingString:@" 44pt target"]);
 if(!CGRectIsNull(rail)) {
  CGFloat reserve=SGRVerticalBarTopReservation(rail.size.height);
  CGRect candidate=CGRectMake(CGRectGetMidX(rail)-22,rail.origin.y+60,44,44);
  UINavigationBar *bar=p.navigationController.navigationBar;
  CGRect barFrame=[bar convertRect:bar.bounds toView:w];
  if(CGRectIntersectsRect(barFrame,candidate)) candidate.origin.y=CGRectGetMaxY(barFrame)+8;
  BOOL fits=reserve>=112 && CGRectContainsRect(rail,candidate) && CGRectGetMaxY(candidate)+8<=rail.origin.y+reserve;
  check(p.more.hidden==!fits,[phase stringByAppendingString:@" hides only when reserved slot cannot fit"]);
  if(!fits) { NSLog(@"GEOMETRY %@ safely hidden; rail=%@",phase,NSStringFromCGRect(rail)); return; }
  check(CGRectGetMaxY(f)+8<=rail.origin.y+reserve,[phase stringByAppendingString:@" clear of bottom navigation reservation"]);
  check(fabs(CGRectGetMidX(f)-CGRectGetMidX(rail))<.5 && CGRectGetMinY(f)>=CGRectGetMinY(rail)+60,[phase stringByAppendingString:@" below Back slot, centered in rail"]);
  CGPoint back=CGPointMake(CGRectGetMidX(rail),CGRectGetMinY(rail)+24);
  UIView *backHit=[w hitTest:back withEvent:nil];
  check(backHit && ![backHit isDescendantOfView:p.view],[phase stringByAppendingFormat:@" native Back reachable (%@)",NSStringFromClass(backHit.class)]);
 } else check(fabs(f.origin.x-(w.bounds.size.width-60))<.5 && fabs(f.origin.y-w.safeAreaInsets.top)<.5,[phase stringByAppendingString:@" phone corner unchanged"]);
 CGPoint points[]={{.5,.5},{.025,.025},{.975,.025},{.025,.975},{.975,.975}};
 for(int i=0;i<5;i++) {
  CGPoint point=CGPointMake(f.origin.x+f.size.width*points[i].x,f.origin.y+f.size.height*points[i].y);
  UIView *hit=[w hitTest:point withEvent:nil];
  check(hit==p.more || [hit isDescendantOfView:p.more],[phase stringByAppendingFormat:@" hit %d (%@)",i,NSStringFromClass(hit.class)]);
 }
 NSLog(@"GEOMETRY %@ frame=%@ rail=%@",phase,NSStringFromCGRect(f),NSStringFromCGRect(rail));
}
static void later(NSTimeInterval delay, dispatch_block_t work) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,delay*NSEC_PER_SEC),dispatch_get_main_queue(),work); }
@interface App : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation App
- (UISceneConfiguration *)application:(UIApplication *)a configurationForConnectingSceneSession:(UISceneSession *)s options:(UISceneConnectionOptions *)o {
 UISceneConfiguration *c=[[UISceneConfiguration alloc] initWithName:@"Menu" sessionRole:s.role]; c.delegateClass=self.class; return c;
}
- (void)scene:(UIScene *)s willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)o {
 self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)s];
 UIViewController *root=[UIViewController new]; root.title=@"Library";
 UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:root];
 Page *page=[Page new]; page.title=@"Playlist";
 [nav pushViewController:page animated:NO]; self.window.rootViewController=nav; [self.window makeKeyAndVisible];
 later(2, ^{
  for (CGFloat height=0; height<=700; height+=10) {
   CGFloat reserve=SGRVerticalBarTopReservation(height);
   check(reserve>=0 && reserve<=height && height-reserve>=MIN(height,SGRVerticalBarNavigationRowHeight(NO)+4),@"short rail preserves navigation row");
  }
  verify(page,@"playlist");
  for(int i=0;i<8;i++) { SGRPinnedMore(page.view,&key,page.source); }
  [page.more sendActionsForControlEvents:UIControlEventTouchDown]; [page.more sendActionsForControlEvents:UIControlEventTouchUpInside];
  check(page.taps==1,@"repeated feeding produces exactly one source action");
  SGRPinnedMore(page.view,&key,nil); check(page.more.hidden,@"missing source hides menu"); SGRPinnedMore(page.view,&key,page.source);
  UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:page.view.bounds]; scroll.contentSize=CGSizeMake(300,3000); [page.view insertSubview:scroll atIndex:0]; scroll.contentOffset=CGPointMake(0,450); verify(page,@"scrolled");
  UIViewController *sheet=[UIViewController new]; sheet.view.backgroundColor=UIColor.darkGrayColor; sheet.modalPresentationStyle=UIModalPresentationFullScreen;
  [page presentViewController:sheet animated:NO completion:^{
   CGPoint pt=[page.more convertPoint:CGPointMake(22,22) toView:self.window];
   check(![[self.window hitTest:pt withEvent:nil] isDescendantOfView:page.view],@"presented sheet owns hits; menu does not overlay");
   [sheet dismissViewControllerAnimated:NO completion:^{
    verify(page,@"dismissed");
    [page.more sendActionsForControlEvents:UIControlEventTouchDown]; [page.more sendActionsForControlEvents:UIControlEventTouchUpInside]; check(page.taps==2,@"menu reopens once after dismissal");
    for(NSString *name in @[@"Album",@"Artist",@"Playlist again"]) {
     Page *next=[Page new]; next.title=name; [nav pushViewController:next animated:NO]; [nav.view layoutIfNeeded]; [next.view layoutIfNeeded]; verify(next,name);
     [next.more sendActionsForControlEvents:UIControlEventTouchDown]; [next.more sendActionsForControlEvents:UIControlEventTouchUpInside]; check(next.taps==1,[name stringByAppendingString:@" own source once"]);
     check(SGRPinnedMoreRecentPage()==next.view,[name stringByAppendingString:@" page identity"]);
     [nav popViewControllerAnimated:NO]; [nav.view layoutIfNeeded];
    }
    verify(page,@"returned");
    page.stopFeeding=YES; CGRect original=self.window.frame; CGRect smaller=original; smaller.size.width-=70; smaller.size.height-=80; self.window.frame=smaller;
    later(.3,^{
     [self.window layoutIfNeeded]; verify(page,@"resize without header feed"); self.window.frame=original;
     later(.3,^{
      [self.window layoutIfNeeded]; verify(page,@"restored without header feed");
      CGRect shortFrame=original; shortFrame.size.height=130; self.window.frame=shortFrame;
      later(.3,^{
       [self.window layoutIfNeeded]; verify(page,@"short window"); self.window.frame=original;
       later(.3,^{ [self.window layoutIfNeeded]; verify(page,@"restored after short window"); NSLog(@"ENTITY MENU CHECKS: %d checks, %d failures -- %@",checks,failures,failures?@"FAIL":@"PASS"); });
      });
     });
    });
   }];
  }];
 });
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class)); } }
