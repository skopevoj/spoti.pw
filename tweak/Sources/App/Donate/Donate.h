// Donate: Ko-fi, asked for from the Mod Settings row, a sheet after the first welcome tour (after its
// restart when the look changed), then two days on and every fourteen after that.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

extern NSString *const SGKofiURL;
UIColor *SGKofiColor(void);

void SGShowDonateSheet(void);
SGModRow *SGDonateRow(void);
void SGWatchForDonate(void);
// A tour is done: the sheet follows it, or follows Home after the restart.
void SGDonateAfterTour(BOOL restarting);
BOOL SGDonateAfterTourPending(void);
void SGOfferDonate(void);
BOOL SGDonateShown(void);     // this run
void SGDonateHoldOff(void);   // another sheet asked instead; the next ask waits a full round
