import AppKit
import AuthenticationServices

/// What Apple's native sign-in sheet hands back, as the friends server
/// takes it.
struct AppleNativeCredential: Equatable {
    let identityToken: String
    let authorizationCode: String?
    /// The name Apple shares on the first sign-in, if the user kept it.
    let name: String?
}

/// Runs Apple's native Sign in with Apple sheet (the App Store build, whose
/// profile grants the entitlement) and waits for its answer.
///
/// It drives `ASAuthorizationController` itself rather than through
/// SwiftUI's `SignInWithAppleButton`, so it can make Tabbi the active app
/// and hand the sheet the window the button is in. Tabbi has no Dock icon,
/// so its Settings window can be on screen while another app is active,
/// and Apple's sheet would then have nowhere to appear: the button seemed
/// to do nothing. `SyncStore` takes this as a closure, so tests stand in a
/// fake sheet.
@MainActor
final class AppleNativeSignIn: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<AppleNativeCredential?, any Error>?
    private weak var anchor: NSWindow?

    /// Apple's answer, or nil when the user cancelled the sheet.
    func credential(from window: NSWindow?) async throws -> AppleNativeCredential? {
        finish(.success(nil))
        anchor = window
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // The name greets the user; no email is asked for or kept.
        request.requestedScopes = [.fullName]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleNativeCredential?, any Error>) {
        controller = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        let token = credential?.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        let code = credential?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        let name = credential?.fullName
            .map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            .flatMap { $0.isEmpty ? nil : $0 }
        MainActor.assumeIsolated {
            guard let token else { return finish(.failure(ASAuthorizationError(.invalidResponse))) }
            finish(.success(AppleNativeCredential(identityToken: token, authorizationCode: code, name: name)))
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        // Cancelling is a choice, not an error.
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        MainActor.assumeIsolated {
            finish(cancelled ? .success(nil) : .failure(error))
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            anchor ?? NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor()
        }
    }
}
