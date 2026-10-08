#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>

// Interpose only the test executable's SecItem calls. No real password item is read or written.
static OSStatus readStatus = errSecInteractionNotAllowed;
static OSStatus updateStatus = errSecSuccess;
static OSStatus addStatus = errSecSuccess;
static OSStatus deleteStatus = errSecSuccess;
static int reads = 0;
static int interactiveReads = 0;
static int writes = 0;

void mihomo_test_read_status(OSStatus status) { readStatus = status; }
void mihomo_test_update_status(OSStatus status) { updateStatus = status; }
void mihomo_test_add_status(OSStatus status) { addStatus = status; }
void mihomo_test_delete_status(OSStatus status) { deleteStatus = status; }
int mihomo_test_reads(void) { return reads; }
int mihomo_test_interactive_reads(void) { return interactiveReads; }
int mihomo_test_writes(void) { return writes; }

static OSStatus testCopy(CFDictionaryRef query, CFTypeRef *result) {
    Boolean allowed = false;
    if (SecKeychainGetUserInteractionAllowed(&allowed) != errSecSuccess) return errSecInternalComponent;
    reads++;
    if (allowed) interactiveReads++;
    if (readStatus != errSecSuccess) return readStatus;
    const char *value = "fixture-secret";
    *result = CFDataCreate(NULL, (const UInt8 *)value, 14);
    return errSecSuccess;
}
static OSStatus testUpdate(CFDictionaryRef query, CFDictionaryRef attributes) { writes++; return updateStatus; }
static OSStatus testAdd(CFDictionaryRef attributes, CFTypeRef *result) { writes++; return addStatus; }
static OSStatus testDelete(CFDictionaryRef query) { writes++; return deleteStatus; }

#define INTERPOSE(replacement, original) \
    __attribute__((used)) static const struct { const void *replace; const void *original; } \
    interpose_##original __attribute__((section("__DATA,__interpose"))) = { (const void *)replacement, (const void *)original }
INTERPOSE(testCopy, SecItemCopyMatching);
INTERPOSE(testUpdate, SecItemUpdate);
INTERPOSE(testAdd, SecItemAdd);
INTERPOSE(testDelete, SecItemDelete);
