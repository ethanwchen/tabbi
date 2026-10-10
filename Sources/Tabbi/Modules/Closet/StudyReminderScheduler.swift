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
@MainActor
final class StudyReminderScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private static let requestID = "streaks.studyReminder"

    @Published private(set) var save: StudyReminderSave
    /// The user turned the reminder on but macOS has Tabbi's notifications off.
    @Published private(set) var isBlocked = false

    private let pet: ClosetStore
    private let center: UNUserNotificationCenter?
    private let saveURL: URL?
    /// Set when the file could not be read: run on defaults, never overwrite.
    private let saveIsUnreadable: Bool
    /// The day's study goal is met (`StudyReminder.goalMet(in:)`).
    @Published private var goalMet = false
    private var observers: Set<AnyCancellable> = []
    private lazy var alarm = WallClockAlarm { [weak self] in self?.replan() }

    init(storage: EditionStorage, runMode: RunMode, pet: ClosetStore,
         progress: AnyPublisher<[ProgressItem], Never>) {
        self.pet = pet
        let isLive = !runMode.isEphemeral
        center = isLive && Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
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
        if let center, center.delegate == nil { center.delegate = self }
        progress.map(StudyReminder.goalMet(in:)).removeDuplicates().assign(to: &$goalMet)
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
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                self?.replan()
            }
            self?.refreshPermission()
        }
    }

    /// The reminder's time today, for a time picker.
    var time: Date {
        get {
            Calendar.current.date(bySettingHour: save.settings.hour, minute: save.settings.minute,
                                  second: 0, of: .now) ?? .now
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
            let denied = await center.notificationSettings().authorizationStatus == .denied
            guard let self else { return }
            isBlocked = denied && isEnabled
        }
    }

    /// Withdraws the pending reminder and sets the next one, if any.
    private func replan(now: Date = .now) {
        guard let center else { return }
        let streak = pet.streak
        let before = save
        let fire = save.plan(now: now, studiedToday: streak.studiedToday, goalMetToday: goalMet)
        if save != before { persist() }
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
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
        center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger))
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
