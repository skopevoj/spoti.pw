#import <Foundation/Foundation.h>
#define SGLog(fmt, ...) do { if (getenv("SGVERBOSE")) fprintf(stderr, "  log: %s\n", [NSString stringWithFormat:(fmt), ##__VA_ARGS__].UTF8String); } while (0)
