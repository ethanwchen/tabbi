import Foundation
import TabbiKitCore

extension FocusTimer {
    /// The timer as Today would share it, for tests that drive followers of
    /// the shared focus clock with a real Pomodoro state machine.
    var shared: ProvidedFocus { provided(by: .planner) }

    /// The same clock from an engine that logs nothing when a focus phase is
    /// cut short (such as Party's), which the pet pays from the clock alone.
    var unlogged: ProvidedFocus {
        var focus = shared
        focus.logsEarlyEnds = false
        return focus
    }
}
