// A page of sections of rows, the shape of every feature's settings page.
#import "SGPage.h"

// A row is a switch when it has a key, a link to another page when it has a page, a slider when it has
// a number and a view of its own when it has a view. A flag row
// switches one of Spotify's remote-config flags: on forces it (off for a forceOff row, which is how
// a flag Spotify ships on is turned off), the switch off leaves Spotify's own value. A row
// with a value reads one out on the right and is asked again while the page is open; a page row
// with a value reads it out too, next to the chevron, and is asked when the page appears. A row
// with an action runs it when tapped.
@interface SGModRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *key;
@property (nonatomic) BOOL defaultOn;
@property (nonatomic) BOOL flag;
@property (nonatomic) BOOL forceOff;
@property (nonatomic, copy) UIViewController *(^page)(void);
@property (nonatomic, copy) NSString *(^value)(void);
@property (nonatomic, copy) void (^action)(void);
@property (nonatomic, copy) NSString *warning;
@property (nonatomic, copy) void (^changed)(BOOL on);   // after the switch is stored; the page reloads
@property (nonatomic, strong) UIColor *color;   // title, subtitle and symbol, for a warning row
@property (nonatomic, copy) NSString *symbol;
// A switch row that changes the whole app draws SGGlowSwitch instead of a UISwitch.
@property (nonatomic) BOOL glows;
// An ⓘ button beside the row's switch, whose tap reads this out under the row's title.
@property (nonatomic, copy) NSString *info;
// The row shows only while this answers YES, asked again whenever a switch on the page is flipped, a row is
// tapped or the page comes back from a choice's list: the row fades in or out where it sits, and a section
// whose rows are all hidden goes with its header and footer. Nil shows it always.
@property (nonatomic, copy) BOOL (^visible)(void);
// A row of a list picked from on the page itself (SGChoiceListRows): a checkmark while this answers YES.
@property (nonatomic, copy) BOOL (^checked)(void);
// A row that is a view of its own, `height` tall, on no card (SGViewRow).
@property (nonatomic, strong) UIView *view;
@property (nonatomic) CGFloat height;
// A choice row's: a line under each name in its list, in the same order, and what runs once one is stored.
@property (nonatomic, copy) NSArray<NSString *> *choiceNotes;
@property (nonatomic, copy) NSString *choiceFooter;   // under a choice row's list
@property (nonatomic, copy) void (^chosen)(NSInteger index);
// A slider row's (SGSliderRow): its range and step, and the blocks that read its number, store one and
// write one out.
@property (nonatomic) double minimum, maximum, step;
@property (nonatomic, copy) double (^number)(void);
@property (nonatomic, copy) void (^setNumber)(double value);
@property (nonatomic, copy) NSString *(^format)(double value);
// A row whose value moves along with something going on (a download): a thin bar along its bottom shows
// `progress` while it answers 0...1 and goes while it answers less, and whenever `refreshOn` is posted
// the page reads its rows out again and asks which of them show, rather than waiting for its next tick.
@property (nonatomic, copy) double (^progress)(void);
@property (nonatomic, copy) NSNotificationName refreshOn;
@end

@interface SGModSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<SGModRow *> *rows;
@property (nonatomic, copy) NSString *footer;
@property (nonatomic, copy) NSString *footerLink;   // an address the footer ends with and opens when tapped
@end

@interface SGModPage : SGPage
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray<SGModSection *> *)sections footer:(NSString *)footer;
@end

// The intro of every page whose switches the hooks read at launch.
extern NSString *const SGRestartNote;

SGModRow *SGSwitchRow(NSString *title, NSString *subtitle, NSString *key);   // on until switched off
SGModRow *SGHideRow(NSString *title, NSString *subtitle, NSString *key);     // off until switched on
// A switch for something the mod adds rather than takes away: off until it is asked for.
SGModRow *SGOptionRow(NSString *title, NSString *subtitle, NSString *key);
// A switch whose work is not finished: turning it on says so first, and offers the repo.
SGModRow *SGUnstableRow(NSString *title, NSString *subtitle, NSString *key, NSString *warning);
SGModRow *SGFlagRow(NSString *title, NSString *key);   // forces one of Spotify's flags on
SGModRow *SGKillRow(NSString *title, NSString *key);   // forces a flag Spotify ships on off
SGModRow *SGStatRow(NSString *title, NSString *(^value)(void));
SGModRow *SGActionRow(NSString *title, NSString *subtitle, void (^action)(void));
// Red, with a warning symbol: something is wrong and tapping the row says what to do about it.
SGModRow *SGWarningRow(NSString *title, NSString *subtitle, void (^action)(void));
SGModRow *SGPageRow(NSString *title, UIViewController *(^page)(void));
// A setting picked from a list of names, stored under `key` as the index into it: the row reads the
// name of the current one out and opens a list of them, a checkmark against that one.
SGModRow *SGChoiceRow(NSString *title, NSString *subtitle, NSString *key, NSArray<NSString *> *choices, NSInteger fallback);
// The same setting listed on the page itself, one row per name over its note, a checkmark against the one
// set: a tap stores it and runs `chosen`, and the rows that show only for some choices come or go under it.
NSArray<SGModRow *> *SGChoiceListRows(NSString *key, NSArray<NSString *> *choices, NSArray<NSString *> *notes, NSInteger fallback,
                                      void (^chosen)(NSInteger index));
// A view in the list as it is, with no card behind it: a preview, alone in its section, over the rows that
// set it.
SGModRow *SGViewRow(UIView *view, CGFloat height);
// A number on a slider under the row's title, written out by `format` on the right: the thumb snaps to
// `step` and each step is stored through `set` as the thumb reaches it, so a setting applying as it
// changes applies while it is dragged. `subtitle` may be nil.
SGModRow *SGSliderRow(NSString *title, NSString *subtitle, double minimum, double maximum, double step,
                      double (^get)(void), void (^set)(double value), NSString *(^format)(double value));
SGModRow *SGLinkRow(NSString *title, NSString *subtitle, NSString *url);
// A text typed into an alert, `prompt` over the field and `placeholder` in it: the row reads `value`
// out, Save hands `set` what was typed and Remove an empty string. `set` answers what is wrong with the
// text, which is said, or nil once it is stored. The field starts empty: what is stored may be private.
SGModRow *SGTextRow(NSString *title, NSString *prompt, NSString *placeholder, NSString *(^value)(void),
                    NSString *(^set)(NSString *text));
SGModRow *SGStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void));
SGModSection *SGSection(NSString *title, NSArray<SGModRow *> *rows);
SGModSection *SGNotedSection(NSString *title, NSArray<SGModRow *> *rows, NSString *footer);
// Gives a row its leading symbol, drawn on a tile unless the row has a colour of its own.
SGModRow *SGWithSymbol(SGModRow *row, NSString *symbol);
// A row as the page draws it, but for the switch a row with a key gets from the page, for other lists
// that carry rows of this kind (Settings/SGOrderPage).
void SGFillRowCell(UITableViewCell *cell, SGModRow *row);
UIView *SGSectionFooterFor(UITableView *table, SGModSection *section);
CGFloat SGSectionFooterHeightFor(UITableView *table, SGModSection *section);
