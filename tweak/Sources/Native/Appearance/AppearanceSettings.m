#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Appearance.h"

static UIColor *spotifyAccentPreview(void) {
    return [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
}

// The native look's rows of the Appearance page (App/Pages.m).
NSArray<SGModRow *> *SGNativeAppearanceRows(void) {
    NSArray<NSString *> *palettes = @[@"Spotify", @"Apple Music", @"Custom"];
    SGModRow *palette = SGMenuChoiceRow(@"Accent color preset", nil, SGKeyAccentChoice, palettes, SGCurrentAccentChoice());
    palette.chosen = ^(NSInteger index) { SGRefreshAccent(); };
    SGModRow *color = SGStatActionRow(@"Accent color", nil, ^NSString *{ return SGAccentLabel(); }, ^{ SGPickAccent(); });
    color.swatch = ^UIColor *{ return SGAccentColor() ?: spotifyAccentPreview(); };
    return @[
        SGWithSymbol(SGOptionRow(@"AMOLED background", nil, SGKeyAmoled), @"moon"),
        SGWithSymbol(palette, @"paintpalette"),
        SGWithSymbol(color, @"paintpalette"),
    ];
}
