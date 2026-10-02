import Foundation
import NotchKitCore

/// Which Study state `--snapshot` renders, so every method and the
/// in-notch overlays can be reviewed without clicking:
///
///     NOTCHDECK_DEMO=1 NOTCHDECK_STUDY_SNAPSHOT=info:flowtime \
///         swift run NotchDeck --snapshot snapshots-study --kit medicine
///
/// Values: `method:<kind>` (the timer running that method; without the
/// demo, a fresh session on it), `picker`,
/// `sounds` (the sound mixer), `paused` (the demo Pomodoro paused, so the
/// pet dozes), or `info:<kind>` (that method's info popover over a Pomodoro session). Kinds are
/// `StudyMethodKind` raw values. Ignored outside snapshot runs.
enum StudySnapshotState: Equatable {
    case method(StudyMethodKind)
    case picker
    case sounds
    case paused
    case info(StudyMethodKind)

    static let current: StudySnapshotState? = {
        guard CommandLine.arguments.contains("--snapshot"),
              let value = ProcessInfo.processInfo.environment["NOTCHDECK_STUDY_SNAPSHOT"]
        else { return nil }
        return parse(value)
    }()

    static func parse(_ value: String) -> StudySnapshotState? {
        if value == "picker" { return .picker }
        if value == "sounds" { return .sounds }
        if value == "paused" { return .paused }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = StudyMethodKind(rawValue: parts[1]) else { return nil }
        switch parts[0] {
        case "method": return .method(kind)
        case "info": return .info(kind)
        default: return nil
        }
    }

    /// The method the demo session should run. Info popovers keep the
    /// default, so other methods show their "Use" button.
    var demoMethod: StudyMethodKind? {
        if case .method(let kind) = self { kind } else { nil }
    }
}
