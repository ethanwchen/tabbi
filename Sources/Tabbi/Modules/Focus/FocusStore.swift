import AppKit
import Combine
import TabbiKit
import TabbiKitCore
@preconcurrency import UserNotifications

/// The Pomodoro timer, shown as a card in Today and as the Focus tab.
///
/// The store owns the `FocusTimer`, so the countdown keeps going while the
/// notch is closed: time comes from a wall-clock end date, and a single
/// one-shot timer fires at that date to play a soft sound and roll into the
/// next phase. A local notification is scheduled for the same date so the
/// user hears about it even if the app is busy or the Mac just woke. The view
/// only ticks once a second while the panel is visible.
///
/// Notification permission is requested the first time the user starts the
/// timer. In demo mode it shows a running sample session; in demo and
/// snapshot runs it never touches notifications, sounds, or disk.
@MainActor
final class FocusStore: ObservableObject {
    @Published private(set) var timer: FocusTimer {
        didSet { focusMode?.timerChanged(timer) }
    }
    /// The moment the view measures against; advances every second while visible.
    @Published private(set) var now = Date()

    private let isDemo: Bool
    /// Demo or snapshot run: nothing is saved, scheduled, played or logged.
    private let isEphemeral: Bool
    /// Starts and ends focus mode with the focus phases; nil in tests.
    private let focusMode: FocusController?
    private let storage: FocusTimerStorage
    /// Where finished focus stretches and breaks are logged, as the Focus module's.
    private let activity: ActivityLog?
    /// Celebrates a focus session that just finished; nil in tests.
    private let celebrations: CelebrationCenter?
    /// The panels showing the timer right now (Today, Focus). Tracked per
    /// viewer because switching tabs may show the new panel before the old
    /// one disappears.
    private var viewers: Set<FocusViewer> = []
    private var isVisible: Bool { !viewers.isEmpty }
    private var ticker: Timer?
    /// Catches up when the running phase ends, even if the Mac slept through it.
    private lazy var phaseEnd = WallClockAlarm { [weak self] in self?.catchUp() }
    private let notifications: FocusNotifications?

    init(activity: ActivityLog? = nil, focusMode: FocusController? = nil, celebrations: CelebrationCenter? = nil,
         runMode: RunMode, defaults: UserDefaults = .standard) {
        self.activity = activity
        self.celebrations = celebrations
        storage = FocusTimerStorage(defaults: defaults)
        self.focusMode = focusMode
        isDemo = runMode.isDemo
        isEphemeral = runMode.isEphemeral
        if isDemo {
            timer = Self.demoTimer(now: Date())
            notifications = nil
            return
        }
        timer = storage.loadTimer()
        if isEphemeral {
            // A snapshot shows the saved timer as it stands now and leaves it be.
            notifications = nil
            _ = timer.advance(to: Date())
            return
        }
        notifications = FocusNotifications.make()
        // Older builds kept finished focus phases in a log of their own; it is
        // dropped only once the activity log has them on disk.
        if let activity {
            storage.moveSessionLog { activity.record($0.activityRecords(source: FocusModule.descriptor.id)) }
        }
        // A phase may have ended while the app wasn't running; catch up quietly.
        record(timer.advance(to: Date()))
        scheduleSideEffects(withdrawingPending: false)
    }

    var remaining: TimeInterval { timer.remaining(at: now) }
    var progress: Double { timer.progress(at: now) }

    /// Call from a panel's `onAppear` / `onDisappear`; the clock ticks while
    /// any viewer is visible.
    func setVisible(_ visible: Bool, viewer: FocusViewer) {
        let wasVisible = isVisible
        if visible { viewers.insert(viewer) } else { viewers.remove(viewer) }
        guard isVisible != wasVisible else { return }
        catchUp()
        updateTicker()
    }

    func toggleRunning() {
        if timer.isRunning { pause() } else { start() }
    }

    func start() {
        catchUp()
        if !isEphemeral, !timer.isRunning {
            // The phase-end request scheduled below is rejected while permission
            // is still undecided, so schedule it again once the user allows it.
            notifications?.requestAuthorizationIfNeeded { [weak self] in self?.rescheduleNotification() }
        }
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

    /// "Focus on this": links the item and, if nothing is under way yet,
    /// starts a focus session so it's one click from the checklist.
    func focus(on itemID: UUID) {
        link(itemID)
        if timer.runState == .idle, timer.phase == .focus { start() }
    }

    // MARK: Private

    /// Applies `edit`, then saves and reschedules the sound, notification, and ticker.
    private func change(_ edit: (inout FocusTimer) -> Void) {
        var updated = timer
        edit(&updated)
        guard updated != timer else { return }
        timer = updated
        scheduleSideEffects(withdrawingPending: true)
        updateTicker()
    }

    /// Moves `now` forward and applies phase ends that have passed, playing
    /// the sound for one that just happened.
    private func catchUp() {
        now = Date()
        let completions = timer.advance(to: now)
        guard !completions.isEmpty else { return }
        record(completions)
        // Stale ends (the Mac was asleep) already got their notification; stay quiet.
        if !isEphemeral, let last = completions.last, now.timeIntervalSince(last.endedAt) < 60 {
            Self.playChime()
            if last.phase == .focus {
                celebrations?.celebrate(.burst, style: .confetti, accent: FocusModule.descriptor.accentColor,
                                        from: FocusModule.descriptor.id, hasOwnSound: true)
            }
        }
        scheduleSideEffects(withdrawingPending: false)
        updateTicker()
    }

    /// Logs every finished phase in the shared activity log, which the
    /// End-of-Day Review counts focus sessions from.
    private func record(_ completions: [FocusPhaseCompletion]) {
        guard !isEphemeral, !completions.isEmpty else { return }
        activity?.record(completions.map { $0.activityRecord(config: timer.config, source: FocusModule.descriptor.id) })
    }

    /// Saves the timer and arms the phase-end timer and notification. A user
    /// action withdraws the pending banner; a phase that ended on its own keeps
    /// it, since macOS may not have delivered it yet.
    private func scheduleSideEffects(withdrawingPending: Bool) {
        guard !isEphemeral else { return }
        storage.save(timer)

        if withdrawingPending { notifications?.cancelPending() }
        guard let endsAt = timer.endsAt else {
            phaseEnd.cancel()
            return
        }
        notifications?.schedule(phaseEndingAt: endsAt, timer: timer)
        phaseEnd.schedule(at: endsAt, tolerance: 0.2)
    }

    /// Re-adds the pending phase-end notification, e.g. after permission was granted.
    private func rescheduleNotification() {
        guard !isEphemeral, let endsAt = timer.endsAt else { return }
        notifications?.schedule(phaseEndingAt: endsAt, timer: timer)
    }

    /// Ticks once a second, only while the panel is visible and the clock runs.
    private func updateTicker() {
        guard isVisible, timer.isRunning, !isEphemeral else {
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

/// A panel that shows the focus timer.
enum FocusViewer: Hashable {
    case today, focus
}

/// Local notifications for phase ends. Only exists inside a real app bundle:
/// `UNUserNotificationCenter` aborts in a bare `swift run` executable.
@MainActor
private final class FocusNotifications: NSObject, UNUserNotificationCenterDelegate {
    private static let requestPrefix = "planner.focus.phaseEnd"
    private let center: UNUserNotificationCenter
    /// The request for the current phase. Each phase end gets its own ID so
    /// scheduling the next phase never replaces a banner that is about to show.
    private var pendingID: String?

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

    /// Asks for permission if the user hasn't decided yet, and calls
    /// `onGranted` on the main actor when they allow it.
    func requestAuthorizationIfNeeded(onGranted: @escaping @MainActor @Sendable () -> Void) {
        let center = center
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                Task { @MainActor in onGranted() }
            }
        }
    }

    /// Schedules the banner for the running phase's end.
    /// It's silent because the app plays its own softer chime.
    func schedule(phaseEndingAt endsAt: Date, timer: FocusTimer) {
        let (title, body) = FocusTimerFormat.completionMessage(
            FocusPhaseCompletion(phase: timer.phase, endedAt: endsAt), config: timer.config)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let interval = max(endsAt.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let id = "\(Self.requestPrefix).\(Int64(endsAt.timeIntervalSinceReferenceDate * 1000))"
        pendingID = id
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Withdraws the current phase's banner, e.g. after pause, reset, or skip.
    func cancelPending() {
        guard let id = pendingID else { return }
        pendingID = nil
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Tabbi is always "frontmost" as an accessory app, so ask for the
    /// banner explicitly or macOS would swallow it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
