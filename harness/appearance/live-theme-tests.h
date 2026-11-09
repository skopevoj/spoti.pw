// Actual bridge transactions, not merely changing the owned appearance flag.
static void liveThemeChecks(void) {
    NSInteger saved=SGInt(SGRKeyAppearance,SGRAppearanceSystem);
    expect(SGRAppearanceApplyMode(SGRAppearanceDark,NO),@"live bridge can select Dark");
    UIView *root=[UIView new];
    UILabel *darkOrigin=[UILabel new]; darkOrigin.text=@"Same song";darkOrigin.textColor=UIColor.whiteColor;
    [root addSubview:darkOrigin]; SGRApplyNativeLightSurface(root,YES);
    UIView *nested=[UIView new];[root addSubview:nested];SGRApplyNativeLightSurface(nested,NO);
    UILabel *secondary=[UILabel new];secondary.textColor=[UIColor colorWithWhite:179./255 alpha:1];[nested addSubview:secondary];
    expect(SGRAppearanceApplyMode(SGRAppearanceLight,NO),@"live bridge commits both providers to Light");
    expect(SGTestNativeIsLight() && objcMain==[SPTEncoreColorTheme light],@"live Light updates raw native and ObjC stores");
    expect(same(darkOrigin.textColor,[UIColor colorWithWhite:.08 alpha:1]),@"retained Dark-origin text becomes dark ink");
    UILabel *lightOrigin=[UILabel new];lightOrigin.textColor=UIColor.blackColor;[root addSubview:lightOrigin];
    UILabel *lightSecondary=[UILabel new];lightSecondary.textColor=[UIColor colorWithWhite:101./255 alpha:1];[root addSubview:lightSecondary];
    UILabel *attributed=[UILabel new];attributed.attributedText=[[NSAttributedString alloc]initWithString:@"Current title" attributes:@{NSForegroundColorAttributeName:UIColor.blackColor,NSKernAttributeName:@3}];[root addSubview:attributed];
    UIView *lightSurface=[UIView new];lightSurface.backgroundColor=UIColor.whiteColor;[root addSubview:lightSurface];
    UILabel *inCard=[UILabel new];inCard.textColor=UIColor.blackColor;[lightSurface addSubview:inCard];
    UIView *layered=[UIView new];[root addSubview:layered];
    layered.backgroundColor=[UIColor colorWithWhite:.97 alpha:1];
    layered.layer.backgroundColor=[UIColor colorWithWhite:.92 alpha:1].CGColor;
    UIView *detached=[UIView new];SGRApplyNativeLightSurface(detached,YES);
    UILabel *detachedText=[UILabel new];detachedText.textColor=UIColor.blackColor;[detached addSubview:detachedText];
    UIButton *attributedButton=[UIButton new];[root addSubview:attributedButton];
    [attributedButton setAttributedTitle:[[NSAttributedString alloc]initWithString:@"Initial normal" attributes:@{NSForegroundColorAttributeName:UIColor.blackColor}] forState:UIControlStateNormal];
    [attributedButton setAttributedTitle:[[NSAttributedString alloc]initWithString:@"Selected title" attributes:@{NSForegroundColorAttributeName:[UIColor colorWithWhite:101./255 alpha:1]}] forState:UIControlStateSelected];
    UIButton *search=[UIButton new];search.accessibilityIdentifier=@"YourLibraryHeader.search";[root addSubview:search];
    UIImage *lightGlyphSource=glyphImage(UIColor.blackColor);
    UIImageView *retainedGlyph=[[UIImageView alloc]initWithImage:lightGlyphSource];[search addSubview:retainedGlyph];
    SGRRefreshNativeGlyph(retainedGlyph);
    NSUInteger rootCount=root.subviews.count; CGRect frame=root.frame;
    for (NSUInteger i=0;i<12;i++) {
        BOOL light=i%2;
        expect(SGRAppearanceApplyMode(light?SGRAppearanceLight:SGRAppearanceDark,NO),@"repeated live transition verifies providers");
        expect(SGTestNativeIsLight()==light && objcMain==(light?[SPTEncoreColorTheme light]:[SPTEncoreColorTheme dark]),@"both provider stores agree after each transition");
        expect(same(darkOrigin.textColor,light?[UIColor colorWithWhite:.08 alpha:1]:UIColor.whiteColor),@"Dark-origin native ink rebinds both directions");
        expect(same(lightOrigin.textColor,light?UIColor.blackColor:UIColor.whiteColor),@"Light-origin native primary has an explicit Dark pair");
        expect(same(lightSecondary.textColor,[UIColor colorWithWhite:(light?101.:179.)/255 alpha:1]),@"Light-origin native subdued has an explicit Dark pair");
        expect(same([attributed.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nil],light?UIColor.blackColor:UIColor.whiteColor),@"retained Light-origin attributed role rebinds without stale content");
        expect([attributed.text isEqual:@"Current title"] && [[attributed.attributedText attribute:NSKernAttributeName atIndex:0 effectiveRange:nil] isEqual:@3],@"appearance preserves attributed content and noncolor metadata");
        expect(same(detachedText.textColor,light?UIColor.blackColor:UIColor.whiteColor),@"detached retained root refreshes without a window");
        expect(contrast(inCard.textColor,lightSurface.backgroundColor)>7,@"Light-created semantic background and foreground switch together");
        expect(same([UIColor colorWithCGColor:layered.layer.backgroundColor],[UIColor colorWithWhite:light?.92:31./255 alpha:1]),@"Light-origin direct layer role survives paired UIView replay in both directions");
        NSString *expectedTitle=i<2?@"Initial normal":@"Changed normal";
        NSAttributedString *normal=[attributedButton attributedTitleForState:UIControlStateNormal];
        NSAttributedString *selected=[attributedButton attributedTitleForState:UIControlStateSelected];
        expect([normal.string isEqual:expectedTitle] && same([normal attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nil],light?UIColor.blackColor:UIColor.whiteColor),@"Light-origin attributed button normal role and current text survive transitions");
        expect([selected.string isEqual:@"Selected title"] && same([selected attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nil],[UIColor colorWithWhite:(light?101.:179.)/255 alpha:1]),@"Light-origin attributed button nonnormal role survives transitions");
        if (i==1) [attributedButton setAttributedTitle:[[NSAttributedString alloc]initWithString:@"Changed normal" attributes:@{NSForegroundColorAttributeName:UIColor.blackColor}] forState:UIControlStateNormal];
        UIColor *actualGlyphInk=glyphCenter(retainedGlyph.image);
        expect(light?(same(actualGlyphInk,UIColor.blackColor)||same(actualGlyphInk,[UIColor colorWithWhite:.08 alpha:1])):same(actualGlyphInk,UIColor.whiteColor),@"retained Light-origin UIImage control draws matching semantic ink after each live transition");
        expect(root.subviews.count==rootCount && CGRectEqualToRect(frame,root.frame),@"live transaction does not reconstruct views or change frames");
    }
    // A rejected raw setter must preserve the last rendered style, selection and provider.
    expect(SGRAppearanceApplyMode(SGRAppearanceLight,NO),@"prepare rejected transaction");
    rejectObjCWrites=YES;
    expect(!SGRAppearanceApplyMode(SGRAppearanceDark,NO),@"rejected ObjC setter fails live transaction");
    expect(SGTestNativeIsLight() && objcMain==[SPTEncoreColorTheme light] && SGRedesignLightAppearance(),@"failed transaction restores Swift and preserves original ObjC and rendered mode");
    expect(same(lightOrigin.textColor,UIColor.blackColor),@"failed transaction leaves visible ink unchanged");
    rejectObjCWrites=NO;
    expect(SGRAppearanceApplyMode(SGRAppearanceDark,NO),@"successful retry clears live failure");
    UIView *outside=[UIView new];[outside addSubview:lightOrigin];
    expect(same(lightOrigin.textColor,UIColor.blackColor),@"Light-origin provenance restores exact native value on scope exit");
    [outside addSubview:attributedButton];
    expect([[attributedButton attributedTitleForState:UIControlStateNormal].string isEqual:@"Changed normal"] && same([[attributedButton attributedTitleForState:UIControlStateNormal] attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nil],UIColor.blackColor),@"attributed button scope exit restores source ink without resurrecting old text");
    [outside addSubview:search];
    expect(retainedGlyph.image==lightGlyphSource,@"retained UIImage glyph restores exact Light-origin source on scope exit");
    [outside addSubview:layered];
    expect(same([UIColor colorWithCGColor:layered.layer.backgroundColor],[UIColor colorWithWhite:.92 alpha:1]),@"Light-origin direct layer exact source survives scope exit after transitions");
    expect(SGRAppearanceApplyMode(SGRAppearanceLight,NO),@"prepare coalesced picker changes");
    NSObject *coalescingOwner=[NSObject new];
    __block NSUInteger refreshes=0;
    SGRegisterAppearanceRefresh(coalescingOwner,^(id owner){refreshes++;});
    for (NSNumber *mode in @[@0,@1,@0]) { SGSetInt(SGRKeyAppearance,mode.integerValue);SGRAppearanceApplyPreference(); }
    [[NSRunLoop mainRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    expect(refreshes==1 && !SGRedesignLightAppearance() && !SGTestNativeIsLight(),@"rapid picker changes coalesce into one final verified appearance pass");
    SGSetInt(SGRKeyAppearance,saved);
    expect(SGRAppearanceApplyMode(saved,NO),@"fixture restores requested initial mode");
}
