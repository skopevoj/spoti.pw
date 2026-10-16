// A page of sources dragged into the order they are asked in; tapping one moves it below the line, off.
#import <UIKit/UIKit.h>

@class SGModSection;

@interface SGOrderItem : NSObject
@property (nonatomic, copy) NSString *key;      // stored in the order, never shown
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *detail;   // one line under the name
// Asked whenever the list is drawn: what keeps the item from working, shown in place of the detail.
@property (nonatomic, copy) NSString *(^problem)(void);
@end

SGOrderItem *SGOrderItemMake(NSString *key, NSString *name, NSString *detail);

// `items` in the order a fresh install asks them; `read` answers the keys switched on, in order, and
// `write` stores a new one. `note` sits under the list.
UIViewController *SGOrderPage(NSString *title, NSArray<SGOrderItem *> *items, NSArray<NSString *> *(^read)(void),
                              void (^write)(NSArray<NSString *> *order), NSString *note);
// The same with a card of rows (Settings/SGModPage.h) under the list, for what an item needs set up.
// Its switchless rows work as on any page; the list is drawn again when a row's refreshOn is posted.
UIViewController *SGOrderPageWithSection(NSString *title, NSArray<SGOrderItem *> *items, NSArray<NSString *> *(^read)(void),
                                         void (^write)(NSArray<NSString *> *order), NSString *note, SGModSection *extra);
