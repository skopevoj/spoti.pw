// The header's text and controls, the redesign's own. Laid out top down from where the content has to start
// for its bottom to sit SGRHeaderInfoBottom above the view's.
#import "Core/SGCore.h"
#import "SGRHeaderInfo.h"
#import "SGRActionRow.h"
#import "SGRRestyle.h"
#import "SGRTokens.h"

const CGFloat SGRHeaderInfoBottom = 14;
const CGFloat SGRHeaderInfoTitleRise = 56;

// The text kSide in from the edges; Play at least kPlayWidth wide, the Music app's; the gaps between.
static const CGFloat kSide = 20, kPlayWidth = 148, kRowSpacing = 16, kRowAbove = 16, kAboutAbove = 14;

static UILabel *infoLabel(UIView *parent, UIFont *font, UIColor *color, NSInteger lines, NSTextAlignment alignment) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = alignment;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.hidden = YES;
    [parent addSubview:label];
    return label;
}

static BOOL setText(UILabel *label, NSString *text) {
    if ([label.text ?: @"" isEqualToString:text ?: @""]) return NO;
    label.text = text;
    label.hidden = text.length == 0;
    return YES;
}

@implementation SGRHeaderInfo {
    UILabel *_title, *_creator, *_length, *_about;
    SGRMirrorButton *_shuffle, *_trailing;
    SGRPlayCapsule *_play;
    __weak UIView *_creatorLink;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _title = infoLabel(self, SGRFont(UIFontTextStyleTitle2, UIFontWeightBold, UIContentSizeCategoryExtraLarge),
                       SGRPrimary(), 2, NSTextAlignmentCenter);
    _title.accessibilityTraits = UIAccessibilityTraitHeader;
    _creator = infoLabel(self, SGRFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryExtraLarge),
                         SGRSecondary(), 1, NSTextAlignmentCenter);
    _length = infoLabel(self, SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryExtraLarge),
                        SGRTertiary(), 1, NSTextAlignmentCenter);
    _about = infoLabel(self, SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryExtraLarge),
                       SGRSecondary(), 2, NSTextAlignmentNatural);

    _shuffle = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
    _shuffle.fallbackGlyph = [UIImage systemImageNamed:@"shuffle"];
    // White like the buttons beside it while off -- Spotify's off grey read as a disabled button next to the
    // white download (issue #65) -- and the accent while on, so its state still shows.
    _shuffle.glyphColor = SGRPrimary();
    _shuffle.onGlyphColor = SGRAccent();
    _play = [[SGRPlayCapsule alloc] initWithFrame:CGRectZero];
    _play.fillColor = UIColor.whiteColor;
    _trailing = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
    for (UIView *button in @[_shuffle, _play, _trailing]) {
        button.hidden = YES;
        [self addSubview:button];
    }
    return self;
}

// Touches only for the buttons and, where there is one, the creator line: the rest of the text lets a
// pull or a tap through to the page under it.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // The creator label is the width of the view, so the label itself answers a touch well away from the
    // name; both it and the view answer only where the name is drawn.
    if (hit == self || hit == _creator) return [self sgr_creatorHit:point];
    return hit;
}

- (BOOL)showTitle:(NSString *)title creator:(NSString *)creator length:(NSString *)length about:(NSString *)about {
    BOOL changed = NO;
    changed |= setText(_title, title);
    changed |= setText(_creator, creator);
    changed |= setText(_length, length);
    changed |= setText(_about, about);
    if (changed) [self setNeedsLayout];
    return changed;
}

// The creator line, tappable. The label is as wide as the view and centred, so the target is narrowed to
// the text itself -- a tap either side of a short name belongs to the page under it, which a pull down
// starts on. Spotify's own control stays concealed where it is and only fires.
- (void)showCreatorLink:(UIView *)control {
    _creatorLink = control;
    BOOL live = control != nil;
    if (_creator.userInteractionEnabled == live) return;
    _creator.userInteractionEnabled = live;
    _creator.accessibilityTraits = live ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    if (!live || _creator.gestureRecognizers.count) return;
    [_creator addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_creatorTapped)]];
}

- (void)sgr_creatorTapped {
    SGRActivate(_creatorLink);
}

// The creator line takes a touch only where its text is; everything else of the view is the page's.
- (UIView *)sgr_creatorHit:(CGPoint)point {
    if (!_creator.userInteractionEnabled || _creator.hidden) return nil;
    CGSize text = [_creator sizeThatFits:CGSizeMake(_creator.bounds.size.width, CGFLOAT_MAX)];
    CGRect frame = _creator.frame;
    CGRect word = CGRectInset(CGRectMake(round(CGRectGetMidX(frame) - text.width / 2), frame.origin.y,
                                         MIN(text.width, frame.size.width), frame.size.height), -8, -6);
    return CGRectContainsPoint(word, point) ? _creator : nil;
}

- (void)showShuffle:(UIView *)shuffle play:(UIView *)play trailing:(UIView *)trailing
   trailingFallback:(UIImage *)trailingFallback playColor:(UIColor *)playColor {
    _trailing.fallbackGlyph = trailingFallback;
    if (_trailing.readState != self.trailingState) {
        _trailing.readState = self.trailingState;
        _trailing.stateOffSymbol = self.trailingOffSymbol;
        _trailing.stateOnSymbol = self.trailingOnSymbol;
    }
    if (shuffle) [_shuffle feedFrom:shuffle];
    if (play) {
        if (playColor) _play.contentColor = playColor;
        [_play feedFrom:play];
    }
    if (trailing) [_trailing feedFrom:trailing];

    BOOL changed = NO;
    NSArray<UIView *> *buttons = @[_shuffle, _play, _trailing];
    NSArray<NSNumber *> *shown = @[@(shuffle != nil), @(play != nil), @(trailing != nil)];
    for (NSUInteger i = 0; i < buttons.count; i++) {
        BOOL hide = !shown[i].boolValue;
        if (buttons[i].hidden != hide) {
            buttons[i].hidden = hide;
            changed = YES;
        }
    }
    if (changed) [self setNeedsLayout];
}

- (void)trailingStateChanged {
    if (_trailing.source) [_trailing feedFrom:_trailing.source];
}

- (CGFloat)contentHeightForWidth:(CGFloat)width {
    CGFloat text = MAX(0, width - 2 * kSide), height = 0;
    UILabel *previous = nil;
    for (UILabel *label in @[_title, _creator, _length]) {
        if (label.hidden) continue;
        if (previous) height += previous == _creator ? 4 : 2;
        height += ceil([label sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height);
        previous = label;
    }
    if (previous) height += kRowAbove;
    height += SGRActionHeight;
    if (!_about.hidden) height += kAboutAbove + ceil([_about sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height);
    return height;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, text = MAX(0, width - 2 * kSide);
    CGFloat y = round(self.bounds.size.height - SGRHeaderInfoBottom - [self contentHeightForWidth:width]);

    UILabel *previous = nil;
    for (UILabel *label in @[_title, _creator, _length]) {
        if (label.hidden) continue;
        if (previous) y += previous == _creator ? 4 : 2;
        CGFloat height = ceil([label sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height);
        label.frame = CGRectMake(kSide, y, text, height);
        y += height;
        previous = label;
    }
    if (previous) y += kRowAbove;

    // Play on the middle of the page, the other two hung off its sides, so it holds its place whether both
    // are there or not.
    CGFloat side = SGRActionHeight;
    CGFloat playWidth = MAX(kPlayWidth, [_play sgr_width]);
    CGRect play = CGRectMake(round((width - playWidth) / 2), y, playWidth, side);
    _play.frame = play;
    _shuffle.frame = CGRectMake(CGRectGetMinX(play) - kRowSpacing - side, y, side, side);
    _trailing.frame = CGRectMake(CGRectGetMaxX(play) + kRowSpacing, y, side, side);
    y += side;

    if (!_about.hidden) {
        y += kAboutAbove;
        _about.frame = CGRectMake(kSide, y, text, ceil([_about sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height));
    }
}

@end
