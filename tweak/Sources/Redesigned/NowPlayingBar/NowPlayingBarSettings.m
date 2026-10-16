// The redesign's rows on the Player page (App/Pages.m puts them there): the bar and what moves behind
// the player.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlayingBar.h"
#import "Redesigned/Player/Player.h"

NSArray<SGModSection *> *SGRNowPlayingSections(void) {
    return [@[
        SGSection(nil, @[
            SGHideRow(@"Hide the device button", nil, SGRHideBarConnect),
        ]),
        SGNotedSection(@"The ⋯ button", @[
            SGOptionRow(@"Music app style menu", @"A menu of glass in place of the sheet", SGRKeyPlayerMusicMenu),
        ], @"Off, the ⋯ slides Spotify's own sheet up from the bottom with all its options, and Speed and pitch in it. "
           "On, the same options open as a menu grown out of the button, as the Music app draws one. Applies after you restart Spotify."),
    ] arrayByAddingObjectsFromArray:SGRPlayerBackgroundSections()];
}
