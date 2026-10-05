// Settings of the player that hold for either look.
#import <UIKit/UIKit.h>

UIViewController *SGLockScreenWidgetPage(void);
@class SGModSection;
// Speed and pitch, which the player's more menu draws its sliders for: here the switch that has the pitch follow
// the speed, as a record played faster, by resampling rather than the time and pitch unit's stretching.
SGModSection *SGSpeedPitchSection(void);
