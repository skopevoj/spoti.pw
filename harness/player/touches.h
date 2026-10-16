// Real touches for the harness (touches.m): each returns the view the touch landed on and calls `done`
// a moment after the finger has lifted.
#import <UIKit/UIKit.h>

UIView *SGRHarnessTap(UIWindow *window, CGPoint point, void (^done)(void));
// A tap held down for `hold` seconds before it lifts, long enough to see a pressed state.
UIView *SGRHarnessPress(UIWindow *window, CGPoint point, NSTimeInterval hold, void (^done)(void));
UIView *SGRHarnessDrag(UIWindow *window, CGPoint from, CGPoint to, NSTimeInterval duration, void (^done)(void));
