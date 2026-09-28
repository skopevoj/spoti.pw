#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "App/About/About.h"
#import "App/Onboarding/Onboarding.h"
#import "Donate.h"
#import "App/Sheet/SGCardSheet.h"

NSString *const SGKofiURL = @"https://ko-fi.com/darkksh";

// Outside the "spotifyglass." prefix, so Reset all settings does not bring the sheet back early.
static NSString *const kNextKey = @"spotipw.donate.next";
static NSString *const kAfterTourKey = @"spotipw.donate.aftertour";
static const NSTimeInterval kDay = 86400;
static const NSTimeInterval kFirstAsk = 2 * kDay, kEvery = 14 * kDay, kAfterDonating = 90 * kDay;
static const NSTimeInterval kSettle = 20, kRetry = 5;
static const NSInteger kTries = 24;

UIColor *SGKofiColor(void) { return SGColorHex(0xFF5E5B, 1); }

#pragma mark - schedule

static NSTimeInterval now(void) {
    return NSDate.date.timeIntervalSince1970;
}

static NSTimeInterval nextAsk(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    double next = [store doubleForKey:kNextKey];
    if (next <= 0) {
        next = now() + kFirstAsk;
        [store setDouble:next forKey:kNextKey];
    }
    return next;
}

static void askAgainIn(NSTimeInterval wait) {
    [NSUserDefaults.standardUserDefaults setDouble:now() + wait forKey:kNextKey];
}

BOOL SGDonateAfterTourPending(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:kAfterTourKey];
}

#pragma mark - sheet

// The cup on a warm Ko-fi disc, with a heart badge on its shoulder.
static UIView *hero(UIImageView **cupOut, UIImageView **heartOut) {
    UIView *disc = SGCardSheetDisc(SGColorHex(0xFF8A7A, 1), SGColorHex(0xE8434B, 1), SGKofiColor());
    UIImageView *cup = SGSymbolView(@"cup.and.saucer.fill", 32, UIImageSymbolWeightSemibold, 80);
    cup.tintColor = UIColor.whiteColor;
    cup.translatesAutoresizingMaskIntoConstraints = NO;
    [disc addSubview:cup];
    UIImageView *heart = SGSymbolView(@"heart.fill", 13, UIImageSymbolWeightBold, 28);
    heart.tintColor = SGKofiColor();
    heart.backgroundColor = UIColor.whiteColor;
    heart.layer.cornerRadius = 14;
    heart.translatesAutoresizingMaskIntoConstraints = NO;
    [disc addSubview:heart];
    [NSLayoutConstraint activateConstraints:@[
        [cup.centerXAnchor constraintEqualToAnchor:disc.centerXAnchor],
        [cup.centerYAnchor constraintEqualToAnchor:disc.centerYAnchor],
        [heart.widthAnchor constraintEqualToConstant:28],
        [heart.heightAnchor constraintEqualToConstant:28],
        [heart.trailingAnchor constraintEqualToAnchor:disc.trailingAnchor constant:4],
        [heart.bottomAnchor constraintEqualToAnchor:disc.bottomAnchor constant:2],
    ]];
    *cupOut = cup;
    *heartOut = heart;
    return disc;
}

static void bounce(UIImageView *view, NSTimeInterval delay) {
    if (@available(iOS 17.0, *)) {
        __weak UIImageView *weak = view;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weak addSymbolEffect:[NSClassFromString(@"NSSymbolBounceEffect") effect]];
        });
    }
}

#pragma mark - entry

static BOOL sg_offered;

void SGShowDonateSheet(void) {
    UIImageView *cup, *heart;
    SGCardSheet *sheet = [SGCardSheet new];
    sheet.color = SGKofiColor();
    sheet.hero = hero(&cup, &heart);
    sheet.eyebrow = @"A STUDENT PROJECT";
    sheet.heading = @"Enjoying spoti.pw?";
    sheet.body = @"I'm a student and I build it for free, in my spare time. If it made your music better, a coffee helps me keep going.";
    sheet.actionTitle = @"Buy me a coffee";
    sheet.actionSymbol = @"cup.and.saucer.fill";
    sheet.dismissTitle = @"Maybe later";
    sheet.action = ^{
        askAgainIn(kAfterDonating);
        SGLog(@"donate: opened Ko-fi");
        SGOpenURL(SGKofiURL);
    };
    sheet.appeared = ^{
        bounce(cup, 0.35);
        bounce(heart, 0.6);
    };
    [sheet present];
}

SGModRow *SGDonateRow(void) {
    SGModRow *row = SGWithSymbol(SGActionRow(@"Support spoti.pw", @"Buy the student behind it a coffee", ^{ SGShowDonateSheet(); }), @"cup.and.saucer.fill");
    row.color = SGKofiColor();
    return row;
}

// Never over the tour or an alert. On schedule it also stays out of an update-notice run and asks once
// a run; after a tour, first or replayed from the Mod page, it always comes.
static void offerWhenClear(NSInteger tries) {
    BOOL afterTour = SGDonateAfterTourPending();
    if (!afterTour && (sg_offered || now() < nextAsk() || SGUpdateNoticeShown() || SGCertificateOfferShown())) return;
    UIViewController *top = SGTopController();
    BOOL busy = !top || SGOnboardingShowing() || [top isKindOfClass:UIAlertController.class]
        || UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
    if (busy) {
        if (tries > 0)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ offerWhenClear(tries - 1); });
        return;
    }
    sg_offered = YES;
    askAgainIn(kEvery);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kAfterTourKey];
    SGShowDonateSheet();
    SGLog(@"donate: asked over %@%@", NSStringFromClass(top.class), afterTour ? @", after the tour" : @"");
}

BOOL SGDonateShown(void) {
    return sg_offered;
}

void SGDonateHoldOff(void) {
    if (nextAsk() < now() + kEvery) askAgainIn(kEvery);
}

void SGDonateAfterTour(BOOL restarting) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kAfterTourKey];
    if (!restarting) SGOfferDonate();
}

void SGOfferDonate(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ offerWhenClear(kTries); });
}

void SGWatchForDonate(void) {
    nextAsk();
    __block id observer = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                          object:nil
                                                                           queue:NSOperationQueue.mainQueue
                                                                      usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ offerWhenClear(kTries); });
    }];
}
