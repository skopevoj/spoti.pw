// The redesign's design tokens: every redesigned screen takes its colours, type, spacing, radii and
// motion from here, so the screens read as one app and nothing is tuned per screen by hand.
//
// Dark colors are white over the artwork field (SGRField.h), whose raw palette is kept dark enough that
// SGRPrimary and SGRSecondary both pass WCAG AA on it. Type is the system font (SF Pro) sized by the
// text style and capped, since Spotify's pages lay out for a fixed header height. Motion is springs,
// critically damped for layout and a little bounce for press feedback; under Reduce Motion both
// become instant, while crossfades stay, a fade not being motion.
//
// Threading: the constants and the colours are safe anywhere; fonts, SGRAnimate and the
// accessibility reads are main thread only.
#import <UIKit/UIKit.h>

extern const CGFloat SGRSideMargin;      // 16, the page's side margin
extern const CGFloat SGRGrid;            // 8, every gap is a multiple of it
extern const CGFloat SGRRadiusArtwork;   // 12, the player's cover
extern const CGFloat SGRRadiusCard;      // 16, a content card
extern const CGFloat SGRRadiusCover;     // 8, a release cover in a list
extern const CGFloat SGRRadiusThumb;     // 6, a row's thumbnail up to 64pt
extern const CGFloat SGRGlassCircleSize; // 44, a round glass behind a top bar button
extern const CGFloat SGRActionHeight;    // 48, a button of the action row under a hero
extern const CGFloat SGRActionSpacing;   // 12, between the buttons of an action row
extern const CGFloat SGRGlassSpacing;    // 16, how near two glass shapes merge in one container
extern const NSTimeInterval SGRCrossfade;   // 0.35, a new image or field colour fading in

UIColor *SGRPrimary(void);      // dark ink in light appearance, white in dark
UIColor *SGRSecondary(void);    // adaptive secondary ink; increased contrast supported
UIColor *SGRTertiary(void);     // adaptive tertiary ink; increased contrast supported
UIColor *SGRAccent(void);       // the accent colour of Appearance, else Spotify's green
UIColor *SGRNeutralField(void); // neutral appearance-matched field before artwork arrives
// Where glass cannot be (Reduce Transparency), the shape it would have had: white 16% over the field.
UIColor *SGRSolidGlassFill(void);
// A content surface on the field (a card), a step lighter than the field it sits on.
UIColor *SGRElevated(UIColor *field);
// The line between two rows of a list, drawn a pixel thick from the text's leading edge: white 12%, 20% with
// Increase Contrast. Never a border around anything -- the redesign's surfaces are told apart by their fill.
UIColor *SGRHairline(void);

// The system font at the size `style` has for the current content size category, but never larger
// than it has at `largest`, in `weight`. Callers re-ask on traitCollectionDidChange:.
UIFont *SGRFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest);
// The same font with digits of one width, so a time or a count does not twitch as it changes.
UIFont *SGRMonospacedDigitsFont(UIFont *font);

BOOL SGRReduceMotion(void);
BOOL SGRReduceTransparency(void);
BOOL SGRIncreaseContrast(void);

typedef NS_ENUM(NSInteger, SGRMotion) {
    SGRMotionLayout,   // a spring with no overshoot, for anything moving or resizing
    SGRMotionPress,    // a spring with a little bounce, for press feedback
    SGRMotionFade,     // an ease in and out over SGRCrossfade, kept under Reduce Motion
};
// Runs `animations` with the motion's timing, or at once under Reduce Motion (except a fade), and
// always calls `completion`. Only transform, alpha and colour belong in it while a page scrolls.
void SGRAnimate(SGRMotion motion, void (^animations)(void), void (^completion)(BOOL finished));

// Exact neutral light surfaces are also stripped from the known page roots in light appearance.
BOOL SGRIsBaseSurface(CGColorRef color);
