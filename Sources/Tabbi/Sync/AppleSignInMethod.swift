import Foundation
import Security

/// How this build signs in with Apple. Only a build whose provisioning
/// profile grants `com.apple.developer.applesignin` (the App Store edition)
/// can use AuthenticationServices' native sheet. Apple leaves the
/// entitlement out of Developer ID profiles, so the direct download, dev
/// and ad-hoc builds sign in on Apple's web page instead
/// (`AppleWebSignIn`, see `docs/sync.md`). Both look the same in Settings.
enum AppleSignInMethod: Equatable {
    case native
    case web

    static let entitlement = "com.apple.developer.applesignin"

    /// Native when this process's own code signature carries the
    /// entitlement, the web otherwise.
    static var current: AppleSignInMethod {
        isEntitled ? .native : .web
    }

    private static var isEntitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
        else { return false }
        return (value as? [String])?.isEmpty == false
    }
}
