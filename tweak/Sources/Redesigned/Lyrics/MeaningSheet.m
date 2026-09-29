#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "MeaningSheet.h"
#import "Redesigned/Kit/SGRTokens.h"

static const CGFloat kSide = 24, kTop = 28, kGap = 12;

static NSString *authorName(SGLyricsMeaningAuthor author) {
    switch (author) {
        case SGLyricsMeaningByArtist: return @"From the artist";
        case SGLyricsMeaningByEditors: return @"Genius editors";
        case SGLyricsMeaningByCommunity: return @"Genius community";
    }
    return nil;
}

static NSString *authorSymbol(SGLyricsMeaningAuthor author) {
    return author == SGLyricsMeaningByArtist ? @"checkmark.seal.fill" : author == SGLyricsMeaningByEditors ? @"checkmark.circle" : @"person.2";
}

@interface SGRMeaningSheet : UIViewController
@end

@implementation SGRMeaningSheet {
    NSString *_lineText;
    NSArray<SGLyricsMeaning *> *_meanings;
    NSUInteger _index;
    UIScrollView *_scroll;
    UILabel *_quote, *_body, *_count;
    UIButton *_author, *_next, *_open;
}

- (instancetype)initWithLine:(NSString *)lineText meanings:(NSArray<SGLyricsMeaning *> *)meanings {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _lineText = [lineText copy];
    _meanings = [meanings copy];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = self.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    sheet.prefersGrabberVisible = YES;
    sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    return self;
}

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.numberOfLines = 0;
    label.font = font;
    label.textColor = color;
    label.adjustsFontForContentSizeCategory = YES;
    [_scroll addSubview:label];
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.title = title;
    config.contentInsets = NSDirectionalEdgeInsetsZero;
    config.baseForegroundColor = SGRAccent();
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
        NSMutableDictionary *out = [attributes mutableCopy];
        out[NSFontAttributeName] = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        return out;
    };
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:button];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];

    _quote = [self labelWithFont:[UIFont systemFontOfSize:20 weight:UIFontWeightBold] color:SGRPrimary()];
    UIButtonConfiguration *badge = [UIButtonConfiguration filledButtonConfiguration];
    badge.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    badge.buttonSize = UIButtonConfigurationSizeMini;
    badge.imagePadding = 4;
    badge.contentInsets = NSDirectionalEdgeInsetsMake(4, 10, 4, 10);
    badge.baseBackgroundColor = [SGRAccent() colorWithAlphaComponent:0.2];
    badge.baseForegroundColor = SGRAccent();
    _author = [UIButton buttonWithConfiguration:badge primaryAction:nil];
    _author.userInteractionEnabled = NO;
    [_scroll addSubview:_author];
    _body = [self labelWithFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody] color:SGRPrimary()];
    _count = [self labelWithFont:[UIFont systemFontOfSize:13 weight:UIFontWeightRegular] color:SGRTertiary()];
    _count.numberOfLines = 1;
    _next = [self buttonWithTitle:@"Next" action:@selector(showNext)];
    _open = [self buttonWithTitle:@"View on Genius" action:@selector(openGenius)];
    [self show];
}

- (void)show {
    SGLyricsMeaning *meaning = _meanings[_index];
    _quote.text = [NSString stringWithFormat:@"“%@”", _lineText];
    UIButtonConfiguration *badge = _author.configuration;
    badge.title = authorName(meaning.author);
    badge.image = [UIImage systemImageNamed:authorSymbol(meaning.author)
                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold]];
    _author.configuration = badge;
    _body.text = meaning.body;
    _count.text = _meanings.count > 1 ? [NSString stringWithFormat:@"Genius · %lu of %lu", (unsigned long)_index + 1, (unsigned long)_meanings.count]
                                      : @"Genius";
    _next.hidden = _meanings.count < 2;
    _open.hidden = !meaning.url.length;
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width - 2 * kSide;
    CGFloat y = kTop;
    _quote.frame = CGRectMake(kSide, y, width, [_quote sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
    y = CGRectGetMaxY(_quote.frame) + kGap;
    CGSize badge = [_author sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    _author.frame = CGRectMake(kSide, y, MIN(width, badge.width), badge.height);
    y = CGRectGetMaxY(_author.frame) + kGap + 4;
    _body.frame = CGRectMake(kSide, y, width, [_body sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
    y = CGRectGetMaxY(_body.frame) + kGap * 2;
    _count.frame = CGRectMake(kSide, y, [_count sizeThatFits:CGSizeMake(width, 22)].width, 22);
    CGFloat right = kSide + width;
    if (!_next.hidden) {
        CGSize size = [_next sizeThatFits:CGSizeZero];
        _next.frame = CGRectMake(right - size.width, y, size.width, 22);
        right = CGRectGetMinX(_next.frame) - 20;
    }
    if (!_open.hidden) {
        CGSize size = [_open sizeThatFits:CGSizeZero];
        _open.frame = CGRectMake(right - size.width, y, size.width, 22);
    }
    _scroll.contentSize = CGSizeMake(self.view.bounds.size.width, y + 22 + kTop + self.view.safeAreaInsets.bottom);
}

- (void)showNext {
    _index = (_index + 1) % _meanings.count;
    [UIView transitionWithView:_scroll duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ [self show]; [self.view layoutIfNeeded]; } completion:nil];
    [_scroll setContentOffset:CGPointMake(0, -_scroll.adjustedContentInset.top) animated:NO];
}

- (void)openGenius {
    NSURL *url = [NSURL URLWithString:_meanings[_index].url];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

@end

void SGRShowMeanings(NSString *lineText, NSArray<SGLyricsMeaning *> *meanings) {
    if (!meanings.count) return;
    UIViewController *top = SGTopController();
    if (!top || [top isKindOfClass:SGRMeaningSheet.class]) return;
    [top presentViewController:[[SGRMeaningSheet alloc] initWithLine:lineText meanings:meanings] animated:YES completion:nil];
}
