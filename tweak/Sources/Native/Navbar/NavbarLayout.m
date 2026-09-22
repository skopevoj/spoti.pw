// The saved composition of the bar, as NSUserDefaults property lists.
#import "Navbar.h"

NSString *const SGNavbarID = @"id";
NSString *const SGNavbarTitle = @"title";
NSString *const SGNavbarURI = @"uri";
NSString *const SGNavbarIcon = @"icon";
NSString *const SGNavbarIconKind = @"iconKind";
NSString *const SGNavbarIconKindEncore = @"encore";
NSString *const SGNavbarIconKindSymbol = @"sfSymbol";
NSString *const SGNavbarHidden = @"hidden";

static NSString *const kNavbarLayout = @"spotifyglass.navbar.layout";
static NSString *const kNavbarStock = @"spotifyglass.navbar.stock";

// Only property list types go in, so a corrupt read cannot be anything but an array of dictionaries.
static NSArray *listOfKind(NSString *key, Class kind) {
    NSArray *list = [NSUserDefaults.standardUserDefaults arrayForKey:key];
    for (id item in list) if (![item isKindOfClass:kind]) return @[];
    return list ?: @[];
}

NSArray<NSDictionary *> *SGNavbarLayout(void) {
    return listOfKind(kNavbarLayout, NSDictionary.class);
}

void SGSetNavbarLayout(NSArray<NSDictionary *> *layout) {
    [NSUserDefaults.standardUserDefaults setObject:layout ?: @[] forKey:kNavbarLayout];
}

NSArray<NSString *> *SGNavbarStock(void) {
    return listOfKind(kNavbarStock, NSString.class);
}

void SGSetNavbarStock(NSArray<NSString *> *stock) {
    [NSUserDefaults.standardUserDefaults setObject:stock ?: @[] forKey:kNavbarStock];
}
