#import "Redesigned/Kit/SGRFlow.h"
static CGFloat chroma(UIColor *color) {
    CGFloat r=0,g=0,b=0;[color getRed:&r green:&g blue:&b alpha:NULL];return MAX(r,MAX(g,b))-MIN(r,MIN(g,b));
}
static void ambientPaletteChecks(void) {
    UIUserInterfaceStyle saved=SGRedesignAppearanceStyle();
    NSArray<UIColor *> *raw=@[UIColor.redColor,UIColor.orangeColor,UIColor.blueColor,UIColor.magentaColor,UIColor.cyanColor];
    SGRFlowLayer *flow=[SGRFlowLayer layer];flow.bounds=CGRectMake(0,0,393,852);[flow layoutIfNeeded];
    SGConfigureRedesignAppearance(UIUserInterfaceStyleDark);[flow setColors:raw animated:NO];
    NSArray *layers=flow.sublayers;
    NSArray *darkBase=[NSArray arrayWithObjects:(__bridge id)((CALayer *)layers[0]).backgroundColor,((CAGradientLayer *)layers[1]).colors,((CAGradientLayer *)layers[5]).colors,((CAGradientLayer *)layers[6]).colors,nil];
    CGRect frame=((CALayer *)layers[1]).frame;
    for(NSUInteger i=0;i<12;i++) {
        BOOL light=(i%2)==0;
        SGConfigureRedesignAppearance(light?UIUserInterfaceStyleLight:UIUserInterfaceStyleDark);[flow refreshAppearance];
        expect(flow.sublayers==layers || [flow.sublayers isEqual:layers],@"ambient switching retains existing layers");
        expect(CGRectEqualToRect(((CALayer *)layers[1]).frame,frame),@"ambient switching leaves motion geometry untouched");
        UIColor *base=[UIColor colorWithCGColor:((CALayer *)layers[0]).backgroundColor];
        if(light) {
            expect(contrast(SGRTertiary(),base)>=4.5,@"light ambient base keeps tertiary contrast");
            expect(chroma(base)>.10,@"light ambient base retains visible artwork hue rather than whiteout");
            for(NSUInteger j=1;j<=5;j++) {
                CAGradientLayer *disc=layers[j];
                UIColor *c=[UIColor colorWithCGColor:(__bridge CGColorRef)disc.colors[0]];
                expect(contrast(SGRTertiary(),c)>=4.5,@"all ambient disc stops retain tertiary contrast");
                expect(chroma(c)>.06,@"all colored ambient stops visibly retain hue");
            }
        } else {
            expect(CGColorEqualToColor(((CALayer *)layers[0]).backgroundColor,(__bridge CGColorRef)darkBase[0]),@"Dark restores exact original ambient base");
            expect([((CAGradientLayer *)layers[1]).colors isEqual:darkBase[1]] && [((CAGradientLayer *)layers[5]).colors isEqual:darkBase[2]] && [((CAGradientLayer *)layers[6]).colors isEqual:darkBase[3]],@"Dark restores exact original ambient discs and shade");
        }
    }
    SGConfigureRedesignAppearance(UIUserInterfaceStyleLight);
    NSMutableArray *pastels=[NSMutableArray new];
    for(NSUInteger h=0;h<36;h++) {
        UIColor *c=SGRLightAmbientColor([UIColor colorWithHue:h/36. saturation:.9 brightness:.4 alpha:1]);
        [pastels addObject:c];expect(contrast(SGRTertiary(),c)>=4.5,@"ambient hue spectrum remains readable");
    }
    for(UIColor *a in pastels)for(UIColor *b in pastels) {
        CGFloat ar,ag,ab,br,bg,bb;[a getRed:&ar green:&ag blue:&ab alpha:NULL];[b getRed:&br green:&bg blue:&bb alpha:NULL];
        UIColor *mid=[UIColor colorWithRed:(ar+br)/2 green:(ag+bg)/2 blue:(ab+bb)/2 alpha:1];
        expect(contrast(SGRTertiary(),mid)>=4.5,@"interpolated moving ambient colors remain readable");
    }
    SGConfigureRedesignAppearance(saved);SGRefreshAppearanceOwners();
}
