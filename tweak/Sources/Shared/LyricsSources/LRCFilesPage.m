#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "LRCFiles.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Headers/SPTPlayer.h"

@interface SGLRCFilesController : SGPage <UIDocumentPickerDelegate>
@property (nonatomic, copy) NSArray<NSString *> *files;
@property (nonatomic) BOOL assignToCurrentTrack;
@property (nonatomic, copy) NSString *pendingTrackID;
@end

@implementation SGLRCFilesController
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"Imported LRC files";
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableFooterView = SGNote(@"Play a local track, then use ‘Import for current track’ to choose its LRC file. Other imports are matched by title and artist.");
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
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? MAX(1, self.files.count) : 2; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(tableView, @"lrc");
    if (path.section == 1 && path.row == 0) {
        NSString *trackID = SGKaraokePlayingTrack();
        SPTPlayerTrack *track = SGKaraokeTrackFor(trackID);
        NSString *title = track.trackTitle.length ? track.trackTitle : @"Current local track";
        SGFillCell(cell, @"Import for current track…", SGKaraokeTrackKeyIsLocal(trackID) ? title : @"Start playing a local track first", nil, @"music.note.list");
    } else if (path.section == 1) SGFillCell(cell, @"Import LRC…", @"Add a file for automatic title matching", nil, @"square.and.arrow.down");
    else SGFillCell(cell, self.files.count ? self.files[(NSUInteger)path.row] : @"No imported files", nil, self.files.count ? nil : SGGrey(), nil);
    return cell;
}
- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != 1) return NO;
    return path.row != 0 || SGKaraokeTrackKeyIsLocal(SGKaraokePlayingTrack());
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    self.assignToCurrentTrack = path.row == 0;
    self.pendingTrackID = self.assignToCurrentTrack ? SGKaraokePlayingTrack() : nil;
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
    NSString *name = SGLRCImport(url, &error);
    if (!name) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import failed" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (self.assignToCurrentTrack && self.pendingTrackID.length) SGLRCAssignToTrack(name, self.pendingTrackID);
    BOOL assigned = self.assignToCurrentTrack && self.pendingTrackID.length;
    self.assignToCurrentTrack = NO;
    self.pendingTrackID = nil;
    self.files = SGLRCFiles();
    [self.tableView reloadData];
    if (assigned) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LRC assigned" message:@"This file is now linked to the local track you were playing." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end

UIViewController *SGLRCFilesPage(void) { return [SGLRCFilesController new]; }
