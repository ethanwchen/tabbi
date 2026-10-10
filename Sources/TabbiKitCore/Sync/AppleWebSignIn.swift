import CryptoKit
import Foundation

/// One Sign in with Apple attempt on the web, for builds that cannot use
/// AuthenticationServices' native sign-in (the Developer ID build, whose
/// provisioning profile lacks the entitlement, and later Windows).
///
/// 1. Make one with `AppleWebSignIn()`, keep it, and open `authorizeURL`
///    (Apple's page, with the Services ID, the `state` and its `nonce`).
/// 2. Apple posts the result to the friends server's callback, which
///    checks it and sends the browser to `tabbi://auth/apple?code=...`
///    (read with `Callback(url:)`).
/// 3. Hand the code and this attempt's `state` to
///    `SyncClient.exchangeWebSignIn(code:state:)`. The server takes a code
///    once, for two minutes, and only with its state, so a code that leaks
///    from the link is useless on its own.
///
/// The server side is `backend/src/webauth.ts`; `docs/sync.md` has the setup.
public struct AppleWebSignIn: Hashable, Sendable {
    /// Apple's authorize endpoint.
    public static let authorizeEndpoint = URL(string: "https://appleid.apple.com/auth/authorize")!
    /// The Services ID registered for web sign-in. The server reads the same
    /// value from its `APPLE_SERVICES_ID` variable.
    public static let servicesID = "dev.tabbi.Tabbi.signin"
    /// Where Apple posts the result, on the friends server.
    public static let callbackPath = "/v1/auth/apple/web/callback"
    /// The scheme the callback answers with (`tabbi://auth/apple`), which
    /// the web authentication session waits for.
    public static let callbackScheme = PartyInvite.scheme
    static let callbackHost = "auth"
    static let callbackPathComponent = "apple"

    /// A random value only this Mac knows: 32 bytes, base64url (43
    /// characters). The token exchange needs it, so it never leaves the app
    /// except to Apple and back through the server's own callback.
    public let state: String

    /// A fresh attempt with a new random state.
    public init() {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        self.state = Self.base64URL(Data(bytes))
    }

    /// An attempt with a known state (tests, or a state kept elsewhere).
    public init(state: String) {
        self.state = state
    }

    /// base64url(SHA-256(state)). The server derives the same value to check
    /// the identity token's nonce, so it needs nothing stored before the
    /// callback, and the hash keeps the state itself out of the token.
    public var nonce: String {
        Self.base64URL(Data(SHA256.hash(data: Data(state.utf8))))
    }

    /// Apple's authorize page for this attempt. `server` is the friends
    /// server that receives Apple's form post.
    public func authorizeURL(server: URL = PartyServer.productionURL) -> URL {
        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code id_token"),
            URLQueryItem(name: "response_mode", value: "form_post"),
            URLQueryItem(name: "client_id", value: Self.servicesID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI(server: server).absoluteString),
            URLQueryItem(name: "scope", value: "name"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        return components.url!
    }

    /// The callback on `server`, registered as the Services ID's return URL.
    public static func redirectURI(server: URL = PartyServer.productionURL) -> URL {
        server.appendingPathComponent(String(callbackPath.dropFirst()))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension AppleWebSignIn {
    /// What the server's callback sent back through `tabbi://auth/apple`.
    public enum Callback: Hashable, Sendable {
        /// A one-time code to exchange with this attempt's state.
        case code(String)
        case failure(Failure)

        /// The callback in `url`, or `nil` if `url` is not
        /// `tabbi://auth/apple` with a well-formed `code` or an `error`.
        /// The link can come from anywhere, so a code must look exactly like
        /// the server's (64 lowercase hex characters).
        public init?(url: URL) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.scheme?.lowercased() == AppleWebSignIn.callbackScheme,
                  components.host?.lowercased() == AppleWebSignIn.callbackHost,
                  components.path.split(separator: "/") == [Substring(AppleWebSignIn.callbackPathComponent)]
            else { return nil }
            let items = components.queryItems ?? []
            func value(_ name: String) -> String? {
                let values = items.filter { $0.name == name }
                return values.count == 1 ? values[0].value : nil
            }
            if let code = value("code") {
                guard code.count == 64, code.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
                self = .code(code)
            } else if let error = value("error") {
                self = .failure(Failure(reason: error))
            } else {
                return nil
            }
        }
    }

    /// Why the callback did not sign in, from its `error` value.
    public enum Failure: Hashable, Sendable {
        /// The user closed Apple's page or chose Cancel.
        case cancelled
        /// Something went wrong that trying again may fix: Apple or the
        /// server was unavailable, or too many attempts came at once.
        case unavailable
        /// The server is not set up for web sign-in yet.
        case notConfigured
        /// Apple's answer did not check out (a stale page, a mismatched
        /// state or a refused identity token).
        case rejected

        public init(reason: String) {
            switch reason {
            case "cancelled": self = .cancelled
            case "not_configured": self = .notConfigured
            case "invalid_state", "invalid_identity_token", "apple_error": self = .rejected
            default: self = .unavailable
            }
        }

        /// A short message for the Account row; nil when nothing needs
        /// saying (the user cancelled).
        public var message: String? {
            switch self {
            case .cancelled: return nil
            case .unavailable: return "Sign in with Apple is not available right now. Try again in a moment."
            case .notConfigured: return "Sign in with Apple is not set up on the server yet."
            case .rejected: return "Apple could not confirm the sign-in. Try again."
            }
        }
    }
}
