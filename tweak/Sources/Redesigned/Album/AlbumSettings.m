#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Album.h"

UIViewController *SGRAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGNotedSection(@"Header", @[
            SGSwitchRow(@"Animated cover", @"Apple Music's, where the album has one", SGRKeyAnimatedCovers),
        ], @"Apple Music gets only the artist and album name. Nothing is downloaded in Low Data or Low Power Mode."),
    ];
    return [[SGModPage alloc] initWithTitle:@"Albums" intro:nil sections:sections footer:nil];
}
