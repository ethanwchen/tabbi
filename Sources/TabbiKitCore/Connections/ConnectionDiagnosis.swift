import Foundation

/// One question the troubleshooter answers, such as String(localized: "Is Anki open?", bundle: .tabbi), with
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
    public static let notReached = String(localized: "Not checked yet. Fix the step above first.", bundle: .tabbi)
    /// The answer while a check is still running.
    public static let stillChecking = String(localized: "Still checking.", bundle: .tabbi)

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

/// Everything the String(localized: "Something not working?", bundle: .tabbi) troubleshooter shows for one
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
    /// The command line tool the check found (Claude's), so a walkthrough
    /// can offer a line that runs it by its full path. Never shown as is
    /// and never put in the support details, since it names the user's
    /// home folder.
    public var executable: URL?

    public init(kind: ConnectionKind, status: ConnectionStatus, checks: [ConnectionCheck], technical: String,
                executable: URL? = nil) {
        self.kind = kind
        self.status = status
        self.checks = checks
        self.technical = technical
        self.executable = executable
    }

    /// The first check that failed, which is what the row's button fixes.
    public var firstFailure: ConnectionCheck? { checks.first { $0.outcome == .failed } }

    /// The one-line verdict at the top of the troubleshooter.
    public var verdict: String {
        if status.light == .checking {
            return String(localized: "Tabbi is still checking. This takes a second.", bundle: .tabbi)
        }
        if status.isConnected {
            return Sentences.join([String(localized: "Everything checks out.", bundle: .tabbi), status.detail])
        }
        // The headline has no stop of its own; Japanese and Chinese end it with 。.
        return Sentences.join([String(localized: "\(status.headline).", bundle: .tabbi), status.detail])
    }

    /// Plain text for String(localized: "Copy details", bundle: .tabbi): what a user pastes into a message to
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
            checks = ConnectionCheck.chain([(String(localized: "Is Anki on this Mac?", bundle: .tabbi), nil, "")])
        } else {
            let installed = self != .notInstalled
            let open = installed && self != .notRunning
            var addOn: ConnectionCheck.Outcome? = .passed
            var addOnAnswer = String(localized: "Yes, AnkiConnect answers.", bundle: .tabbi)
            switch self {
            case .starting:
                addOn = nil
            case .addOnMissing:
                addOn = .failed
                addOnAnswer = String(localized: "No. Install it, or restart Anki if you just did.", bundle: .tabbi)
            default: break
            }
            var cards: ConnectionCheck.Outcome = .passed
            var cardsAnswer = String(localized: "Yes, Tabbi can count your cards.", bundle: .tabbi)
            if case .problem(let error) = self {
                cards = .failed
                cardsAnswer = switch error {
                case .collectionUnavailable: String(localized: "No. Anki is waiting for you to pick a profile.", bundle: .tabbi)
                case .timeout: String(localized: "No. Anki is busy. A window inside Anki may be open.", bundle: .tabbi)
                default: String(localized: "No. Anki didn't answer this time.", bundle: .tabbi)
                }
            }
            let accessAnswer = self == .needsPermission(.apiKeyRequired)
                ? String(localized: "No. AnkiConnect is set to ask for a key.", bundle: .tabbi)
                : String(localized: "No. Anki turned Tabbi down when it asked.", bundle: .tabbi)
            checks = ConnectionCheck.chain([
                (String(localized: "Is Anki on this Mac?", bundle: .tabbi), installed ? .passed : .failed,
                 installed ? String(localized: "Yes, Anki is installed.", bundle: .tabbi) : String(localized: "No. Anki is a free app from apps.ankiweb.net.", bundle: .tabbi)),
                (String(localized: "Is Anki open?", bundle: .tabbi), open ? .passed : .failed,
                 open ? String(localized: "Yes, Anki is open.", bundle: .tabbi) : String(localized: "No. Tabbi can only see your cards while Anki is open.", bundle: .tabbi)),
                (String(localized: "Is the AnkiConnect add-on on?", bundle: .tabbi), addOn, addOnAnswer),
                (String(localized: "Is AnkiConnect up to date?", bundle: .tabbi), self == .addOnOutdated ? .failed : .passed,
                 self == .addOnOutdated ? String(localized: "No. This copy is too old for Tabbi.", bundle: .tabbi) : String(localized: "Yes.", bundle: .tabbi)),
                (String(localized: "Does Anki let Tabbi in?", bundle: .tabbi), isNeedsPermission ? .failed : .passed,
                 isNeedsPermission ? accessAnswer : String(localized: "Yes.", bundle: .tabbi)),
                (String(localized: "Can Tabbi see your cards?", bundle: .tabbi), cards, cardsAnswer),
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
        case .notDetermined where !canAsk: String(localized: "No. This copy of Tabbi can't ask for it.", bundle: .tabbi)
        case .notDetermined: String(localized: "Not yet. Your Mac hasn't asked you.", bundle: .tabbi)
        case .denied: String(localized: "No. It's turned off in System Settings.", bundle: .tabbi)
        case .restricted: String(localized: "No. A setting on this Mac blocks it.", bundle: .tabbi)
        case .writeOnly: String(localized: "Only partly. Tabbi can add events but can't read them.", bundle: .tabbi)
        case .fullAccess: String(localized: "Yes.", bundle: .tabbi)
        }
        let count = accounts.count
        var checks = ConnectionCheck.chain([
            (String(localized: "Did you let Tabbi see your calendar?", bundle: .tabbi), access == .fullAccess ? .passed : .failed, accessAnswer),
            (String(localized: "Does your Mac have any calendars?", bundle: .tabbi), count > 0 ? .passed : .failed,
             count == 0 ? String(localized: "No. Add your Google or school account in Internet Accounts.", bundle: .tabbi)
                 : String(localized: "Yes, from \(count) accounts.", bundle: .tabbi)),
        ])
        if access == .fullAccess, count > 0 {
            checks.append(hasGoogleAccount
                ? ConnectionCheck(String(localized: "Is a Google calendar on this Mac?", bundle: .tabbi), .passed, String(localized: "Yes.", bundle: .tabbi))
                : ConnectionCheck(String(localized: "Is a Google calendar on this Mac?", bundle: .tabbi), .note,
                                  String(localized: "No. That's fine if you don't use Google. The Calendar row can add it.", bundle: .tabbi)))
        }
        // Account names can be email addresses, so only counts go to support.
        return ConnectionDiagnosis(kind: .calendar, status: connectionStatus, checks: checks,
                                   technical: "calendar.\(access.rawValue)\(canAsk ? "" : ".cannotAsk") accounts=\(count) google=\(hasGoogleAccount)")
    }
}

extension ClaudeConnectionState {
    public var diagnosis: ConnectionDiagnosis { diagnosis(executable: nil) }

    /// The diagnosis, carrying where `claude` was found for the sign-in
    /// walkthrough's line.
    public func diagnosis(executable: URL?) -> ConnectionDiagnosis {
        let installed: ConnectionCheck.Outcome? = switch self {
        case .checking: nil
        case .notInstalled: .failed
        case .signedOut, .ready: .passed
        }
        let checks = ConnectionCheck.chain([
            (String(localized: "Is Claude on this Mac?", bundle: .tabbi), installed,
             installed == .failed ? String(localized: "No. Set it up to use Plan my day and Ask AI with Claude.", bundle: .tabbi) : String(localized: "Yes.", bundle: .tabbi)),
            (String(localized: "Are you signed in to Claude?", bundle: .tabbi), self == .signedOut ? .failed : .passed,
             self == .signedOut ? String(localized: "No. Sign in once and Tabbi can use it.", bundle: .tabbi) : String(localized: "Yes.", bundle: .tabbi)),
        ])
        return ConnectionDiagnosis(kind: .claude, status: connectionStatus, checks: checks,
                                   technical: "claude.\(String(describing: self))",
                                   executable: self == .notInstalled ? nil : executable)
    }
}

extension MusicConnectionState {
    public var diagnosis: ConnectionDiagnosis {
        let name = app.displayName
        let allowed: ConnectionCheck.Outcome
        let answer: String
        switch permission {
        case .granted:
            (allowed, answer) = (.passed, String(localized: "Yes.", bundle: .tabbi))
        case .appClosed where grantedBefore:
            (allowed, answer) = (.passed, String(localized: "Yes, the last time \(name) was open.", bundle: .tabbi))
        case .denied:
            (allowed, answer) = (.failed, String(localized: "No. It's turned off in System Settings.", bundle: .tabbi))
        case .notAsked:
            (allowed, answer) = (.failed, String(localized: "Not yet. Your Mac hasn't asked you.", bundle: .tabbi))
        case .appClosed:
            (allowed, answer) = (.failed, String(localized: "Not yet. Your Mac can only ask while \(name) is open.", bundle: .tabbi))
        }
        let checks = ConnectionCheck.chain([
            (String(localized: "Is \(name) on this Mac?", bundle: .tabbi), isInstalled ? .passed : .failed,
             isInstalled ? String(localized: "Yes, \(name) is installed.", bundle: .tabbi) : String(localized: "No. Get \(name) to control music from the notch.", bundle: .tabbi)),
            (String(localized: "Did you let Tabbi control \(name)?", bundle: .tabbi), allowed, answer),
        ])
        let id = app == .spotify ? "spotify" : "music"
        return ConnectionDiagnosis(kind: app == .spotify ? .spotify : .music, status: connectionStatus, checks: checks,
                                   technical: "\(id).installed=\(isInstalled) permission=\(permission.rawValue) grantedBefore=\(grantedBefore)")
    }
}

extension NotificationAccess {
    public var diagnosis: ConnectionDiagnosis {
        let answer = switch self {
        case .notDetermined: String(localized: "Not yet. Your Mac hasn't asked you.", bundle: .tabbi)
        case .denied: String(localized: "No. They're turned off in System Settings.", bundle: .tabbi)
        case .allowed: String(localized: "Yes.", bundle: .tabbi)
        }
        let checks = [ConnectionCheck(String(localized: "Did you let Tabbi show alerts?", bundle: .tabbi), self == .allowed ? .passed : .failed, answer)]
        return ConnectionDiagnosis(kind: .notifications, status: connectionStatus, checks: checks,
                                   technical: "notifications.\(rawValue)")
    }
}

extension FocusShortcutsState {
    public var diagnosis: ConnectionDiagnosis {
        let checks: [ConnectionCheck]
        if !isTurnedOn {
            checks = [ConnectionCheck(String(localized: "Is Do Not Disturb turned on in Tabbi?", bundle: .tabbi), .failed,
                                      String(localized: "No. Click Turn on, or switch it on in Settings under Focus.", bundle: .tabbi))]
        } else if couldNotList {
            checks = [ConnectionCheck(String(localized: "Can Tabbi see your shortcuts?", bundle: .tabbi), .failed,
                                      String(localized: "No. The Shortcuts app didn't answer. Click Check again.", bundle: .tabbi))]
        } else if let installed {
            // The two shortcuts don't depend on each other, so both are checked.
            checks = [onName, offName].map { name in
                installed.contains(name)
                    ? ConnectionCheck(String(localized: "Is the \u{201C}\(name)\u{201D} shortcut there?", bundle: .tabbi), .passed, String(localized: "Yes.", bundle: .tabbi))
                    : ConnectionCheck(String(localized: "Is the \u{201C}\(name)\u{201D} shortcut there?", bundle: .tabbi), .failed,
                                      String(localized: "No. Make it in Shortcuts with this exact name.", bundle: .tabbi))
            }
        } else {
            checks = ConnectionCheck.chain([(String(localized: "Is the \u{201C}\(onName)\u{201D} shortcut there?", bundle: .tabbi), nil, "")])
        }
        // Says which shortcut is missing without repeating the user's names.
        let technical = !isTurnedOn ? "doNotDisturb.off" : couldNotList ? "doNotDisturb.listFailed" : installed.map { "doNotDisturb.on=\($0.contains(onName)) off=\($0.contains(offName))" }
            ?? "doNotDisturb.checking"
        return ConnectionDiagnosis(kind: .doNotDisturb, status: connectionStatus, checks: checks, technical: technical)
    }
}

extension PartyConnectionState {
    public var diagnosis: ConnectionDiagnosis {
        let online: ConnectionCheck.Outcome? = switch self {
        case .notSetUp, .connected: .passed
        case .ageCheck, .connecting: nil
        case .offline: .failed
        }
        let ageAnswer: (outcome: ConnectionCheck.Outcome, answer: String) = switch self {
        case .ageCheck(nil): (.failed, String(localized: "Not yet. Open the Party tab to answer.", bundle: .tabbi))
        case .ageCheck: (.failed, String(localized: "Party is for people \(PartyAgeCheck.minimumAge) and older.", bundle: .tabbi))
        default: (.passed, String(localized: "Yes.", bundle: .tabbi))
        }
        let checks = ConnectionCheck.chain([
            (String(localized: "Did you answer the age question?", bundle: .tabbi), ageAnswer.outcome, ageAnswer.answer),
            (String(localized: "Did you pick a name?", bundle: .tabbi), self == .notSetUp ? .failed : .passed,
             self == .notSetUp ? String(localized: "Not yet. Pick a name and a pet to start.", bundle: .tabbi) : String(localized: "Yes.", bundle: .tabbi)),
            (String(localized: "Can Tabbi reach Party?", bundle: .tabbi), online,
             online == .failed ? String(localized: "No. Check that your Wi-Fi is on, then try again.", bundle: .tabbi) : String(localized: "Yes.", bundle: .tabbi)),
        ])
        let technical = switch self {
        case .notSetUp: "party.notSetUp"
        case .ageCheck(nil): "party.ageCheck"
        case .ageCheck: "party.tooYoung"
        case .connecting: "party.connecting"
        case .offline: "party.offline"
        case .connected: "party.connected"
        }
        return ConnectionDiagnosis(kind: .party, status: connectionStatus, checks: checks, technical: technical)
    }
}
