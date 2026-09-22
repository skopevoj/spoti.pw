#import "NavbarIconPicker.h"
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Headers/SPTEncoreIconView.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

static id encoreIconNamed(NSString *name) {
    Class iconClass = NSClassFromString(@"SPTEncoreIcon");
    SEL selector = NSSelectorFromString(name);
    if (!iconClass || !name.length || ![iconClass respondsToSelector:selector]) return nil;
    id (*makeIcon)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return makeIcon(iconClass, selector);
}

// SPTEncoreIcon exposes one zero-argument class method per glyph. Reading the class at runtime keeps
// this page current when Spotify adds an icon, without maintaining a second hard-coded list in the mod.
static NSArray<NSString *> *encoreIconNames(void) {
    Class iconClass = NSClassFromString(@"SPTEncoreIcon");
    if (!iconClass) return @[];

    NSMutableSet<NSString *> *names = [NSMutableSet set];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(object_getClass(iconClass), &count);
    for (unsigned int i = 0; i < count; i++) {
        Method method = methods[i];
        if (method_getNumberOfArguments(method) != 2) continue;
        const char *types = method_getTypeEncoding(method);
        if (!types || types[0] != '@') continue;

        const char *cName = sel_getName(method_getName(method));
        if (!cName || strchr(cName, ':')) continue;
        NSString *name = [NSString stringWithUTF8String:cName];
        id icon = encoreIconNamed(name);
        NSString *reportedName = [icon respondsToSelector:@selector(name)] ? [icon name] : nil;
        if ([reportedName isKindOfClass:NSString.class] && reportedName.length) [names addObject:name];
    }
    free(methods);

    return [[names allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

@interface SGNavbarIconCell : UITableViewCell
@property (nonatomic, strong) UIView *preview;
- (void)setIconName:(NSString *)name;
@end

@implementation SGNavbarIconCell

- (void)prepareForReuse {
    [super prepareForReuse];
    [_preview removeFromSuperview];
    _preview = nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = 32;
    _preview.frame = CGRectMake(16, round((self.contentView.bounds.size.height - side) / 2), side, side);
}

- (void)setIconName:(NSString *)name {
    [_preview removeFromSuperview];

    id icon = encoreIconNamed(name);
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    UIView *preview = icon && viewClass ? [[viewClass alloc] initWithIcon:icon] : nil;
    if ([preview respondsToSelector:@selector(setForegroundColor:)]) {
        [(SPTEncoreIconView *)preview setForegroundColor:UIColor.whiteColor];
    }
    if (!preview) preview = SGSymbolView(@"questionmark", 20, UIImageSymbolWeightRegular, 32);

    _preview = preview;
    _preview.userInteractionEnabled = NO;
    [self.contentView addSubview:_preview];

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = name;
    content.secondaryText = @"Tap to copy";
    content.textProperties.font = SGTitleFont();
    content.textProperties.color = UIColor.whiteColor;
    content.secondaryTextProperties.font = SGSubtitleFont();
    content.secondaryTextProperties.color = SGGrey();
    content.textToSecondaryTextVerticalPadding = 0;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(8, 58, 8, 16);
    self.contentConfiguration = content;
    self.backgroundColor = SGCardBackground();
    self.accessoryView = nil;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    [self setNeedsLayout];
}

@end

@interface SGNavbarIconPickerController : SGPage
@property (nonatomic, copy) NSArray<NSString *> *iconNames;
@property (nonatomic, strong) UIView *footer;
@end

@implementation SGNavbarIconPickerController

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"All Icons";
    _iconNames = encoreIconNames();
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.footer = SGNote([NSString stringWithFormat:@"Tap an icon to copy its name for the Icon field. %@ icons available.",
                          @(self.iconNames.count)]);
    self.tableView.tableFooterView = self.footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, self.footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 1;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.iconNames.count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return SGSectionHeader(table, @"Spotify Encore icons");
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return SGSectionHeaderHeight;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGNavbarIconCell *cell = (SGNavbarIconCell *)[table dequeueReusableCellWithIdentifier:@"navbar-icon"];
    if (!cell) cell = [[SGNavbarIconCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"navbar-icon"];
    [cell setIconName:self.iconNames[(NSUInteger)path.row]];
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    NSString *name = self.iconNames[(NSUInteger)path.row];
    UIPasteboard.generalPasteboard.string = name;
    [table deselectRowAtIndexPath:path animated:YES];
}

@end

UIViewController *SGNavbarIconPickerPage(void) {
    return [SGNavbarIconPickerController new];
}
