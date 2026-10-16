// The Lyrics page's parts; App/Pages.m assembles the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Lyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"

SGModSection *SGLyricsSourcesSection(BOOL namingSource) {
    SGModRow *sources = SGPageRow(@"Sources", ^UIViewController *{ return SGLyricsSourcesPage(); });
    sources.value = ^NSString *{
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *key in SGLyricsOrder()) [names addObject:SGLyricsProviderFor(key).name];
        return names.count ? [names componentsJoinedByString:@", "] : @"Off";
    };
    NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObjects:sources,
        SGOptionRow(@"Lyrics for every track", @"Even where Spotify has none", SGKeyLyricsAllTracks), nil];
    if (namingSource) [rows addObject:SGOptionRow(@"Show source", nil, SGKeyLyricsCredit)];
    [rows addObjectsFromArray:SGLyricsOfflineRows()];
    if (!SGLyricsEeveeReplaces()) return SGSection(@"Sources", rows);
    return SGNotedSection(@"Sources", rows, @"EeveeSpotify is replacing lyrics, so these sources stay off. To use them, "
                          "turn on Do Not Replace Lyrics in EeveeSpotify's lyrics settings and restart Spotify.");
}

SGModRow *SGLockScreenLyricsRow(void) {
    return SGOptionRow(@"Lock screen lyrics", @"The line being sung on the lock screen", SGKeyLockScreenLyrics);
}

SGModRow *SGLockScreenLyricsPlaceRow(void) {
    SGModRow *row = SGChoiceRow(@"Show the line", nil, SGKeyLockScreenLyricsPlace, @[@"In place of the artist", @"As the artwork", @"Both"],
                                SGLockScreenLyricsArtist);
    row.choiceNotes = @[@"The line under the title", @"The line and the next over the cover, blurred", @"Under the title and over the cover"];
    SGWaitsOn(row, SGKeyLockScreenLyrics, NO);
    return row;
}

SGModRow *SGLyricsTranslationLanguageRow(void) {
    SGModRow *row = SGChoiceRow(@"Translation language", nil, SGKeyLyricsTranslationLanguage, SGLyricsTranslationLanguageNames(), 0);
    row.choiceFooter = @"Used when the lyrics come with translations. Any shows the first.";
    return row;
}

// Only the redesign's lyrics view sweeps words.
SGModRow *SGLyricsWordTimingRow(void) {
    return SGOptionRow(@"Simulate word timing", nil, SGKeyLyricsSimulateWords);
}
