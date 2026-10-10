// Standalone dylib, separate from spotifyglass.dylib entirely: no shared symbols, no shared state,
// and critically - no hooking of anything Spotify or the real mod also hooks. An earlier version
// hooked SPTEsperantoPlayer.state, the exact method the real mod also hooks (KaraokeSource.x), and
// two independent dylibs' Logos-generated swizzles on the same selector crashed in practice - two
// method_exchangeImplementations swaps on the same selector from dylibs that don't know about each
// other is not safe, whatever the theory says. This version hooks nothing at all: it polls the
// public MPNowPlayingInfoCenter (which Spotify already populates for the lock screen and Control
// Center, same as any audio app) and matches the title against a small known-tracks table, since
// that API gives a title/artist, not Spotify's own track id - fine while there are only a couple of
// VTL tracks, not a real search.
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>

static NSString *const kVTLBase = @"https://api.vexqyq.com/lyrics/";
static NSString *sg_lastTitle;

// title substring -> VTL track id. Add a line here for each track uploaded to VTL.
static NSDictionary<NSString *, NSString *> *knownTracks(void) {
    return @{
        @"car keys": @"7tDPdMsVJFfF7p6BAi3s6n",
        @"boxed in": @"6IoOoTChdJ6MJL4uSAyXVO",
    };
}

static NSArray<NSString *> *linesFromTTML(NSString *xml) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<p\\b[^>]*>(.*?)</p>"
        options:NSRegularExpressionDotMatchesLineSeparators | NSRegularExpressionCaseInsensitive error:&err];
    if (!re) return out;
    [re enumerateMatchesInString:xml options:0 range:NSMakeRange(0, xml.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        NSString *inner = [xml substringWithRange:[m rangeAtIndex:1]];
        NSString *text = [inner stringByReplacingOccurrencesOfString:@"<[^>]+>" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, inner.length)];
        NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        text = [trimmed stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, trimmed.length)];
        if (text.length) [out addObject:text];
    }];
    return out;
}

static UIWindow *keyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return nil;
}

static void showCard(NSArray<NSString *> *lines) {
    UIWindow *win = keyWindow();
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (card.superview) dismiss();
    });
}

static void tryVTL(NSString *trackID) {
    if (!trackID.length) return;
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

static void pollNowPlaying(void) {
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    NSString *title = info[MPMediaItemPropertyTitle];
    if (!title.length || [title isEqualToString:sg_lastTitle]) return;
    sg_lastTitle = title;
    NSString *lower = title.lowercaseString;
    [knownTracks() enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *trackID, BOOL *stop) {
        if ([lower containsString:key]) { tryVTL(trackID); *stop = YES; }
    }];
}

static UIWindow *keyWindowForBadge(int attemptsLeft, void (^onFound)(UIWindow *win)) {
    UIWindow *win = keyWindow();
    if (win) { onFound(win); return win; }
    if (attemptsLeft > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            keyWindowForBadge(attemptsLeft - 1, onFound);
        });
    }
    return nil;
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        keyWindowForBadge(15, ^(UIWindow *win) {
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
        });

        NSTimer *timer = [NSTimer timerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) { pollNowPlaying(); }];
        [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    });
}
