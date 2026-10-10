import AppKit
import Combine
@preconcurrency import UserNotifications
import TabbiKitCore
import TabbiKit

/// The daily study reminder ("Mochi misses you. 10 minutes?"): saves the
/// user's choice and keeps one pending system notification at the moment
/// `StudyReminderSave.plan` picks. It plans again whenever study, the day's
/// goal, the pet's name, the day, the time zone or the settings change, so a day the user
/// already studied gets no reminder, and none gets two.
///
/// Off by default. Notification permission is asked only when the user
/// turns it on. The banner uses the default interruption level, so Focus
/// modes silence it like any other app's. The pending request stays when
/// the module stops (as when Tabbi quits), since the system delivers it
/// without Tabbi running. Demo and snapshot runs, and a bare `swift run`
/// (where `UNUserNotificationCenter` aborts), post and save nothing.
/// What the reminder needs from the system's notification center, so tests
/// can stand in for `UNUserNotificationCenter` (which aborts outside an
/// `.app` bundle) and see what would be posted.
@MainActor
protocol StudyReminderNotifying: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async
    func withdraw(id: String)
    func schedule(_ request: UNNotificationRequest)
}

extension UNUserNotificationCenter: StudyReminderNotifying {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        _ = try? await requestAuthorization(options: [.alert, .sound])
    }

    func withdraw(id: String) {
        removePendingNotificationRequests(withIdentifiers: [id])
    }

    func schedule(_ request: UNNotificationRequest) {
        add(request, withCompletionHandler: nil)
    }
}

@MainActor
final class StudyReminderScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let requestID = "streaks.studyReminder"

    @Published private(set) var save: StudyReminderSave
    /// The user turned the reminder on but macOS has Tabbi's notifications off.
    @Published private(set) var isBlocked = false

    private let pet: ClosetStore
    private let center: (any StudyReminderNotifying)?
    private let clock: () -> Date
    private let saveURL: URL?
    /// Set when the file could not be read: run on defaults, never overwrite.
    private let saveIsUnreadable: Bool
    /// The day's study goal is met (`StudyReminder.goalMet(in:)`).
    @Published private var goalMet = false
    private var observers: Set<AnyCancellable> = []
    private lazy var alarm = WallClockAlarm { [weak self] in self?.replan() }

    init(storage: EditionStorage, runMode: RunMode, pet: ClosetStore,
         progress: AnyPublisher<[ProgressItem], Never>,
         notifications: (any StudyReminderNotifying)? = StudyReminderScheduler.systemCenter(),
         clock: @escaping () -> Date = Date.init) {
        self.pet = pet
        self.clock = clock
        let isLive = !runMode.isEphemeral
        center = isLive ? notifications : nil
        saveURL = isLive ? Self.saveURL(in: storage) : nil
        var unreadable = false
        var save = StudyReminderSave()
        // A realistic Settings pane in demo: the reminder on at 7 pm.
        if runMode.isDemo { save.settings.isEnabled = true }
        if let saveURL {
            do {
                save = try StudyReminderSave.load(from: saveURL) ?? save
            } catch {
                unreadable = true
            }
        }
        self.save = save
        saveIsUnreadable = unreadable
        super.init()
        if let system = center as? UNUserNotificationCenter, system.delegate == nil { system.delegate = self }
        progress.map(StudyReminder.goalMet(in:)).removeDuplicates().assign(to: &$goalMet)
    }

    /// The system's notification center, or nil in a bare `swift run`.
    static func systemCenter() -> UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
    }

    /// `~/Library/Application Support/<edition>/Pet/reminder.json`.
    static func saveURL(in storage: EditionStorage) -> URL {
        storage.file("reminder.json", in: "Pet")
    }

    /// Plans now and again on every change that can move the reminder.
    func start() {
        guard center != nil else { return }
        let changes = NotificationCenter.default
        let wake = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        Publishers.MergeMany(
            pet.$milestones.map { _ in () }.eraseToAnyPublisher(),
            pet.profiles.map { _ in () }.eraseToAnyPublisher(),
            changes.publisher(for: .NSCalendarDayChanged).map { _ in () }.eraseToAnyPublisher(),
            changes.publisher(for: .NSSystemTimeZoneDidChange).map { _ in () }.eraseToAnyPublisher(),
            wake.map { _ in () }.eraseToAnyPublisher(),
            $save.map(\.settings).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $goalMet.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        )
        // Starting (and one study record) emits several of these at once.
        .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
        .sink { [weak self] _ in MainActor.assumeIsolated { self?.replan() } }
        .store(in: &observers)
        refreshPermission()
    }

    /// Stops following changes; the pending reminder stays (see the type's notes).
    func stop() {
        observers.removeAll()
        alarm.cancel()
    }

    // MARK: Settings

    var isEnabled: Bool { save.settings.isEnabled }

    /// Whose voice the reminder speaks in.
    var petName: String { StudyReminder.speaker(for: pet.profile) }

    /// Turns the reminder on or off. Turning it on asks for notification
    /// permission if the user hasn't decided yet.
    func setEnabled(_ on: Bool) {
        save.settings.isEnabled = on
        persist()
        guard on, let center else {
            isBlocked = false
            return
        }
        Task { [weak self] in
            if await center.authorizationStatus() == .notDetermined {
                await center.requestAuthorization()
                self?.replan()
            }
            self?.refreshPermission()
        }
    }

    /// The reminder's time today, for a time picker.
    var time: Date {
        get {
            Calendar.current.date(bySettingHour: save.settings.hour, minute: save.settings.minute,
                                  second: 0, of: clock()) ?? clock()
        }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            save.settings.minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            persist()
        }
    }

    /// Opens System Settings at Notifications, where a blocked reminder is fixed.
    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Planning

    private func refreshPermission() {
        guard let center else { return }
        Task { [weak self] in
            let denied = await center.authorizationStatus() == .denied
            guard let self else { return }
            isBlocked = denied && isEnabled
        }
    }

    /// Withdraws the pending reminder and sets the next one, if any.
    private func replan() {
        guard let center else { return }
        let now = clock()
        let streak = pet.streak
        let before = save
        let fire = save.plan(now: now, studiedToday: streak.studiedToday, goalMetToday: goalMet)
        if save != before { persist() }
        center.withdraw(id: Self.requestID)
        guard let fire else {
            alarm.cancel()
            return
        }
        // The streak the reminder protects is the one still running on that day.
        let message = StudyReminder.message(petName: petName, streakLength: streak.length)
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.schedule(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger))
        // Plan the following day once this one has fired.
        alarm.schedule(at: fire.addingTimeInterval(1), tolerance: 30)
    }

    private func persist() {
        guard let saveURL, !saveIsUnreadable else { return }
        try? save.write(to: saveURL)
    }

    /// Tabbi is always "frontmost" as an accessory app, so ask for the
    /// banner explicitly or macOS would swallow it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
