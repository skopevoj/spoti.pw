// Included after expect/contrast helpers. Same objects survive every mode change.
#import "Redesigned/Kit/SGRDownload.h"
static void ownedLiveChecks(void) {
    UIUserInterfaceStyle saved = SGRedesignAppearanceStyle();
    SGConfigureRedesignAppearance(UIUserInterfaceStyleDark);
    SGRefreshAppearanceOwners();
    UIViewController *controller = [UIViewController new];
    SGRegisterAppearanceController(controller);
    UIView *root = controller.view;
    SGRegisterAppearanceView(root);
    UILabel *label = [UILabel new];
    UIColor *retainedInk = SGRPrimary();
    label.textColor = retainedInk;
    label.attributedText = [[NSAttributedString alloc] initWithString:@"Retained text" attributes:@{NSForegroundColorAttributeName:SGRSecondary()}];
    [root addSubview:label];
    SGRGlyphView *glyph = [[SGRGlyphView alloc] initWithSymbol:@"plus" pointSize:20 weight:UIImageSymbolWeightRegular];
    [root addSubview:glyph];
    UIView *source = [[UIView alloc] initWithFrame:CGRectMake(0,0,44,44)];
    UIImageView *sourceGlyph = [[UIImageView alloc] initWithFrame:source.bounds];
    sourceGlyph.image = [UIImage systemImageNamed:@"play.fill"];
    sourceGlyph.tintColor = UIColor.whiteColor;
    [source addSubview:sourceGlyph];
    SGRMirrorButton *mirror = [[SGRMirrorButton alloc] initWithFrame:source.bounds];
    mirror.glyphColor = SGRPrimary();
    [mirror feedFrom:source];
    [root addSubview:mirror];
    SGRPlayCapsule *play = [[SGRPlayCapsule alloc] initWithFrame:CGRectMake(0,0,120,48)];
    play.contentColor = SGRPrimary();
    [play feedFrom:source];
    [root addSubview:play];
    SGRArtworkField *field = [[SGRArtworkField alloc] initWithFrame:CGRectMake(0,0,300,600)];
    [field setProvisionalColor:[UIColor colorWithRed:.1 green:.2 blue:.3 alpha:1]];
    [root addSubview:field];
    UIColor *raw = [field valueForKey:@"rawColor"];
    NSNumber *generation = [field valueForKey:@"generation"];
    SGRDownloadGlyph *download = [[SGRDownloadGlyph alloc] initWithFrame:CGRectMake(0,0,24,24)];
    [download showState:SGRDownloadDownloading progress:.4 animated:NO];
    [root addSubview:download];
    CAShapeLayer *arc = [download valueForKey:@"arc"];
    CAShapeLayer *track = [download valueForKey:@"track"];
    CGFloat progress = arc.strokeEnd;
    UIView *control = [[UIView alloc] initWithFrame:CGRectMake(0,0,120,48)];
    static char glassKey;
    UIView *glass = SGRGlassCapsuleInside(control, &glassKey, control.bounds.size, YES);
    [root addSubview:control];
    __block NSUInteger calls = 0;
    __weak NSObject *released;
    @autoreleasepool {
        NSObject *owner = [NSObject new];
        released = owner;
        SGRegisterAppearanceRefresh(owner, ^(id value) { calls++; });
        SGRegisterAppearanceRefresh(owner, ^(id value) { calls++; });
        SGRefreshAppearanceOwners();
        expect(calls == 1, @"duplicate owner registration replaces rather than duplicates callback");
    }
    expect(released == nil, @"appearance registry does not retain owners");
    for (NSNumber *mode in @[@1,@2,@1,@2]) {
        UIUserInterfaceStyle style = mode.integerValue;
        BOOL light = style == UIUserInterfaceStyleLight;
        SGConfigureRedesignAppearance(style);
        SGRefreshAppearanceOwners();
        expect(controller.overrideUserInterfaceStyle == style && root.overrideUserInterfaceStyle == style, @"existing controller and owned root update together");
        expect(glass.overrideUserInterfaceStyle == style && glyph.overrideUserInterfaceStyle == style, @"existing glass and glyph style updates");
        UITraitCollection *traits = [UITraitCollection traitCollectionWithUserInterfaceStyle:style];
        UIColor *paper = light ? UIColor.whiteColor : UIColor.blackColor;
        expect(contrast([retainedInk resolvedColorWithTraitCollection:traits], paper)>7, @"retained primary color resolves both directions");
        UIImageView *mirrorGlyph = [mirror valueForKey:@"glyph"];
        UIImageView *playGlyph = [play valueForKey:@"glyph"];
        expect(contrast([mirrorGlyph.tintColor resolvedColorWithTraitCollection:traits], paper)>7, @"existing mirror preserves semantic pinned glyph color");
        expect(contrast([playGlyph.tintColor resolvedColorWithTraitCollection:traits], paper)>7, @"existing play capsule ink updates without feeding playback again");
        expect(contrast([glyph.tintColor resolvedColorWithTraitCollection:traits], paper)>7, @"existing glyph is black on light and white on dark");
        UIColor *attributed = [label.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
        expect(contrast([attributed resolvedColorWithTraitCollection:traits], paper)>3, @"retained attributed ink remains readable");
        expect(contrast(SGRTertiary(),field.fieldColor)>=(light?4.5:1), @"ambient tint preserves readable owned tertiary ink");
        expect(((CALayer *)[field valueForKey:@"lightFloor"]).hidden == !light, @"existing artwork floor toggles both directions");
        expect([[field valueForKey:@"rawColor"] isEqual:raw] && [[field valueForKey:@"generation"] isEqual:generation], @"field appearance neither rereads artwork nor reuses washed color as raw");
        expect(contrast([UIColor colorWithCGColor:track.strokeColor], paper)>1.4, @"download track CGColor repaints");
        expect(arc.strokeEnd == progress, @"download appearance leaves progress untouched");
    }
    field.flows = YES;
    id flow = [field valueForKey:@"flow"];
    field.motionHeld = YES;
    for (NSNumber *mode in @[@1,@2]) {
        SGConfigureRedesignAppearance(mode.integerValue);
        SGRefreshAppearanceOwners();
        expect([field valueForKey:@"flow"] == flow && field.motionHeld, @"appearance preserves flow and motion hold");
        expect(((CALayer *)[field valueForKey:@"lightFloor"]).hidden, @"flow never enables static floor");
    }
    expect(calls == 1, @"released owner never receives later refresh");
    SGConfigureRedesignAppearance(saved);
    SGRefreshAppearanceOwners();
}
