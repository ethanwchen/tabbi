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
    /// Where Claude's native installer puts `claude`. A fresh Terminal
    /// window often lacks that folder on its PATH (the installer only
    /// prints a hint), so the lines Tabbi offers name the file itself.
    public static let installedExecutable = "~/.local/bin/claude"
    /// The arguments that sign in. They open a sign-in page in the
    /// browser, so Tabbi never sees the password.
    public static let signInArguments = ["auth", "login"]
    /// The one line offered to copy for a first setup: the official Mac
    /// installer from the setup page, then the sign-in, run by the path the
    /// installer just wrote so it works before PATH knows about it. `&&`
    /// skips the sign-in when the install fails.
    public static let installCommand =
        "curl -fsSL https://claude.ai/install.sh | bash && \(installedExecutable) \(signInArguments.joined(separator: " "))"

    /// The sign-in line offered to copy. It runs the `claude` Tabbi found
    /// by its full path, since a Terminal window may not find it by name,
    /// and falls back to the plain command only when no path is known.
    public static func signInCommand(executable: URL?) -> String {
        guard let executable else { return (["claude"] + signInArguments).joined(separator: " ") }
        return ShellCommandLine.running(executable, arguments: signInArguments)
    }
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
            return ConnectionStatus(light: .checking, headline: String(localized: "Looking for Claude", bundle: .tabbi),
                                    detail: String(localized: "This takes a second.", bundle: .tabbi))
        case .notInstalled:
            return ConnectionStatus(light: .notInstalled, headline: String(localized: "Claude is optional", bundle: .tabbi),
                                    detail: String(localized: "It's an AI helper that can plan your day and answer questions. Everything else works without it.", bundle: .tabbi),
                                    action: .showGuide(.claudeInstall))
        case .signedOut:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Sign in to Claude", bundle: .tabbi),
                                    detail: String(localized: "Claude is installed. Sign in once and Tabbi can use it.", bundle: .tabbi),
                                    action: .showGuide(.claudeSignIn))
        case .ready:
            return ConnectionStatus(light: .connected, headline: String(localized: "Claude is ready", bundle: .tabbi),
                                    detail: String(localized: "Plan my day and Ask AI can use it.", bundle: .tabbi))
        }
    }
}
