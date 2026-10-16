// Spotify's shared keychain group, kept in a file in an App Group the re-signed IPA does have.
//
// Spotify's app stores the signed-in account's login token in the keychain access group
// <team>.com.spotify.client.extension-credentials, so its Siri (Intents) extension, a different
// process, can read it. That group belongs to Spotify's team: re-signed, neither process is entitled to
// it any more, every SecItem call that names it fails with errSecMissingEntitlement, the extension finds
// no account and Siri answers "verify your account details".
//
// This file is part of the dylib loaded by Spotify and by every extension of it (AppGroups.m's, which
// scripts/pipeline.sh adds the load command of to each). It answers the SecItem calls that name that group
// itself, from a property list in the container of the first App Group the process is entitled to (the one
// AppGroups.m puts the others in too), so the app and the extension, which share that container, see the
// same items again. Every other call goes to the real keychain as it was. A process that is entitled to the
// group for real (a signature that kept Spotify's entitlements) is left alone entirely.
//
// The calls are interposed with dyld's __interpose section rather than rebound by hand: the dylib is a load
// command of the app and of each extension, so dyld points every image's SecItem* imports at the functions
// here before any of Spotify's code runs; this image's own calls to them reach the real ones.
//
// Only generic and internet passwords are kept here, which is what a login token is. The file is not
// encrypted: the items that land in it are the ones that were meant for a keychain, in a container only
// Spotify and its extensions can open, and the file is kept out of backups and out of reach until the first
// unlock after a restart. A query for a password with no access group at all that the real keychain does not
// have is also answered from the file, for an extension that asks without naming the group.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <os/log.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>

typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

// The group's name after the team: the team is Spotify's, whatever the re-signed one is.
static NSString *const kCredentialsSuffix = @".com.spotify.client.extension-credentials";

static os_log_t sLog;
static dispatch_once_t sOnce;
static NSArray<NSString *> *sKeychainGroups;
static NSURL *sFile, *sLockFile;   // nil while there is no App Group to keep the items in
static NSObject *sGuard;

static NSArray *Entitlement(NSString *name) {
  SecTaskRef task = SecTaskCreateFromSelf(NULL);
  if (!task) return @[];
  CFTypeRef value = SecTaskCopyValueForEntitlement(task, (__bridge CFStringRef)name, NULL);
  CFRelease(task);
  NSArray *list = CFBridgingRelease(value);
  return [list isKindOfClass:NSArray.class] ? list : @[];
}

static void SetUp(void) {
  dispatch_once(&sOnce, ^{
    sLog = os_log_create("spotifyglass", "keychain");
    sGuard = [NSObject new];
    sKeychainGroups = Entitlement(@"keychain-access-groups");
    // Sorted, as AppGroups.m sorts them, so the app and its extensions pick the same group.
    NSArray *groups = [Entitlement(@"com.apple.security.application-groups") sortedArrayUsingSelector:@selector(compare:)];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *group in groups) {
      if (![group isKindOfClass:NSString.class]) continue;
      NSURL *host = [fm containerURLForSecurityApplicationGroupIdentifier:group];
      if (!host) continue;
      NSURL *folder = [host URLByAppendingPathComponent:@"Library/SpotifyGlass" isDirectory:YES];
      [fm createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL];
      NSURL *excluded = folder;
      [excluded setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
      sFile = [folder URLByAppendingPathComponent:@"keychain.plist"];
      sLockFile = [folder URLByAppendingPathComponent:@"keychain.lock"];
      break;
    }
    os_log(sLog, "[spotifyglass] keychain: %{public}@ keeps the shared group's items %{public}@", NSBundle.mainBundle.bundleIdentifier,
           sFile ? sFile.path : @"nowhere (no App Group), so the real keychain answers");
  });
}

#pragma mark - which calls are ours

static BOOL EntitlementCovers(NSString *group) {
  for (NSString *entitled in sKeychainGroups) {
    if (![entitled isKindOfClass:NSString.class]) continue;
    if ([entitled isEqualToString:group] || [entitled isEqualToString:@"*"]) return YES;
    if ([entitled hasSuffix:@"*"] && [group hasPrefix:[entitled substringToIndex:entitled.length - 1]]) return YES;
  }
  return NO;
}

// Whether this process reaches the shared group in the real keychain: an entitlement naming it, or a wildcard.
static BOOL EntitledToCredentialsGroup(void) {
  for (NSString *entitled in sKeychainGroups) {
    if ([entitled isKindOfClass:NSString.class] && ([entitled hasSuffix:kCredentialsSuffix] || [entitled hasSuffix:@"*"])) return YES;
  }
  return NO;
}

static NSString *Key(CFStringRef key) { return (__bridge NSString *)key; }

static BOOL IsPasswordClass(id cls) {
  return [cls isEqual:Key(kSecClassGenericPassword)] || [cls isEqual:Key(kSecClassInternetPassword)];
}

static BOOL IsTrue(id value) {
  return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

// A query or an item that names the shared group, which this process cannot reach in the real keychain, as
// a dictionary; nil to let the real keychain have it.
static NSDictionary *OurDictionary(CFDictionaryRef dictionary) {
  SetUp();
  if (!dictionary || !sFile || CFGetTypeID(dictionary) != CFDictionaryGetTypeID()) return nil;
  NSDictionary *dict = (__bridge NSDictionary *)dictionary;
  NSString *group = dict[Key(kSecAttrAccessGroup)];
  if (![group isKindOfClass:NSString.class] || ![group hasSuffix:kCredentialsSuffix] || EntitlementCovers(group)) return nil;
  return IsPasswordClass(dict[Key(kSecClass)]) ? dict : nil;
}

#pragma mark - the file

// Reads, changes and writes the items while holding a lock every process shares. `change` gets the items and
// says whether to write them back.
static void WithItems(BOOL (^change)(NSMutableArray<NSMutableDictionary *> *items)) {
  @synchronized (sGuard) {
    int lock = open(sLockFile.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (lock >= 0) flock(lock, LOCK_EX);
    NSData *data = [NSData dataWithContentsOfURL:sFile];
    id stored = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:NULL] : nil;
    NSMutableArray<NSMutableDictionary *> *items = [NSMutableArray array];
    if ([stored isKindOfClass:NSArray.class]) {
      for (id item in stored) if ([item isKindOfClass:NSMutableDictionary.class]) [items addObject:item];
    }
    if (change(items)) {
      NSData *out = [NSPropertyListSerialization dataWithPropertyList:items format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
      NSError *error = nil;
      if (!out || ![out writeToURL:sFile options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&error]) {
        os_log_error(sLog, "[spotifyglass] keychain: could not write the items: %{public}@", error);
      }
    }
    if (lock >= 0) {
      flock(lock, LOCK_UN);
      close(lock);
    }
  }
}

#pragma mark - matching

// What a query says about the call and not about the item.
static BOOL IsControl(NSString *key) {
  static NSSet<NSString *> *controls;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    controls = [NSSet setWithObjects:Key(kSecClass), Key(kSecAttrAccessGroup), Key(kSecMatchLimit), Key(kSecReturnData),
                Key(kSecReturnAttributes), Key(kSecReturnRef), Key(kSecReturnPersistentRef), Key(kSecUseAuthenticationUI),
                Key(kSecUseDataProtectionKeychain), nil];
  });
  return [controls containsObject:key] || [key hasPrefix:@"m_"] || [key hasPrefix:@"r_"] || [key hasPrefix:@"u_"];
}

static BOOL ItemMatches(NSDictionary *item, NSDictionary *query) {
  if (![item[Key(kSecClass)] isEqual:query[Key(kSecClass)]]) return NO;
  NSString *synchronizable = Key(kSecAttrSynchronizable);
  for (NSString *key in query) {
    if (![key isKindOfClass:NSString.class] || IsControl(key)) continue;
    id want = query[key], have = item[key];
    if ([key isEqualToString:synchronizable]) {
      if (CFEqual((__bridge CFTypeRef)want, kSecAttrSynchronizableAny)) continue;
      have = have ?: @NO;
    }
    if (!have || ![have isEqual:want]) return NO;
  }
  return YES;
}

// The attributes two items of a class cannot share.
static NSArray<NSString *> *UniqueKeys(id cls) {
  if ([cls isEqual:Key(kSecClassInternetPassword)]) {
    return @[Key(kSecAttrServer), Key(kSecAttrPort), Key(kSecAttrProtocol), Key(kSecAttrPath), Key(kSecAttrAccount),
             Key(kSecAttrAuthenticationType), Key(kSecAttrSecurityDomain), Key(kSecAttrSynchronizable)];
  }
  return @[Key(kSecAttrService), Key(kSecAttrAccount), Key(kSecAttrSynchronizable)];
}

static BOOL ItemsCollide(NSDictionary *a, NSDictionary *b) {
  if (![a[Key(kSecClass)] isEqual:b[Key(kSecClass)]]) return NO;
  for (NSString *key in UniqueKeys(a[Key(kSecClass)])) {
    id x = a[key], y = b[key];
    if ([key isEqualToString:Key(kSecAttrSynchronizable)]) {
      x = x ?: @NO;
      y = y ?: @NO;
    }
    if (x != y && ![x isEqual:y]) return NO;
  }
  return YES;
}

// What the caller asked to get back, of `matches`: the data, the attributes (and data with them when both are
// asked for), one or all; nil when it asked for nothing.
static id ResultFor(NSArray<NSDictionary *> *matches, NSDictionary *query) {
  BOOL data = IsTrue(query[Key(kSecReturnData)]), attributes = IsTrue(query[Key(kSecReturnAttributes)]);
  if (!data && !attributes) return nil;
  BOOL all = [query[Key(kSecMatchLimit)] isEqual:(__bridge id)kSecMatchLimitAll];
  NSMutableArray *out = [NSMutableArray array];
  for (NSDictionary *item in matches) {
    if (attributes) {
      NSMutableDictionary *copy = [item mutableCopy];
      if (!data) [copy removeObjectForKey:Key(kSecValueData)];
      [out addObject:copy];
    } else {
      [out addObject:item[Key(kSecValueData)] ?: NSData.data];
    }
    if (!all) break;
  }
  return all ? out : out.firstObject;
}

static OSStatus Deliver(id result, CFTypeRef *out) {
  if (out && result) *out = CFBridgingRetain(result);
  return errSecSuccess;
}

#pragma mark - the four calls

static BOOL PlistSafe(id value) {
  return value && [NSPropertyListSerialization propertyList:@[value] isValidForFormat:NSPropertyListBinaryFormat_v1_0];
}

static OSStatus OurAdd(NSDictionary *attributes, CFTypeRef *result) {
  NSMutableDictionary *item = [NSMutableDictionary dictionary];
  for (NSString *key in attributes) {
    if (![key isKindOfClass:NSString.class] || [key hasPrefix:@"m_"] || [key hasPrefix:@"r_"] || [key hasPrefix:@"u_"]) continue;
    if ([key isEqualToString:Key(kSecUseDataProtectionKeychain)] || [key isEqualToString:Key(kSecUseAuthenticationUI)]) continue;
    if (PlistSafe(attributes[key])) item[key] = attributes[key];
  }
  NSDate *now = [NSDate date];
  item[Key(kSecAttrCreationDate)] = now;
  item[Key(kSecAttrModificationDate)] = now;
  __block OSStatus status = errSecSuccess;
  WithItems(^BOOL(NSMutableArray<NSMutableDictionary *> *items) {
    for (NSDictionary *existing in items) {
      if (ItemsCollide(existing, item)) {
        status = errSecDuplicateItem;
        return NO;
      }
    }
    [items addObject:item];
    return YES;
  });
  if (status != errSecSuccess) return status;
  return Deliver(ResultFor(@[item], attributes), result);
}

// `anyGroup`: a query that names no group, answered from the file only after the real keychain had nothing.
static OSStatus OurCopy(NSDictionary *query, CFTypeRef *result) {
  __block NSArray<NSDictionary *> *found = @[];
  WithItems(^BOOL(NSMutableArray<NSMutableDictionary *> *items) {
    NSMutableArray *matches = [NSMutableArray array];
    BOOL all = [query[Key(kSecMatchLimit)] isEqual:(__bridge id)kSecMatchLimitAll];
    for (NSDictionary *item in items) {
      if (!ItemMatches(item, query)) continue;
      [matches addObject:item];
      if (!all) break;
    }
    found = matches;
    return NO;
  });
  if (!found.count) return errSecItemNotFound;
  return Deliver(ResultFor(found, query), result);
}

static OSStatus OurUpdate(NSDictionary *query, NSDictionary *changes) {
  __block NSUInteger updated = 0;
  WithItems(^BOOL(NSMutableArray<NSMutableDictionary *> *items) {
    for (NSMutableDictionary *item in items) {
      if (!ItemMatches(item, query)) continue;
      for (NSString *key in changes) {
        if (![key isKindOfClass:NSString.class] || IsControl(key)) continue;
        if (PlistSafe(changes[key])) item[key] = changes[key];
      }
      item[Key(kSecAttrModificationDate)] = [NSDate date];
      updated++;
    }
    return updated > 0;
  });
  return updated ? errSecSuccess : errSecItemNotFound;
}

static OSStatus OurDelete(NSDictionary *query) {
  __block NSUInteger removed = 0;
  WithItems(^BOOL(NSMutableArray<NSMutableDictionary *> *items) {
    for (NSInteger i = (NSInteger)items.count - 1; i >= 0; i--) {
      if (!ItemMatches(items[(NSUInteger)i], query)) continue;
      [items removeObjectAtIndex:(NSUInteger)i];
      removed++;
    }
    return removed > 0;
  });
  return removed ? errSecSuccess : errSecItemNotFound;
}

static void Log(const char *call, NSDictionary *query, OSStatus status, BOOL fallback) {
  os_log(sLog, "[spotifyglass] keychain: %{public}s %{public}@ -> %d%{public}s", call,
         query[Key(kSecAttrService)] ?: query[Key(kSecAttrServer)] ?: @"(no service)", (int)status, fallback ? " (from the file, not the keychain)" : "");
}

static OSStatus SGSecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
  NSDictionary *ours = OurDictionary(attributes);
  if (!ours) return SecItemAdd(attributes, result);
  OSStatus status = OurAdd(ours, result);
  Log("add", ours, status, NO);
  return status;
}

static OSStatus SGSecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
  NSDictionary *ours = OurDictionary(query);
  if (ours) {
    OSStatus status = OurCopy(ours, result);
    Log("copy", ours, status, NO);
    return status;
  }
  OSStatus status = SecItemCopyMatching(query, result);
  // A query that names no group, in a process that cannot see Spotify's: the file may have what it means.
  if ((status == errSecItemNotFound || status == errSecMissingEntitlement) && query && sFile
      && CFGetTypeID(query) == CFDictionaryGetTypeID()) {
    NSDictionary *dict = (__bridge NSDictionary *)query;
    if (!dict[Key(kSecAttrAccessGroup)] && IsPasswordClass(dict[Key(kSecClass)]) && !EntitledToCredentialsGroup()) {
      OSStatus fromFile = OurCopy(dict, result);
      if (fromFile == errSecSuccess) {
        Log("copy", dict, fromFile, YES);
        return fromFile;
      }
    }
  }
  return status;
}

static OSStatus SGSecItemUpdate(CFDictionaryRef query, CFDictionaryRef changes) {
  NSDictionary *ours = OurDictionary(query);
  if (!ours || !changes || CFGetTypeID(changes) != CFDictionaryGetTypeID()) return SecItemUpdate(query, changes);
  OSStatus status = OurUpdate(ours, (__bridge NSDictionary *)changes);
  Log("update", ours, status, NO);
  return status;
}

static OSStatus SGSecItemDelete(CFDictionaryRef query) {
  NSDictionary *ours = OurDictionary(query);
  if (!ours) return SecItemDelete(query);
  OSStatus status = OurDelete(ours);
  Log("delete", ours, status, NO);
  return status;
}

// dyld puts each replacement where its original was imported, in every image, ahead of any code of Spotify's.
#define SG_INTERPOSE(replacement, replacee) \
  __attribute__((used)) static const struct { const void *new_; const void *old_; } sg_interpose_##replacee \
  __attribute__((section("__DATA,__interpose"))) = {(const void *)(unsigned long)&replacement, (const void *)(unsigned long)&replacee}

SG_INTERPOSE(SGSecItemAdd, SecItemAdd);
SG_INTERPOSE(SGSecItemCopyMatching, SecItemCopyMatching);
SG_INTERPOSE(SGSecItemUpdate, SecItemUpdate);
SG_INTERPOSE(SGSecItemDelete, SecItemDelete);
