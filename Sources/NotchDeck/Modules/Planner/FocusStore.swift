import AppKit
import Combine
import NotchDeckCore
@preconcurrency import UserNotifications

/// The Today panel's Pomodoro timer.
///
/// The store owns the `FocusTimer`, so the countdown keeps going while the
/// notch is closed: time comes from a wall-clock end date, and a single
/// one-shot timer fires at that date to play a soft sound and roll into the
/// next phase. A local notification is scheduled for the same date so the
/// user hears about it even if the app is busy or the Mac just woke. The view
/// only ticks once a second while the panel is visible.
///
/// Notification permission is requested the first time the user starts the
/// timer. With `NOTCHDECK_DEMO=1` it shows a running sample session and never
/// touches notifications, sounds, or disk.
@MainActor
final class FocusStore: ObservableObject {
    @Published private(set) var timer: FocusTimer
    /// The moment the view measures against; advances every second while visible.
    @Published private(set) var now = Date()

    private let isDemo: Bool
    private let defaults = UserDefaults.standard
    private var isVisible = false
    private var ticker: Timer?
    private var phaseEndTimer: Timer?
    private let notifications: FocusNotifications?

    private static let timerKey = "planner.focusTimer"

    init() {
        isDemo = ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1"
        if isDemo {
            timer = Self.demoTimer(now: Date())
            notifications = nil
            return
        }
        notifications = FocusNotifications.make()
        timer = defaults.data(forKey: Self.timerKey)
            .flatMap { try? JSONDecoder().decode(FocusTimer.self, from: $0) } ?? FocusTimer()
        // A phase may have ended while the app wasn't running; catch up quietly.
        timer.advance(to: Date())
        scheduleSideEffects()
    }

    var remaining: TimeInterval { timer.remaining(at: now) }
    var progress: Double { timer.progress(at: now) }

    /// Call from the panel's `onAppear` / `onDisappear`.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        catchUp()
        updateTicker()
    }

    func toggleRunning() {
        if timer.isRunning { pause() } else { start() }
    }

    func start() {
        catchUp()
        if !isDemo, !timer.isRunning { notifications?.requestAuthorizationIfNeeded() }
        change { $0.start(at: now) }
    }

    func pause() {
        catchUp()
        change { $0.pause(at: now) }
    }

    func reset() {
        catchUp()
        change { $0.reset() }
    }

    func skip() {
        catchUp()
        change { $0.skip(at: now) }
    }

    /// Links the timer to a checklist item, or clears the link with `nil`.
    func link(_ itemID: UUID?) {
        change { $0.linkedItemID = itemID }
    }

    // MARK: Private

    /// Applies `edit`, then saves and reschedules the sound, notification, and ticker.
    private func change(_ edit: (inout FocusTimer) -> Void) {
        var updated = timer
        edit(&updated)
        guard updated != timer else { return }
        timer = updated
        scheduleSideEffects()
        updateTicker()
    }

    /// Moves `now` forward and applies phase ends that have passed, playing
    /// the sound for one that just happened.
    private func catchUp() {
        now = Date()
        let completions = timer.advance(to: now)
        guard !completions.isEmpty else { return }
        // Stale ends (the Mac was asleep) already got their notification; stay quiet.
        if let last = completions.last, now.timeIntervalSince(last.endedAt) < 60 {
            Self.playChime()
        }
        scheduleSideEffects()
        updateTicker()
    }

    private func scheduleSideEffects() {
        guard !isDemo else { return }
        if let data = try? JSONEncoder().encode(timer) { defaults.set(data, forKey: Self.timerKey) }

        phaseEndTimer?.invalidate()
        phaseEndTimer = nil
        guard let endsAt = timer.endsAt else {
            notifications?.cancel()
            return
        }
        notifications?.schedule(phaseEndingAt: endsAt, timer: timer)
        let fire = Timer(fire: endsAt, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.catchUp() }
        }
        fire.tolerance = 0.2
        RunLoop.main.add(fire, forMode: .common)
        phaseEndTimer = fire
    }

    /// Ticks once a second, only while the panel is visible and the clock runs.
    private func updateTicker() {
        guard isVisible, timer.isRunning, !isDemo else {
            ticker?.invalidate()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.catchUp() }
        }
        tick.tolerance = 0.1
        RunLoop.main.add(tick, forMode: .common)
        ticker = tick
    }

    private static func playChime() {
        guard let sound = NSSound(named: "Glass") else { return }
        sound.volume = 0.5
        sound.play()
    }

    /// A focus block a third of the way through, linked to the sample
    /// checklist's first open item.
    private static func demoTimer(now: Date) -> FocusTimer {
        var timer = FocusTimer(linkedItemID: PlannerDay.sample(on: PlannerDayKey(date: now)).items.first { !$0.isDone }?.id)
        timer.start(at: now.addingTimeInterval(-(10 * 60 + 28)))
        return timer
    }
}

/// Local notifications for phase ends. Only exists inside a real app bundle:
/// `UNUserNotificationCenter` aborts in a bare `swift run` executable.
@MainActor
private final class FocusNotifications: NSObject, UNUserNotificationCenterDelegate {
    private static let requestID = "planner.focus.phaseEnd"
    private let center: UNUserNotificationCenter

    /// Nil outside an `.app` bundle.
    static func make() -> FocusNotifications? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return FocusNotifications(center: .current())
    }

    private init(center: UNUserNotificationCenter) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        let center = center
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Replaces any pending notification with one for the running phase.
    /// It's silent because the app plays its own softer chime.
    func schedule(phaseEndingAt endsAt: Date, timer: FocusTimer) {
        let (title, body) = FocusTimerFormat.completionMessage(
            FocusPhaseCompletion(phase: timer.phase, endedAt: endsAt), config: timer.config)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let interval = max(endsAt.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger))
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
    }

    /// NotchDeck is always "frontmost" as an accessory app, so ask for the
    /// banner explicitly or macOS would swallow it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
