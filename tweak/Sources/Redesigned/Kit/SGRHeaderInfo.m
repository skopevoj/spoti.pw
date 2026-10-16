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
// The faces: Spotify's 24pt, overlap and 8pt gap, but no taller than the name's line, so none moves the title.
static const CGFloat kFaceMax = 22, kFaceStep = 0.85, kFaceGap = 8, kFaceRing = 1.5;
static const NSUInteger kFaceCap = 3;

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

// Each face of the Encore facepile under `row` is a plain UIImageView inside an AvatarView; the pile's icon
// disc and its "+N" are not faces. Left to right, as the pile draws them.
static NSArray<UIImageView *> *faceViewsIn(UIView *row, BOOL *found) {
    __block UIView *pile = nil;
    SGForEachView(row, ^(UIView *v) {
        if (!pile && [NSStringFromClass(v.class) containsString:@"FacepileView"]) pile = v;
    });
    *found = pile != nil;
    if (!pile) return nil;
    NSMutableArray<UIImageView *> *faces = [NSMutableArray array];
    SGForEachView(pile, ^(UIView *v) {
        if (![v isKindOfClass:UIImageView.class] || v.hidden) return;
        BOOL avatar = NO;
        for (UIView *up = v.superview; up && up != pile; up = up.superview) {
            if (up.hidden) return;
            if ([NSStringFromClass(up.class) containsString:@"AvatarView"]) avatar = YES;
        }
        if (avatar) [faces addObject:(UIImageView *)v];
    });
    [faces sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = [a convertPoint:CGPointZero toView:pile].x, bx = [b convertPoint:CGPointZero toView:pile].x;
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return faces;
}

static BOOL sameImages(NSArray<UIImage *> *a, NSArray<UIImage *> *b) {
    if (a.count != b.count) return NO;
    for (NSUInteger i = 0; i < a.count; i++) {
        if (a[i] != b[i]) return NO;
    }
    return YES;
}

@implementation SGRHeaderInfo {
    UILabel *_title, *_creator, *_length, *_about;
    SGRMirrorButton *_shuffle, *_trailing;
    SGRPlayCapsule *_play;
    __weak UIView *_creatorLink;
    UIView *_faces;
    NSMutableArray<UIImageView *> *_faceViews;
    NSArray<UIImage *> *_faceImages;
    __weak UIView *_facesRow;
    NSHashTable<UIImageView *> *_watchedFaces;
    CGFloat _faceSide;
    BOOL _facesQueued, _creatorDrawn;
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

    _faces = [UIView new];
    _faces.hidden = YES;
    // Transparent while empty: a fade begins from what is on screen, and a hidden layer is there at 1.
    _faces.alpha = 0;
    _faces.userInteractionEnabled = NO;
    _faces.accessibilityElementsHidden = YES;
    [self addSubview:_faces];
    _faceViews = [NSMutableArray array];
    _faceImages = @[];
    return self;
}

// Touches only for the buttons and, where there is one, the creator line: the rest of the text lets a
// pull or a tap through to the page under it.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
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

// The creator line, tappable where its name and faces are drawn -- a tap either side of a short name belongs
// to the page under it, which a pull down starts on. Spotify's own control stays concealed and only fires.
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

// The label is only as wide as its name, and the faces take no touches of their own: both answer as the name.
- (UIView *)sgr_creatorHit:(CGPoint)point {
    if (!_creator.userInteractionEnabled || _creator.hidden) return nil;
    CGRect line = _creator.frame;
    if (!_faces.hidden) line = CGRectUnion(line, _faces.frame);
    return CGRectContainsPoint(CGRectInset(line, -8, -6), point) ? _creator : nil;
}

- (void)showFacesIn:(UIView *)row {
    _facesRow = row;
    BOOL pile = NO;
    NSArray<UIImageView *> *views = row ? faceViewsIn(row, &pile) : nil;
    NSMutableArray<UIImage *> *images = [NSMutableArray array];
    for (UIImageView *view in views) {
        [self sgr_watchFace:view];
        if (view.image && images.count < kFaceCap) [images addObject:view.image];
    }
    static BOOL loggedNoPile, loggedEmpty;
    if (row && !pile && !loggedNoPile) {
        loggedNoPile = YES;
        SGLog(@"redesign header: no facepile under %@ (%@)", NSStringFromClass(row.class), row.accessibilityIdentifier);
    }
    if (views.count && !images.count && !_faceImages.count && !loggedEmpty) {
        loggedEmpty = YES;
        SGLog(@"redesign header: %lu face(s) before \"%@\", no picture yet", (unsigned long)views.count, _creator.text);
    }
    // Faces still loading, or loading again, keep what is drawn; one with no picture ever draws nothing.
    if (views.count && !images.count) return;
    [self sgr_takeFaces:images];
}

// A picture lands with no layout pass anywhere, so its image view is watched; the Kit's class-level watch
// covers Encore's own classes, and these are plain UIImageViews.
- (void)sgr_watchFace:(UIImageView *)view {
    if (!_watchedFaces) _watchedFaces = [NSHashTable weakObjectsHashTable];
    if ([_watchedFaces containsObject:view]) return;
    [_watchedFaces addObject:view];
    __weak SGRHeaderInfo *weakSelf = self;
    SGRObserveImage(view, ^(UIImageView *changed) { [weakSelf sgr_faceLanded]; });
}

// Called from inside Spotify's setImage:, so read once it has returned, and once for faces landing together.
- (void)sgr_faceLanded {
    if (_facesQueued) return;
    _facesQueued = YES;
    __weak SGRHeaderInfo *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGRHeaderInfo *info = weakSelf;
        if (!info) return;
        info->_facesQueued = NO;
        UIView *row = info->_facesRow;
        if (row) [info showFacesIn:row];
    });
}

- (void)sgr_takeFaces:(NSArray<UIImage *> *)images {
    if (sameImages(images, _faceImages)) return;
    BOOL arriving = !_faceImages.count && images.count;
    _faceImages = [images copy];
    while (_faceViews.count < images.count) {
        UIImageView *face = [UIImageView new];
        face.contentMode = UIViewContentModeScaleAspectFill;
        face.clipsToBounds = YES;
        // Each face under the one before it, as the pile draws them.
        [_faces insertSubview:face atIndex:0];
        [_faceViews addObject:face];
        _faceSide = 0;
    }
    for (NSUInteger i = 0; i < _faceViews.count; i++) {
        _faceViews[i].image = i < images.count ? images[i] : nil;
        _faceViews[i].hidden = i >= images.count;
    }
    if (arriving) {
        static BOOL loggedFirst, loggedLate;
        BOOL *logged = _creatorDrawn ? &loggedLate : &loggedFirst;
        if (!*logged) {
            *logged = YES;
            SGLog(@"redesign header: %lu face(s) before \"%@\", %@", (unsigned long)images.count, _creator.text,
                  _creatorDrawn ? @"landed after the line was drawn, faded in" : @"there on the first pass");
        }
    }
    [self setNeedsLayout];
    if (!images.count) _faces.alpha = 0;
    if (!arriving) return;
    if (!_creatorDrawn || !self.window || _creator.hidden) {
        _faces.alpha = 1;
        return;
    }
    // Late, over a line already drawn: the name slides aside once while the faces fade in beside it.
    CGPoint from = _creator.center;
    [UIView performWithoutAnimation:^{ [self layoutIfNeeded]; }];
    CGPoint to = _creator.center;
    _creator.center = from;
    SGRAnimate(SGRMotionLayout, ^{ self->_creator.center = to; }, nil);
    SGRAnimate(SGRMotionFade, ^{ self->_faces.alpha = 1; }, nil);
}

// The name as wide as its text, the faces before it (after it, right to left), the two centred as one.
- (void)sgr_layoutCreator:(CGRect)line {
    NSUInteger count = _faceImages.count;
    CGFloat side = MIN(kFaceMax, ceil(_creator.font.lineHeight) + 1), step = round(side * kFaceStep);
    CGFloat faces = count ? side + (count - 1) * step : 0, lead = count ? faces + kFaceGap : 0;
    CGFloat name = MIN(ceil([_creator sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width), line.size.width - lead);
    CGFloat x = line.origin.x + round((line.size.width - lead - name) / 2);
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    _creator.frame = CGRectMake(rtl ? x : x + lead, line.origin.y, name, line.size.height);
    _creatorDrawn = YES;
    _faces.hidden = count == 0;
    if (!count) return;
    _faces.frame = CGRectMake(rtl ? x + name + kFaceGap : x, line.origin.y + round((line.size.height - side) / 2), faces, side);
    for (NSUInteger i = 0; i < count; i++) _faceViews[i].frame = CGRectMake(i * step, 0, side, side);
    if (_faceSide == side) return;
    _faceSide = side;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _faceViews.count; i++) {
        CALayer *layer = _faceViews[i].layer;
        layer.cornerRadius = side / 2;
        if (i == 0) continue;
        // A ring of the field between a face and the one over it, cut rather than drawn, whatever the colour.
        UIBezierPath *cut = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, side, side)];
        [cut appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectInset(CGRectMake(-step, 0, side, side), -kFaceRing, -kFaceRing)]];
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.fillRule = kCAFillRuleEvenOdd;
        mask.path = cut.CGPath;
        layer.mask = mask;
    }
    [CATransaction commit];
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
        UIView *button = buttons[i];
        BOOL hide = !shown[i].boolValue;
        if (button.hidden == hide) continue;
        button.hidden = hide;
        changed = YES;
        // One of Spotify's buttons that turns up after the page is on screen (save, on a playlist opened for
        // the first time) fades in beside the others rather than popping in.
        if (!hide && self.window) {
            button.alpha = 0;
            SGRAnimate(SGRMotionFade, ^{ button.alpha = 1; }, nil);
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
        if (label == _creator) [self sgr_layoutCreator:CGRectMake(kSide, y, text, height)];
        else label.frame = CGRectMake(kSide, y, text, height);
        y += height;
        previous = label;
    }
    if (_creator.hidden) _faces.hidden = YES;
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
