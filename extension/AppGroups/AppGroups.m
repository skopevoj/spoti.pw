// Spotify's App Groups, redirected into whichever group the sideload signature really has.
//
// The main app hands the home screen widget everything it shows through UserDefaults suites named
// group.com.spotify.client.widget, .widget.data and .widget.lifecycle. Those groups belong to
// Spotify's team, so a re-signed IPA never has them: its profile carries groups of its own
// (group.<hash>.N from a paid certificate service, something else from AltStore), each process
// then gets a private, empty suite, and the widget stays on its "Open Spotify and play" placeholder.
//
// This dylib is loaded by Spotify, its WidgetExtension.appex and its Siri (Intents) extensions
// (scripts/pipeline.sh adds the load command to each); without it Siri reads no signed-in account and
// answers that you need to log in. In each it maps every group.* identifier the process is not entitled
// to onto a folder inside one group it is entitled to, the same folder in both processes, so the
// suites and container files meet again. It is plain runtime swizzling, no Substrate, because the
// extension carries nothing else of the tweak.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/log.h>

typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

@interface NSUserDefaults (SGAppGroups)
- (instancetype)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container;
@end

static os_log_t sLog;
static NSArray<NSString *> *sEntitled;
static NSURL *(*sOrigContainerURL)(id, SEL, NSString *);
static id (*sOrigInitWithSuiteName)(id, SEL, NSString *);

static NSArray<NSString *> *EntitledGroups(void) {
  SecTaskRef task = SecTaskCreateFromSelf(NULL);
  if (!task) return @[];
  CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.security.application-groups"), NULL);
  CFRelease(task);
  NSArray *groups = CFBridgingRelease(value);
  if (![groups isKindOfClass:NSArray.class]) return @[];
  // Sorted, so the app and its extensions pick the same host group whatever order the signer wrote.
  return [groups sortedArrayUsingSelector:@selector(compare:)];
}

// The folder that stands in for `group`, or nil when the process may use the group as it is (or
// has no group at all to put it in).
static NSURL *RedirectedContainer(NSString *group) {
  if (![group isKindOfClass:NSString.class] || ![group hasPrefix:@"group."]) return nil;
  if ([sEntitled containsObject:group]) return nil;
  NSFileManager *fm = NSFileManager.defaultManager;
  // AltStore and SideStore register the original group with the team appended, which is the
  // real thing already.
  NSString *prefix = [group stringByAppendingString:@"."];
  for (NSString *entitled in sEntitled) {
    if ([entitled hasPrefix:prefix]) return sOrigContainerURL(fm, @selector(containerURLForSecurityApplicationGroupIdentifier:), entitled);
  }
  for (NSString *entitled in sEntitled) {
    NSURL *host = sOrigContainerURL(fm, @selector(containerURLForSecurityApplicationGroupIdentifier:), entitled);
    if (!host) continue;
    NSURL *url = [host URLByAppendingPathComponent:group isDirectory:YES];
    [fm createDirectoryAtURL:[url URLByAppendingPathComponent:@"Library/Preferences" isDirectory:YES]
        withIntermediateDirectories:YES attributes:nil error:NULL];
    return url;
  }
  return nil;
}

static NSURL *SGContainerURL(id self, SEL _cmd, NSString *group) {
  NSURL *url = RedirectedContainer(group);
  return url ?: sOrigContainerURL(self, _cmd, group);
}

// initWithSuiteName: is the public door every UserDefaults(suiteName:) goes through; the container
// variant is what App Group suites resolve to inside Foundation, so it is handed the stand-in.
static id SGInitWithSuiteName(NSUserDefaults *self, SEL _cmd, NSString *suite) {
  NSURL *url = RedirectedContainer(suite);
  if (url && [self respondsToSelector:@selector(_initWithSuiteName:container:)]) {
    os_log(sLog, "[spotifyglass] appgroups: %{public}@ -> %{public}@", suite, url.path);
    return [self _initWithSuiteName:suite container:url];
  }
  return sOrigInitWithSuiteName(self, _cmd, suite);
}

__attribute__((constructor)) static void SGAppGroupsInit(void) {
  sLog = os_log_create("spotifyglass", "appgroups");
  sEntitled = EntitledGroups();
  os_log(sLog, "[spotifyglass] appgroups: %{public}@ entitled to %{public}@",
         NSBundle.mainBundle.bundleIdentifier, [sEntitled componentsJoinedByString:@", "]);
  if (sEntitled.count == 0) return;

  Method m = class_getInstanceMethod(NSFileManager.class, @selector(containerURLForSecurityApplicationGroupIdentifier:));
  sOrigContainerURL = (void *)method_setImplementation(m, (IMP)SGContainerURL);
  m = class_getInstanceMethod(NSUserDefaults.class, @selector(initWithSuiteName:));
  sOrigInitWithSuiteName = (void *)method_setImplementation(m, (IMP)SGInitWithSuiteName);
}
