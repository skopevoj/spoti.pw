// Standalone dylib, separate from spotifyglass.dylib entirely: no shared symbols, no shared state.
// Hooks the exact same two classes the real mod hooks for the same reason (observing Spotify's own
// color-lyrics replies as they pass through its networking stack) - same hook targets, same %orig
// chaining pattern, so this coexists with the real dylib instead of fighting it. When Spotify's own
// reply has no lines, this fetches VTL's own hosted TTML for the same track id and, if found, pops
// up a small self-contained card automatically - it does not touch the real mod's lyrics page or any
// of its private symbols, so there is nothing here that can corrupt its state.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kLyricsPath = @"/color-lyrics/v2/track/";
static NSString *const kVTLBase = @"https://api.vexqyq.com/lyrics/";
static char kBodyKey;
static NSMutableSet<NSString *> *sg_vtlTried;   // one VTL lookup per track id per app run

static NSString *trackInURL(NSURL *url) {
    NSString *path = url.path;
    NSRange marker = [path rangeOfString:kLyricsPath];
    if (marker.location == NSNotFound) return nil;
    NSString *track = [[path substringFromIndex:NSMaxRange(marker)] componentsSeparatedByString:@"/"].firstObject;
    return track.length ? track : nil;
}

// True when Spotify's own color-lyrics JSON genuinely has no lines - a light check (not a full
// protobuf/JSON parser for every shape Spotify might reply with), good enough to decide whether to
// also try VTL, not to replace the real mod's own, more thorough body parsing.
static BOOL looksEmpty(NSData *body) {
    if (body.length < 200) return YES;   // a real lyrics reply, JSON or protobuf, runs well past this
    id root = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if (![root isKindOfClass:NSDictionary.class]) return NO;   // sizeable and not JSON - has real content, don't guess further
    id lyrics = root[@"lyrics"];
    if (![lyrics isKindOfClass:NSDictionary.class]) return YES;
    id lines = lyrics[@"lines"];
    return !([lines isKindOfClass:NSArray.class] && [lines count] > 0);
}

// A minimal TTML line reader: just the text of each <p>, nothing about syllables, voices or
// translations - enough for a plain scrolling lyrics card, not a full karaoke view.
static NSArray<NSString *> *linesFromTTML(NSString *xml) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<p\\b[^>]*>(.*?)</p>"
        options:NSRegularExpressionDotMatchesLineSeparators | NSRegularExpressionCaseInsensitive error:&err];
    if (!re) return out;
    [re enumerateMatchesInString:xml options:0 range:NSMakeRange(0, xml.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        NSString *inner = [xml substringWithRange:[m rangeAtIndex:1]];
        // Strip any nested tags (<span> for word timing etc), keep the text.
        NSString *text = [inner stringByReplacingOccurrencesOfString:@"<[^>]+>" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, inner.length)];
        text = [[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
            stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, text.length)];
        if (text.length) [out addObject:text];
    }];
    return out;
}

static void showCard(NSArray<NSString *> *lines) {
    UIWindow *win = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
        }
        if (win) break;
    }
    if (!win) return;

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.92];
    card.layer.cornerRadius = 18;
    card.clipsToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [UILabel new];
    title.text = @"Lyrics from VTL";
    title.textColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.43 alpha:1];
    title.font = [UIFont boldSystemFontOfSize:12];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *body = [UILabel new];
    body.numberOfLines = 0;
    body.textColor = UIColor.whiteColor;
    body.font = [UIFont systemFontOfSize:15];
    body.text = [lines componentsJoinedByString:@"\n"];
    body.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"Close" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithRed:0.35 green:1.0 blue:0.43 alpha:1] forState:UIControlStateNormal];
    close.translatesAutoresizingMaskIntoConstraints = NO;

    [scroll addSubview:body];
    [card addSubview:title];
    [card addSubview:scroll];
    [card addSubview:close];
    [win addSubview:card];

    UILayoutGuide *safe = win.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [card.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-100],
        [card.heightAnchor constraintEqualToConstant:260],

        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],

        [close.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
        [close.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],

        [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [scroll.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],

        [body.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [body.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [body.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [body.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],
    ]];

    void (^dismiss)(void) = ^{
        [UIView animateWithDuration:0.25 animations:^{ card.alpha = 0; } completion:^(BOOL done) { [card removeFromSuperview]; }];
    };
    [close addAction:[UIAction actionWithHandler:^(UIAction *a) { dismiss(); }] forControlEvents:UIControlEventTouchUpInside];

    card.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{ card.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (card.superview) dismiss();
    });
}

static void tryVTL(NSString *trackID) {
    if (!trackID.length) return;
    @synchronized (sg_vtlTried) {
        if ([sg_vtlTried containsObject:trackID]) return;
        [sg_vtlTried addObject:trackID];
    }
    NSURL *url = [NSURL URLWithString:[kVTLBase stringByAppendingString:trackID]];
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        if (error || status != 200 || !data.length) return;
        NSString *xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSArray<NSString *> *lines = xml ? linesFromTTML(xml) : nil;
        if (!lines.count) return;
        dispatch_async(dispatch_get_main_queue(), ^{ showCard(lines); });
    }] resume];
}

static void received(NSURLSession *session, NSURLSessionTask *task, NSData *data) {
    if (!trackInURL(task.currentRequest.URL)) return;
    NSMutableData *body = objc_getAssociatedObject(task, &kBodyKey);
    if (!body) objc_setAssociatedObject(task, &kBodyKey, (body = [NSMutableData data]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [body appendData:data];
}

static void completed(NSURLSessionTask *task, NSError *error) {
    NSMutableData *body = objc_getAssociatedObject(task, &kBodyKey);
    if (!body) return;
    objc_setAssociatedObject(task, &kBodyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSString *track = trackInURL(task.currentRequest.URL);
    if (error || !track) return;
    if (looksEmpty(body)) tryVTL(track);
}

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    received(session, task, data);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completed(task, error);
    %orig;
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    received(session, task, data);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completed(task, error);
    %orig;
}
%end

// Diagnostic only: proves the dylib is actually loaded and running, separate from whether the
// lyrics-detection logic works. No key window exists yet at %ctor time, so this retries briefly
// until one shows up, then shows a small badge for a few seconds and never again this run.
static void showLoadedBadge(int attemptsLeft) {
    UIWindow *win = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { win = w; break; }
        }
        if (win) break;
    }
    if (!win) {
        if (attemptsLeft > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                showLoadedBadge(attemptsLeft - 1);
            });
        }
        return;
    }
    UILabel *badge = [UILabel new];
    badge.text = @"VTLAuto active";
    badge.textColor = UIColor.blackColor;
    badge.backgroundColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.43 alpha:1];
    badge.font = [UIFont boldSystemFontOfSize:11];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 8;
    badge.clipsToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [win addSubview:badge];
    [NSLayoutConstraint activateConstraints:@[
        [badge.topAnchor constraintEqualToAnchor:win.safeAreaLayoutGuide.topAnchor constant:6],
        [badge.centerXAnchor constraintEqualToAnchor:win.centerXAnchor],
        [badge.widthAnchor constraintEqualToConstant:120],
        [badge.heightAnchor constraintEqualToConstant:22],
    ]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{ badge.alpha = 0; } completion:^(BOOL done) { [badge removeFromSuperview]; }];
    });
}

%ctor {
    sg_vtlTried = [NSMutableSet set];
    dispatch_async(dispatch_get_main_queue(), ^{ showLoadedBadge(15); });
}
