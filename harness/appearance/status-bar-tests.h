#import "Redesigned/Kit/SGRStatusBarAppearance.h"
static char statusUpdateCount;
static void recordStatusUpdate(id self, SEL selector) {
    NSUInteger count=[objc_getAssociatedObject(self,&statusUpdateCount) unsignedIntegerValue];
    objc_setAssociatedObject(self,&statusUpdateCount,@(count+1),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void statusBarAppearanceChecks(void) {
    NSInteger saved=SGInt(SGRKeyAppearance,SGRAppearanceSystem);
    SGRAppearanceApplyMode(SGRAppearanceLight,NO);
    for (NSString *name in @[@"_TtC33Navigation_PageAPIIntegrationImpl35IdentifiedPageHostingViewController",
                             @"_TtC19NowPlaying_ViewImpl37NowPlayingViewContainerViewController"]) {
        Class cls=NSClassFromString(name);
        if(!cls) {
            cls=objc_allocateClassPair(UIViewController.class,name.UTF8String,0);
            class_addMethod(cls,@selector(setNeedsStatusBarAppearanceUpdate),(IMP)recordStatusUpdate,"v@:");
            objc_registerClassPair(cls);
        }
        UIViewController *owner=[cls new];
        expect(SGRNativeStatusBarStyle(owner,UIStatusBarStyleLightContent)==UIStatusBarStyleLightContent && !owner.isViewLoaded,@"unloaded status owner stays native and is not forced to load");
        owner.view=[UIView new];
        expect(SGRNativeStatusBarStyle(owner,UIStatusBarStyleLightContent)==UIStatusBarStyleLightContent,@"known host with native-only content retains native status choice");
        UIView *page=[UIView new];[owner.view addSubview:page];SGRApplyNativeLightSurface(page,YES);
        expect(SGRNativeStatusBarStyle(owner,UIStatusBarStyleLightContent)==UIStatusBarStyleDarkContent,@"proven page/player owner with registered Light page requests dark status ink");
        NSUInteger before=[objc_getAssociatedObject(owner,&statusUpdateCount) unsignedIntegerValue];
        SGRAppearanceApplyMode(SGRAppearanceDark,NO);
        expect(SGRNativeStatusBarStyle(owner,UIStatusBarStyleDarkContent)==UIStatusBarStyleLightContent,@"known Dark page/player requests light status ink");
        expect([objc_getAssociatedObject(owner,&statusUpdateCount) unsignedIntegerValue]>before,@"live appearance invalidates tracked status owner without changing child routing");
        [page removeFromSuperview];
        SGRAppearanceApplyMode(SGRAppearanceLight,NO);
        expect(SGRNativeStatusBarStyle(owner,UIStatusBarStyleLightContent)==UIStatusBarStyleLightContent,@"host whose themed page left relinquishes status styling");
    }
    UIViewController *unrelated=[UIViewController new];unrelated.view=[UIView new];SGRApplyNativeLightSurface(unrelated.view,YES);
    expect(SGRNativeStatusBarStyle(unrelated,UIStatusBarStyleLightContent)==UIStatusBarStyleLightContent,@"unrelated media/auth/OS controller is not styled even with a registered descendant");
    expect(SGRAppearanceApplyMode(saved,NO),@"status fixture restores requested appearance");
}
