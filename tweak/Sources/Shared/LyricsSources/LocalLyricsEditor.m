// The Lyrics page's row for the local file playing (LocalLyrics.m): it opens a sheet to type or paste its
// lyrics into, LRC with [mm:ss.xx] stamps to have them timed or plain lines to have them shown, prefilled
// with what was typed before, or with the lines LRCLIB gave as LRC to correct. Save keeps them at once;
// emptying the text and saving goes back to LRCLIB. The sheet is presented, not pushed, so it is never on
// Spotify's own navigation stack.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsSources.h"

@interface SGLocalLyricsEditor : UIViewController <UITextViewDelegate>
@property (nonatomic, copy) NSString *localID, *name;
@end

@implementation SGLocalLyricsEditor {
    UITextView *_text;
}

static NSString *lrcOf(NSArray<SGKaraokeLine *> *lines) {
    NSMutableString *lrc = [NSMutableString string];
    BOOL timed = SGKaraokeLinesTiming(lines) != SGKaraokeTimingNone;
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line) ?: @"";
        if (timed) {
            NSInteger ms = MAX(0, line.start);
            [lrc appendFormat:@"[%02ld:%02ld.%02ld] %@\n", (long)(ms / 60000), (long)(ms / 1000 % 60), (long)(ms / 10 % 100), text];
        } else {
            [lrc appendFormat:@"%@\n", text];
        }
    }
    return lrc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.blackColor;
    self.title = @"Lyrics";
    self.navigationItem.prompt = self.name;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                          target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                           target:self action:@selector(save)];
    _text = [[UITextView alloc] initWithFrame:self.view.bounds];
    _text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _text.backgroundColor = UIColor.blackColor;
    _text.textColor = UIColor.whiteColor;
    _text.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    _text.autocorrectionType = UITextAutocorrectionTypeNo;
    _text.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    _text.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _text.textContainerInset = UIEdgeInsetsMake(16, 12, 16, 12);
    NSArray<SGKaraokeLine *> *kept = SGKaraokeLinesForTrack(self.localID);
    _text.text = SGLocalLyricsSaved(self.localID) ?: (kept ? lrcOf(kept) : @"");
    [self.view addSubview:_text];
    if (!_text.text.length) {
        UILabel *hint = [UILabel new];
        hint.numberOfLines = 0;
        hint.textColor = [UIColor colorWithWhite:1 alpha:0.4];
        hint.font = [UIFont systemFontOfSize:15];
        hint.text = @"Paste the lyrics. With [01:23.45] before each line they follow the song; without, they show as they are.";
        hint.tag = 1;
        hint.frame = CGRectMake(17, 16, self.view.bounds.size.width - 34, 80);
        hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [_text addSubview:hint];
        _text.delegate = self;
    }
}

- (void)textViewDidChange:(UITextView *)textView {
    [textView viewWithTag:1].hidden = textView.text.length > 0;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_text becomeFirstResponder];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    NSString *problem = SGLocalLyricsSave(self.localID, _text.text);
    if (!problem) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Not saved" message:problem preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

SGModRow *SGLocalLyricsRow(void) {
    SGModRow *row = SGActionRow(@"Lyrics of this local file", nil, ^{
        NSString *localID, *name;
        if (!SGLocalLyricsPlaying(&localID, &name)) return;
        SGLocalLyricsEditor *editor = [SGLocalLyricsEditor new];
        editor.localID = localID;
        editor.name = name;
        UINavigationController *sheet = [[UINavigationController alloc] initWithRootViewController:editor];
        sheet.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [SGTopController() presentViewController:sheet animated:YES completion:nil];
    });
    row.subtitle = @"Type or paste them, timed or not";
    row.visible = ^BOOL { return SGLocalLyricsPlaying(NULL, NULL); };
    return row;
}
