// Keeping Spotify's views the way a redesigned screen set them: Spotify re-applies its own look on
// reuse, on state changes and on every layout pass, so each helper here either survives that or is
// cheap enough to run again on every pass. Nothing here uses `hidden` on a view Spotify arranges in a
// stack: OverflowStackView and some Encore stacks trap in updateConstraints when an arranged view
// hides, so a view goes away by alpha, touches and accessibility instead.
//
// Ownership: what a helper creates belongs to the view it was made for (associated objects), and a
// helper keeps only weak references to Spotify's views.
// Threading: main thread only.
#import <UIKit/UIKit.h>

#pragma mark - views

// Alpha 0, no touches, hidden from accessibility, and kept so: the instance becomes a runtime subclass
// of its own class (the way KVO does it, `class` still answers the original) whose setAlpha: and
// setUserInteractionEnabled: hold those values. For plain UIKit views (a UIImageView, a UILabel); a
// Swift class, or an instance already observed with KVO, gets the values once instead, re-applied on
// the next call, and a log line says so once.
void SGRSuppress(UIView *view);

// Digits of one width in the label, kept through Spotify's own setText:, setAttributedText: and
// setFont: by a runtime subclass of the instance, like SGRSuppress. Idempotent.
void SGRMonospacedDigits(UILabel *label);

// `changed` after every setImage: on the image view, Spotify's included, for as long as the view lives: by a
// runtime subclass of the instance like SGRSuppress, or, for one of Spotify's own classes (Encore's image
// views, which no instance of can be subclassed), by an override on that class, which only ever reports the
// instances that asked. A second call replaces the block. NO when neither took, which a log line says once:
// the caller then only sees what its own passes read.
//
// This is how a picture that lands after a screen has been laid out reaches it: setting an image lays no
// ancestor out, so nothing else tells the screen it is there.
BOOL SGRObserveImage(UIImageView *view, void (^changed)(UIImageView *view));

// `laidOut` after every layoutSubviews of the view, Spotify's included, for as long as the view lives, by
// a runtime subclass of the instance like SGRSuppress. A second call replaces the block, and a pass started
// from inside the block is not reported again. NO when the view cannot be subclassed (one of Spotify's Swift
// classes, a KVO-observed instance): the caller then has only the passes it hooks itself to work from.
//
// For a screen that arranges Spotify's controls its own way: a parent lays its children out after the
// hook that placed them has returned, so frames set from an ancestor's pass are the ones overwritten.
BOOL SGRObserveLayout(UIView *view, void (^laidOut)(UIView *view));

// The first view under `root` (itself included) with the accessibility identifier, depth first. The
// answer is kept weakly on `root` under `cacheKey` and searched for again only when it is gone, has
// left `root` or changed its identifier. nil when there is none; a miss is not cached.
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey);

// A view that draws only a shadow, for a view whose own layer clips (rounded artwork): made once per
// host under `key`, inserted at the bottom of `host`. The caller gives it its frame and transform; its
// shadowPath follows its bounds and cornerRadius.
@interface SGRShadowPlate : UIView
@property (nonatomic) CGFloat cornerRadius;   // SGRRadiusArtwork unless set
@end
SGRShadowPlate *SGRShadowPlateIn(UIView *host, const void *key);

#pragma mark - Spotify's controls and pages

// The base surface a list cell paints over a page's field, cleared: the #121212 the redesign's AMOLED
// black has already turned black, on the cell and on everything under it nearly as wide as the cell, and
// the full-width fade a "see more" draws over its last row, which the black makes a dark band. The Kit's
// repaint hook misses all of it -- it only hears about a colour when Spotify sets it, and a cell is painted
// before it is inside the page and brings its old paint with it when it is reused -- so this runs from the
// cell's own layout pass, and is cheap enough to.
//
// Only what is nearly as wide as the cell: a badge's black disc, a card's grey and an image's placeholder
// are their own. A cell nested inside the cell and narrower than that (a card in a carousel) is not walked
// into: its own row decides for it.
void SGRClearCellPaint(UIView *cell);

// Fires one of Spotify's own buttons the way a tap on it would: the first control under `source`, through
// SGRFire, and through -accessibilityActivate when that control answers its touches some other way. For a
// control the redesign conceals and draws itself (the action row's buttons, a header's creator line).
void SGRActivate(UIView *source);

// Fires a control's action the way a tap would: the actions registered for primary action triggered,
// else those for touch up inside. NO when the control has neither (an Encore control that reads its
// touches through a gesture recognizer); what was found is logged once per class.
BOOL SGRFire(UIControl *control);
