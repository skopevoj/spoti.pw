#import "GlobalIcons.h"
#import "Core/SGCore.h"

SGAppIconStyle SGAppIconStyleValue(void) {
    return SGInt(SGKeyAppIconStyle, SGAppIconStyleEncore) == SGAppIconStyleSFSymbols ? SGAppIconStyleSFSymbols : SGAppIconStyleEncore;
}

NSString *SGAppIconStyleLabel(void) {
    return SGAppIconStyleValue() == SGAppIconStyleSFSymbols ? @"SF Symbols" : @"Spotify Encore";
}

static NSDictionary<NSString *, NSString *> *encoreToSF(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"home": @"house.fill", @"homeActive": @"house.fill", @"search": @"magnifyingglass",
            @"collection": @"square.grid.2x2.fill", @"library": @"square.grid.2x2.fill", @"heart": @"heart.fill",
            @"playlist": @"music.note.list", @"album": @"square.stack.fill", @"artist": @"person.2.fill",
            @"podcasts": @"dot.radiowaves.left.and.right", @"audiobook": @"book.closed.fill", @"downloaded": @"arrow.down.circle.fill",
            @"bookmark": @"bookmark.fill", @"browse": @"square.grid.2x2.fill", @"star": @"star.fill", @"user": @"person.fill",
            @"events": @"calendar", @"queue": @"list.bullet", @"plus": @"plus", @"radio": @"dot.radiowaves.left.and.right",
            @"gears": @"gearshape.fill", @"spotifyLogo": @"music.note", @"create": @"plus.circle.fill",
            @"play": @"play.fill", @"pause": @"pause.fill", @"next": @"forward.fill", @"previous": @"backward.fill",
            @"forward": @"forward.fill", @"back": @"backward.fill", @"shuffle": @"shuffle", @"repeat": @"repeat",
            @"repeatOne": @"repeat.1", @"volume": @"speaker.wave.2.fill", @"volumeOff": @"speaker.slash.fill",
            @"mute": @"speaker.slash.fill", @"check": @"checkmark", @"close": @"xmark", @"cancel": @"xmark.circle.fill",
            @"more": @"ellipsis", @"moreHorizontal": @"ellipsis", @"menu": @"line.3.horizontal", @"settings": @"gearshape.fill",
            @"download": @"arrow.down.circle", @"upload": @"arrow.up.circle", @"share": @"square.and.arrow.up",
            @"link": @"link", @"edit": @"pencil", @"delete": @"trash", @"trash": @"trash", @"info": @"info.circle",
            @"warning": @"exclamationmark.triangle.fill", @"lock": @"lock.fill", @"unlock": @"lock.open.fill",
            @"eye": @"eye.fill", @"eyeOff": @"eye.slash.fill", @"folder": @"folder.fill", @"document": @"doc.fill",
            @"clock": @"clock.fill", @"calendar": @"calendar", @"music": @"music.note", @"mic": @"mic.fill",
            @"headphones": @"headphones", @"airplay": @"airplayaudio", @"cast": @"rectangle.connected.to.line.below",
            @"devices": @"hifispeaker.2.fill", @"phone": @"iphone", @"car": @"car.fill", @"tv": @"tv.fill",
            @"bell": @"bell.fill", @"mail": @"envelope.fill", @"camera": @"camera.fill", @"photo": @"photo.fill",
            @"playlists": @"music.note.list", @"tracks": @"music.note", @"albums": @"square.stack.fill",
            @"artists": @"person.2.fill", @"podcast": @"dot.radiowaves.left.and.right", @"episode": @"play.rectangle.fill",
        };
    });
    return map;
}

NSString *SGAppIconSymbolForEncoreName(NSString *name) {
    NSString *symbol = encoreToSF()[name];
    if (!symbol.length && [UIImage systemImageNamed:name]) symbol = name;
    return symbol.length ? symbol : @"questionmark.circle.fill";
}
