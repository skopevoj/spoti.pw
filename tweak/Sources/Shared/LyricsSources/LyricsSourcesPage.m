#import "Settings/SGModPage.h"
#import "Settings/SGOrderPage.h"
#import "LyricsSources.h"

static NSString *const kSpicyDashboard = @"https://developers.spicylyrics.org/dashboard";

static SGModSection *spicySection(void) {
    SGModRow *key = SGTextRow(@"Spicy Lyrics key",
        @"Paste the publishable key (sl_pk_…) of your application on Spicy Lyrics' developer platform.", @"sl_pk_…",
        ^NSString *{
            NSString *shown = SGSpicyLyricsKeyShown();
            return !shown ? @"Not set" : SGSpicyLyricsProblem() ? @"Rejected" : shown;
        },
        ^NSString *(NSString *text) { return SGSpicyLyricsSetKey(text); });
    key.refreshOn = SGSpicyLyricsKeyDidChangeNotification;
    SGModSection *section = SGNotedSection(@"Spicy Lyrics", @[key],
        @"Spicy Lyrics needs a free key of your own. Sign up on its developer platform, create an application, turn "
         "on client access with No origin header allowed, and paste the publishable key here. The lyrics show "
         "who synced them, as its terms require.");
    section.footerLink = kSpicyDashboard;
    return section;
}

UIViewController *SGLyricsSourcesPage(void) {
    NSMutableArray<SGOrderItem *> *items = [NSMutableArray array];
    for (SGLyricsProvider *provider in SGLyricsAllProviders()) {
        SGOrderItem *item = SGOrderItemMake(provider.key, provider.name, provider.detail);
        if ([provider.key isEqualToString:@"spicylyrics"]) item.problem = ^NSString *{ return SGSpicyLyricsProblem(); };
        [items addObject:item];
    }
    return SGOrderPageWithSection(@"Lyrics sources", items, ^NSArray<NSString *> *{ return SGLyricsOrder(); },
                                  ^(NSArray<NSString *> *order) { SGLyricsSetOrder(order); },
                                  @"Asked top to bottom until one has word timing. Sources get only the track, never "
                                   "your account.", spicySection());
}
