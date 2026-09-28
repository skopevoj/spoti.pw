// Album discovery (issue #119): let Spotify measure and present its entire footer, including
// More by, related videos, recommendations and their spacers, in the server's original order.
// No translated heading matching and no zero-height cells: links, carousels and accessibility
// stay Spotify's. The album's length and copyright retain the redesign's subdued treatment.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Album.h"

static BOOL isFooterContent(UIView *content) {
    static NSMutableDictionary<id, NSNumber *> *answers;
    if (!answers) answers = [NSMutableDictionary dictionary];
    Class cls = object_getClass(content);
    if (!cls) return NO;
    NSNumber *answer = answers[(id<NSCopying>)cls];
    if (!answer) {
        answer = @([NSStringFromClass(cls) containsString:@"Album_PageImpl20FooterStructuredData"]);
        answers[(id<NSCopying>)cls] = answer;
    }
    return answer.boolValue;
}

%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *content = cell.contentView.subviews.firstObject;
    if (!SGRAlbumPageOf(cell)) return;
    // Related releases are nested Element_List cells. Their ContentCardAlbum button is painted
    // before attachment, so neither the repaint hook nor the outer cell's full-width cleanup sees
    // it (device, 2026-09-24). Clear that backing only; the artwork, badges and placeholders are
    // separate descendants and keep their own paint. Run on the card's own layout for reuse too.
    UIView *card = SGRFindByIdentifier(content, @"Components.UI.ContentCardAlbum", NULL);
    if (card && SGIsBaseSurface(card.layer.backgroundColor)) card.backgroundColor = UIColor.clearColor;
    if (!isFooterContent(content)) return;
    for (NSString *identifier in @[@"Album.ConsumptionExperience", @"Album.Copyright"]) {
        UIView *metadata = SGRFindByIdentifier(content, identifier, NULL);
        SGForEachView(metadata, ^(UIView *view) {
            if (![view isKindOfClass:UILabel.class]) return;
            UILabel *label = (UILabel *)view;
            if (![label.textColor isEqual:SGRTertiary()]) label.textColor = SGRTertiary();
        });
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
