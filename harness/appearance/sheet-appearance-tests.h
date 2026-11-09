#import "Redesigned/Kit/SGRSheetAppearance.h"

// Reproduce the screenshots structurally: a presented owner missing from the page-root
// registry, forced-dark chrome, Light-origin native rows, and a white custom Speed row.
static void sheetAppearanceChecks(void) {
    NSInteger saved=SGInt(SGRKeyAppearance,SGRAppearanceSystem);
    expect(SGRAppearanceApplyMode(SGRAppearanceLight,NO),@"sheet fixture selects Light provider");
    UIViewController *sheet=[UIViewController new];
    sheet.view=[UIView new];sheet.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UIColor *nativeBacking=[UIColor colorWithWhite:.24 alpha:1];sheet.view.backgroundColor=nativeBacking;
    sheet.view.frame=CGRectMake(0,0,390,620);CGRect originalFrame=sheet.view.frame;
    UILabel *native=[UILabel new];native.text=@"Share";native.textColor=UIColor.blackColor;[sheet.view addSubview:native];
    UILabel *speed=[UILabel new];speed.text=@"Speed and pitch";speed.textColor=UIColor.whiteColor;[sheet.view addSubview:speed];
    expect(!SGRNativeSurfaceManaged(native),@"reproduction: newly presented context sheet has no page appearance owner");
    UIBlurEffect *nativeDarkEffect=[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *glass=[[UIVisualEffectView alloc]initWithEffect:nativeDarkEffect];
    glass.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[sheet.view addSubview:glass];
    UILabel *glassLabel=[UILabel new];glassLabel.textColor=UIColor.whiteColor;[glass.contentView addSubview:glassLabel];
    Class previewClass=NSClassFromString(@"_TtC12Share_ECMKit24SharePreviewScaffoldView");
    if(!previewClass) {previewClass=objc_allocateClassPair(UIView.class,"_TtC12Share_ECMKit24SharePreviewScaffoldView",0);objc_registerClassPair(previewClass);}
    UIView *preview=[previewClass new];preview.backgroundColor=[UIColor colorWithWhite:18./255 alpha:1];
    UILabel *mediaText=[UILabel new];mediaText.text=@"Share card title";mediaText.textColor=UIColor.whiteColor;[preview addSubview:mediaText];
    UIImage *mediaImage=glyphImage(UIColor.cyanColor);UIImageView *art=[[UIImageView alloc]initWithImage:mediaImage];[preview addSubview:art];
    [sheet.view addSubview:preview];
    SGRApplyNativeSheetAppearance(sheet);
    expect(sheet.overrideUserInterfaceStyle==UIUserInterfaceStyleLight && sheet.view.overrideUserInterfaceStyle==UIUserInterfaceStyleLight,@"actual sheet owner and root replace forced-dark traits");
    expect(contrast(native.textColor,sheet.view.backgroundColor)>=7 && contrast(speed.textColor,sheet.view.backgroundColor)>=7,@"native black row and custom white Speed row become coherent Light ink");
    expect(glass.effect!=nativeDarkEffect && glass.overrideUserInterfaceStyle==UIUserInterfaceStyleLight && same(glassLabel.textColor,[UIColor colorWithWhite:.08 alpha:1]),@"sheet glass and its separately scoped content follow Light together");
    sheet.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;sheet.view.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;glass.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    expect(sheet.overrideUserInterfaceStyle==UIUserInterfaceStyleLight && sheet.view.overrideUserInterfaceStyle==UIUserInterfaceStyleLight && glass.overrideUserInterfaceStyle==UIUserInterfaceStyleLight,@"late native forced-dark assignments cannot split registered sheet chrome");
    expect(!SGRNativeSurfaceManaged(preview) && !SGRNativeSurfaceManaged(mediaText),@"entire share preview scaffold is outside app chrome adaptation");
    for(NSUInteger i=0;i<4;i++) {
        BOOL light=i%2;expect(SGRAppearanceApplyMode(light?SGRAppearanceLight:SGRAppearanceDark,NO),@"presented sheet changes appearance live");
        expect(contrast(native.textColor,sheet.view.backgroundColor)>=7 && contrast(speed.textColor,sheet.view.backgroundColor)>=7,@"Light-origin native and Dark-origin custom rows remain readable on both round trips");
        expect(CGRectEqualToRect(sheet.view.frame,originalFrame) && (light || (same(sheet.view.backgroundColor,nativeBacking) && glass.effect==nativeDarkEffect)),@"Dark restores exact native sheet backing and blur object; geometry remains unchanged");
        expect(same(preview.backgroundColor,[UIColor colorWithWhite:18./255 alpha:1]) && same(mediaText.textColor,UIColor.whiteColor) && art.image==mediaImage,@"share preview background, white card copy and bitmap remain exact through both modes");
    }
    UIView *latePreview=[previewClass new];UILabel *lateText=[UILabel new];lateText.textColor=UIColor.whiteColor;[latePreview addSubview:lateText];[sheet.view addSubview:latePreview];
    expect(!SGRNativeSurfaceManaged(lateText) && same(lateText.textColor,UIColor.whiteColor),@"share preview inserted after sheet registration keeps native media semantics");
    UIVisualEffectView *lateGlass=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    lateGlass.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[sheet.view addSubview:lateGlass];
    UILabel *lateChrome=[UILabel new];lateChrome.textColor=UIColor.whiteColor;[lateGlass.contentView addSubview:lateChrome];
    expect(lateGlass.overrideUserInterfaceStyle==UIUserInterfaceStyleLight && same(lateChrome.textColor,[UIColor colorWithWhite:.08 alpha:1]),@"late-inserted sheet glass adopts the owner without sweeping the window");
    UIView *outside=[UIView new];
    [outside addSubview:glass];
    expect(glass.effect==nativeDarkEffect && glass.overrideUserInterfaceStyle==UIUserInterfaceStyleDark && same(glassLabel.textColor,UIColor.whiteColor),@"reused glass outside sheet restores effect, style and native ink");
    expect(!SGRNativeSurfaceManaged(glassLabel),@"reused glass content does not retain an independent managed root");
    expect(SGRAppearanceApplyMode(SGRAppearanceDark,NO) && SGRAppearanceApplyMode(SGRAppearanceLight,NO),@"theme changes after sheet glass reuse");
    expect(glass.effect==nativeDarkEffect && glass.overrideUserInterfaceStyle==UIUserInterfaceStyleDark,@"unregistered reused effect no longer follows global theme callbacks");
    [sheet.view addSubview:glass];
    expect(glass.effect!=nativeDarkEffect && same(glassLabel.textColor,[UIColor colorWithWhite:.08 alpha:1]),@"reused glass re-enters exact sheet scope");
    [preview addSubview:glass];
    expect(glass.effect==nativeDarkEffect && glass.overrideUserInterfaceStyle==UIUserInterfaceStyleDark && same(glassLabel.textColor,UIColor.whiteColor),@"moving reused sheet glass into a share preview relinquishes all appearance overrides");
    UIBlurEffect *replacement=[UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight];glass.effect=replacement;
    expect(glass.effect==replacement,@"a reused preview effect can accept native effects without transformation");
    for (UIColor *lightBase in @[UIColor.whiteColor,[UIColor colorWithWhite:247./255 alpha:1]]) {
        UIViewController *lightSheet=[UIViewController new];lightSheet.view=[UIView new];lightSheet.view.backgroundColor=lightBase;
        UILabel *lightRow=[UILabel new];lightRow.textColor=UIColor.blackColor;[lightSheet.view addSubview:lightRow];
        SGRApplyNativeSheetAppearance(lightSheet);
        expect(SGRAppearanceApplyMode(SGRAppearanceDark,NO) && contrast(lightRow.textColor,lightSheet.view.backgroundColor)>=7 && !same(lightSheet.view.backgroundColor,lightBase),@"Light-origin white sheet backing maps to Dark semantic base, not literal white restoration");
        expect(SGRAppearanceApplyMode(SGRAppearanceLight,NO),@"restore Light for native sheet reassignment");
        lightSheet.view.backgroundColor=UIColor.whiteColor;
        expect(SGRAppearanceApplyMode(SGRAppearanceDark,NO) && contrast(lightRow.textColor,lightSheet.view.backgroundColor)>=7,@"native post-registration white base assignment also reverses on Dark");
        SGRAppearanceApplyMode(SGRAppearanceLight,NO);
    }
    UIViewController *clearSheet=[UIViewController new];clearSheet.view=[UIView new];
    clearSheet.view.backgroundColor=nil;SGRApplyNativeSheetAppearance(clearSheet);
    expect(SGRAppearanceApplyMode(SGRAppearanceDark,NO) && clearSheet.view.backgroundColor==nil,@"transparent native sheet base returns exactly after Light");
    UIViewController *unrelated=[UIViewController new];unrelated.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    expect(unrelated.overrideUserInterfaceStyle==UIUserInterfaceStyleDark,@"unrelated modal owners retain native appearance policy");
    expect(SGRAppearanceApplyMode(saved,NO),@"sheet fixture restores requested appearance");
}
