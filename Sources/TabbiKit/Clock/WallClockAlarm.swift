import AppKit
import Combine

/// A one-shot timer for a moment on the wall clock.
///
/// A plain `Timer` counts only the time the Mac is awake, so one armed
/// before the lid closes fires late by however long the Mac slept: a focus
/// phase that ended during sleep would sit at 0:00 in the notch for the rest
/// of its old countdown. This alarm re-arms itself when the Mac wakes, so it
/// fires right away if its moment passed during sleep and on time otherwise.
@MainActor
public final class WallClockAlarm {
    private let action: @MainActor () -> Void
    private var timer: Timer?
    private var fireDate: Date?
    private var tolerance: TimeInterval = 0
    private var wakeObserver: AnyCancellable?

    /// - Parameter action: runs on the main actor when the alarm goes off.
    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
        wakeObserver = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.arm() } }
    }

    /// The moment the alarm goes off, or nil when it is not set.
    public var date: Date? { fireDate }

    /// Sets the alarm for `date`, replacing any earlier one. A date in the
    /// past goes off on the next run loop pass.
    public func schedule(at date: Date, tolerance: TimeInterval = 0) {
        fireDate = date
        self.tolerance = tolerance
        arm()
    }

    /// Turns the alarm off.
    public func cancel() {
        fireDate = nil
        timer?.invalidate()
        timer = nil
    }

    /// (Re)creates the run loop timer, which converts the date into awake time
    /// as of now.
    private func arm() {
        timer?.invalidate()
        timer = nil
        guard let fireDate else { return }
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() {
        fireDate = nil
        timer = nil
        action()
    }
}
