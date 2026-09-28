// Only remove a credit when its information is already on this album page. Keep ambiguous
// punctuation, missing metadata and compilation artists rather than guessing at artist identities.
#import <Foundation/Foundation.h>

static inline NSString *SGRAlbumCreditText(NSString *text) {
    NSArray *words = [text.precomposedStringWithCanonicalMapping.lowercaseString
        componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *nonempty = [NSMutableArray array];
    for (NSString *word in words) if (word.length) [nonempty addObject:word];
    return [nonempty componentsJoinedByString:@" "];
}

static inline BOOL SGRAlbumArtistCreditIsRedundant(NSString *albumArtist, NSString *trackArtists,
                                                  NSString *title) {
    NSString *album = SGRAlbumCreditText(albumArtist), *artists = SGRAlbumCreditText(trackArtists);
    // ParentRow separates co-artists with bullets; retrieval rows use comma-space. Translate
    // only that known presentation separator, without splitting punctuation inside an artist name.
    album = [album stringByReplacingOccurrencesOfString:@" • " withString:@", "];
    if (!album.length || !artists.length) return NO;
    if ([album isEqualToString:artists]) return YES;

    // Spotify joins credits with comma-space. Do not split a band's ampersand, a slash or an 'x'.
    NSString *prefix = [album stringByAppendingString:@", "];
    if (![artists hasPrefix:prefix]) return NO;
    NSString *guests = [artists substringFromIndex:prefix.length];
    if (!guests.length) return NO;

    // A name occurring in ordinary lyrics/title text is not evidence of a featured credit.
    // Require an explicit suffix such as '(feat. Justice)' or '- with Anitta'. Unknown formats stay.
    static NSRegularExpression *credit;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        credit = [NSRegularExpression regularExpressionWithPattern:
            @"(?:\\(|\\[| - )\\s*(?:feat\\.?|ft\\.?|featuring|with)\\s+([^\\)\\]]+)[\\)\\]]?\\s*$"
            options:0 error:nil];
    });
    NSString *name = SGRAlbumCreditText(title);
    NSTextCheckingResult *match = [credit firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];
    if (!match) return NO;
    NSString *credited = SGRAlbumCreditText([name substringWithRange:[match rangeAtIndex:1]]);
    // Comparing the complete guest string avoids treating 'Ann' as 'Anne', or a comma inside
    // one artist name as two people. Different ordering/separators conservatively keep the line.
    return [guests isEqualToString:credited];
}
