// Sing's voice model download going on while Spotify is away (SGSingModel.h). When its background session
// has news for an app that was suspended or quit, iOS wakes Spotify and hands the news to the app delegate.
// Spotify's (MusicApp_ContainerWiring.SpotifyAppDelegate in 9.1.78) has no
// application:handleEventsForBackgroundURLSession:completionHandler: of its own -- its method list in the
// binary has none -- so the mod adds one that takes its own session's events and leaves any other
// session's alone. Firebase's app delegate swizzler (GULAppDelegateSwizzler, in the binary) hands the same
// completion handler to its own interceptors and then to this method, so answering another session's here
// would call a handler its owner calls again later. A launch also reconnects to a download left running.
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "SGSingController.h"
#import "SGSingModel.h"

%hook _TtC24MusicApp_ContainerWiring18SpotifyAppDelegate
%new
- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier
  completionHandler:(void (^)(void))completionHandler {
    SGSingModelHandlesSession(identifier, completionHandler);
}
%end

%ctor {
    if (!SGSingSupported()) return;
    %init;
    SGRequireClasses(@[@"_TtC24MusicApp_ContainerWiring18SpotifyAppDelegate"]);
    dispatch_async(dispatch_get_main_queue(), ^{ SGSingModelReconnect(); });
}
