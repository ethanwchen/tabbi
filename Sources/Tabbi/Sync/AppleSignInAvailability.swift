import Foundation
import Security

/// Whether this build may use Sign in with Apple. Only a Developer ID
/// release with the embedded provisioning profile carries the
/// `com.apple.developer.applesignin` entitlement (see `docs/sync.md`);
/// dev, ad-hoc and snapshot builds do not, and Settings says so calmly
/// instead of failing.
enum AppleSignInAvailability {
    static let entitlement = "com.apple.developer.applesignin"

    /// Reads the entitlement from this process's own code signature.
    static var isEntitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
        else { return false }
        return (value as? [String])?.isEmpty == false
    }
}
