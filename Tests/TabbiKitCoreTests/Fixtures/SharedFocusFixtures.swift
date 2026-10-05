import Foundation
import TabbiKitCore

extension FocusTimer {
    /// The timer as Today would share it, for tests that drive followers of
    /// the shared focus clock with a real Pomodoro state machine.
    var shared: ProvidedFocus { provided(by: .planner) }
}
