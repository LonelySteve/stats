import Foundation
import Security
import Darwin

@main
struct MihomoKeychainTests {
    static func symbol<T>(_ name: String, as type: T.Type) -> T {
        unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)!, to: type)
    }

    static func main() throws {
        let reads = symbol("mihomo_test_reads", as: (@convention(c) () -> Int32).self)
        let interactiveReads = symbol("mihomo_test_interactive_reads", as: (@convention(c) () -> Int32).self)
        let readStatus = symbol("mihomo_test_read_status", as: (@convention(c) (OSStatus) -> Void).self)
        let updateStatus = symbol("mihomo_test_update_status", as: (@convention(c) (OSStatus) -> Void).self)
        let addStatus = symbol("mihomo_test_add_status", as: (@convention(c) (OSStatus) -> Void).self)
        let deleteStatus = symbol("mihomo_test_delete_status", as: (@convention(c) (OSStatus) -> Void).self)
        var previous: DarwinBoolean = false
        precondition(SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess)
        precondition(SecKeychainSetUserInteractionAllowed(true) == errSecSuccess)
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }

        // Background polling cannot ask for authorization or treat denied access as an empty password.
        for _ in 0..<100 {
            do {
                _ = try MihomoKeychain.read()
                preconditionFailure("Denied access must fail")
            } catch let error as MihomoKeychain.AccessError {
                precondition(error.status == errSecInteractionNotAllowed)
            }
        }
        precondition(reads() == 1 && interactiveReads() == 0)
        var restored: DarwinBoolean = false
        precondition(SecKeychainGetUserInteractionAllowed(&restored) == errSecSuccess && restored.boolValue)

        // Cancelling an explicitly requested read must not restart authorization on the next poll.
        readStatus(errSecUserCanceled)
        do {
            _ = try MihomoKeychain.read(allowInteraction: true)
            preconditionFailure("Cancelled authorization must fail")
        } catch let error as MihomoKeychain.AccessError {
            precondition(error.status == errSecUserCanceled)
        }
        for _ in 0..<10 { precondition((try? MihomoKeychain.read()) == nil) }
        precondition(reads() == 2 && interactiveReads() == 1)

        // A user-triggered retry loads the credential once and polling reuses it.
        readStatus(errSecSuccess)
        let authorized = try MihomoKeychain.read(allowInteraction: true)
        precondition(authorized == "fixture-secret")
        for _ in 0..<100 {
            let value = try MihomoKeychain.read()
            precondition(value == authorized)
        }
        precondition(reads() == 3 && interactiveReads() == 2)

        // Failed saves preserve the current credential; successful saves replace it without another read.
        updateStatus(errSecAuthFailed)
        precondition(MihomoKeychain.write("replacement") == errSecAuthFailed)
        let unchanged = try MihomoKeychain.read()
        precondition(unchanged == authorized)
        updateStatus(errSecSuccess)
        precondition(MihomoKeychain.write("replacement") == errSecSuccess)
        let replacement = try MihomoKeychain.read()
        precondition(replacement == "replacement" && reads() == 3)

        updateStatus(errSecItemNotFound)
        addStatus(errSecAuthFailed)
        precondition(MihomoKeychain.write("new-item") == errSecAuthFailed)
        let afterFailedAdd = try MihomoKeychain.read()
        precondition(afterFailedAdd == replacement)
        addStatus(errSecSuccess)
        precondition(MihomoKeychain.write("new-item") == errSecSuccess)
        let added = try MihomoKeychain.read()
        precondition(added == "new-item")

        // Secretless operation is allowed only when no password item exists or the user clears it.
        deleteStatus(errSecItemNotFound)
        precondition(MihomoKeychain.write("") == errSecSuccess)
        let cleared = try MihomoKeychain.read()
        precondition(cleared.isEmpty && reads() == 3)
        readStatus(errSecItemNotFound)
        let missing = try MihomoKeychain.read(allowInteraction: true)
        precondition(missing.isEmpty)
        for _ in 0..<100 {
            let value = try MihomoKeychain.read()
            precondition(value.isEmpty)
        }
        precondition(reads() == 4 && interactiveReads() == 3)
        precondition(SecKeychainGetUserInteractionAllowed(&restored) == errSecSuccess && restored.boolValue)
        print("Mihomo Keychain tests passed: silent polling, cancellation, explicit authorization, credential updates and secretless operation")
    }
}
