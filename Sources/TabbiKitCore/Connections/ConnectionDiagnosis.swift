import Foundation

/// One question the troubleshooter answers, such as "Is Anki open?", with
/// its answer in plain words.
public struct ConnectionCheck: Hashable, Sendable {
    public enum Outcome: String, Hashable, Sendable {
        case passed
        case failed
        /// Not checked, because an earlier check failed or a check is
        /// still running.
        case skipped
        /// Worth knowing but optional (no Google calendar yet, say).
        case note
    }

    /// A yes-or-no question about one piece of the connection.
    public var question: String
    public var outcome: Outcome
    /// The answer, one short sentence.
    public var answer: String

    public init(_ question: String, _ outcome: Outcome, _ answer: String) {
        self.question = question
        self.outcome = outcome
        self.answer = answer
    }

    /// The answer for a check that was never reached.
    public static let notReached = "Not checked yet. Fix the step above first."
    /// The answer while a check is still running.
    public static let stillChecking = "Still checking."

    /// Checks that depend on each other, in order: once one fails, the
    /// rest are skipped, because their answers wouldn't mean anything.
    /// A nil outcome means the check is still running, which also stops
    /// the chain.
    static func chain(_ steps: [(question: String, outcome: Outcome?, answer: String)]) -> [ConnectionCheck] {
        var stopped = false
        return steps.map { step in
            if stopped { return ConnectionCheck(step.question, .skipped, notReached) }
            guard let outcome = step.outcome else {
                stopped = true
                return ConnectionCheck(step.question, .skipped, stillChecking)
            }
            if outcome == .failed { stopped = true }
            return ConnectionCheck(step.question, outcome, step.answer)
        }
    }
}

/// Everything the "Something not working?" troubleshooter shows for one
/// row: the row's status, the checks behind it in plain words, and a
/// short technical label that only goes into the copied support details.
public struct ConnectionDiagnosis: Hashable, Sendable {
    public var kind: ConnectionKind
    public var status: ConnectionStatus
    public var checks: [ConnectionCheck]
    /// A compact name for the exact state, such as `anki.notRunning`, so
    /// support can tell similar-looking cases apart. Never shown in the UI
    /// and never holds personal details (no account names or addresses).
    public var technical: String

    public init(kind: ConnectionKind, status: ConnectionStatus, checks: [ConnectionCheck], technical: String) {
        self.kind = kind
        self.status = status
        self.checks = checks
        self.technical = technical
    }

    /// The first check that failed, which is what the row's button fixes.
    public var firstFailure: ConnectionCheck? { checks.first { $0.outcome == .failed } }

    /// The one-line verdict at the top of the troubleshooter.
    public var verdict: String {
        if status.light == .checking { return "Tabbi is still checking. This takes a second." }
        if status.isConnected { return "Everything checks out. \(status.detail)" }
        return "\(status.headline). \(status.detail)"
    }

    /// Plain text for "Copy details": what a user pastes into a message to
    /// support. It names the app and system versions so nobody has to ask.
    public func details(appVersion: String, systemVersion: String, checkedAt: Date,
                        timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = [
            "Tabbi connection details",
            "Connection: \(kind.title)",
            "Status: \(status.light.title) (\(status.headline))",
            "Checked: \(formatter.string(from: checkedAt))",
            "Tabbi: \(appVersion)",
            "macOS: \(systemVersion)",
            "State: \(technical)",
            "",
        ]
        lines += checks.map { "[\($0.outcome.label)] \($0.question) \($0.answer)" }
        return lines.joined(separator: "\n")
    }
}

extension ConnectionCheck.Outcome {
    /// The tag in copied details.
    var label: String {
        switch self {
        case .passed: "ok"
        case .failed: "problem"
        case .skipped: "skipped"
        case .note: "note"
        }
    }
}

// MARK: - Each connection's checks

extension AnkiConnectionState {
    public var diagnosis: ConnectionDiagnosis {
        let checks: [ConnectionCheck]
        if self == .checking {
            checks = ConnectionCheck.chain([("Is Anki on this Mac?", nil, "")])
        } else {
            let installed = self != .notInstalled
            let open = installed && self != .notRunning
            var addOn: ConnectionCheck.Outcome? = .passed
            var addOnAnswer = "Yes, AnkiConnect answers."
            switch self {
            case .starting:
                addOn = nil
            case .addOnMissing:
                addOn = .failed
                addOnAnswer = "No. Install it, or restart Anki if you just did."
            default: break
            }
            var cards: ConnectionCheck.Outcome = .passed
            var cardsAnswer = "Yes, Tabbi can count your cards."
            if case .problem(let error) = self {
                cards = .failed
                cardsAnswer = switch error {
                case .collectionUnavailable: "No. Anki is waiting for you to pick a profile."
                case .timeout: "No. Anki is busy. A window inside Anki may be open."
                default: "No. Anki didn't answer this time."
                }
            }
            let accessAnswer = self == .needsPermission(.apiKeyRequired)
                ? "No. AnkiConnect is set to ask for a key."
                : "No. Anki turned Tabbi down when it asked."
            checks = ConnectionCheck.chain([
                ("Is Anki on this Mac?", installed ? .passed : .failed,
                 installed ? "Yes, Anki is installed." : "No. Anki is a free app from apps.ankiweb.net."),
                ("Is Anki open?", open ? .passed : .failed,
                 open ? "Yes, Anki is open." : "No. Tabbi can only see your cards while Anki is open."),
                ("Is the AnkiConnect add-on on?", addOn, addOnAnswer),
                ("Is AnkiConnect up to date?", self == .addOnOutdated ? .failed : .passed,
                 self == .addOnOutdated ? "No. This copy is too old for Tabbi." : "Yes."),
                ("Does Anki let Tabbi in?", isNeedsPermission ? .failed : .passed,
                 isNeedsPermission ? accessAnswer : "Yes."),
                ("Can Tabbi see your cards?", cards, cardsAnswer),
            ])
        }
        return ConnectionDiagnosis(kind: .anki, status: connectionStatus, checks: checks,
                                   technical: technicalLabel)
    }

    /// `anki.<state>` plus the error's case for the states that carry one,
    /// such as `anki.problem.timeout`. Leaves out any message text.
    private var technicalLabel: String {
        func caseName(_ value: Any) -> String { String(String(describing: value).prefix { $0 != "(" }) }
        switch self {
        case .needsPermission(let error): return "anki.needsPermission.\(caseName(error))"
        case .problem(let error): return "anki.problem.\(caseName(error))"
        default: return "anki.\(caseName(self))"
        }
    }

    private var isNeedsPermission: Bool {
        if case .needsPermission = self { return true }
        return false
    }
}

extension CalendarConnectionState {
    public var diagnosis: ConnectionDiagnosis {
        let accessAnswer = switch access {
        case .notDetermined: "Not yet. Your Mac hasn't asked you."
        case .denied: "No. It's turned off in System Settings."
        case .restricted: "No. A setting on this Mac blocks it."
        case .writeOnly: "Only partly. Tabbi can add events but can't read them."
        case .fullAccess: "Yes."
        }
        let count = accounts.count
        var checks = ConnectionCheck.chain([
            ("Did you let Tabbi see your calendar?", access == .fullAccess ? .passed : .failed, accessAnswer),
            ("Does your Mac have any calendars?", count > 0 ? .passed : .failed,
             count == 0 ? "No. Add your Google or school account in Internet Accounts."
                 : "Yes, from \(count) \(count == 1 ? "account" : "accounts")."),
        ])
        if access == .fullAccess, count > 0 {
            checks.append(hasGoogleAccount
                ? ConnectionCheck("Is a Google calendar on this Mac?", .passed, "Yes.")
                : ConnectionCheck("Is a Google calendar on this Mac?", .note,
                                  "No. That's fine if you don't use Google. The Calendar row can add it."))
        }
        // Account names can be email addresses, so only counts go to support.
        return ConnectionDiagnosis(kind: .calendar, status: connectionStatus, checks: checks,
                                   technical: "calendar.\(access.rawValue) accounts=\(count) google=\(hasGoogleAccount)")
    }
}

extension ClaudeConnectionState {
    public var diagnosis: ConnectionDiagnosis {
        let installed: ConnectionCheck.Outcome? = switch self {
        case .checking: nil
        case .notInstalled: .failed
        case .signedOut, .ready: .passed
        }
        let checks = ConnectionCheck.chain([
            ("Is Claude on this Mac?", installed,
             installed == .failed ? "No. Set it up to use Plan my day and Ask Claude." : "Yes."),
            ("Are you signed in to Claude?", self == .signedOut ? .failed : .passed,
             self == .signedOut ? "No. Sign in once and Tabbi can use it." : "Yes."),
        ])
        return ConnectionDiagnosis(kind: .claude, status: connectionStatus, checks: checks,
                                   technical: "claude.\(String(describing: self))")
    }
}

extension MusicConnectionState {
    public var diagnosis: ConnectionDiagnosis {
        let name = app.name
        let allowed: ConnectionCheck.Outcome
        let answer: String
        switch permission {
        case .granted:
            (allowed, answer) = (.passed, "Yes.")
        case .appClosed where grantedBefore:
            (allowed, answer) = (.passed, "Yes, the last time \(name) was open.")
        case .denied:
            (allowed, answer) = (.failed, "No. It's turned off in System Settings.")
        case .notAsked:
            (allowed, answer) = (.failed, "Not yet. Your Mac hasn't asked you.")
        case .appClosed:
            (allowed, answer) = (.failed, "Not yet. Your Mac can only ask while \(name) is open.")
        }
        let checks = ConnectionCheck.chain([
            ("Is \(name) on this Mac?", isInstalled ? .passed : .failed,
             isInstalled ? "Yes, \(name) is installed." : "No. Get \(name) to control music from the notch."),
            ("Did you let Tabbi control \(name)?", allowed, answer),
        ])
        let id = app == .spotify ? "spotify" : "music"
        return ConnectionDiagnosis(kind: app == .spotify ? .spotify : .music, status: connectionStatus, checks: checks,
                                   technical: "\(id).installed=\(isInstalled) permission=\(permission.rawValue) grantedBefore=\(grantedBefore)")
    }
}

extension NotificationAccess {
    public var diagnosis: ConnectionDiagnosis {
        let answer = switch self {
        case .notDetermined: "Not yet. Your Mac hasn't asked you."
        case .denied: "No. They're turned off in System Settings."
        case .allowed: "Yes."
        }
        let checks = [ConnectionCheck("Did you let Tabbi show alerts?", self == .allowed ? .passed : .failed, answer)]
        return ConnectionDiagnosis(kind: .notifications, status: connectionStatus, checks: checks,
                                   technical: "notifications.\(rawValue)")
    }
}

extension FocusShortcutsState {
    public var diagnosis: ConnectionDiagnosis {
        let checks: [ConnectionCheck]
        if couldNotList {
            checks = [ConnectionCheck("Can Tabbi see your shortcuts?", .failed,
                                      "No. The Shortcuts app didn't answer. Click Check again.")]
        } else if let installed {
            // The two shortcuts don't depend on each other, so both are checked.
            checks = [onName, offName].map { name in
                installed.contains(name)
                    ? ConnectionCheck("Is the \u{201C}\(name)\u{201D} shortcut there?", .passed, "Yes.")
                    : ConnectionCheck("Is the \u{201C}\(name)\u{201D} shortcut there?", .failed,
                                      "No. Make it in Shortcuts with this exact name.")
            }
        } else {
            checks = ConnectionCheck.chain([("Is the \u{201C}\(onName)\u{201D} shortcut there?", nil, "")])
        }
        // Says which shortcut is missing without repeating the user's names.
        let technical = couldNotList ? "doNotDisturb.listFailed" : installed.map { "doNotDisturb.on=\($0.contains(onName)) off=\($0.contains(offName))" }
            ?? "doNotDisturb.checking"
        return ConnectionDiagnosis(kind: .doNotDisturb, status: connectionStatus, checks: checks, technical: technical)
    }
}

extension PartyConnectionState {
    public var diagnosis: ConnectionDiagnosis {
        let online: ConnectionCheck.Outcome? = switch self {
        case .notSetUp, .connected: .passed
        case .connecting: nil
        case .offline: .failed
        }
        let checks = ConnectionCheck.chain([
            ("Did you pick a name?", self == .notSetUp ? .failed : .passed,
             self == .notSetUp ? "Not yet. Pick a name and a pet to start." : "Yes."),
            ("Can Tabbi reach Party?", online,
             online == .failed ? "No. Check that your Wi-Fi is on, then try again." : "Yes."),
        ])
        let technical = switch self {
        case .notSetUp: "party.notSetUp"
        case .connecting: "party.connecting"
        case .offline: "party.offline"
        case .connected: "party.connected"
        }
        return ConnectionDiagnosis(kind: .party, status: connectionStatus, checks: checks, technical: technical)
    }
}
