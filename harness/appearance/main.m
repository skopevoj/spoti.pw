#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRAppearance.h"
#import "Redesigned/Kit/SGRNativeTheme.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
extern BOOL SGTestNativeIsLight(void);
extern void SGTestNativeSetDark(void);

// Independent icon state for testing Swift-style direct property writes that bypass ObjC.
@interface SPTEncoreIconView : UIView
@property(nonatomic,strong) UIColor *foregroundColor;
@property(nonatomic,strong) UIColor *activeForegroundColor;
- (void)bypassForeground:(UIColor *)color active:(UIColor *)active;
@end
@implementation SPTEncoreIconView
- (void)bypassForeground:(UIColor *)color active:(UIColor *)active { _foregroundColor=color;_activeForegroundColor=active; }
@end

// Mock only the proven native semantic provider; bridge, colors, fields and glass are production code.
@interface SPTEncoreColorTheme : NSObject
+ (id)main; + (void)setMain:(id)value; + (id)light; + (id)dark;
@end
static BOOL envOn(const char *key) { const char *value = getenv(key); return value && value[0] == '1'; }
static id objcMain;
static BOOL rejectObjCWrites;
@implementation SPTEncoreColorTheme
+ (id)light { if (envOn("SG_TEST_NIL_THEME")) return nil; static id value; if (!value) value=[self new]; return value; }
+ (id)dark { static id value; if (!value) value=[self new]; return value; }
+ (id)main { return objcMain ?: [self dark]; }
+ (void)setMain:(id)value { if (rejectObjCWrites) return; objcMain = envOn("SG_TEST_REJECT_THEME") ? [self dark] : value; }
@end

__attribute__((constructor(101))) static void defaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
    const char *mode=getenv("SG_TEST_APPEARANCE");
    if (mode && strcmp(mode,"unset")) [NSUserDefaults.standardUserDefaults setInteger:atoi(mode) forKey:SGRKeyAppearance];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyAppearance];
}
static UIColor *chosenAccent;
UIColor *SGRAccentColor(void) { return chosenAccent; }
static int checks, failures;
static void expect(BOOL success, NSString *message) { checks++; if (!success) { failures++; NSLog(@"FAIL: %@", message); } }
static double linear(double c) { return c <= .04045 ? c/12.92 : pow((c+.055)/1.055, 2.4); }
static double luminance(UIColor *color, UIColor *background) {
    CGFloat r=0,g=0,b=0,a=1,br=0,bg=0,bb=0,ba=1;
    [color getRed:&r green:&g blue:&b alpha:&a]; [background getRed:&br green:&bg blue:&bb alpha:&ba];
    return .2126*linear(r*a+br*(1-a))+.7152*linear(g*a+bg*(1-a))+.0722*linear(b*a+bb*(1-a));
}
static double contrast(UIColor *ink, UIColor *background) {
    double a=luminance(ink,background),b=luminance(background,background); return (MAX(a,b)+.05)/(MIN(a,b)+.05);
}
#include "native-surface-tests.h"
#include "owned-live-tests.h"
#import "ambient-palette-tests.h"
#include "native-glyph-tests.h"
#include "live-theme-tests.h"
#include "native-chrome-tests.h"
#include "sheet-appearance-tests.h"
#include "status-bar-tests.h"

@interface Delegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic) NSUInteger systemTransitions;
- (void)recordSystemAppearance;
@end
@implementation Delegate
- (void)recordSystemAppearance {
    NSDictionary *state=@{@"style":@(SGRedesignAppearanceStyle()),@"transitions":@(self.systemTransitions),
        @"nativeLight":@(SGTestNativeIsLight()),@"objcLight":@(objcMain==[SPTEncoreColorTheme light]),
        @"status":SGRAppearanceStatus()};
    NSString *path=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"system-live.json"];
    [[NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path atomically:YES];
}
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    BOOL broken=envOn("SG_TEST_NIL_THEME") || envOn("SG_TEST_REJECT_THEME") || envOn("SG_TEST_REJECT_NATIVE_THEME");
    NSInteger mode=SGInt(SGRKeyAppearance,SGRAppearanceSystem);
    BOOL wantLight=!broken && (mode==1 || (mode==2 && UIScreen.mainScreen.traitCollection.userInterfaceStyle==UIUserInterfaceStyleLight));
    expect(SGRedesignLightAppearance()==wantLight,@"resolved mode and fail-closed behavior");
    expect(SGTestNativeIsLight()==wantLight,@"independent native Swift main matches owned kit");
    expect([SPTEncoreColorTheme main]==(wantLight ? [SPTEncoreColorTheme light] : [SPTEncoreColorTheme dark]),@"native main matches kit");
    if (!broken) {
        id originalObjC = objcMain;
        objcMain = wantLight ? [SPTEncoreColorTheme dark] : [SPTEncoreColorTheme light];
        expect([SGRAppearanceStatus() containsString:@"Retry appearance"],@"direct ObjC-wrapper drift is visible in applied status");
        objcMain = originalObjC;
        expect(SGRNativeThemeMatches(wantLight),@"native ABI readback matches selected theme");
        for (NSInteger i=0;i<1000;i++) expect(SGRSetNativeTheme(wantLight,nil),@"repeated native transfers retain valid Swift objects");
        BOOL rolledBack = !SGRSetNativeTheme(!wantLight,^BOOL{ return NO; });
        expect(rolledBack && SGTestNativeIsLight()==wantLight,@"failed ObjC commit rolls native Swift main back");
        SGTestNativeSetDark();
        expect(!wantLight || [SGRAppearanceStatus() containsString:@"Retry appearance"],@"native-only drift is visible in applied status");
        expect(SGRSetNativeTheme(wantLight,nil),@"restore selected native theme after drift fixture");
        [SPTEncoreColorTheme setMain:wantLight ? [SPTEncoreColorTheme dark] : [SPTEncoreColorTheme light]];
        expect([SPTEncoreColorTheme main]==(wantLight ? [SPTEncoreColorTheme light] : [SPTEncoreColorTheme dark]),@"native writes cannot drift away from selected appearance");
    }
    if (envOn("SG_TEST_REJECT_THEME")) {
        unsetenv("SG_TEST_REJECT_THEME");
        expect(SGRAppearanceApplyMode(SGRAppearanceLight,NO),@"initial provider rejection can recover without relaunch");
        [SPTEncoreColorTheme setMain:[SPTEncoreColorTheme dark]];
        expect(objcMain==[SPTEncoreColorTheme light] && SGTestNativeIsLight(),@"recovered bridge hooks pin the eventual selected theme");
        expect(SGRAppearanceApplyMode(SGRAppearanceDark,NO),@"recovery fixture restores dark fallback visuals");
        setenv("SG_TEST_REJECT_THEME","1",1);
    }
    nativeSurfaceChecks(wantLight);
    ownedLiveChecks();
    nativeChromeChecks();
    if (!broken) { liveThemeChecks(); sheetAppearanceChecks(); statusBarAppearanceChecks(); }
    nativeGlyphChecks(wantLight);
    ambientPaletteChecks();
    UIViewController *controller=[UIViewController new];
    controller.overrideUserInterfaceStyle=SGRedesignAppearanceStyle();
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=controller;
    [self.window makeKeyAndVisible];
    controller.view.backgroundColor=SGAppearanceColor(UIColor.whiteColor,UIColor.blackColor);
    CGFloat w=controller.view.bounds.size.width;
    SGRArtworkField *field=[[SGRArtworkField alloc] initWithFrame:controller.view.bounds];
    field.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    field.flows=YES;
    [controller.view addSubview:field];
    UIImage *art=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300,300)] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithRed:.05 green:.35 blue:.8 alpha:1] setFill]; UIRectFill(CGRectMake(0,0,300,300));
        [[UIColor colorWithRed:.8 green:.1 blue:.35 alpha:1] setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(75,-55,300,300)] fill];
    }];
    [field setArtwork:art identity:@"fixture" animated:NO];
    UIImageView *cover=[[UIImageView alloc] initWithImage:art];
    cover.frame=CGRectMake((w-220)/2,105,220,220); cover.layer.cornerRadius=12;cover.clipsToBounds=YES;
    [controller.view addSubview:cover];
    NSArray *texts=@[@"Appearance preview",@"Native theme • album artwork preserved",@"Live appearance, with scoped semantic roles"];
    NSArray *inks=@[SGRPrimary(),SGRSecondary(),SGRTertiary()];
    for (NSInteger i=0;i<3;i++) {
        UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(20,350+i*36,w-40,32)];
        label.text=texts[i];label.textColor=inks[i];label.textAlignment=NSTextAlignmentCenter;
        label.font=[UIFont systemFontOfSize:i?14:26 weight:i?UIFontWeightRegular:UIFontWeightBold];
        [controller.view addSubview:label];
    }
    static char key;
    UIButton *control=[[UIButton alloc] initWithFrame:CGRectMake((w-180)/2,492,180,50)];
    [control setTitle:@"▶  Play" forState:UIControlStateNormal];
    [control setTitleColor:SGRAccent() forState:UIControlStateNormal];
    [controller.view addSubview:control];
    UIView *glass=SGRGlassCapsuleInside(control,&key,control.bounds.size,YES);
    expect(glass.overrideUserInterfaceStyle==SGRedesignAppearanceStyle(),@"glass style matches foreground");
    CALayer *grey=[CALayer layer];grey.backgroundColor=[UIColor colorWithWhite:.07 alpha:1].CGColor;
    CGFloat g=CGColorGetComponents(grey.backgroundColor)[0];
    expect(wantLight ? fabs(g-.07)<.001 : g<.001,@"AMOLED hook disabled in light");
    expect(SGRIsBaseSurface(UIColor.whiteColor.CGColor)==wantLight,@"white surface detection limited to light");
    expect(!SGRIsBaseSurface(UIColor.redColor.CGColor),@"artwork colors never guessed as surfaces");
    expect(cover.image==art,@"artwork image retained without recoloring");
    [controller.view layoutIfNeeded];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if (wantLight) {
            expect(contrast(SGRPrimary(),field.fieldColor)>=7,@"light primary contrast");
            expect(contrast(SGRSecondary(),field.fieldColor)>=4.5,@"light secondary contrast");
            expect(contrast(SGRTertiary(),field.fieldColor)>=4.5,@"light tertiary contrast");
            expect(contrast(SGRAccent(),field.fieldColor)>=4.5,@"light accent contrast");
            for (UIColor *sample in @[UIColor.whiteColor, UIColor.yellowColor, UIColor.cyanColor, UIColor.greenColor,
                                      UIColor.magentaColor, UIColor.redColor, UIColor.blueColor, UIColor.blackColor]) {
                chosenAccent=sample;
                expect(contrast(SGRAccent(),[UIColor colorWithWhite:0.90 alpha:1])>=4.5,@"chosen accent stays readable on pale controls");
            }
            chosenAccent=nil;
            expect(luminance(field.fieldColor,UIColor.whiteColor)>.82,@"animated artwork surface stays pale");
        } else expect(contrast(SGRPrimary(),field.fieldColor)>=5.5,@"dark primary contrast");
        for (NSInteger i=0;i<50;i++) { field.frame=CGRectMake(0,0,i%2?852:393,i%2?393:852); [field setNeedsLayout]; [field layoutIfNeeded]; }
        field.frame=controller.view.bounds;[field layoutIfNeeded];
        expect(field.layer.sublayers.count==5,@"repeat resize does not accumulate appearance layers");
        UILabel *status=[[UILabel alloc] initWithFrame:CGRectMake(20,580,w-40,50)];
        status.numberOfLines=2;status.textAlignment=NSTextAlignmentCenter;status.textColor=SGRPrimary();
        status.text=[NSString stringWithFormat:@"%@ mode\n%d checks, %d failures",wantLight?@"Light":@"Dark",checks,failures];[controller.view addSubview:status];
        if (envOn("SG_TEST_SELECTOR")) {
            NSArray<SGModRow *> *rows=SGRAppearanceRows();
            SGModPage *page=[[SGModPage alloc] initWithTitle:@"Appearance" intro:nil sections:@[SGSection(nil,rows)] footer:nil];
            UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:page];
            self.window.rootViewController=nav;
            UITableViewController *picker=(UITableViewController *)rows.firstObject.page();
            [nav pushViewController:picker animated:NO];
            [picker.view layoutIfNeeded];
            NSInteger target=wantLight?SGRAppearanceDark:SGRAppearanceLight;
            [picker.tableView.delegate tableView:picker.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:target inSection:0]];
            expect(SGInt(SGRKeyAppearance,-1)==target,@"real settings choice persists exact appearance key");
            expect(SGRAppearanceNeedsRestart(),@"queued selection distinguished until main-queue transaction");
            expect(SGRedesignLightAppearance()==wantLight && SGTestNativeIsLight()==wantLight,@"picker coalesces before changing either provider");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
                expect(!SGRAppearanceNeedsRestart() && SGRedesignLightAppearance()!=wantLight && SGTestNativeIsLight()!=wantLight,@"real picker applies native and owned appearance live");
                expect(!nav.presentedViewController && nav.topViewController==page,@"picker returns without a restart alert or navigation reconstruction");
                NSLog(@"APPEARANCE CHECKS: %d checks, %d failures -- %@",checks,failures,failures?@"FAIL":@"PASS");
            });
        } else NSLog(@"APPEARANCE CHECKS: %d checks, %d failures -- %@",checks,failures,failures?@"FAIL":@"PASS");
        if (envOn("SG_TEST_LIVE_SYSTEM")) {
            self.systemTransitions=0;
            SGRegisterAppearanceRefresh(self, ^(id owner) {
                Delegate *delegate=owner;
                delegate.systemTransitions++;
                [delegate recordSystemAppearance];
            });
            [self recordSystemAppearance];
            NSLog(@"SYSTEM LIVE READY");
        }
    });
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(Delegate.class)); } }
