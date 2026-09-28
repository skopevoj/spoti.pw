// What SpicyLyrics.m takes from Core, on the Mac: SGLog to stderr with SGVERBOSE set, and its
// defaults kept in memory so the test writes nothing to the Mac's own preferences.
#import <Foundation/Foundation.h>
#define SGLog(fmt, ...) do { if (getenv("SGVERBOSE")) fprintf(stderr, "  log: %s\n", [NSString stringWithFormat:(fmt), ##__VA_ARGS__].UTF8String); } while (0)

@interface SGHarnessDefaults : NSObject
+ (instancetype)standardUserDefaults;
- (id)objectForKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
@end
#define NSUserDefaults SGHarnessDefaults
