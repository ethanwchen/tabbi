import AppKit
import AuthenticationServices
import TabbiKitCore

/// Opens Apple's sign-in page in a web authentication session and waits for
/// the friends server to send it back to `tabbi://auth/apple`. The session
/// catches that link itself, so it never reaches another copy of the app.
///
/// `SyncStore` takes this as a closure, so tests stand in a fake page.
@MainActor
final class AppleWebAuthentication: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// The `tabbi://auth/apple` link the page ended on, or nil when the user
    /// closed it.
    func callback(from url: URL) async throws -> URL? {
        session?.cancel()
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let completion: ASWebAuthenticationSession.CompletionHandler = { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.presentationContextInvalid))
                }
            }
            let session: ASWebAuthenticationSession
            if #available(macOS 14.4, *) {
                session = ASWebAuthenticationSession(url: url, callback: .customScheme(AppleWebSignIn.callbackScheme),
                                                     completionHandler: completion)
            } else {
                session = ASWebAuthenticationSession(url: url, callbackURLScheme: AppleWebSignIn.callbackScheme,
                                                     completionHandler: completion)
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: ASWebAuthenticationSessionError(.presentationContextNotProvided))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor()
        }
    }
}
