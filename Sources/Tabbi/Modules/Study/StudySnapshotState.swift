import Foundation
import TabbiKitCore

/// Which Study state `--snapshot` renders, so every method and the
/// in-notch overlays can be reviewed without clicking:
///
///     TABBI_DEMO=1 TABBI_STUDY_SNAPSHOT=info:flowtime \
///         swift run Tabbi --snapshot snapshots-study --kit medicine
///
/// Values: `method:<kind>` (the timer running that method; without the
/// demo, a fresh session on it), `picker`,
/// `sounds` (the sound mixer), `custom` (the Custom lengths), `paused` (the demo Pomodoro paused, so the
/// pet dozes), or `info:<kind>` (that method's info popover over a Pomodoro session). Kinds are
/// `StudyMethodKind` raw values. Ignored outside snapshot runs.
enum StudySnapshotState: Equatable {
    case method(StudyMethodKind)
    case picker
    case sounds
    case custom
    case paused
    case info(StudyMethodKind)

    static let current: StudySnapshotState? = {
        guard RunMode.current.isSnapshot,
              let value = ProcessInfo.processInfo.environment["TABBI_STUDY_SNAPSHOT"]
        else { return nil }
        return parse(value)
    }()

    static func parse(_ value: String) -> StudySnapshotState? {
        if value == "picker" { return .picker }
        if value == "sounds" { return .sounds }
        if value == "custom" { return .custom }
        if value == "paused" { return .paused }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = StudyMethodKind(rawValue: parts[1]) else { return nil }
        switch parts[0] {
        case "method": return .method(kind)
        case "info": return .info(kind)
        default: return nil
        }
    }

    /// Seconds left in the demo Pomodoro's focus block, from
    /// `TABBI_DEMO_FOCUS_LEFT`, so a recording can start at 4 seconds left
    /// and show the session end on camera. Only read in demo runs (live
    /// demo or snapshot); nil keeps the store's default.
    static let demoFocusLeft: TimeInterval? = {
        guard RunMode.current.isDemo,
              let value = ProcessInfo.processInfo.environment["TABBI_DEMO_FOCUS_LEFT"]
        else { return nil }
        return TimeInterval(value).flatMap { $0 > 0 ? $0 : nil }
    }()

    /// The method the demo session should run. Info popovers keep the
    /// default, so other methods show their "Use" button.
    var demoMethod: StudyMethodKind? {
        if case .method(let kind) = self { kind } else { nil }
    }
}
