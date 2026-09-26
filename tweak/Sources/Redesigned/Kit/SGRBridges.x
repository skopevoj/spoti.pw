// The Kit's bridge into Spotify: the now playing artwork. The player's state, its open and close and
// links are Shared's (Shared/Player/PlayerState.h, Shared/Player/PlayerEvents.h,
// Shared/Navigation/Links.h). SGRBridges.h names the hook and why it is the one.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerEvents.h"
#import "SGRBridges.h"
#import "SGRedesign.h"
#import "SGRRestyle.h"
#import <MediaPlayer/MediaPlayer.h>

#pragma mark - now playing artwork

NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"spotifyglass.redesign.nowPlayingArtworkDidChange";

// The picture published, the track it was published for, the picture it is (its key) and how it was had.
static UIImage *sg_artwork;
static NSString *sg_artworkURI, *sg_artworkKey;
static SGRArtworkQuality sg_artworkQuality;
static NSUInteger sg_artworkSerial;
// The playing track and the picture its metadata names.
static NSString *sg_wantedURI, *sg_wantedKey;
// Every picture published, held weakly, with the key it was published as. A view still showing one of
// these while another picture is wanted is showing the last track's.
static NSMapTable<UIImage *, NSString *> *sg_published;
static NSURLSessionDataTask *sg_fetch;

// Retries of a fetch that failed, and how long before each.
static const NSTimeInterval kFetchRetry = 2;
static const NSUInteger kFetchAttempts = 2;

static void artworkLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void artworkLog(NSString *format, ...) {
    static NSUInteger logged;
    if (logged++ >= 40) return;
    va_list args;
    va_start(args, format);
    SGLog(@"redesign kit: artwork %@", [[NSString alloc] initWithFormat:format arguments:args]);
    va_end(args);
}

// The image id in a metadata value: spotify:image:<id>, or an https URL ending in it.
static NSString *imageIDIn(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length]) return nil;
    NSString *string = value;
    if ([string hasPrefix:@"spotify:image:"]) return [string substringFromIndex:@"spotify:image:".length];
    if ([string hasPrefix:@"https://"]) return string.lastPathComponent;
    return nil;
}

// The picture a track names, largest first, and where it can be fetched from.
static NSString *pictureOf(SPTPlayerTrack *track, NSURL **url) {
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    if (![metadata isKindOfClass:NSDictionary.class]) return nil;
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url", @"image_small_url"]) {
        NSString *value = metadata[field], *identifier = imageIDIn(value);
        if (!identifier) continue;
        if (url) *url = [value hasPrefix:@"https://"] ? [NSURL URLWithString:value]
                                                     : [NSURL URLWithString:[@"https://i.scdn.co/image/" stringByAppendingString:identifier]];
        // Every size of one picture shares its last 24 digits; the first 16 are the size.
        return identifier.length == 40 ? [identifier substringFromIndex:16] : identifier;
    }
    return nil;
}

static id objectResultForNoArgumentSelector(id object, SEL selector) {
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    // The private method may change its signature between Spotify releases. Only invoke the form
    // this fallback expects: an object return and no arguments beyond self/_cmd.
    if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = object;
    invocation.selector = selector;
    [invocation invoke];
    __unsafe_unretained id result = nil;
    [invocation getReturnValue:&result];
    return result;
}

// Local-file cover URLs are resolved by Spotify's own local-image URL category to a cached file.
// These selectors are private and vary between releases, so call them only when the runtime object
// advertises the selector and accept only an image or a readable local path as the result.
static UIImage *localImageFromValue(id value) {
    if ([value isKindOfClass:UIImage.class]) return value;

    NSMutableArray *candidates = [NSMutableArray array];
    if ([value isKindOfClass:NSURL.class]) [candidates addObject:value];
    if ([value isKindOfClass:NSString.class]) {
        NSString *string = value;
        NSURL *url = [NSURL URLWithString:string];
        if (url) [candidates addObject:url];
        [candidates addObject:string];
    }

    for (id candidate in candidates) {
        NSString *path = nil;
        if ([candidate isKindOfClass:NSURL.class] && [candidate isFileURL]) path = [candidate path];
        else if ([candidate isKindOfClass:NSString.class] && [candidate hasPrefix:@"/"]) path = candidate;

        // Spotify 9.1.74 exposes this local image path resolver in its binary. A runtime selector
        // check keeps this fallback inert if a later app version removes or renames it.
        SEL resolver = @selector(spt_localFileImagePath);
        if (!path && [candidate respondsToSelector:resolver]) {
            id resolved = objectResultForNoArgumentSelector(candidate, resolver);
            if ([resolved isKindOfClass:NSURL.class] && [resolved isFileURL]) path = [resolved path];
            else if ([resolved isKindOfClass:NSString.class] && [resolved hasPrefix:@"/"]) path = resolved;
        }
        if (path.length && [NSFileManager.defaultManager fileExistsAtPath:path]) {
            UIImage *image = [UIImage imageWithContentsOfFile:path];
            if (image) return image;
        }
    }
    return nil;
}

static UIImage *localArtwork(SPTPlayerTrack *track) {
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    if ([metadata isKindOfClass:NSDictionary.class]) {
        for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url", @"image_small_url"]) {
            UIImage *image = localImageFromValue(metadata[field]);
            if (image) return image;
        }
    }
    // Spotify already supplies this image to iOS for the lock screen; use it when the local
    // track metadata has no image URL the redesigned player can resolve.
    NSDictionary *nowPlaying = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    NSString *title = nowPlaying[MPMediaItemPropertyTitle];
    NSString *artist = nowPlaying[MPMediaItemPropertyArtist];
    if (title.length && track.trackTitle.length &&
        [title compare:track.trackTitle options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch] != NSOrderedSame) return nil;
    if (artist.length && track.artistName.length &&
        [artist compare:track.artistName options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch] != NSOrderedSame) return nil;
    id artwork = nowPlaying[MPMediaItemPropertyArtwork];
    if ([artwork isKindOfClass:UIImage.class]) return artwork;
    if ([artwork isKindOfClass:MPMediaItemArtwork.class])
        return [(MPMediaItemArtwork *)artwork imageWithSize:CGSizeMake(1200, 1200)];
    return nil;
}

static void publish(UIImage *image, NSString *key, SGRArtworkQuality quality) {
    sg_artwork = image;
    sg_artworkURI = sg_wantedURI;
    sg_artworkKey = key;
    sg_artworkQuality = quality;
    sg_artworkSerial++;
    [sg_published setObject:key forKey:image];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil userInfo:@{
        @"image": image,
        @"trackURI": sg_wantedURI ?: @"",
        @"quality": @(quality),
    }];
}

static NSURLSession *artworkSession(void) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
        // An image id is the picture's own digest, so a stored answer never goes stale.
        NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        configuration.URLCache = [[NSURLCache alloc] initWithMemoryCapacity:0 diskCapacity:24 * 1024 * 1024
                                                               directoryURL:[caches URLByAppendingPathComponent:@"spotifyglass-artwork"]];
        configuration.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
        configuration.timeoutIntervalForRequest = 20;
        session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}

static void fetchPicture(NSString *key, NSURL *url, NSUInteger attempt) {
    CFTimeInterval started = CACurrentMediaTime();
    sg_fetch = [artworkSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        UIImage *image = data.length && status == 200 ? [UIImage imageWithData:data] : nil;
        // Decoded here, off the main thread, rather than on the first frame that draws it.
        image = image.imageByPreparingForDisplay ?: image;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error.code == NSURLErrorCancelled) return;
            // A newer track asked for another picture meanwhile: this one would put the old one back.
            if (![key isEqualToString:sg_wantedKey]) {
                artworkLog(@"%@ came after the track moved on to %@, dropped", key, sg_wantedKey);
                return;
            }
            if (!image) {
                artworkLog(@"%@ not fetched (%ld, %@), attempt %lu", key, (long)status, error.localizedDescription, (unsigned long)attempt + 1);
                if (attempt + 1 >= kFetchAttempts) return;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFetchRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if ([key isEqualToString:sg_wantedKey] && !([sg_artworkKey isEqualToString:key] && sg_artworkQuality == SGRArtworkQualityExact)) {
                        fetchPicture(key, url, attempt + 1);
                    }
                });
                return;
            }
            artworkLog(@"%@ fetched %.0fx%.0f in %.0f ms", key, image.size.width, image.size.height, (CACurrentMediaTime() - started) * 1000);
            publish(image, key, SGRArtworkQualityExact);
        });
    }];
    [sg_fetch resume];
}

// Brings the playing track's picture up to date with the player's state, and fetches a picture newly
// wanted. Called on every state report and before any view read is believed, whichever comes first.
static void followPlayer(void) {
    SPTPlayerTrack *track = SGPlayerState().track;
    NSString *uri = SGURIString(track.URI);
    if (!uri) return;
    // The same track is looked at again only while its metadata has named no picture yet.
    BOOL local = [uri hasPrefix:@"spotify:local:"];
    if ([uri isEqualToString:sg_wantedURI] && ![sg_wantedKey hasPrefix:@"track:"] && !local) return;
    sg_wantedURI = uri;
    if (local) {
        UIImage *image = localArtwork(track);
        if (image) {
            NSString *key = [@"local-cache:" stringByAppendingString:uri];
            if (![key isEqualToString:sg_wantedKey]) {
                sg_wantedKey = key;
                [sg_fetch cancel];
                sg_fetch = nil;
            }
            if (![key isEqualToString:sg_artworkKey] || sg_artworkQuality != SGRArtworkQualityExact) {
                publish(image, key, SGRArtworkQualityExact);
            }
            return;
        }
    }
    NSURL *url = nil;
    // A track whose metadata names no picture is its own key: only the screens can show it then.
    NSString *key = pictureOf(track, &url) ?: [@"track:" stringByAppendingString:uri];
    if ([key isEqualToString:sg_wantedKey]) return;
    sg_wantedKey = key;
    [sg_fetch cancel];
    sg_fetch = nil;
    if ([key isEqualToString:sg_artworkKey] && sg_artworkQuality == SGRArtworkQualityExact) return;
    if (url) fetchPicture(key, url, 0);
}

void SGRSetNowPlayingArtwork(UIImage *image, NSString *trackURI, SGRArtworkQuality quality) {
    if (!image || !trackURI) return;
    followPlayer();
    // Read for a track that is no longer playing.
    if (![trackURI isEqualToString:sg_wantedURI]) return;
    NSString *key = sg_wantedKey;
    NSString *publishedAs = [sg_published objectForKey:image];
    // The screen still shows a picture published for another one.
    if (publishedAs && ![publishedAs isEqualToString:key]) {
        artworkLog(@"%@ still on screen while %@ is wanted, not believed", publishedAs, key);
        return;
    }
    if ([key isEqualToString:sg_artworkKey] && (image == sg_artwork || quality < sg_artworkQuality)) return;
    publish(image, key, MIN(quality, SGRArtworkQualityHigh));
}

UIImage *SGRNowPlayingArtwork(NSString **trackURI, NSString **identity) {
    if (trackURI) *trackURI = sg_artworkURI;
    // A fetched picture is known for what it is; one read off a screen is only what it looked like then,
    // so each of those is a picture of its own and a field redraws it.
    if (identity) {
        *identity = !sg_artwork ? nil : sg_artworkQuality == SGRArtworkQualityExact
            ? [sg_artworkKey stringByAppendingString:@"#exact"]
            : [NSString stringWithFormat:@"%@#%lu", sg_artworkKey, (unsigned long)sg_artworkSerial];
    }
    return sg_artwork;
}

// The player's reports, in the order they come.
@interface SGRArtworkFollower : NSObject <SGPlayerStateObserver>
@end

@implementation SGRArtworkFollower
- (void)playerStateDidChange:(SPTPlayerState *)state {
    followPlayer();
}
@end

static SGRArtworkFollower *sg_follower;

static char kBarCardKey, kBarImageKey;
static __weak UIView *sg_barView;

static void publishBarArtwork(void) {
    UIView *card = SGRFindByIdentifier(sg_barView, @"SPTNowPlayingBar", &kBarCardKey);
    UIView *holder = SGRFindByIdentifier(card, @"Encore.ImageView", &kBarImageKey);
    UIImageView *cover = nil;
    for (UIView *sub in holder.subviews) {
        if ([sub isKindOfClass:UIImageView.class]) cover = (UIImageView *)sub;
    }
    UIImage *image = cover.image;
    NSString *uri = SGURIString(SGPlayerState().track.URI);
    if (!image || !uri) return;
    SGRSetNowPlayingArtwork(image, uri, SGRArtworkQualityLow);
}

// The bar sets its picture when the image has loaded, which lays nothing out, so a track change looks
// again a few times while the picture comes in. One that loads later still is the fetch's to bring.
@interface SGRBarArtworkWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRBarArtworkWatcher {
    NSString *_track;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = SGURIString(state.track.URI);
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    for (NSNumber *delay in @[@0, @0.3, @1, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ publishBarArtwork(); });
    }
}

@end

static SGRBarArtworkWatcher *sg_barWatcher;

%group SGRBarArtworkHooks
%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    sg_barView = ((UIViewController *)self).viewIfLoaded;
    publishBarArtwork();
}
%end
%end

#pragma mark - the player's open and close

BOOL SGRPlayerIsTransitioning(void) {
    return SGPlayerTransitionEnds() > 0;
}

@interface SGRTransitionObservation : NSObject
@property (nonatomic, strong) NSArray *tokens;
@end

@implementation SGRTransitionObservation
- (void)dealloc {
    for (id token in self.tokens) [NSNotificationCenter.defaultCenter removeObserver:token];
}
@end

static char kTransitionKey;

void SGRObservePlayerTransition(id owner, void (^began)(id owner), void (^ended)(id owner)) {
    if (!owner) return;
    __weak id weakOwner = owner;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSMutableArray *tokens = [NSMutableArray array];
    if (began) {
        [tokens addObject:[center addObserverForName:SGPlayerTransitionNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            id strongOwner = weakOwner;
            if (strongOwner) began(strongOwner);
        }]];
    }
    if (ended) {
        [tokens addObject:[center addObserverForName:SGPlayerTransitionEndedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            id strongOwner = weakOwner;
            if (strongOwner) ended(strongOwner);
        }]];
    }
    SGRTransitionObservation *observation = [SGRTransitionObservation new];
    observation.tokens = tokens;
    NSMutableArray *kept = objc_getAssociatedObject(owner, &kTransitionKey);
    if (!kept) {
        kept = [NSMutableArray array];
        objc_setAssociatedObject(owner, &kTransitionKey, kept, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [kept addObject:observation];
}

%ctor {
    if (!SGRedesignedUI()) return;
    // By pointer: two images of one picture are still two reads.
    sg_published = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                             valueOptions:NSPointerFunctionsStrongMemory capacity:16];
    // Ahead of the watchers, so the picture a track wants is known before any screen is read for it.
    sg_follower = [SGRArtworkFollower new];
    SGAddPlayerStateObserver(sg_follower);
    sg_barWatcher = [SGRBarArtworkWatcher new];
    SGAddPlayerStateObserver(sg_barWatcher);
    %init(SGRBarArtworkHooks);
    SGRequireClasses(@[@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
}
