// Spotify 9.1.94: player preferredStatusBarStyle at 0x105ca6f60 returns LightContent;
// page host at 0x105886c28 reads statusBarSettings. Root's child getter at 0x102f70778
// delegates to native content: preserve that routing exactly, including OS/media flows.
#import "Core/SGCore.h"
#import "SGRNativeSurface.h"
#import "SGRStatusBarAppearance.h"

static NSHashTable<UIViewController *> *owners;
static NSObject *refreshOwner;
static void track(UIViewController *owner) {
    if (!NSThread.isMainThread || !SGRedesignedUI()) return;
    if (!owners) owners=[NSHashTable weakObjectsHashTable];
    [owners addObject:owner];
    if (!refreshOwner) {
        refreshOwner=[NSObject new];
        SGRegisterAppearanceRefresh(refreshOwner,^(id ignored) {
            for (UIViewController *controller in owners.allObjects)
                [controller setNeedsStatusBarAppearanceUpdate];
        });
    }
}
static BOOL knownStyleOwner(UIViewController *owner) {
    NSString *name=NSStringFromClass(owner.class);
    return [name isEqualToString:@"_TtC33Navigation_PageAPIIntegrationImpl35IdentifiedPageHostingViewController"] ||
        [name isEqualToString:@"Navigation_PageAPIIntegrationImpl.IdentifiedPageHostingViewController"] ||
        [name isEqualToString:@"_TtC19NowPlaying_ViewImpl37NowPlayingViewContainerViewController"] ||
        [name isEqualToString:@"NowPlaying_ViewImpl.NowPlayingViewContainerViewController"];
}
UIStatusBarStyle SGRNativeStatusBarStyle(UIViewController *owner, UIStatusBarStyle nativeStyle) {
    if (!SGRedesignedUI() || !NSThread.isMainThread || !knownStyleOwner(owner)) return nativeStyle;
    track(owner);
    // Unknown/native-only content gets its own status choice. A presented fullscreen
    // media/auth/OS controller keeps native delegation instead of inheriting this policy.
    UIViewController *presented=owner.presentedViewController;
    if (presented && !knownStyleOwner(presented) &&
        (presented.modalPresentationStyle==UIModalPresentationFullScreen ||
         presented.modalPresentationStyle==UIModalPresentationOverFullScreen)) return nativeStyle;
    if (!SGRNativeSurfaceHasRootWithin(owner.viewIfLoaded)) return nativeStyle;
    return SGRedesignLightAppearance()?UIStatusBarStyleDarkContent:UIStatusBarStyleLightContent;
}

%group SGRStatusBarAppearanceHooks
%hook _TtC33Navigation_PageAPIIntegrationImpl35IdentifiedPageHostingViewController
- (UIStatusBarStyle)preferredStatusBarStyle { return SGRNativeStatusBarStyle((id)self,%orig); }
- (void)viewDidAppear:(BOOL)animated { %orig; track((id)self); [(UIViewController *)self setNeedsStatusBarAppearanceUpdate]; }
%end
%hook _TtC19NowPlaying_ViewImpl37NowPlayingViewContainerViewController
- (UIStatusBarStyle)preferredStatusBarStyle { return SGRNativeStatusBarStyle((id)self,%orig); }
- (void)viewDidAppear:(BOOL)animated { %orig; track((id)self); [(UIViewController *)self setNeedsStatusBarAppearanceUpdate]; }
%end
%hook _TtC30ContainerUI_RootUIInternalImpl18RootViewController
- (UIViewController *)childViewControllerForStatusBarStyle {
    track((id)self);
    return %orig;
}
%end
%end
%ctor { if (!SGRedesignedUI()) return; %init(SGRStatusBarAppearanceHooks); }
