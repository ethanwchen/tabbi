import Foundation

/// Where Do Not Disturb stands. macOS lets an app switch Focus only through
/// the user's own shortcuts, so this checks that the two Tabbi runs exist.
public struct FocusShortcutsState: Hashable, Sendable {
    /// The shortcut that turns Do Not Disturb on.
    public var onName: String
    /// The shortcut that turns it off.
    public var offName: String
    /// The names of the user's shortcuts, or nil while they're being listed.
    public var installed: Set<String>?
    /// Listing the shortcuts failed (the tool didn't start or took too
    /// long), so Tabbi can't tell whether the two are there. Without this
    /// a slow Mac would read as "not set up" and send the user into the
    /// walkthrough for shortcuts they already made.
    public var couldNotList: Bool
    /// Whether the user turned on Do Not Disturb during focus. With it off
    /// Tabbi never runs the shortcuts, so the row must not read as working
    /// even when both shortcuts exist.
    public var isTurnedOn: Bool

    public init(onName: String, offName: String, installed: Set<String>?, couldNotList: Bool = false,
                isTurnedOn: Bool = true) {
        self.onName = onName
        self.offName = offName
        self.installed = installed
        self.couldNotList = couldNotList
        self.isTurnedOn = isTurnedOn
    }

    /// Reads `shortcuts list` output: one shortcut name per line.
    public static func parseList(_ output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    /// The shortcuts still to make, on first.
    public var missing: [String] {
        guard !couldNotList, let installed else { return [] }
        return [onName, offName].filter { !installed.contains($0) }
    }

    public var connectionStatus: ConnectionStatus {
        guard isTurnedOn else {
            return ConnectionStatus(light: .notSetUp, headline: "Do Not Disturb is off",
                                    detail: "Tabbi leaves your alerts alone until you turn it on.",
                                    action: .turnOnDoNotDisturb)
        }
        if couldNotList {
            return ConnectionStatus(light: .needsStep, headline: "Couldn't check your shortcuts",
                                    detail: "The Shortcuts app didn't answer in time. Try again in a moment.",
                                    action: .checkAgain)
        }
        guard installed != nil else {
            return ConnectionStatus(light: .checking, headline: "Looking for your shortcuts",
                                    detail: "This takes a second.")
        }
        switch missing.count {
        case 0:
            return ConnectionStatus(light: .connected, headline: "Do Not Disturb is ready",
                                    detail: "Alerts go quiet while you focus.",
                                    suggestion: .testDoNotDisturb)
        case 1:
            return ConnectionStatus(light: .needsStep, headline: "One shortcut left",
                                    detail: "Make \u{201C}\(missing[0])\u{201D} so Tabbi can switch Do Not Disturb both ways.",
                                    action: .showGuide(.focusShortcuts))
        default:
            return ConnectionStatus(light: .notSetUp, headline: "Do Not Disturb isn't set up",
                                    detail: "Make two quick shortcuts in the Shortcuts app. It takes about two minutes.",
                                    action: .showGuide(.focusShortcuts))
        }
    }
}

/// The result of the Do Not Disturb "Test it" button, which runs the on
/// shortcut, waits a moment, then runs the off shortcut. Each outcome is one
/// plain sentence; the shortcuts tool's own wording never reaches the user.
public enum DoNotDisturbTest: Equatable, Sendable {
    /// Which half of the test a result belongs to.
    public enum Step: Hashable, Sendable {
        case on
        case off
    }

    case turningOn
    case turningOff
    case passed
    case failed(Step, name: String, FocusShortcutResult)

    /// Whether the test is still running.
    public var isRunning: Bool {
        self == .turningOn || self == .turningOff
    }

    /// Whether the test is over and something went wrong.
    public var isFailure: Bool {
        if case .failed = self { true } else { false }
    }

    /// A short support label such as `test.off.timedOut`, without the
    /// shortcut's name or the shortcuts tool's own text.
    public var technical: String {
        switch self {
        case .turningOn: "test.turningOn"
        case .turningOff: "test.turningOff"
        case .passed: "test.passed"
        case .failed(let step, _, let result):
            "test.\(step == .on ? "on" : "off")." + {
                switch result {
                case .succeeded: "succeeded"
                case .notFound: "notFound"
                case .unavailable: "unavailable"
                case .timedOut: "timedOut"
                case .failed: "failed"
                }
            }()
        }
    }

    /// One sentence for the row or the walkthrough.
    public var message: String {
        switch self {
        case .turningOn: "Turning Do Not Disturb on..."
        case .turningOff: "It's on. Turning it off again..."
        case .passed: "It works. Do Not Disturb turned on, then off again."
        case .failed(_, let name, let result):
            switch result {
            case .succeeded: "It works."
            case .notFound: "Tabbi can't find \u{201C}\(name)\u{201D}. Check its name in Shortcuts."
            case .unavailable: "This Mac can't run shortcuts for Tabbi. Make sure macOS is up to date."
            case .timedOut: "\u{201C}\(name)\u{201D} took too long. Open it in Shortcuts and run it once yourself."
            case .failed: "\u{201C}\(name)\u{201D} didn't finish. Open it in Shortcuts and run it once to see why."
            }
        }
    }

    /// Every stage and outcome the test can show, for snapshots and tests.
    public static func everyOutcome(onName: String, offName: String) -> [DoNotDisturbTest] {
        [.turningOn, .turningOff, .passed,
         .failed(.on, name: onName, .notFound(name: onName)),
         .failed(.off, name: offName, .timedOut),
         .failed(.on, name: onName, .failed(message: "Couldn't communicate with a helper application.")),
         .failed(.on, name: onName, .unavailable)]
    }

    /// Runs the test with `run`, reporting each stage to `update`. Stops at
    /// the first shortcut that fails; returns the final result.
    @discardableResult
    public static func run(onName: String, offName: String, pause: Duration = .seconds(2),
                           run: @Sendable (String) async -> FocusShortcutResult,
                           update: @Sendable (DoNotDisturbTest) async -> Void) async -> DoNotDisturbTest {
        await update(.turningOn)
        let on = await run(onName)
        guard on.succeeded else {
            let result = DoNotDisturbTest.failed(.on, name: onName, on)
            await update(result)
            return result
        }
        await update(.turningOff)
        try? await Task.sleep(for: pause)
        let off = await run(offName)
        let result = off.succeeded ? DoNotDisturbTest.passed : .failed(.off, name: offName, off)
        await update(result)
        return result
    }
}
