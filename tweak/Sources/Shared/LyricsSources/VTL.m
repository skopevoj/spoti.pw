// VTL, a self-hosted source for hand-curated TTML: one file per track, uploaded by hand, served from
// api.vexqyq.com. Matches by Spotify's own track id - the same file a track plays under is the file
// it is looked up under, no search and nothing to name first. Answers nothing for a track nobody has
// uploaded a file for, which is most of them; that is by design, not a bug.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kAPI = @"https://api.vexqyq.com/lyrics/";

SGLyricsAsk SGVTLAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    NSURL *url = [NSURL URLWithString:[kAPI stringByAppendingString:query.trackID]];
    SGLyricsGetText(url, ^(NSString *ttml) {
        if (!ttml.length) {
            done(nil);
            return;
        }
        NSArray<SGKaraokeLine *> *lines = SGTTMLLines(ttml);
        if (!lines) {
            SGLog(@"vtl: %@ gave nothing the page could show", query.trackID);
            done(nil);
            return;
        }
        SGLyricsResult *result = [SGLyricsResult new];
        result.synced = YES;
        result.wordTimed = SGKaraokeLinesTiming(lines) == SGKaraokeTimingWords;
        result.karaokeLines = lines;
        NSArray<NSNumber *> *starts;
        NSArray<NSString *> *texts;
        SGLyricsPageLines(lines, &starts, &texts);
        result.starts = starts;
        result.texts = texts;
        SGLog(@"vtl: %@ has %lu %@ lines", query.trackID, (unsigned long)lines.count,
              result.wordTimed ? @"word timed" : @"line timed");
        done(result);
    });
};
