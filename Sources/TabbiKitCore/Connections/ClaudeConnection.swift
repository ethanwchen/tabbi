import Foundation

/// Whether the user is signed in to Claude, read from
/// `claude auth status --json`. Tabbi only looks at the yes/no answer; it
/// never reads or keeps the account details the command also prints.
public enum ClaudeSignIn: Hashable, Sendable {
    case signedIn
    case signedOut
    /// The probe gave no answer we understand (an older Claude without the
    /// command, say). Treated as signed in: Claude itself explains if not.
    case unknown

    /// Reads the probe's output. Only the `loggedIn` field counts.
    public static func parse(authStatusOutput output: String) -> ClaudeSignIn {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [String: Any],
              let loggedIn = object["loggedIn"] as? Bool
        else { return .unknown }
        return loggedIn ? .signedIn : .signedOut
    }
}

/// Where the Claude connection stands, for Plan my day and Ask Claude.
public enum ClaudeConnectionState: Hashable, Sendable {
    case checking
    case notInstalled
    case signedOut
    case ready

    /// The official setup page, for "Show me how".
    public static let installPage = URL(string: "https://code.claude.com/docs/en/setup")!
    /// The one line the setup page gives for a Mac, offered to copy.
    public static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"
    /// The line that signs in, offered to copy. It opens a sign-in page in
    /// the browser, so Tabbi never sees the password.
    public static let signInCommand = "claude auth login"
    /// The arguments of the sign-in probe.
    public static let probeArguments = ["auth", "status", "--json"]

    /// The state for a lookup and probe. `signIn` is nil while the probe runs.
    public static func resolve(isInstalled: Bool, signIn: ClaudeSignIn?) -> ClaudeConnectionState {
        guard isInstalled else { return .notInstalled }
        switch signIn {
        case nil: return .checking
        case .signedOut: return .signedOut
        case .signedIn, .unknown: return .ready
        }
    }

    public var connectionStatus: ConnectionStatus {
        switch self {
        case .checking:
            return ConnectionStatus(light: .checking, headline: "Looking for Claude",
                                    detail: "This takes a second.")
        case .notInstalled:
            return ConnectionStatus(light: .notInstalled, headline: "Claude is optional",
                                    detail: "Claude is an AI helper that can plan your day and answer questions. Everything else works without it.",
                                    action: .showGuide(.claudeInstall))
        case .signedOut:
            return ConnectionStatus(light: .needsStep, headline: "Sign in to Claude",
                                    detail: "Claude is installed. Sign in once and Tabbi can use it.",
                                    action: .showGuide(.claudeSignIn))
        case .ready:
            return ConnectionStatus(light: .connected, headline: "Claude is ready",
                                    detail: "Plan my day and Ask AI can use it.")
        }
    }
}
