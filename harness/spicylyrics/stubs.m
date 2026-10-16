// What SpicyLyrics.m links against beyond the real line model: the lyrics value types, the request
// (answered with whatever the test sets), the walk's failure count, the page lines and the language.
#import "Core/SGCore.h"
#import "LyricsSources.h"

@implementation SGLyricsCredit @end
@implementation SGLyricsResult @end
@implementation SGLyricsQuery @end
@implementation SGLyricsProvider @end

@implementation SGHarnessDefaults {
    NSMutableDictionary *_values;
}
+ (instancetype)standardUserDefaults {
    static SGHarnessDefaults *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [SGHarnessDefaults new];
        shared->_values = [NSMutableDictionary dictionary];
    });
    return shared;
}
- (id)objectForKey:(NSString *)key { return _values[key]; }
- (NSString *)stringForKey:(NSString *)key { id value = _values[key]; return [value isKindOfClass:NSString.class] ? value : nil; }
- (void)setObject:(id)value forKey:(NSString *)key { _values[key] = value; }
- (void)removeObjectForKey:(NSString *)key { [_values removeObjectForKey:key]; }
@end

// What the last request carried, how many went out, and what the next one is answered with.
NSURL *sg_sentTo;
NSDictionary<NSString *, NSString *> *sg_sentHeaders;
NSUInteger sg_sentCount;
id sg_replyBody;
NSInteger sg_replyStatus = 200;
NSDictionary<NSString *, NSString *> *sg_replyHeaders;
NSInteger sg_notedFailures;
NSString *sg_language;

void SGLyricsGetJSONReply(NSURL *url, NSDictionary<NSString *, NSString *> *headers,
                          void (^done)(id root, NSHTTPURLResponse *response)) {
    sg_sentTo = url;
    sg_sentHeaders = headers;
    sg_sentCount++;
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:sg_replyStatus HTTPVersion:@"HTTP/2"
                                                            headerFields:sg_replyHeaders ?: @{}];
    SGLyricsNoteReply(response, nil);
    done(sg_replyBody, response);
}

void SGLyricsNoteReply(NSURLResponse *response, NSError *error) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    if (error || status == 429 || status >= 500) sg_notedFailures++;
}

NSString *SGLyricsTranslationLanguage(void) {
    return sg_language;
}

// LyricsSources.m's own, less the ♪ lines it puts between breaks.
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray<NSNumber *> *at = [NSMutableArray array];
    NSMutableArray<NSString *> *said = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line);
        if (line.backing) text = [text stringByAppendingFormat:@" %@", SGKaraokeLineText(line.backing)];
        [at addObject:@(line.start)];
        [said addObject:text];
    }
    *starts = at;
    *texts = said;
}
