// The card the Ko-fi ask and the certificate offer rise in: a glowing disc, a title, a line or two, one
// glowing button and a quiet way out, over the dimmed screen.
#import <UIKit/UIKit.h>

UIColor *SGColorHex(uint32_t hex, CGFloat alpha);

// A glass capsule with a rim of `color` circling it and a breathing glow. Prominent tints the glass itself.
@interface SGGlowButton : UIControl
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol color:(UIColor *)color prominent:(BOOL)prominent;
@end

// An 80 pt disc filled top to bottom that glows into the card in `glow`; the caller puts its art on it.
UIView *SGCardSheetDisc(UIColor *top, UIColor *bottom, UIColor *glow);

@interface SGCardSheet : UIViewController
@property (nonatomic, strong) UIColor *color;   // the warmth over the card and the button's rim
@property (nonatomic, strong) UIView *hero;
@property (nonatomic, copy) NSString *eyebrow;  // optional
@property (nonatomic, copy) NSString *heading;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, copy) NSString *note;     // optional, small under the buttons
@property (nonatomic, copy) NSString *actionTitle;
@property (nonatomic, copy) NSString *actionSymbol;
@property (nonatomic, copy) NSString *dismissTitle;
@property (nonatomic, copy) void (^action)(void);     // once the card is gone
@property (nonatomic, copy) void (^appeared)(void);
- (void)present;   // over the top controller, if the screen has one
@end
