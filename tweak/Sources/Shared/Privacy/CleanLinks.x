// Clean shared links: strips tracking parameters (si, utm_*, nd, pt, context) when sharing or copying
// links to Spotify tracks, albums, playlists, artists and episodes.
#import "Core/SGCore.h"
#import "Privacy.h"

static NSString *cleanQueryInURLString(NSString *urlString) {
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    if (!components || ![components.host.lowercaseString isEqualToString:@"open.spotify.com"] || !components.queryItems.count) {
        return urlString;
    }
    NSMutableArray<NSURLQueryItem *> *kept = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems) {
        NSString *name = item.name.lowercaseString;
        if ([name isEqualToString:@"si"] ||
            [name hasPrefix:@"utm_"] ||
            [name isEqualToString:@"nd"] ||
            [name isEqualToString:@"pt"] ||
            [name isEqualToString:@"context"]) {
            continue;
        }
        [kept addObject:item];
    }
    components.queryItems = kept.count ? kept : nil;
    return components.string ?: urlString;
}

static NSString *cleanedSpotifyURLString(NSString *string) {
    if (!string || ![string containsString:@"open.spotify.com"]) return string;
    if ([string hasPrefix:@"http://"] || [string hasPrefix:@"https://"]) {
        NSString *cleaned = cleanQueryInURLString(string);
        if (cleaned) return cleaned;
    }
    static NSRegularExpression *regex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"https?://open\\.spotify\\.com/[^\\s]+"
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:nil];
    });
    if (!regex) return string;
    NSMutableString *result = [string mutableCopy];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:string options:0 range:NSMakeRange(0, string.length)];
    for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--) {
        NSRange range = matches[(NSUInteger)i].range;
        NSString *matchedURL = [string substringWithRange:range];
        NSString *cleanedURL = cleanQueryInURLString(matchedURL);
        if (cleanedURL && ![cleanedURL isEqualToString:matchedURL]) {
            [result replaceCharactersInRange:range withString:cleanedURL];
        }
    }
    return result;
}

static NSURL *cleanedSpotifyURL(NSURL *url) {
    if (!url) return nil;
    if (![url.host.lowercaseString isEqualToString:@"open.spotify.com"]) return url;
    NSString *clean = cleanedSpotifyURLString(url.absoluteString);
    return [NSURL URLWithString:clean] ?: url;
}

static id cleanedShareObject(id object) {
    if (!SGEnabled(SGKeyCleanSharedURLs) || !object) return object;
    if ([object isKindOfClass:NSString.class]) {
        return cleanedSpotifyURLString((NSString *)object);
    }
    if ([object isKindOfClass:NSURL.class]) {
        return cleanedSpotifyURL((NSURL *)object);
    }
    return object;
}

%hook UIPasteboard

- (void)setString:(NSString *)string {
    %orig(cleanedShareObject(string));
}

- (void)setURL:(NSURL *)url {
    %orig(cleanedShareObject(url));
}

- (void)setObjects:(NSArray *)objects {
    if (SGEnabled(SGKeyCleanSharedURLs) && objects.count) {
        NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:objects.count];
        for (id obj in objects) {
            [cleaned addObject:cleanedShareObject(obj)];
        }
        objects = cleaned;
    }
    %orig(objects);
}

- (void)setObjects:(NSArray *)objects options:(NSDictionary<UIPasteboardOption, id> *)options {
    if (SGEnabled(SGKeyCleanSharedURLs) && objects.count) {
        NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:objects.count];
        for (id obj in objects) {
            [cleaned addObject:cleanedShareObject(obj)];
        }
        objects = cleaned;
    }
    %orig(objects, options);
}

- (void)setItems:(NSArray<NSDictionary<NSString *, id> *> *)items options:(NSDictionary<UIPasteboardOption, id> *)options {
    if (SGEnabled(SGKeyCleanSharedURLs) && items.count) {
        NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:items.count];
        for (NSDictionary *dict in items) {
            NSMutableDictionary *m = [dict mutableCopy];
            for (NSString *key in dict) {
                m[key] = cleanedShareObject(dict[key]);
            }
            [cleaned addObject:m];
        }
        items = cleaned;
    }
    %orig(items, options);
}

%end

%hook UIActivityViewController

- (instancetype)initWithActivityItems:(NSArray *)activityItems applicationActivities:(NSArray<UIActivity *> *)applicationActivities {
    if (SGEnabled(SGKeyCleanSharedURLs) && activityItems.count) {
        NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:activityItems.count];
        for (id item in activityItems) {
            [cleaned addObject:cleanedShareObject(item)];
        }
        activityItems = cleaned;
    }
    return %orig(activityItems, applicationActivities);
}

%end

%hook UIActivityItemProvider

- (id)item {
    id res = %orig;
    return cleanedShareObject(res);
}

%end

%ctor {
    %init;
}
