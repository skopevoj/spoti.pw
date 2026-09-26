// Main-thread ownership of the system grant required for background GPU inference.
#import <Foundation/Foundation.h>
// expired is YES when iOS (or the user through its task UI) ends an acquired grant.
void SGSingBackgroundStart(void (^changed)(BOOL expired));
void SGSingBackgroundEnd(void);
BOOL SGSingBackgroundAllowed(void);
NSString *SGSingBackgroundExplanation(void);
void SGSingBackgroundProgress(uint64_t generation, uint64_t completed, uint64_t total);
