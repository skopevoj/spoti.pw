// AirPods gestures start at launch when switched on (HeadGestures.h).
#import "Core/SGCore.h"
#import "HeadGestures.h"

%ctor {
    if (SGOff("headgestures")) return;
    dispatch_async(dispatch_get_main_queue(), ^{ SGHeadGesturesApply(); });
}
