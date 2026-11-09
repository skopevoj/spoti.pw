// Models only the binary-proven native trait -> gradient rebuild contract. The production
// SGRAmoled hook must register this otherwise-unmanaged sibling of the content/tab bar.
@interface _TtC23NavigationUI_TabBarImpl18TabBarGradientView : UIView
@property(nonatomic) NSUInteger refreshCount;
- (instancetype)initBypassingObjCFrameEntry;
@end
@implementation _TtC23NavigationUI_TabBarImpl18TabBarGradientView
+ (Class)layerClass { return CAGradientLayer.class; }
- (void)refreshNativeStops {
    self.refreshCount++;
    UIColor *base=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleLight?UIColor.whiteColor:UIColor.blackColor;
    CAGradientLayer *gradient=(CAGradientLayer *)self.layer;
    gradient.colors=@[(id)[base colorWithAlphaComponent:0].CGColor,(id)[base colorWithAlphaComponent:.4].CGColor,(id)base.CGColor];
    gradient.locations=@[@0,@.5,@1];
    gradient.startPoint=CGPointMake(.5,0);gradient.endPoint=CGPointMake(.5,1);
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) [self refreshNativeStops];
    return self;
}
- (instancetype)initBypassingObjCFrameEntry {
    if ((self=[super initWithFrame:CGRectMake(0,459,466,219)])) [self refreshNativeStops];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self=[super initWithCoder:coder])) [self refreshNativeStops];
    return self;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (!previous || previous.userInterfaceStyle!=self.traitCollection.userInterfaceStyle) [self refreshNativeStops];
}
@end
static void nativeChromeChecks(void) {
    UIUserInterfaceStyle saved=SGRedesignAppearanceStyle();
    SGConfigureRedesignAppearance(UIUserInterfaceStyleLight);SGRefreshAppearanceOwners();
    UIView *systemLightParent=[UIView new];systemLightParent.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;
    UIView *chrome=[[_TtC23NavigationUI_TabBarImpl18TabBarGradientView alloc]initWithFrame:CGRectMake(0,459,466,219)];
    [systemLightParent addSubview:chrome];
    UIView *swiftEntry=[[_TtC23NavigationUI_TabBarImpl18TabBarGradientView alloc]initBypassingObjCFrameEntry];
    [systemLightParent addSubview:swiftEntry];
    CAGradientLayer *layer=(CAGradientLayer *)chrome.layer;
    CAGradientLayer *unowned=[CAGradientLayer layer];
    NSArray *unownedColors=@[(id)UIColor.cyanColor.CGColor,(id)UIColor.magentaColor.CGColor];unowned.colors=unownedColors;
    CGRect originalFrame=chrome.frame;
    for (NSNumber *mode in @[@2,@1,@2,@1]) {
        UIUserInterfaceStyle style=mode.integerValue;
        SGConfigureRedesignAppearance(style);SGRefreshAppearanceOwners();
        expect(swiftEntry.overrideUserInterfaceStyle==style && same([UIColor colorWithCGColor:(__bridge CGColorRef)((CAGradientLayer *)swiftEntry.layer).colors.lastObject],style==UIUserInterfaceStyleLight?UIColor.whiteColor:UIColor.blackColor),@"native gradient lifecycle registers direct Swift-style initializer path");
        expect(chrome.overrideUserInterfaceStyle==style && chrome.traitCollection.userInterfaceStyle==style,@"native bottom gradient follows selected style despite system-light ancestor");
        UIColor *opaque=[UIColor colorWithCGColor:(__bridge CGColorRef)layer.colors.lastObject];
        expect(same(opaque,style==UIUserInterfaceStyleLight?UIColor.whiteColor:UIColor.blackColor),@"existing bottom chrome gradient rebinds native stops Light and Dark");
        expect(layer==chrome.layer && CGRectEqualToRect(originalFrame,chrome.frame) && [layer.locations isEqual:@[@0,@.5,@1]],@"bottom gradient refresh retains layer, geometry and native stops");
        expect([unowned.colors isEqual:unownedColors],@"unrelated artwork/chromatic gradients are unchanged");
    }
    [chrome removeFromSuperview];
    SGConfigureRedesignAppearance(UIUserInterfaceStyleDark);SGRefreshAppearanceOwners();
    expect(same([UIColor colorWithCGColor:(__bridge CGColorRef)layer.colors.lastObject],UIColor.blackColor),@"detached retained bottom gradient receives native refresh");
    SGConfigureRedesignAppearance(saved);SGRefreshAppearanceOwners();
}
