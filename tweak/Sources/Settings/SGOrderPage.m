#import "SGOrderPage.h"
#import "SGModPage.h"
#import "SGPage.h"
#import "SGPageStyle.h"

@implementation SGOrderItem
@end

SGOrderItem *SGOrderItemMake(NSString *key, NSString *name, NSString *detail) {
    SGOrderItem *item = [SGOrderItem new];
    item.key = key;
    item.name = name;
    item.detail = detail;
    return item;
}

typedef NS_ENUM(NSInteger, SGOrderSection) {
    SGOrderSectionOn = 0,
    SGOrderSectionOff,
    SGOrderSectionExtra,
};

@interface SGOrderController : SGPage
@property (nonatomic, copy) NSArray<SGOrderItem *> *items;
@property (nonatomic, copy) NSArray<NSString *> *(^read)(void);
@property (nonatomic, copy) void (^write)(NSArray<NSString *> *order);
@property (nonatomic, copy) NSString *note;
@property (nonatomic, strong) SGModSection *extra;
@end

@implementation SGOrderController {
    NSMutableArray<NSString *> *_on;    // keys, in the order they are asked
    NSMutableArray<NSString *> *_off;
    UIView *_footer;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (SGOrderItem *)itemFor:(NSString *)key {
    for (SGOrderItem *item in self.items) {
        if ([item.key isEqualToString:key]) return item;
    }
    return nil;
}

- (void)load {
    _on = [NSMutableArray array];
    for (NSString *key in self.read()) {
        if ([self itemFor:key]) [_on addObject:key];
    }
    _off = [NSMutableArray array];
    for (SGOrderItem *item in self.items) {
        if (![_on containsObject:item.key]) [_off addObject:item.key];
    }
}

- (void)save {
    self.write(_on);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self load];
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
    _footer = SGNote(self.note);
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

// A row's alert or an item's problem changes under the page, so it is drawn again when it shows and
// whenever a row says so.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    for (SGModRow *row in self.extra.rows) {
        if (!row.refreshOn) continue;
        [NSNotificationCenter.defaultCenter removeObserver:self name:row.refreshOn object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(redraw) name:row.refreshOn object:nil];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    for (SGModRow *row in self.extra.rows) {
        if (row.refreshOn) [NSNotificationCenter.defaultCenter removeObserver:self name:row.refreshOn object:nil];
    }
}

- (void)redraw {
    [self.tableView reloadData];
}

- (NSMutableArray<NSString *> *)keysIn:(NSInteger)section {
    return section == SGOrderSectionOn ? _on : _off;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return self.extra ? SGOrderSectionExtra + 1 : SGOrderSectionExtra;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == SGOrderSectionExtra) return (NSInteger)self.extra.rows.count;
    return (NSInteger)[self keysIn:section].count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    if (section == SGOrderSectionOn) return SGSectionHeader(table, _on.count ? @"Asked in this order" : @"None on");
    if (section == SGOrderSectionExtra) return self.extra.title ? SGSectionHeader(table, self.extra.title) : nil;
    return _off.count ? SGSectionHeader(table, @"Off") : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    if (section == SGOrderSectionExtra) return self.extra.title ? SGSectionHeaderHeight : SGSectionGap;
    return section == SGOrderSectionOn || _off.count ? SGSectionHeaderHeight : CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return section == SGOrderSectionExtra ? SGSectionFooterFor(table, self.extra) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return section == SGOrderSectionExtra ? SGSectionFooterHeightFor(table, self.extra) : CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == SGOrderSectionExtra) {
        UITableViewCell *cell = SGDequeueCell(table, @"row");
        SGFillRowCell(cell, self.extra.rows[(NSUInteger)path.row]);
        return cell;
    }
    UITableViewCell *cell = SGDequeueCell(table, @"source");
    SGOrderItem *item = [self itemFor:[self keysIn:path.section][(NSUInteger)path.row]];
    BOOL on = path.section == SGOrderSectionOn;
    // The asked ones are numbered, so the order reads as an order rather than a list.
    NSString *title = on ? [NSString stringWithFormat:@"%ld. %@", (long)path.row + 1, item.name] : item.name;
    NSString *problem = item.problem ? item.problem() : nil;
    SGFillCell(cell, title, problem ?: item.detail, on ? nil : SGGrey(), on ? @"checkmark.circle.fill" : @"circle");
    if (problem && on) {
        UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
        content.secondaryTextProperties.color = SGRed();
        cell.contentConfiguration = content;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGOrderSectionOn;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section != SGOrderSectionExtra;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path {
    return NO;
}

// Dragging stays inside the order; a source is switched on and off by tapping it, not by dropping
// it into the other section, so an order is never lost to a stray drag.
- (NSIndexPath *)tableView:(UITableView *)table targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    return to.section == SGOrderSectionOn ? to : from;
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSString *key = _on[(NSUInteger)from.row];
    [_on removeObjectAtIndex:(NSUInteger)from.row];
    [_on insertObject:key atIndex:(NSUInteger)to.row];
    [self save];
    [table reloadData];   // the numbers in front of the names have all moved
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == SGOrderSectionExtra) {
        SGModRow *row = self.extra.rows[(NSUInteger)path.row];
        if (row.page) [self.navigationController pushViewController:row.page() animated:YES];
        if (row.action) row.action();
        return;
    }
    NSString *key = [self keysIn:path.section][(NSUInteger)path.row];
    if (path.section == SGOrderSectionOn) {
        [_on removeObject:key];
        // Back to where it sits among the sources that are off, in the order they all come in.
        NSUInteger at = 0;
        for (SGOrderItem *item in self.items) {
            if ([item.key isEqualToString:key]) break;
            if ([_off containsObject:item.key]) at++;
        }
        [_off insertObject:key atIndex:at];
    } else {
        [_off removeObject:key];
        [_on addObject:key];
    }
    [self save];
    [table reloadData];
}

@end

UIViewController *SGOrderPageWithSection(NSString *title, NSArray<SGOrderItem *> *items, NSArray<NSString *> *(^read)(void),
                                         void (^write)(NSArray<NSString *> *order), NSString *note, SGModSection *extra) {
    SGOrderController *page = [SGOrderController new];
    page.title = title;
    page.items = items;
    page.read = read;
    page.write = write;
    page.note = note;
    page.extra = extra;
    return page;
}

UIViewController *SGOrderPage(NSString *title, NSArray<SGOrderItem *> *items, NSArray<NSString *> *(^read)(void),
                              void (^write)(NSArray<NSString *> *order), NSString *note) {
    return SGOrderPageWithSection(title, items, read, write, note, nil);
}
