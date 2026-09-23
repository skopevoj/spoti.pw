#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGRAccent.h"

static UIColor *spotifyAccentPreview(void) {
    return [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
}

// The redesign's rows of the Appearance page (App/Pages.m). AMOLED has no row: the redesign is always black.
NSArray<SGModRow *> *SGRAppearanceRows(void) {
    NSArray<NSString *> *palettes = @[@"Spotify", @"Apple Music", @"Custom"];
    SGModRow *palette = SGMenuChoiceRow(@"Accent color preset", nil, SGRKeyAccentChoice, palettes, SGRCurrentAccentChoice());
    palette.chosen = ^(NSInteger index) { SGRRefreshAccent(); };
    SGModRow *color = SGStatActionRow(@"Accent color", nil, ^NSString *{ return SGRAccentLabel(); }, ^{ SGRPickAccent(); });
    color.swatch = ^UIColor *{ return SGRAccentColor() ?: spotifyAccentPreview(); };
    return @[
        SGWithSymbol(palette, @"paintpalette"),
        SGWithSymbol(color, @"paintpalette"),
    ];
}
