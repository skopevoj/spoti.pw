// The Appearance card's Font row (AppFont.h): Spotify's own, the system's four designs, then every family
// on this iPhone. The list stores an index for its checkmark and the name for the hooks, kept in step, so a
// family list that changes with iOS never points the hooks at the wrong one.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "AppFont.h"

static NSArray<NSString *> *values(void) {
    static NSArray<NSString *> *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *all = [NSMutableArray arrayWithObjects:@"", SGAppFontSystem, SGAppFontRounded, SGAppFontSerif, SGAppFontMono, nil];
        NSArray<NSString *> *families = [UIFont.familyNames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *family in families) {
            // Symbol and ornament faces have no letters to read.
            if ([family containsString:@"Dingbats"] || [family containsString:@"Ornaments"] || [family isEqualToString:@"Symbol"]) continue;
            [all addObject:family];
        }
        list = all;
    });
    return list;
}

static NSString *nameOf(NSString *value) {
    if (!value.length) return @"Spotify's own";
    if ([value isEqualToString:SGAppFontSystem]) return @"San Francisco";
    if ([value isEqualToString:SGAppFontRounded]) return @"SF Rounded";
    if ([value isEqualToString:SGAppFontSerif]) return @"New York";
    if ([value isEqualToString:SGAppFontMono]) return @"SF Mono";
    return value;
}

SGModRow *SGAppFontRow(void) {
    NSArray<NSString *> *list = values();
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:list.count];
    for (NSString *value in list) [names addObject:nameOf(value)];
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFont] ?: @"";
    NSUInteger index = [list indexOfObject:stored];
    SGSetInt(SGKeyAppFontIndex, index == NSNotFound ? 0 : (NSInteger)index);
    SGModRow *row = SGChoiceRow(@"Font", nil, SGKeyAppFontIndex, names, 0);
    row.chosen = ^(NSInteger chosen) {
        NSString *value = chosen >= 0 && chosen < (NSInteger)list.count ? list[(NSUInteger)chosen] : @"";
        if (value.length) [NSUserDefaults.standardUserDefaults setObject:value forKey:SGKeyAppFont];
        else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyAppFont];
    };
    row.choiceFooter = @"Every text in Spotify, in this family, at its size and as near its weight as the family goes. Applies after you restart Spotify.";
    return SGWithSymbol(row, @"textformat");
}
