#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "LRCFiles.h"

@interface SGLRCFilesController : SGPage <UIDocumentPickerDelegate>
@property (nonatomic, copy) NSArray<NSString *> *files;
@end

@implementation SGLRCFilesController
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"Imported LRC files";
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableFooterView = SGNote(@"Import .lrc files. Lyrics with timestamps follow playback; matching uses the title and, when present, artist.");
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.files = SGLRCFiles();
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? MAX(1, self.files.count) : 1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(tableView, @"lrc");
    if (path.section == 1) SGFillCell(cell, @"Import LRC…", @"Choose a file from Files", nil, @"square.and.arrow.down");
    else SGFillCell(cell, self.files.count ? self.files[(NSUInteger)path.row] : @"No imported files", nil, self.files.count ? nil : SGGrey(), nil);
    return cell;
}
- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)path { return path.section == 1; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != 0 || !self.files.count) return nil;
    NSString *name = self.files[(NSUInteger)path.row];
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        SGLRCDelete(name);
        self.files = SGLRCFiles();
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
        done(YES);
    }];
    remove.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (![url.pathExtension.lowercaseString isEqualToString:@"lrc"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Choose an LRC file" message:@"The selected file does not have the .lrc extension." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSError *error = nil;
    if (!SGLRCImport(url, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import failed" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.files = SGLRCFiles();
    [self.tableView reloadData];
}
@end

UIViewController *SGLRCFilesPage(void) { return [SGLRCFilesController new]; }
