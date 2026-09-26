// The redesign's Apple Music style lyrics, always on: the line being sung lights up word by word, the
// rest dim and blur with distance. Lines two voices sing at once are lit together, an instrumental
// break holds three dots, and a line can show its pronunciation and its translation under it. The
// lines and the clock are Shared/Lyrics/Lyrics.h's.
//
// Only words the source timed are swept. A line timed by the line lights up whole as it starts, as
// Apple Music lights such a line, unless the Lyrics page's "Simulate word-by-word timing" asks for
// its estimated words to be swept; lyrics with no timing at all are shown as plain text, every line
// lit, nothing following the clock.
#import "Core/SGCore.h"
#import "SGRKaraokeView.h"
#import "LyricsText.h"
#import "MeaningSheet.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/Player/PlayerEvents.h"
#import "Shared/Haptics/Haptics.h"
#import "Redesigned/Kit/SGRTokens.h"

static const CGFloat kFontSize = 30, kMargin = 24, kLineGap = 24, kRowTighten = 2;
static const CGFloat kDimAlpha = 0.3, kFillEdge = 22, kLift = 2.5, kDimScale = 0.97;
static const CGFloat kAnchor = 0.28;   // where the sung line rests, as a share of the height
static const CGFloat kEdgeFade = 0.1;  // the lines fade out over this share at the top and bottom
static const CGFloat kBlurPerLine = 1.4, kMaxBlur = 6;
// The (oh, aye) hanging under a line: smaller, a little dimmer, and just clear of it.
static const CGFloat kBackingScale = 0.62, kBackingAlpha = 0.8, kBackingGap = 4;
// The mark of a line Genius explains: a bubble after it for the artist's own word, a dotted underline
// for anyone else's.
static const CGFloat kBubbleSide = 22, kBubbleGap = 8, kBubbleGlyph = 11, kBubbleAlpha = 0.75, kBubbleReach = 14;
static const CGFloat kUnderlineDrop = 1, kUnderlineWidth = 2, kUnderlineAlpha = 0.35;
// The line naming the source, under the lyrics and outside the fade so it does not dim with them.
static const CGFloat kCreditSize = 12, kCreditAlpha = 0.4, kCreditBottom = 10;
// The button for the pronunciation and the translation, in the bottom leading corner as Apple Music
// has it, and the gap between it and the credit beside it.
static const CGFloat kExtrasSide = 44, kExtrasBottom = 12, kExtrasGlyph = 17, kExtrasCreditGap = 12;
static const NSTimeInterval kRestyleFade = 0.3;   // the lines crossfading to a new style
static const NSTimeInterval kBrowseHold = 3;   // after scrolling by hand, how long until it follows the song again
static const double kFloatMinMs = 700, kFloatLeadMs = 80;   // a short word still floats up this slowly
// A line lit whole: how long its words take to come up to full white, and to float up together.
static const NSTimeInterval kWholeFade = 0.35;
static const double kWholeRiseMs = 900;
static const double kClockSnapMs = 250, kClockPull = 0.08;
// Lines get views this far outside the visible part, in screen heights: half a screen above it
// and below, and a quarter more before a view is let go. Every view held is one more for the window
// to take in and let go when the lyrics come up; a line comes into view about once in three seconds,
// and a page flung by hand fills in at a few lines a frame.
static const CGFloat kSightBehind = 0.5, kSightAhead = 0.5, kSightSlack = 0.25;
static const NSTimeInterval kTransitionSlack = 0.05;   // after the player's animation, before the link is back
static NSString *const kBlurPath = @"filters.gaussianBlur.inputRadius";
// Two voices can sing at once, rarely more; past this many, the latest ones wait their turn.
enum { kMostSung = 6 };
// A pause in the singing this long is an instrumental break, and three dots hold its place: from the
// end of the last line sung before it to the start of the next, or from the top of the song to the
// first line. BiniLyrics' web player, which copies Apple Music's, draws them from seven seconds.
static const NSInteger kBreakMinMs = 7000;
// The dots' size and the room between them, as shares of the font, which is Apple Music's proportion.
static const CGFloat kDotShare = 0.5, kDotGapShare = 0.27;
// Their timeline, Apple Music's as that player reads it off: in over 0.4 s, breathing between 85 % and
// 112 % of their size in eight second cycles, filling one after another, then swelling to 120 % and
// shrinking away in 0.35 s, which ends half a second before the next line starts so it has that long
// to move up into their place. A cycle is timed to end small, so the swell starts from the bottom.
// They wait a quarter of a second before they come, for the line before them to move up out of the way.
static const double kBreakWait = 0.25, kBreakIn = 0.4, kBreakFadeIn = 0.16, kBreathHalf = 4, kBreathLow = 0.85, kBreathHigh = 1.12;
static const double kBreakOut = 0.35, kBreakSwell = 1.2, kBreakSwellShare = 0.35, kBreakCollapse = 0.5;
// The dots' clock is set again only once it is this far from the song's, or the song stops or starts.
static const double kBreakSlack = 0.03;
// A position that has not moved for this long is a paused player, not two frames between readings.
static const CFTimeInterval kStillFor = 0.1;

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

// Whether a line is written right to left, told by its first letter the way the Unicode bidi algorithm
// tells a paragraph's direction. Each line is asked on its own, since a song can mix scripts, and the
// phone's language has no say in it.
static BOOL readsRightToLeft(NSString *text) {
    static NSCharacterSet *rightToLeft, *leftToRight;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *scripts = [NSMutableCharacterSet new];
        [scripts addCharactersInRange:NSMakeRange(0x0590, 0x370)];    // Hebrew, Arabic, Syriac, Thaana, N'Ko and on
        [scripts addCharactersInRange:NSMakeRange(0xFB1D, 0x2E3)];    // Hebrew and Arabic presentation forms
        [scripts addCharactersInRange:NSMakeRange(0xFE70, 0x90)];     // Arabic presentation forms B
        [scripts addCharactersInRange:NSMakeRange(0x10800, 0x800)];   // the old scripts written right to left
        [scripts addCharactersInRange:NSMakeRange(0x1E800, 0x800)];   // Mende Kikakui and Adlam
        NSMutableCharacterSet *letters = [NSCharacterSet.letterCharacterSet mutableCopy];
        [letters formIntersectionWithCharacterSet:scripts.invertedSet];
        leftToRight = [letters copy];
        [scripts formIntersectionWithCharacterSet:NSCharacterSet.letterCharacterSet];
        rightToLeft = [scripts copy];
    });
    NSUInteger first = [text rangeOfCharacterFromSet:rightToLeft].location;
    return first != NSNotFound && first < [text rangeOfCharacterFromSet:leftToRight].location;
}

// Laid against the right edge: a line written right to left, or a second voice's written left to right.
static BOOL alignsRight(SGKaraokeLine *line) {
    return (line.align == SGKaraokeAlignTrailing) != readsRightToLeft(SGKaraokeLineText(line));
}

static UILabel *wordLabel(NSString *text, UIFont *font, UIColor *color, CGRect frame, BOOL rightToLeft) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.font = font;
    label.textColor = color;
    if (!rightToLeft) return label;
    // A word of a line written right to left is set in the line's direction, so the punctuation at its
    // ends falls where the whole line would put it, a word of a left to right script among them too.
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.baseWritingDirection = NSWritingDirectionRightToLeft;
    label.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: paragraph}];
    return label;
}

#pragma mark - a word

// The word twice: dim underneath, white on top behind a mask whose feathered edge slides across it,
// from the edge its script starts at.
@interface SGRKaraokeWordView : UIView
@property (nonatomic, readonly) SGKaraokeWord *word;
@property (nonatomic, readonly) UILabel *lit;
@property (nonatomic) CGFloat offset;   // where the word starts along its line, rows laid end to end
// Lit with the rest of its line at once rather than swept, and floated up with it over riseStart to
// riseEnd, which are the word's own times until the sweep says otherwise.
@property (nonatomic) BOOL whole;
@property (nonatomic) double riseStart, riseEnd;
- (void)fillTo:(CGFloat)cursor;
- (void)floatAt:(double)ms;
- (void)settle;
@end

@implementation SGRKaraokeWordView {
    CAGradientLayer *_fill;
    CGFloat _filled, _lift;
    BOOL _rightToLeft;
}

- (instancetype)initWithWord:(SGKaraokeWord *)word font:(UIFont *)font rightToLeft:(BOOL)rightToLeft {
    CGSize size = [word.text sizeWithAttributes:@{NSFontAttributeName: font}];
    self = [super initWithFrame:CGRectMake(0, 0, ceil(size.width), ceil(font.lineHeight))];
    if (!self) return nil;
    _word = word;
    _riseStart = word.start;
    _riseEnd = word.end;
    _rightToLeft = rightToLeft;
    [self addSubview:wordLabel(word.text, font, [UIColor colorWithWhite:1 alpha:kDimAlpha], self.bounds, rightToLeft)];
    _lit = wordLabel(word.text, font, UIColor.whiteColor, self.bounds, rightToLeft);
    // Hidden until the line is sung: a masked layer is drawn offscreen every frame even when the
    // mask leaves nothing of it, and a song has hundreds of words waiting their turn.
    _lit.hidden = YES;
    [self addSubview:_lit];

    CGFloat width = self.bounds.size.width + kFillEdge;
    _fill = [CAGradientLayer layer];
    _fill.colors = @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor];
    _fill.locations = @[@0, @((width - kFillEdge) / width), @1];
    _fill.startPoint = CGPointMake(rightToLeft ? 1 : 0, 0.5);
    _fill.endPoint = CGPointMake(rightToLeft ? 0 : 1, 0.5);
    _lit.layer.mask = _fill;
    _filled = NAN;
    [self fillTo:-CGFLOAT_MAX];
    return self;
}

// The cursor is in line units and the feathered edge is centred on it, so the edge runs on through
// the space into the next word instead of starting over at each one. Right to left, the mask is the
// same one turned around: white from the word's right edge, the feather `local` in from it.
- (void)fillTo:(CGFloat)cursor {
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat local = MAX(-kFillEdge / 2, MIN(width + kFillEdge / 2, cursor - _offset));
    if (local == _filled) return;
    _filled = local;
    CGFloat left = _rightToLeft ? width - local - kFillEdge / 2 : local - kFillEdge / 2 - width;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.frame = CGRectMake(left, -height / 2, width + kFillEdge, height * 2);
    [CATransaction commit];
}

// Rises like a critically damped spring let go as the word starts: no jolt, a long soft landing.
// x = 5 at the end of the word is 96 % of the way up.
- (void)floatAt:(double)ms {
    double x = MAX(0, ms - _riseStart + kFloatLeadMs) / MAX(_riseEnd - _riseStart, kFloatMinMs) * 5;
    CGFloat lift = kLift * (1 - (1 + x) * exp(-x));
    if (lift == _lift) return;
    _lift = lift;
    self.transform = CGAffineTransformMakeTranslation(0, -lift);
}

- (void)settle {
    _lift = 0;
    self.transform = CGAffineTransformIdentity;
}

@end

#pragma mark - how a line is set

// Which of a line's texts are shown and how big, from the Lyrics page's order of the three and the
// lyrics menu's switches: the first shown is set at the lyrics' own size, and the next two keep the
// sizes of their places whatever is hidden above them, so a translation stays the smallest with the
// pronunciation off. A song is laid out and measured by one of these, so a change of it is a new one.
@interface SGRKaraokeStyle : NSObject
@property (nonatomic, readonly) NSArray<NSNumber *> *order;   // SGRLyricsText, largest first, shown ones only
@property (nonatomic, readonly) UIFont *lyrics, *pronunciation, *translation;   // nil for a text not shown
@property (nonatomic, readonly) SGRKaraokeStyle *backing;   // the backing row's: smaller, its translation read with the line's
- (instancetype)initWithSize:(CGFloat)size order:(NSArray<NSNumber *> *)order pronunciation:(BOOL)pronunciation translation:(BOOL)translation;
@end

// The second and third place's sizes, as shares of the first: Apple Music's 20 and 16 under its 30.
static const CGFloat kSecondShare = 0.67, kThirdShare = 0.54;

@implementation SGRKaraokeStyle

- (instancetype)initWithSize:(CGFloat)size order:(NSArray<NSNumber *> *)order pronunciation:(BOOL)pronunciation translation:(BOOL)translation {
    if (!(self = [super init])) return nil;
    CGFloat sizes[3] = {size, round(size * kSecondShare), round(size * kThirdShare)};
    NSMutableArray<NSNumber *> *shown = [NSMutableArray array];
    for (NSUInteger place = 0; place < order.count && place < 3; place++) {
        SGRLyricsText text = order[place].integerValue;
        if ((text == SGRLyricsTextPronunciation && !pronunciation) || (text == SGRLyricsTextTranslation && !translation)) continue;
        CGFloat points = shown.count ? sizes[place] : size;
        UIFont *font = [UIFont systemFontOfSize:points weight:text == SGRLyricsTextTranslation ? UIFontWeightSemibold : UIFontWeightBold];
        if (text == SGRLyricsTextLyrics) _lyrics = font;
        else if (text == SGRLyricsTextPronunciation) _pronunciation = font;
        else _translation = font;
        [shown addObject:@(text)];
    }
    if (!_lyrics) {   // an order without the lyrics in it is not one to trust
        _lyrics = [UIFont systemFontOfSize:size weight:UIFontWeightBold];
        [shown insertObject:@(SGRLyricsTextLyrics) atIndex:0];
    }
    _order = shown;
    return self;
}

- (SGRKaraokeStyle *)backing {
    SGRKaraokeStyle *backing = [SGRKaraokeStyle new];
    backing->_lyrics = [UIFont systemFontOfSize:round(_lyrics.pointSize * kBackingScale) weight:UIFontWeightBold];
    if (_pronunciation) backing->_pronunciation = [UIFont systemFontOfSize:round(_pronunciation.pointSize * kBackingScale) weight:UIFontWeightBold];
    NSMutableArray<NSNumber *> *order = [_order mutableCopy];
    [order removeObject:@(SGRLyricsTextTranslation)];
    backing->_order = order;
    return backing;
}

@end

#pragma mark - where a line's words go

// Between a row of words and the row spelling them out under it, between one such pair and the next,
// and between two texts of a line set apart.
static const CGFloat kPairTighten = 2, kPairGap = 4, kPartGap = 6;

// Where everything of a line goes, from its text alone: each word's frame and its place along the
// sweep, the translation's frame and the backing's top. The page lays every line of a song out with
// it off the main thread to stack them, and a line view lays itself out by it when it is made, so the
// two can never disagree about a height.
@interface SGRKaraokeLayout : NSObject
@property (nonatomic) BOOL right;
@property (nonatomic) CGFloat height;
@property (nonatomic, copy) NSArray<NSValue *> *lyricFrames, *spokenFrames;
@property (nonatomic, copy) NSArray<NSNumber *> *lyricOffsets, *spokenOffsets;
@property (nonatomic) CGRect translation;   // CGRectNull without one
@property (nonatomic) CGFloat backingTop;   // 0 without a backing row
@end

@implementation SGRKaraokeLayout
@end

// A run of words set in rows as wide as the page: where each goes along its row, which row, and where
// it sits along the sweep, the rows laid end to end. A joined word follows the one before it flush:
// the scripts that do not space their words would otherwise read with a gap between every syllable.
typedef struct {
    CGFloat x, width, offset;
    NSUInteger row;
} SGRPlace;

static NSUInteger flow(NSArray<SGKaraokeWord *> *words, UIFont *font, CGFloat width, SGRPlace *places) {
    CGFloat space = ceil([@" " sizeWithAttributes:@{NSFontAttributeName: font}].width), x = 0, offset = 0;
    NSUInteger row = 0;
    for (NSUInteger i = 0; i < words.count; i++) {
        CGFloat wide = ceil([words[i].text sizeWithAttributes:@{NSFontAttributeName: font}].width);
        CGFloat lead = x > 0 && !words[i].joined ? space : 0;
        if (x > 0 && x + lead + wide > width) {
            x = lead = 0;
            row++;
        }
        x += lead;
        offset += lead;
        places[i] = (SGRPlace){x, wide, offset, row};
        x += wide;
        offset += wide;
    }
    return words.count ? row + 1 : 0;
}

// Written right to left, rows are laid out left to right and turned around, so the first word is at
// the right edge and each row runs leftwards from it. Then each group of rows goes against the line's
// edge, a second voice's against the far one, as Apple Music sets the two sides of a duet apart; a
// group too wide to fit stays where its first word put it.
static void settle(CGRect *frames, NSUInteger *groups, NSUInteger count, NSUInteger groupCount, CGFloat width, BOOL rightToLeft, BOOL right) {
    if (rightToLeft) {
        for (NSUInteger i = 0; i < count; i++) frames[i].origin.x = width - CGRectGetMaxX(frames[i]);
    }
    for (NSUInteger g = 0; g < groupCount; g++) {
        CGRect extent = CGRectNull;
        for (NSUInteger i = 0; i < count; i++) {
            if (groups[i] == g) extent = CGRectUnion(extent, frames[i]);
        }
        if (CGRectIsNull(extent)) continue;
        CGFloat shift = right ? width - CGRectGetMaxX(extent) : -CGRectGetMinX(extent);
        if (right ? shift <= 0 : shift >= 0) continue;
        for (NSUInteger i = 0; i < count; i++) {
            if (groups[i] == g) frames[i].origin.x += shift;
        }
    }
}

static NSArray<NSValue *> *boxedFrames(CGRect *frames, NSUInteger count) {
    NSMutableArray<NSValue *> *boxed = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [boxed addObject:[NSValue valueWithCGRect:frames[i]]];
    return boxed;
}

static NSArray<NSNumber *> *offsetsOf(SGRPlace *places, NSUInteger count) {
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [offsets addObject:@(places[i].offset)];
    return offsets;
}

// A text of words on its own, from `top`; returns where it ends.
static CGFloat layRun(NSArray<SGKaraokeWord *> *words, UIFont *font, CGFloat width, BOOL right, CGFloat top,
                      NSArray<NSValue *> **frames, NSArray<NSNumber *> **offsets) {
    NSUInteger count = words.count;
    SGRPlace *places = calloc(count + 1, sizeof(SGRPlace));
    CGRect *rects = calloc(count + 1, sizeof(CGRect));
    NSUInteger *groups = calloc(count + 1, sizeof(NSUInteger));
    NSUInteger rows = flow(words, font, width, places);
    CGFloat row = ceil(font.lineHeight) - kRowTighten, high = ceil(font.lineHeight);
    for (NSUInteger i = 0; i < count; i++) {
        rects[i] = CGRectMake(places[i].x, top + places[i].row * row, places[i].width, high);
        groups[i] = places[i].row;
    }
    NSMutableString *text = [NSMutableString string];
    for (SGKaraokeWord *word in words) [text appendString:word.text];
    settle(rects, groups, count, rows, width, readsRightToLeft(text), right);
    *frames = boxedFrames(rects, count);
    *offsets = offsetsOf(places, count);
    free(places);
    free(rects);
    free(groups);
    return top + (rows ? rows - 1 : 0) * row + high;
}

// Two texts of words where the second spells out the first, or the first the second: each row of the
// leading one with the other's words under it, each under the word it starts with, as Apple Music sets
// its pronunciation, so a syllable reads under the syllable it sounds. Returns where the pair ends.
static CGFloat layPair(NSArray<SGKaraokeWord *> *lead, UIFont *leadFont, NSArray<SGKaraokeWord *> *under, UIFont *underFont,
                       CGFloat width, BOOL right, CGFloat top, NSArray<NSValue *> **leadFrames, NSArray<NSNumber *> **leadOffsets,
                       NSArray<NSValue *> **underFrames, NSArray<NSNumber *> **underOffsets) {
    NSUInteger leads = lead.count, unders = under.count, count = leads + unders;
    SGRPlace *places = calloc(count + 1, sizeof(SGRPlace));
    CGRect *rects = calloc(count + 1, sizeof(CGRect));
    NSUInteger *groups = calloc(count + 1, sizeof(NSUInteger));
    NSUInteger rows = flow(lead, leadFont, width, places);
    flow(under, underFont, width, places + leads);   // for their places along their own sweep
    // The leading word each one goes under: the last to start by the time it does.
    NSUInteger *matched = calloc(unders + 1, sizeof(NSUInteger));
    for (NSUInteger j = 0, i = 0; j < unders; j++) {
        while (i + 1 < leads && lead[i + 1].start <= under[j].start) i++;
        matched[j] = i;
    }
    CGFloat leadRow = ceil(leadFont.lineHeight) - kRowTighten, leadHigh = ceil(leadFont.lineHeight);
    CGFloat underRow = ceil(underFont.lineHeight) - kRowTighten, underHigh = ceil(underFont.lineHeight);
    CGFloat space = ceil([@" " sizeWithAttributes:@{NSFontAttributeName: underFont}].width);
    CGFloat y = top, bottom = top;
    NSUInteger j = 0;
    for (NSUInteger r = 0; r < rows; r++) {
        for (NSUInteger i = 0; i < leads; i++) {
            if (places[i].row != r) continue;
            rects[i] = CGRectMake(places[i].x, y, places[i].width, leadHigh);
            groups[i] = r;
        }
        bottom = y + leadHigh;
        // Under the row, each word at the start of its own, pushed along past the one before it, and the
        // pieces of one word flush together, the way the row above has them. A row spelt out wider than
        // it is written, as Korean is, cannot keep to its words and still fit: it is set as plain words
        // from the edge instead, in as many rows as it takes.
        NSUInteger from = j, until = j;
        while (until < unders && places[matched[until]].row == r) until++;
        CGFloat underTop = y + leadHigh - kPairTighten, reached = 0;
        BOOL fits = YES;
        for (NSUInteger k = from; k < until && fits; k++) {
            BOOL flush = k > from && under[k].joined;
            CGFloat x = flush ? reached : MAX(places[matched[k]].x, reached + (reached > 0 ? space : 0));
            rects[leads + k] = CGRectMake(x, underTop, places[leads + k].width, underHigh);
            reached = x + places[leads + k].width;
            fits = reached <= width;
        }
        NSUInteger subRow = 0;
        if (!fits) {
            reached = 0;
            for (NSUInteger k = from; k < until; k++) {
                CGFloat wide = places[leads + k].width, lead = reached > 0 && !under[k].joined ? space : 0;
                if (reached > 0 && reached + lead + wide > width) {
                    subRow++;
                    reached = lead = 0;
                }
                rects[leads + k] = CGRectMake(reached + lead, underTop + subRow * underRow, wide, underHigh);
                reached += lead + wide;
            }
        }
        for (NSUInteger k = from; k < until; k++) groups[leads + k] = r;
        j = until;
        BOOL any = until > from;
        if (any) bottom = underTop + subRow * underRow + underHigh;
        y = any ? bottom + kPairGap : y + leadRow;
    }
    NSMutableString *text = [NSMutableString string];
    for (SGKaraokeWord *word in lead) [text appendString:word.text];
    settle(rects, groups, count, rows, width, readsRightToLeft(text), right);
    *leadFrames = boxedFrames(rects, leads);
    *underFrames = boxedFrames(rects + leads, unders);
    *leadOffsets = offsetsOf(places, leads);
    *underOffsets = offsetsOf(places + leads, unders);
    free(places);
    free(rects);
    free(groups);
    free(matched);
    return bottom;
}

// The texts a line has, in the style's order, the lyrics and their pronunciation set as a pair where
// the order has them side by side, and the backing row after the lyrics. `right` is the side a backing
// row keeps to, its line's; -1 for a line of its own, which takes its side from its voice and script.
static SGRKaraokeLayout *layOut(SGKaraokeLine *line, CGFloat width, SGRKaraokeStyle *style, NSInteger right) {
    SGRKaraokeLayout *layout = [SGRKaraokeLayout new];
    layout.right = right >= 0 ? right : alignsRight(line);
    layout.translation = CGRectNull;
    NSArray<SGKaraokeWord *> *spoken = style.pronunciation ? line.pronunciation.words : nil;
    NSString *translation = style.translation ? line.translation : nil;
    NSMutableArray<NSNumber *> *parts = [NSMutableArray array];
    for (NSNumber *text in style.order) {
        if (text.integerValue == SGRLyricsTextPronunciation && !spoken.count) continue;
        if (text.integerValue == SGRLyricsTextTranslation && !translation.length) continue;
        [parts addObject:text];
    }
    NSArray<NSValue *> *frames;
    NSArray<NSNumber *> *offsets;
    CGFloat y = 0;
    for (NSUInteger p = 0; p < parts.count; p++) {
        SGRLyricsText text = parts[p].integerValue;
        if (p > 0) y += kPartGap;
        if (text == SGRLyricsTextTranslation) {
            CGRect bounds = [translation boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                                                   attributes:@{NSFontAttributeName: style.translation} context:nil];
            layout.translation = CGRectMake(0, y, width, ceil(bounds.size.height));
            y = CGRectGetMaxY(layout.translation);
            continue;
        }
        BOOL lyrics = text == SGRLyricsTextLyrics;
        BOOL paired = p + 1 < parts.count && parts[p + 1].integerValue != SGRLyricsTextTranslation;
        if (paired) {
            NSArray<NSValue *> *pairedFrames;
            NSArray<NSNumber *> *pairedOffsets;
            y = layPair(lyrics ? line.words : spoken, lyrics ? style.lyrics : style.pronunciation,
                        lyrics ? spoken : line.words, lyrics ? style.pronunciation : style.lyrics,
                        width, layout.right, y, &frames, &offsets, &pairedFrames, &pairedOffsets);
            layout.lyricFrames = lyrics ? frames : pairedFrames;
            layout.lyricOffsets = lyrics ? offsets : pairedOffsets;
            layout.spokenFrames = lyrics ? pairedFrames : frames;
            layout.spokenOffsets = lyrics ? pairedOffsets : offsets;
            p++;
            lyrics = YES;
        } else {
            y = layRun(lyrics ? line.words : spoken, lyrics ? style.lyrics : style.pronunciation, width, layout.right, y, &frames, &offsets);
            if (lyrics) {
                layout.lyricFrames = frames;
                layout.lyricOffsets = offsets;
            } else {
                layout.spokenFrames = frames;
                layout.spokenOffsets = offsets;
            }
        }
        if (lyrics && right < 0 && line.backing.words.count) {
            layout.backingTop = y + kBackingGap;
            y = layout.backingTop + layOut(line.backing, width, style.backing, layout.right).height;
        }
    }
    layout.height = y;
    return layout;
}

// Where each line starts in the stack, from the heights alone. Measuring text is safe off the main
// thread, and a song's worth of it is kept off it: the first card of a track lays out while the
// player is opening, and a frame that measured every line then was a frame the animation lost.
static NSArray<NSNumber *> *topsOf(NSArray<SGKaraokeLine *> *lines, CGFloat width, SGRKaraokeStyle *style, CGFloat gap) {
    NSMutableArray<NSNumber *> *tops = [NSMutableArray arrayWithCapacity:lines.count];
    CGFloat top = 0;
    for (SGKaraokeLine *line in lines) {
        [tops addObject:@(top)];
        top += layOut(line, width, style, -1).height + gap;
    }
    return tops;
}

#pragma mark - a sweep

typedef struct {
    double ms, x, slope;
} SGSweepKnot;

// One run of words lit by one sweep: a line's own, or its pronunciation's, each timed by its own words.
// A whole one lights every word of the run at once from `start`, for a run whose words are not timed.
@interface SGRKaraokeSweep : NSObject
@property (nonatomic, readonly) NSArray<SGRKaraokeWordView *> *words;
- (instancetype)initWithWords:(NSArray<SGRKaraokeWordView *> *)words wholeFrom:(double)start;
- (void)showTime:(double)ms;
@end

@implementation SGRKaraokeSweep {
    SGSweepKnot *_knots;
    NSUInteger _knotCount;
    BOOL _whole;
}

// start: NAN to sweep the words by their own times.
- (instancetype)initWithWords:(NSArray<SGRKaraokeWordView *> *)words wholeFrom:(double)start {
    if (!(self = [super init])) return nil;
    _words = words;
    _whole = !isnan(start);
    if (_whole) {
        for (SGRKaraokeWordView *word in words) {
            word.whole = YES;
            word.riseStart = start;
            word.riseEnd = start + kWholeRiseMs;
        }
        return self;
    }
    [self buildSweep];
    return self;
}

- (void)dealloc {
    free(_knots);
}

static double secant(SGSweepKnot *knots, NSUInteger i) {
    return (knots[i + 1].x - knots[i].x) / (knots[i + 1].ms - knots[i].ms);
}

// The fill cursor reaches each word's left edge as the word starts and clears the last word as it
// ends, on a monotone cubic through those points, so the pace changes between words without a kink.
- (void)buildSweep {
    _knots = calloc(_words.count + 1, sizeof(SGSweepKnot));
    if (!_words.count) return;
    for (NSUInteger i = 0; i <= _words.count; i++) {
        SGRKaraokeWordView *word = _words[MIN(i, _words.count - 1)];
        double ms = i < _words.count ? word.word.start : word.word.end;
        double x = i == 0 ? -kFillEdge / 2 : i < _words.count ? word.offset : word.offset + word.bounds.size.width + kFillEdge / 2;
        if (_knotCount && ms <= _knots[_knotCount - 1].ms) {
            _knots[_knotCount - 1].x = x;
            continue;
        }
        _knots[_knotCount++] = (SGSweepKnot){ms, x, 0};
    }
    // Fritsch-Carlson slopes: capped so the cursor never runs backwards or overshoots a word.
    for (NSUInteger k = 0; k < _knotCount; k++) {
        BOOL first = k == 0, last = k + 1 == _knotCount;
        if (first && last) break;
        if (first || last) {
            _knots[k].slope = secant(_knots, first ? 0 : k - 1);
            continue;
        }
        double before = secant(_knots, k - 1), after = secant(_knots, k);
        double h0 = _knots[k].ms - _knots[k - 1].ms, h1 = _knots[k + 1].ms - _knots[k].ms;
        _knots[k].slope = MIN(MIN(2 * before, 2 * after), (before * h1 + after * h0) / (h0 + h1));
    }
}

- (CGFloat)cursorAt:(double)ms {
    if (!_knotCount) return -CGFLOAT_MAX;
    if (ms <= _knots[0].ms) return _knots[0].x;
    if (_knotCount == 1 || ms >= _knots[_knotCount - 1].ms) return _knots[_knotCount - 1].x;
    NSUInteger k = 0;
    while (ms >= _knots[k + 1].ms) k++;
    SGSweepKnot a = _knots[k], b = _knots[k + 1];
    double h = b.ms - a.ms, u = (ms - a.ms) / h, u2 = u * u, u3 = u2 * u;
    return (2 * u3 - 3 * u2 + 1) * a.x + (u3 - 2 * u2 + u) * h * a.slope
         + (3 * u2 - 2 * u3) * b.x + (u3 - u2) * h * b.slope;
}

- (void)showTime:(double)ms {
    // A whole run is only ever shown while its line is sung, so it is lit throughout.
    CGFloat cursor = _whole ? CGFLOAT_MAX : [self cursorAt:ms];
    for (SGRKaraokeWordView *word in _words) {
        [word fillTo:cursor];
        [word floatAt:ms];
    }
}

@end

#pragma mark - a line

@interface SGRKaraokeLineView : UIView
@property (nonatomic, readonly) SGKaraokeLine *line;
// Laid against the right edge: a line written right to left, or a second voice's written left to
// right. A backing row keeps to the edge of the line it hangs under, whatever script each is in.
@property (nonatomic, readonly) BOOL right;
@property (nonatomic) BOOL active;
@property (nonatomic) CGFloat blur;
// under: the line a backing row hangs under, nil for a line of its own. sweepsEstimates: the words of a
// line timed only by the line are swept on their estimated times, rather than lit whole.
- (instancetype)initWithLine:(SGKaraokeLine *)line width:(CGFloat)width style:(SGRKaraokeStyle *)style under:(SGRKaraokeLineView *)under
                     blurred:(BOOL)blurred sweepsEstimates:(BOOL)sweepsEstimates;
- (void)showTime:(double)ms;
// Every word lit and left so, for lyrics with no timing: nothing is sung, so nothing is dim.
- (void)showPlain;
- (void)markMeaning:(NSArray<SGLyricsMeaning *> *)meanings;
// Where the bubble can be tapped, in the line's own space; CGRectNull without one.
@property (nonatomic, readonly) CGRect bubbleTarget;
@end

// The translation of a line being sung, brighter than a line waiting but never as bright as the words.
static const CGFloat kTranslationLit = 0.6;

@implementation SGRKaraokeLineView {
    NSArray<SGRKaraokeSweep *> *_sweeps;   // the line's words, then their pronunciation's where shown
    NSArray<SGRKaraokeWordView *> *_words;   // every word of both
    NSArray<SGRKaraokeWordView *> *_lyricWords;
    UIImageView *_bubble;
    CAShapeLayer *_underline;
    UILabel *_translation;
    NSUInteger _generation;
    SGRKaraokeLineView *_backing;
}

// A sweep's word views, each put where the layout has it and told where it sits along the sweep.
// start: NAN for words timed one by one, else when the run lights up whole.
- (SGRKaraokeSweep *)sweepOf:(NSArray<SGKaraokeWord *> *)words font:(UIFont *)font frames:(NSArray<NSValue *> *)frames
                     offsets:(NSArray<NSNumber *> *)offsets wholeFrom:(double)start {
    if (!words.count || frames.count != words.count) return nil;
    BOOL rightToLeft = readsRightToLeft([[words valueForKey:@"text"] componentsJoinedByString:@""]);
    NSMutableArray<SGRKaraokeWordView *> *views = [NSMutableArray arrayWithCapacity:words.count];
    for (NSUInteger i = 0; i < words.count; i++) {
        SGRKaraokeWordView *view = [[SGRKaraokeWordView alloc] initWithWord:words[i] font:font rightToLeft:rightToLeft];
        CGRect frame = frames[i].CGRectValue;
        view.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        view.offset = offsets[i].doubleValue;
        [self addSubview:view];
        [views addObject:view];
    }
    return [[SGRKaraokeSweep alloc] initWithWords:views wholeFrom:start];
}

// When a run of the line lights up whole, or NAN to sweep it: only words the source timed are swept,
// unless the estimate is asked for.
static double wholeFrom(SGKaraokeLine *run, BOOL sweepsEstimates) {
    if (run.timing == SGKaraokeTimingWords || (run.timing == SGKaraokeTimingLine && sweepsEstimates)) return NAN;
    return run.start;
}

- (instancetype)initWithLine:(SGKaraokeLine *)line width:(CGFloat)width style:(SGRKaraokeStyle *)style under:(SGRKaraokeLineView *)under
                     blurred:(BOOL)blurred sweepsEstimates:(BOOL)sweepsEstimates {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _line = line;
    BOOL backing = under != nil;
    SGRKaraokeLayout *layout = layOut(line, width, style, backing ? under.right : -1);
    _right = layout.right;
    NSMutableArray<SGRKaraokeSweep *> *sweeps = [NSMutableArray array];
    SGRKaraokeSweep *sung = [self sweepOf:line.words font:style.lyrics frames:layout.lyricFrames offsets:layout.lyricOffsets
                                wholeFrom:wholeFrom(line, sweepsEstimates)];
    SGRKaraokeSweep *spoken = [self sweepOf:line.pronunciation.words font:style.pronunciation frames:layout.spokenFrames
                                    offsets:layout.spokenOffsets wholeFrom:wholeFrom(line.pronunciation, sweepsEstimates)];
    if (sung) [sweeps addObject:sung];
    if (spoken) [sweeps addObject:spoken];
    _sweeps = sweeps;
    _words = [sung.words ?: @[] arrayByAddingObjectsFromArray:spoken.words ?: @[]];
    _lyricWords = sung.words;

    if (!CGRectIsNull(layout.translation)) {
        _translation = [[UILabel alloc] initWithFrame:layout.translation];
        _translation.numberOfLines = 0;
        _translation.font = style.translation;
        _translation.textColor = UIColor.whiteColor;
        _translation.alpha = kDimAlpha;
        _translation.textAlignment = _right ? NSTextAlignmentRight : NSTextAlignmentLeft;
        _translation.text = line.translation;
        [self addSubview:_translation];
    }
    if (layout.backingTop > 0) {
        _backing = [[SGRKaraokeLineView alloc] initWithLine:line.backing width:width style:style.backing under:self blurred:NO
                                            sweepsEstimates:sweepsEstimates];
        _backing.alpha = kBackingAlpha;
        _backing.frame = CGRectMake(0, layout.backingTop, width, _backing.bounds.size.height);
        [self addSubview:_backing];
    }
    self.frame = CGRectMake(0, 0, width, layout.height);

    // Scales toward the edge its text is aligned to, and a backing row rides its line's blur.
    if (backing) return self;
    self.layer.anchorPoint = CGPointMake(_right ? 1 : 0, 0.5);
    if (!blurred) return self;
    CAFilter *blur = [NSClassFromString(@"CAFilter") filterWithType:@"gaussianBlur"];
    if (blur) self.layer.filters = @[blur];
    return self;
}

// How many line views are made in one frame: the rest follow on the next, nearest the sung line first.
static const NSUInteger kLinesPerFrame = 4;

// Eases from wherever the blur is on screen, so a line coming into focus sharpens instead of snapping.
- (void)setBlur:(CGFloat)blur {
    if (blur == _blur) return;
    id shown = [self.layer.presentationLayer valueForKeyPath:kBlurPath];
    CGFloat from = [shown isKindOfClass:NSNumber.class] ? [shown doubleValue] : _blur;
    _blur = blur;
    if (!self.layer.filters) return;
    [self.layer setValue:@(blur) forKeyPath:kBlurPath];
    CABasicAnimation *ease = [CABasicAnimation animationWithKeyPath:kBlurPath];
    ease.fromValue = @(from);
    ease.toValue = @(blur);
    ease.duration = 0.6;
    ease.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:ease forKey:@"blur"];
}

- (void)setActive:(BOOL)active {
    if (active == _active) return;
    _active = active;
    _backing.active = active;
    NSUInteger generation = ++_generation;
    if (_translation) {
        [UIView animateWithDuration:active ? 0.3 : 0.5 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ self->_translation.alpha = active ? kTranslationLit : kDimAlpha; } completion:nil];
    }
    if (active) {
        NSMutableArray<SGRKaraokeWordView *> *whole = [NSMutableArray array];
        for (SGRKaraokeWordView *word in _words) {
            [word.layer removeAllAnimations];
            [word.lit.layer removeAllAnimations];
            word.lit.alpha = 1;
            word.lit.hidden = NO;
            [word fillTo:word.whole ? CGFLOAT_MAX : -CGFLOAT_MAX];
            [word settle];
            if (word.whole) [whole addObject:word];
        }
        // A line lit whole comes up to white together rather than popping on, as Apple Music's do.
        if (!whole.count) return;
        for (SGRKaraokeWordView *word in whole) word.lit.alpha = 0;
        [UIView animateWithDuration:kWholeFade delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ for (SGRKaraokeWordView *word in whole) word.lit.alpha = 1; } completion:nil];
        return;
    }
    // A sung line fades back to dim rather than dropping its fill at once, and its words sink back
    // on a spring slow enough to still be seen doing it.
    [UIView animateWithDuration:0.9 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        for (SGRKaraokeWordView *word in self->_words) [word settle];
    } completion:nil];
    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        for (SGRKaraokeWordView *word in self->_words) word.lit.alpha = 0;
    } completion:^(BOOL finished) {
        if (generation != self->_generation) return;
        for (SGRKaraokeWordView *word in self->_words) {
            [word fillTo:-CGFLOAT_MAX];
            word.lit.hidden = YES;
            word.lit.alpha = 1;
        }
    }];
}

- (void)showTime:(double)ms {
    for (SGRKaraokeSweep *sweep in _sweeps) [sweep showTime:ms];
    [_backing showTime:ms];   // timed on its own, so it lags the line as it is sung
}

- (void)showPlain {
    for (SGRKaraokeWordView *word in _words) {
        word.lit.hidden = NO;
        word.lit.alpha = 1;
        [word fillTo:CGFLOAT_MAX];
    }
    _translation.alpha = kTranslationLit;
    [_backing showPlain];
}

- (CGRect)bubbleTarget {
    return _bubble ? CGRectInset(_bubble.frame, -kBubbleReach, -kBubbleReach) : CGRectNull;
}

- (void)markMeaning:(NSArray<SGLyricsMeaning *> *)meanings {
    [_bubble removeFromSuperview];
    _bubble = nil;
    [_underline removeFromSuperlayer];
    _underline = nil;
    if (!meanings.count || !_lyricWords.count) return;
    if (meanings.firstObject.author == SGLyricsMeaningByArtist) {
        SGRKaraokeWordView *last = _lyricWords.lastObject;
        BOOL rightToLeft = readsRightToLeft(SGKaraokeLineText(_line));
        CGRect word = CGRectMake(last.center.x - last.bounds.size.width / 2, last.center.y - last.bounds.size.height / 2,
                                 last.bounds.size.width, last.bounds.size.height);
        CGFloat x = rightToLeft ? CGRectGetMinX(word) - kBubbleGap - kBubbleSide : CGRectGetMaxX(word) + kBubbleGap;
        UIImage *glyph = [UIImage systemImageNamed:@"quote.opening" withConfiguration:
                          [UIImageSymbolConfiguration configurationWithPointSize:kBubbleGlyph weight:UIImageSymbolWeightBold]];
        _bubble = [[UIImageView alloc] initWithImage:glyph];
        _bubble.contentMode = UIViewContentModeCenter;
        _bubble.tintColor = UIColor.blackColor;
        _bubble.backgroundColor = UIColor.whiteColor;
        _bubble.layer.cornerRadius = kBubbleSide / 2;
        _bubble.alpha = kBubbleAlpha;
        _bubble.frame = CGRectMake(x, CGRectGetMidY(word) - kBubbleSide / 2, kBubbleSide, kBubbleSide);
        _bubble.isAccessibilityElement = YES;
        _bubble.accessibilityLabel = @"Meaning from the artist";
        [self addSubview:_bubble];
        return;
    }
    // One dotted stroke under each row the line's words wrap onto.
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat rowY = NAN, from = 0, to = 0;
    for (SGRKaraokeWordView *word in _lyricWords) {
        CGFloat bottom = word.center.y + word.bounds.size.height / 2 + kUnderlineDrop;
        CGFloat left = word.center.x - word.bounds.size.width / 2, right = left + word.bounds.size.width;
        if (bottom != rowY) {
            if (!isnan(rowY)) {
                [path moveToPoint:CGPointMake(from, rowY)];
                [path addLineToPoint:CGPointMake(to, rowY)];
            }
            rowY = bottom;
            from = left;
            to = right;
            continue;
        }
        from = MIN(from, left);
        to = MAX(to, right);
    }
    [path moveToPoint:CGPointMake(from, rowY)];
    [path addLineToPoint:CGPointMake(to, rowY)];
    _underline = [CAShapeLayer layer];
    _underline.path = path.CGPath;
    _underline.strokeColor = [UIColor colorWithWhite:1 alpha:kUnderlineAlpha].CGColor;
    _underline.lineWidth = kUnderlineWidth;
    _underline.lineCap = kCALineCapRound;
    _underline.lineDashPattern = @[@0, @5];
    [self.layer insertSublayer:_underline atIndex:0];
}

@end

#pragma mark - a break

// Three dots in place of the lines through an instrumental break, the way Apple Music keeps a long
// pause from reading as lyrics gone missing: they come in as the break begins, breathe while it
// lasts, fill one after another over its length and swell and go as the next line comes up.
//
// All of it is one Core Animation timeline the length of the break, on a layer whose clock is laid
// against the song's: set once as the break opens and again only when the song jumps, stops or
// starts, so the frames in between cost the page nothing. The view itself is moved by the page like
// a line, so the clock is a layer inside it, where a stopped clock cannot stop that move too.
@interface SGRKaraokeBreakView : UIView
@property (nonatomic) BOOL right;         // against the right edge, where the line after it is
@property (nonatomic) BOOL rightToLeft;   // filling from the right, the way the line after it reads
- (instancetype)initWithFont:(UIFont *)font;
- (void)playFrom:(NSInteger)start to:(NSInteger)end;
- (void)showTime:(double)ms running:(BOOL)running at:(CFTimeInterval)shown;
@end

// Local time on the dots' clock is this far into the break plus this, so no animation begins at 0,
// which Core Animation reads as "now".
static const CFTimeInterval kBreakEpoch = 1;

// The rate the page's display link asks for, asked for here too: an animation that settles for less
// could hold the player's own 120 Hz animations down, as a link asking for 60 once did.
static void atFullRate(CAAnimation *animation) {
    animation.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
}

static double easeOutExpo(double p) {
    return p <= 0 ? 0 : p >= 1 ? 1 : 1 - pow(2, -10 * p);
}

static double smoothstep(double p) {
    p = MAX(0, MIN(1, p));
    return p * p * (3 - 2 * p);
}

@implementation SGRKaraokeBreakView {
    CALayer *_clock, *_group;
    NSArray<CALayer *> *_dots;
    NSInteger _start;
    CGFloat _side, _gap;
}

- (instancetype)initWithFont:(UIFont *)font {
    self = [super initWithFrame:CGRectMake(0, 0, 0, ceil(font.lineHeight))];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    _side = round(font.pointSize * kDotShare);
    _gap = round(font.pointSize * kDotGapShare);
    _clock = [CALayer layer];
    _group = [CALayer layer];
    _group.bounds = CGRectMake(0, 0, 3 * _side + 2 * _gap, _side);
    NSMutableArray<CALayer *> *dots = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
        CALayer *dot = [CALayer layer];
        dot.frame = CGRectMake(i * (_side + _gap), 0, _side, _side);
        dot.cornerRadius = _side / 2;
        dot.backgroundColor = UIColor.whiteColor.CGColor;
        dot.opacity = kDimAlpha;
        [_group addSublayer:dot];
        [dots addObject:dot];
    }
    _dots = dots;
    _group.opacity = 0;
    [_clock addSublayer:_group];
    [self.layer addSublayer:_clock];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGSize size = self.bounds.size, group = _group.bounds.size;
    _clock.frame = self.bounds;
    _group.position = CGPointMake(_right ? size.width - group.width / 2 : group.width / 2, size.height / 2);
    [CATransaction commit];
}

- (void)setRight:(BOOL)right {
    if (right == _right) return;
    _right = right;
    [self setNeedsLayout];
}

// The break's whole run, sampled the way the numbers above describe it: densely where the dots come
// and go, every fifth of a second through the slow breath between.
- (void)playFrom:(NSInteger)start to:(NSInteger)end {
    _start = start;
    [_group removeAllAnimations];
    for (CALayer *dot in _dots) [dot removeAllAnimations];
    double length = (end - start) / 1000.0;
    double exitAt = MAX(kBreakWait + kBreakIn, length - kBreakCollapse - kBreakOut), over = exitAt + kBreakOut;
    BOOL still = SGRReduceMotion();   // no breath and no swell, only the fades and the fill
    NSMutableArray<NSNumber *> *times = [NSMutableArray array], *scales = [NSMutableArray array], *alphas = [NSMutableArray array];
    void (^sample)(double) = ^(double t) {
        double cycle = 2 * kBreathHalf, phase = fmod(t + kBreathHalf - fmod(exitAt, cycle) + cycle, cycle);
        double low = (1 - cos(M_PI * phase / kBreathHalf)) / 2;
        double scale = (kBreathHigh + (kBreathLow - kBreathHigh) * low) * easeOutExpo((t - kBreakWait) / kBreakIn);
        double alpha = MAX(0, MIN(1, (t - kBreakWait) / kBreakFadeIn));
        if (t >= exitAt) {
            double p = (t - exitAt) / kBreakOut;
            BOOL swelling = p <= kBreakSwellShare;
            double eased = smoothstep(swelling ? p / kBreakSwellShare : (p - kBreakSwellShare) / (1 - kBreakSwellShare));
            scale = swelling ? kBreathLow + (kBreakSwell - kBreathLow) * eased : kBreakSwell * (1 - eased);
            alpha = swelling ? 1 : 1 - eased;
        }
        [times addObject:@(t / over)];
        [scales addObject:@(still ? 1 : MAX(scale, 0.001))];
        [alphas addObject:@(alpha)];
    };
    for (double t = 0; t < kBreakWait + kBreakIn; t += 0.025) sample(t);
    for (double t = kBreakWait + kBreakIn; t < exitAt; t += 0.2) sample(t);
    for (double t = exitAt; t < over; t += 0.02) sample(t);
    sample(over);

    CAKeyframeAnimation *scale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    CAKeyframeAnimation *alpha = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    scale.values = scales;
    alpha.values = alphas;
    for (CAKeyframeAnimation *run in @[scale, alpha]) {
        run.keyTimes = times;
        run.duration = over;
        run.beginTime = kBreakEpoch;
        run.fillMode = kCAFillModeBoth;
        run.removedOnCompletion = NO;
        atFullRate(run);
        [_group addAnimation:run forKey:run.keyPath];
    }
    // Each dot fills over its third of the time before they go, in the order the next line reads.
    for (NSUInteger i = 0; i < _dots.count; i++) {
        CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fill.fromValue = @(kDimAlpha);
        fill.toValue = @1;
        fill.beginTime = kBreakEpoch + (_rightToLeft ? _dots.count - 1 - i : i) * exitAt / 3;
        fill.duration = exitAt / 3;
        fill.fillMode = kCAFillModeBoth;
        fill.removedOnCompletion = NO;
        atFullRate(fill);
        [_dots[i] addAnimation:fill forKey:@"fill"];
    }
}

- (void)showTime:(double)ms running:(BOOL)running at:(CFTimeInterval)shown {
    double local = kBreakEpoch + (ms - _start) / 1000.0;
    CFTimeInterval parent = [self.layer convertTime:shown fromLayer:nil];
    BOOL stopped = _clock.speed == 0;
    double now = stopped ? _clock.timeOffset : (parent - _clock.beginTime) * _clock.speed + _clock.timeOffset;
    if (stopped != running && fabs(now - local) < kBreakSlack) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (running) {
        _clock.speed = 1;
        _clock.timeOffset = 0;
        _clock.beginTime = parent - local;
    } else {
        _clock.speed = 0;
        _clock.beginTime = 0;
        _clock.timeOffset = local;
    }
    [CATransaction commit];
}

@end

#pragma mark - the page

// When each line is sung, kept apart from the lines so the page can ask on every frame.
typedef struct {
    NSInteger start, end;   // its start, and when it is sung out (SGKaraokeSungEnd)
} SGRKaraokeSpan;

// A pause long enough for the dots, and the line after it.
typedef struct {
    NSInteger start, end, line;
} SGRKaraokeBreak;

@interface SGRKaraokeView () <UIScrollViewDelegate>
@end

@interface SGRLyricsExtrasButton : UIButton
@property (nonatomic, copy) void (^visibilityChanged)(BOOL visible);
@end
@implementation SGRLyricsExtrasButton
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    [super contextMenuInteraction:interaction willDisplayMenuForConfiguration:configuration animator:animator];
    if (self.visibilityChanged) self.visibilityChanged(YES);
}
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    [super contextMenuInteraction:interaction willEndForConfiguration:configuration animator:animator];
    void (^closed)(void) = ^{ if (self.visibilityChanged) self.visibilityChanged(NO); };
    if (animator) [animator addCompletion:closed];
    else closed();
}
@end

@implementation SGRKaraokeView {
    UIScrollView *_scroll;
    BOOL _browsing;
    CADisplayLink *_link;
    NSString *_track;
    NSArray<SGKaraokeLine *> *_lines;
    // The song is placed from its lines' heights alone; views exist for the lines in and near sight.
    NSArray<NSNumber *> *_tops;   // where each line starts in the stack
    NSMutableDictionary<NSNumber *, SGRKaraokeLineView *> *_shown;   // the views there are, by line
    CGFloat _focusTop;            // the top of the line the stack is arranged around
    CGFloat _sightOffset, _sightFocus;   // what the views in sight were last chosen for
    NSUInteger _sightArrangement;
    NSUInteger _build;   // counts the songs and widths measured, so a measurement that is late is dropped
    UIFont *_font;
    // What is sung now. Most of the time one line, the one at the anchor; where voices overlap, every
    // line being sung, the stack arranged around the one that began first; through a break, none,
    // and the dots at the anchor with the line after them just below.
    SGRKaraokeSpan *_spans;
    SGRKaraokeBreak *_breaks;
    NSUInteger _breakCount;
    NSInteger _sung[kMostSung];
    NSUInteger _sungCount;
    NSInteger _focus;       // the line the stack is arranged around, -1 before the first
    NSInteger _openBreak;   // the line the open break comes before, -1 while no break is open
    NSUInteger _arrangement;   // counts the changes to the three above, for the views in sight
    SGRKaraokeBreakView *_dots;
    NSInteger _dotsLine;   // the line the break the dots are timed for comes before
    CFTimeInterval _stillSince;   // when the position stopped moving, 0 while it moves
    SGRKaraokeStyle *_style;   // how the lines were laid out
    BOOL _hasSpoken, _hasTranslation;   // whether the song has any line with either
    UIButton *_extras;
    CGFloat _builtWidth;
    BOOL _showing;
    CAGradientLayer *_fade;
    UILabel *_credit;
    CGFloat _fontSize, _margin, _lineGap, _blurPerLine, _maxBlur;
    BOOL _crediting;   // the switch is read once: the page asks for the source on every frame until it has one
    double _clock;
    NSInteger _reported;
    CFTimeInterval _clockTime;
    BOOL _sweepsEstimates;   // the Lyrics page's "Simulate word-by-word timing", read once like the credit
    BOOL _plain;             // the song has no timing at all: every line lit, nothing follows the clock
    NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *_meanings;   // Genius's, by line
    NSUInteger _meaningsAsked;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.hidden = YES;
    _focus = _openBreak = -1;
    _fontSize = kFontSize;
    _margin = kMargin;
    _lineGap = kLineGap;
    _blurPerLine = kBlurPerLine;
    _maxBlur = kMaxBlur;
    _shown = [NSMutableDictionary dictionary];
    _sightArrangement = NSUIntegerMax;
    _fade = [CAGradientLayer layer];
    _fade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.whiteColor.CGColor,
                     (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor];
    _fade.locations = @[@0, @(kEdgeFade), @(1 - kEdgeFade), @1];
    _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scroll.layer.mask = _fade;
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.alwaysBounceVertical = YES;
    _scroll.scrollsToTop = NO;
    _scroll.delegate = self;
    [self addSubview:_scroll];
    _credit = [[UILabel alloc] initWithFrame:CGRectZero];
    _credit.font = [UIFont systemFontOfSize:kCreditSize weight:UIFontWeightSemibold];
    _credit.textColor = [UIColor colorWithWhite:1 alpha:kCreditAlpha];
    _credit.hidden = YES;
    _crediting = SGFlag(SGKeyLyricsCredit, NO);
    _sweepsEstimates = SGFlag(SGKeyLyricsSimulateWords, NO);
    [self addSubview:_credit];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
    [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerTransitionChanged:) name:SGPlayerTransitionNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerTransitionChanged:) name:SGPlayerTransitionEndedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(restyle) name:SGRLyricsTextDidChangeNotification object:nil];
    // A locked phone leaves the card in its window, so the link has to be put down by the app going
    // away rather than by the view going: see scheduleLink.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleLink) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleLink) name:UIApplicationWillResignActiveNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    free(_spans);
    free(_breaks);
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (_extras && !_extras.hidden && CGRectContainsPoint(_extras.frame, [tap locationInView:self])) return;
    CGPoint point = [tap locationInView:_scroll];
    for (SGRKaraokeLineView *view in _shown.allValues) {
        CGRect target = view.bubbleTarget;
        if (CGRectIsNull(target) || !CGRectContainsPoint(target, [_scroll convertPoint:point toView:view])) continue;
        [self explainLine:view];
        return;
    }
    if (_plain) return;   // a line with no time has nowhere to seek to
    for (SGRKaraokeLineView *view in _shown.allValues) {
        if (!CGRectContainsPoint(CGRectInset(view.frame, -_margin, -_lineGap / 2), point)) continue;
        SGKaraokeSeek(view.line.start);
        SGPlayFeedback(SGFeedbackSkip);
        [self followSong];
        return;
    }
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan || !_meanings.count) return;
    CGPoint point = [hold locationInView:_scroll];
    for (SGRKaraokeLineView *view in _shown.allValues) {
        if (!CGRectContainsPoint(CGRectInset(view.frame, -_margin, -_lineGap / 2), point)) continue;
        [self explainLine:view];
        return;
    }
}

- (void)explainLine:(SGRKaraokeLineView *)view {
    NSNumber *index = [_shown allKeysForObject:view].firstObject;
    NSArray<SGLyricsMeaning *> *meanings = index ? _meanings[index] : nil;
    if (!meanings.count) return;
    SGPlayFeedback(SGFeedbackSkip);
    SGRShowMeanings(SGKaraokeLineText(view.line), meanings);
}

// Genius is asked once the song's lines are in; lines that change under it are matched again.
- (void)askMeanings {
    _meanings = nil;
    NSUInteger asked = ++_meaningsAsked;
    NSArray<SGKaraokeLine *> *lines = _lines;
    __weak SGRKaraokeView *weakSelf = self;
    SGLyricsMeaningsFor(_track, lines, ^(NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *byLine) {
        SGRKaraokeView *page = weakSelf;
        if (!page || asked != page->_meaningsAsked || lines != page->_lines) return;
        page->_meanings = byLine;
        for (NSNumber *key in page->_shown) [page->_shown[key] markMeaning:byLine[key]];
    });
}

#pragma mark - scrolling by hand

// Lines are placed for a content offset of 0, so following the song means scrolling back to 0.
// While the user browses, placement stands still and every line is sharp.
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (self.interactionChanged) self.interactionChanged(1, YES);
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
    _browsing = YES;
    for (SGRKaraokeLineView *view in _shown.allValues) view.blur = 0;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self showLinesInSight];
}

// Plain text has no song to follow back to: it stays where it was scrolled to, as a page of text does.
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate && !_plain) [self performSelector:@selector(followSong) withObject:nil afterDelay:kBrowseHold];
    if (!decelerate && _plain && self.interactionChanged) self.interactionChanged(1, NO);
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (!_plain) [self performSelector:@selector(followSong) withObject:nil afterDelay:kBrowseHold];
    if (_plain && self.interactionChanged) self.interactionChanged(1, NO);
}

- (void)followSong {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
    if (!_browsing) return;
    _browsing = NO;
    if (self.interactionChanged) self.interactionChanged(1, NO);
    [UIView animateWithDuration:0.7 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self->_scroll.contentOffset = CGPointZero; } completion:nil];
    [self placeLinesAnimated:YES];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
        _browsing = NO;
        if (self.interactionChanged) self.interactionChanged(1, NO);
    }
    [self scheduleLink];
}

// The player opens and closes in animations that run at 120 Hz, and while a display link asked
// for 30 to 60, the range Apple's ProMotion guide says Core Animation gives priority to, those
// animations ran rough; the player and the lyrics themselves were smooth throughout. The card's
// link now asks for 60 but takes 120, and is put down for as long as the player animates, which
// NowPlayingBar.x announces as each animation starts and again as it ends. The timer is for an end
// that is never announced.
//
// The link is also put down whenever the app is not in front. Spotify keeps playing there, and a
// phone locked on the player kept the card ticking at 120 Hz against a screen that was off: 117 of
// the 137 wake ups a second the mod cost over stock Spotify were this one link, measured with
// scripts/battery-probe.sh. Nothing of the card is seen from the background, so nothing is drawn.
- (void)scheduleLink {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startLink) object:nil];
    [_link invalidate];
    _link = nil;
    if (!self.window) return;
    NSTimeInterval wait = SGPlayerTransitionEnds() - CACurrentMediaTime();
    if (wait <= 0) [self startLink];
    else [self performSelector:@selector(startLink) withObject:nil afterDelay:wait + kTransitionSlack inModes:@[NSRunLoopCommonModes]];
}

- (void)startLink {
    if (!self.window || _link) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)playerTransitionChanged:(NSNotification *)note {
    [self scheduleLink];
}

// The mask sits in the scroll view's own coordinates, which move with the content as it scrolls, so
// it is put back over the visible part on every frame, where the presentation layer says the
// content is: that holds through a drag and through the animated scroll home alike. Left where
// layout put it, it covered the first screenful of lines only, and a scroll past them showed nothing.
- (void)alignFade {
    CALayer *shown = (CALayer *)_scroll.layer.presentationLayer ?: _scroll.layer;
    CGRect frame = CGRectMake(0, shown.bounds.origin.y, self.bounds.size.width, self.bounds.size.height);
    if (CGRectEqualToRect(frame, _fade.frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fade.frame = frame;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self alignFade];
    _scroll.contentSize = self.bounds.size;
    [_credit sizeToFit];
    _credit.frame = CGRectMake(_margin, self.bounds.size.height - _credit.bounds.size.height - kCreditBottom,
                               _credit.bounds.size.width, _credit.bounds.size.height);
    if (_extras && !_extras.hidden) {
        _extras.frame = CGRectMake(_margin, self.bounds.size.height - kExtrasSide - kExtrasBottom, kExtrasSide, kExtrasSide);
        _credit.center = CGPointMake(CGRectGetMaxX(_extras.frame) + kExtrasCreditGap + _credit.bounds.size.width / 2, _extras.center.y);
    }
    if (_lines && self.bounds.size.width != _builtWidth) [self rebuild];
}

- (void)dropLineViews {
    for (UIView *view in _shown.allValues) [view removeFromSuperview];
    [_shown removeAllObjects];
    _tops = nil;
    _sightArrangement = NSUIntegerMax;
    _build++;
    [self forgetSung];
}

// Nothing sung, no break open: the state a song starts from, before the clock places it. The dots
// are made again for the next, in case it is laid out in another font.
- (void)forgetSung {
    _sungCount = 0;
    _focus = _openBreak = -1;
    _arrangement++;
    [_dots removeFromSuperview];
    _dots = nil;
}

// When each line is sung and where the breaks are, worked out once per song for the frames to read.
- (void)timeLines {
    free(_spans);
    free(_breaks);
    NSUInteger count = _lines.count;
    _spans = calloc(count + 1, sizeof(SGRKaraokeSpan));
    _breaks = calloc(count + 1, sizeof(SGRKaraokeBreak));
    _breakCount = 0;
    _hasSpoken = _hasTranslation = NO;
    _plain = SGKaraokeLinesTiming(_lines) == SGKaraokeTimingNone;
    NSInteger sungTo = 0;   // the top of the song counts as where the singing before the first line ends
    for (NSUInteger i = 0; i < count; i++) {
        SGKaraokeLine *line = _lines[i];
        _spans[i] = (SGRKaraokeSpan){line.start, SGKaraokeSungEnd(line)};
        if (!_plain && line.start - sungTo >= kBreakMinMs) _breaks[_breakCount++] = (SGRKaraokeBreak){sungTo, line.start, (NSInteger)i};
        sungTo = MAX(sungTo, _spans[i].end);
        _hasSpoken = _hasSpoken || line.pronunciation || line.backing.pronunciation;
        _hasTranslation = _hasTranslation || line.translation.length;
    }
    [self offerExtras];
    [self askMeanings];
}

// Measures the song for the width and, once that is in, places it; Spotify's own lines stay in view
// until then, since the page shows nothing of its own before it has lines to show.
- (void)rebuild {
    [self dropLineViews];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
    BOOL wasBrowsing = _browsing;
    _browsing = NO;
    if (wasBrowsing && self.interactionChanged) self.interactionChanged(1, NO);
    _scroll.contentOffset = CGPointZero;
    _builtWidth = self.bounds.size.width;
    CGFloat width = _builtWidth - 2 * _margin;
    if (width <= 0) return;
    _font = [UIFont systemFontOfSize:_fontSize weight:UIFontWeightBold];
    SGRKaraokeStyle *style = _style = [self styleNow];
    NSArray<SGKaraokeLine *> *lines = _lines;
    CGFloat gap = _lineGap;
    NSUInteger build = _build;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        NSArray<NSNumber *> *tops = topsOf(lines, width, style, gap);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (build != self->_build) return;   // the song or the width moved on meanwhile
            self->_tops = tops;
            [self placeLinesAnimated:NO];
        });
    });
}

#pragma mark - the pronunciation and the translation

// What a line shows besides its words: what the song has, of what the lyrics menu has switched on.
- (SGRKaraokeStyle *)styleNow {
    return [[SGRKaraokeStyle alloc] initWithSize:_fontSize order:SGRLyricsTextOrder()
                                   pronunciation:_hasSpoken && SGFlag(SGRKeyLyricsPronunciation, NO)
                                     translation:_hasTranslation && SGFlag(SGRKeyLyricsTranslation, NO)];
}

// A switch of the menu or the Lyrics page's order: the song is measured again in the new style off
// the main thread, as for a new width, but the lines on the page stay until it is in, and then the
// new ones crossfade over them where they were, so nothing blinks and nothing is lost of the place.
- (void)restyle {
    [self offerExtras];
    if (!_lines || !_tops || _builtWidth <= 0) return;   // the next build picks the style up
    SGRKaraokeStyle *style = [self styleNow];
    NSArray<SGKaraokeLine *> *lines = _lines;
    CGFloat width = _builtWidth - 2 * _margin, gap = _lineGap;
    NSUInteger build = ++_build;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        NSArray<NSNumber *> *tops = topsOf(lines, width, style, gap);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (build != self->_build) return;
            [self showStyle:style tops:tops];
        });
    });
}

- (void)showStyle:(SGRKaraokeStyle *)style tops:(NSArray<NSNumber *> *)tops {
    CATransition *fade = [CATransition animation];
    fade.type = kCATransitionFade;
    fade.duration = kRestyleFade;
    [_scroll.layer addAnimation:fade forKey:@"restyle"];
    for (UIView *view in _shown.allValues) [view removeFromSuperview];
    [_shown removeAllObjects];
    _style = style;
    _tops = tops;
    _sightArrangement = NSUIntegerMax;
    [self placeLinesAnimated:NO];
    [self showLinesInSight];   // placing stands still while the page is scrolled by hand; the views do not
    // The new views come in as the old ones were: the lines being sung lit, and every blur where it
    // was rather than easing in from sharp, which a view made out of sight does unseen.
    for (NSUInteger i = 0; i < _sungCount; i++) [self viewForLine:_sung[i]].active = YES;
    for (SGRKaraokeLineView *view in _shown.allValues) [view.layer removeAnimationForKey:@"blur"];
}

// The button shows only for a song with a pronunciation or a translation to show, and its menu only
// what the song has: a switch for each, reading what tapping it will do.
- (void)offerExtras {
    BOOL offered = _lines && (_hasSpoken || _hasTranslation);
    if (!offered) {
        _extras.hidden = YES;
        return;
    }
    if (!_extras) {
        UIImage *glyph = [UIImage systemImageNamed:@"translate" withConfiguration:
                          [UIImageSymbolConfiguration configurationWithPointSize:kExtrasGlyph weight:UIImageSymbolWeightSemibold]];
        // The system's glass, which turns solid under Reduce Transparency by itself; before iOS 26, the
        // Kit's solid fill in its place.
        UIButtonConfiguration *config;
        if (@available(iOS 26.0, *)) {
            config = [UIButtonConfiguration glassButtonConfiguration];
        } else {
            config = [UIButtonConfiguration filledButtonConfiguration];
            config.baseBackgroundColor = SGRSolidGlassFill();
        }
        config.image = glyph;
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.baseForegroundColor = UIColor.whiteColor;
        SGRLyricsExtrasButton *button = [SGRLyricsExtrasButton buttonWithConfiguration:config primaryAction:nil];
        __weak typeof(self) weak = self;
        button.visibilityChanged = ^(BOOL visible) {
            if (weak.interactionChanged) weak.interactionChanged(2, visible);
        };
        _extras = button;
        _extras.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        _extras.showsMenuAsPrimaryAction = YES;
        _extras.preferredMenuElementOrder = UIContextMenuConfigurationElementOrderFixed;
        _extras.accessibilityLabel = @"Pronunciation and translation";
        [self addSubview:_extras];
    }
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    if (_hasSpoken) {
        BOOL on = SGFlag(SGRKeyLyricsPronunciation, NO);
        [items addObject:[UIAction actionWithTitle:on ? @"Hide Pronunciation" : @"Show Pronunciation"
                                             image:[UIImage systemImageNamed:@"character.phonetic"] identifier:nil
                                           handler:^(UIAction *action) { SGRSetLyricsTextShown(SGRLyricsTextPronunciation, !on); }]];
    }
    if (_hasTranslation) {
        BOOL on = SGFlag(SGRKeyLyricsTranslation, NO);
        [items addObject:[UIAction actionWithTitle:on ? @"Hide Translation" : @"Show Translation"
                                             image:[UIImage systemImageNamed:@"character.bubble"] identifier:nil
                                           handler:^(UIAction *action) { SGRSetLyricsTextShown(SGRLyricsTextTranslation, !on); }]];
    }
    _extras.menu = [UIMenu menuWithChildren:items];
    _extras.hidden = NO;
    _extras.alpha = self.chromeHidden ? 0 : 1;
    [self setNeedsLayout];
}

// Where a line starts on the page, for the stack as it is arranged now: an open break holds the room
// of one row at the anchor, and the lines from the one after it on are moved down by it.
- (CGFloat)topOfLine:(NSInteger)index {
    CGFloat top = self.bounds.size.height * kAnchor + _tops[index].doubleValue - _focusTop;
    return _openBreak >= 0 && index >= _openBreak ? top + [self breakRoom] : top;
}

- (CGFloat)breakRoom {
    return ceil(_font.lineHeight) + _lineGap;
}

- (BOOL)isSung:(NSInteger)index {
    for (NSUInteger i = 0; i < _sungCount; i++) {
        if (_sung[i] == index) return YES;
    }
    return NO;
}

// How many lines away from what is sung a line is, which is what dims, shrinks and blurs it: from the
// nearest line being sung, from an open break as if it were a line of its own, and before the first
// line from the line before it, as ever.
- (NSInteger)distanceOf:(NSInteger)index {
    if (_plain) return 0;   // nothing is sung, so every line reads as clearly as the rest
    if (_openBreak >= 0) return index >= _openBreak ? index - _openBreak + 1 : _openBreak - index;
    if (!_sungCount) return labs(index - _focus);
    NSInteger nearest = NSIntegerMax;
    for (NSUInteger i = 0; i < _sungCount; i++) nearest = MIN(nearest, labs(index - _sung[i]));
    return nearest;
}

// The view of a line, made the first time it is asked for and placed where the stack has it.
- (SGRKaraokeLineView *)viewForLine:(NSInteger)index {
    SGRKaraokeLineView *view = _shown[@(index)];
    if (view || !_tops || index < 0 || index >= (NSInteger)_tops.count) return view;
    view = [[SGRKaraokeLineView alloc] initWithLine:_lines[index] width:_builtWidth - 2 * _margin style:_style under:nil
                                            blurred:_maxBlur > 0 && !_plain sweepsEstimates:_sweepsEstimates];
    if (_plain) [view showPlain];
    [view markMeaning:_meanings[@(index)]];
    [_scroll addSubview:view];
    _shown[@(index)] = view;
    [self placeLine:view at:index animated:NO];
    return view;
}

// Views for the lines just outside the visible part as well as in it, wherever that is: around the
// sung line while following the song, around wherever the page has been scrolled to while browsing.
// The ones further off are let go, so a long song costs a couple of dozen line views rather than
// one for every line, and the lines in sight are the only ones the compositor has to draw.
- (void)showLinesInSight {
    if (!_tops.count) return;
    CGFloat offset = ((CALayer *)_scroll.layer.presentationLayer ?: _scroll.layer).bounds.origin.y;
    if (offset == _sightOffset && _focusTop == _sightFocus && _arrangement == _sightArrangement) return;
    _sightOffset = offset;
    _sightFocus = _focusTop;
    _sightArrangement = _arrangement;
    CGFloat height = self.bounds.size.height;
    CGFloat from = offset - kSightBehind * height, to = offset + (1 + kSightAhead) * height, slack = kSightSlack * height;
    NSMutableArray<NSNumber *> *gone = [NSMutableArray array];
    for (NSNumber *key in _shown) {
        NSInteger index = key.integerValue;
        CGFloat top = [self topOfLine:index], bottom = top + _shown[key].bounds.size.height;
        if (![self isSung:index] && (bottom < from - slack || top > to + slack)) [gone addObject:key];
    }
    for (NSNumber *key in gone) {
        [_shown[key] removeFromSuperview];
        [_shown removeObjectForKey:key];
    }
    NSInteger count = (NSInteger)_tops.count;
    NSMutableArray<NSNumber *> *wanted = [NSMutableArray array];
    for (NSInteger index = 0; index < count; index++) {
        if (_shown[@(index)]) continue;
        CGFloat top = [self topOfLine:index];
        CGFloat bottom = index + 1 < count ? [self topOfLine:index + 1] - _lineGap : top + height;
        if (bottom < from || top > to) continue;
        [wanted addObject:@(index)];
    }
    // A few a frame, the nearest the middle of the visible part first, so a page scrolled by hand
    // fills in what is in view before what is not; the next frame picks up where this one left off.
    CGFloat middle = offset + height / 2;
    [wanted sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        CGFloat da = fabs([self topOfLine:a.integerValue] - middle), db = fabs([self topOfLine:b.integerValue] - middle);
        return da < db ? NSOrderedAscending : da > db ? NSOrderedDescending : NSOrderedSame;
    }];
    NSUInteger made = 0;
    for (NSNumber *index in wanted) {
        if (made++ == kLinesPerFrame) {
            _sightOffset = -CGFLOAT_MAX;
            break;
        }
        [self viewForLine:index.integerValue];
    }
}

// One line's place in the stack: the anchor sits on the edge its text is aligned to, so it scales
// toward its own text, and it dims and blurs with its distance from what is sung.
- (void)placeLine:(SGRKaraokeLineView *)view at:(NSInteger)index animated:(BOOL)animated {
    CGFloat height = self.bounds.size.height;
    NSInteger distance = [self distanceOf:index], below = index - _focus;
    CGRect frame = CGRectMake(_margin, [self topOfLine:index], view.bounds.size.width, view.bounds.size.height);
    CGPoint center = CGPointMake(view.right ? CGRectGetMaxX(frame) : _margin, CGRectGetMidY(frame));
    CGFloat scale = distance == 0 ? 1 : kDimScale;
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    view.blur = distance == 0 || _browsing ? 0 : MIN(_maxBlur, distance * _blurPerLine);
    BOOL near = CGRectIntersectsRect(CGRectInset(self.bounds, 0, -height / 2), frame)
             || CGRectIntersectsRect(CGRectInset(self.bounds, 0, -height / 2), view.frame);
    if (!animated || !near) {
        view.center = center;
        view.transform = transform;
        return;
    }
    NSTimeInterval delay = below > 0 ? MIN(0.3, below * 0.04) : 0;
    [UIView animateWithDuration:0.7 delay:delay usingSpringWithDamping:0.86 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        view.center = center;
        view.transform = transform;
    } completion:nil];
}

// The sung line rests at the anchor and the rest stack around it; lines below it follow a beat
// later, the further down the later, as Apple Music's do. A line sung over it stays where it is
// below, lit; the stack moves on to it once the line at the anchor is sung out.
- (void)placeLinesAnimated:(BOOL)animated {
    if (_browsing || !_tops.count) return;
    _focusTop = _tops[(NSUInteger)MAX(_focus, 0)].doubleValue;
    [self showLinesInSight];
    for (NSNumber *key in _shown) [self placeLine:_shown[key] at:key.integerValue animated:animated];
    [self placeBreak];
    // Room to scroll until the first line or the last one reaches the anchor.
    CGFloat lastTop = _tops.lastObject.doubleValue + (_openBreak >= 0 ? [self breakRoom] : 0);
    _scroll.contentInset = UIEdgeInsetsMake(_focusTop, 0, MAX(0, lastTop - _focusTop), 0);
}

// The dots, at the anchor for as long as a break is open, against the edge the line after it is on.
// They are only ever where they belong: they come and go by their own timeline, not by moving.
- (void)placeBreak {
    if (_openBreak < 0) {
        [_dots removeFromSuperview];
        return;
    }
    if (!_dots) {
        _dots = [[SGRKaraokeBreakView alloc] initWithFont:_font];
        _dotsLine = -1;
    }
    if (_dotsLine != _openBreak) {
        _dots.rightToLeft = readsRightToLeft(SGKaraokeLineText(_lines[(NSUInteger)_openBreak]));
        for (NSUInteger i = 0; i < _breakCount; i++) {
            if (_breaks[i].line == _openBreak) [_dots playFrom:_breaks[i].start to:_breaks[i].end];
        }
        _dotsLine = _openBreak;
    }
    if (_dots.superview != _scroll) [_scroll addSubview:_dots];
    _dots.right = alignsRight(_lines[(NSUInteger)_openBreak]);
    CGFloat top = [self topOfLine:_openBreak] - [self breakRoom];
    _dots.frame = CGRectMake(_margin, top, _builtWidth - 2 * _margin, _dots.bounds.size.height);
}

- (void)creditTo:(NSString *)source {
    NSString *text = source.length && _crediting ? [NSString stringWithFormat:@"Lyrics from %@", source] : nil;
    if (text == _credit.text || [text isEqualToString:_credit.text]) return;
    _credit.text = text;
    _credit.hidden = !_showing || !text.length;
    [self setNeedsLayout];
}

- (void)syncSiblings {
    for (UIView *sibling in self.superview.subviews) {
        if (sibling != self && _showing) sibling.alpha = 0;
    }
}

- (void)setShowing:(BOOL)showing {
    if (showing == _showing) return;
    _showing = showing;
    self.hidden = !showing;
    _credit.hidden = !showing || !_credit.text.length;
    for (UIView *sibling in self.superview.subviews) {
        if (sibling != self) sibling.alpha = showing ? 0 : 1;
    }
}

- (void)setChromeHidden:(BOOL)hidden {
    _chromeHidden = hidden;
    _extras.alpha = hidden ? 0 : 1;
    _extras.accessibilityElementsHidden = hidden;
    _credit.alpha = hidden ? 0 : 1;
}

// The player's position run on by the frame times the display will show and eased toward each new
// reading, so the sweep follows neither the callback's jitter nor the small jumps of the core's
// corrections. A seek or a new track is too far off to ease and is taken at once.
- (double)clockMs {
    NSInteger raw = SGKaraokePositionMs();
    CFTimeInterval shown = _link.targetTimestamp;
    BOOL running = raw != _reported;   // a paused player reports the same position every frame
    if (running) _stillSince = 0;
    else if (!_stillSince) _stillSince = shown;
    double reported = raw + (running ? (shown - CACurrentMediaTime()) * 1000 : 0);
    double predicted = _clock + (running ? (shown - _clockTime) * 1000 : 0);
    double error = reported - predicted;
    _clock = raw < 0 || fabs(error) > kClockSnapMs ? reported : predicted + error * kClockPull;
    _reported = raw;
    _clockTime = shown;
    return _clock;
}

- (void)tick {
    NSString *track = SGKaraokePlayingTrack();
    if (!(track == _track || [track isEqualToString:_track])) {
        SGLog(@"karaoke: page shows track %@, lyrics %@", track, SGKaraokeLinesForTrack(track) ? @"captured" : @"not captured yet");
        _track = track;
        _lines = nil;
        _builtWidth = 0;
        [self creditTo:nil];
        [self dropLineViews];
        [self offerExtras];
    }
    // Plain text is shown while Spotify is asked whether it has the song timed; its answer replaces it.
    NSArray<SGKaraokeLine *> *kept = _plain && _lines && track ? SGKaraokeLinesForTrack(track) : nil;
    if (kept && kept != _lines) {
        SGLog(@"karaoke: timed lines of %@ came in over the plain text", track);
        _lines = nil;
        _builtWidth = 0;
        [self creditTo:nil];
        [self dropLineViews];
    }
    if (!_lines && track && (_lines = SGKaraokeLinesForTrack(track))) {
        SGLog(@"karaoke: showing %lu lines of %@", (unsigned long)_lines.count, track);
        [self timeLines];
        [self setNeedsLayout];
    }
    [self setShowing:_tops != nil];
    // The source is settled a moment after the lines are, so it is asked for until it answers.
    if (_crediting && _lines && !_credit.text.length) [self creditTo:SGLyricsCreditFor(track)];
    if (!_tops) return;
    [self alignFade];
    if (_plain) {
        [self showLinesInSight];   // it moves only when scrolled by hand
        return;
    }

    double now = [self clockMs];
    NSInteger sung[kMostSung], focus, openBreak;
    NSUInteger count = [self sungAt:now into:sung focus:&focus openBreak:&openBreak];
    if (focus != _focus || openBreak != _openBreak || count != _sungCount || memcmp(sung, _sung, count * sizeof(NSInteger))) {
        // Lines sung out go back to dim, lines coming in light up, the ones sung throughout carry on.
        for (NSUInteger i = 0; i < _sungCount; i++) {
            BOOL still = NO;
            for (NSUInteger j = 0; j < count; j++) still = still || sung[j] == _sung[i];
            if (!still) _shown[@(_sung[i])].active = NO;
        }
        for (NSUInteger j = 0; j < count; j++) {
            if (![self isSung:sung[j]]) [self viewForLine:sung[j]].active = YES;
        }
        BOOL jump = labs(focus - _focus) > 2;   // a seek, not the song moving on
        memcpy(_sung, sung, count * sizeof(NSInteger));
        _sungCount = count;
        _focus = focus;
        _openBreak = openBreak;
        _arrangement++;
        if (openBreak < 0) [_dots removeFromSuperview];
        [self placeLinesAnimated:!jump];
    } else {
        [self showLinesInSight];   // the page may be scrolling by hand, or springing back
    }
    for (NSUInteger i = 0; i < _sungCount; i++) [_shown[@(_sung[i])] showTime:now];
    if (_dots.superview) [_dots showTime:now running:!_stillSince || _link.targetTimestamp - _stillSince < kStillFor at:_link.targetTimestamp];
}

// What is sung at `now`: each line from its start until it is sung out, so two voices over each
// other are both lit, and the last line begun on through the pause after it, as Apple Music keeps a
// line lit until the next one comes. A pause that is a break is the dots' instead, until the moment
// before its end when the line after it moves up to the anchor, sharp but not yet lit.
- (NSUInteger)sungAt:(double)now into:(NSInteger *)sung focus:(NSInteger *)focus openBreak:(NSInteger *)openBreak {
    NSInteger count = (NSInteger)_lines.count, last = -1;
    while (last + 1 < count && _spans[last + 1].start <= now) last++;
    *openBreak = -1;
    NSInteger breakLine = -1;
    for (NSUInteger i = 0; i < _breakCount; i++) {
        SGRKaraokeBreak pause = _breaks[i];
        if (now < pause.start || now >= pause.end) continue;
        breakLine = pause.line;
        if (now < pause.end - kBreakCollapse * 1000) *openBreak = pause.line;
    }
    NSUInteger found = 0;
    for (NSInteger i = 0; i <= last && found < kMostSung; i++) {
        if (_spans[i].end > now || (i == last && breakLine < 0)) sung[found++] = i;
    }
    *focus = breakLine >= 0 ? breakLine : found ? sung[0] : last;
    return found;
}

@end
