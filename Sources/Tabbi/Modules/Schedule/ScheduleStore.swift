import AppKit
import Combine
import EventKit
import TabbiKitCore

/// Today's calendar for the Schedule tab, read through EventKit (Google and
/// other accounts come in through macOS Internet Accounts).
///
/// Calendar access is only requested from the panel, never at launch.
/// While the panel is visible the day reloads on every minute boundary (so
/// the now-line moves) and whenever the calendar database changes; while
/// it's hidden nothing runs.
///
/// In demo mode it shows `ScheduleSampleData` seen from 11:20 and never
/// touches EventKit; `TABBI_SCHEDULE_PREVIEW=notAsked|denied|freeDay` renders
/// the empty states instead, and `selected` a block's details.
@MainActor
final class ScheduleStore: ObservableObject {
    enum Access: Equatable {
        case notDetermined
        /// Denied, restricted, or write-only.
        case denied
        /// This build can't ask (no usage description, e.g. `swift run`).
        case unavailable
        case granted
    }

    @Published private(set) var access: Access
    /// Today's events and planned blocks, all-day ones included.
    @Published private(set) var items: [ScheduleItem] = []
    /// Whether any calendar syncs from an online account, so an empty day can
    /// suggest adding one.
    @Published private(set) var hasAccounts = true
    /// The moment the now-line marks; advances once a minute while visible.
    @Published private(set) var now: Date
    /// The item whose details show under the timeline.
    @Published var selectedID: ScheduleItem.ID?

    private let isDemo: Bool
    private lazy var eventStore = EKEventStore()
    private var isVisible = false
    private var ticker: Timer?
    private var changeObserver: AnyCancellable?

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
    static let internetAccountsURL = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!

    init(runMode: RunMode) {
        isDemo = runMode.isDemo
        let date = Date()
        if isDemo {
            let preview = ProcessInfo.processInfo.environment["TABBI_SCHEDULE_PREVIEW"]
            access = switch preview {
            case "notAsked": .notDetermined
            case "denied": .denied
            default: .granted
            }
            now = ScheduleSampleData.now(on: date)
            items = preview == nil || preview == "selected" ? ScheduleSampleData.items(on: date) : []
            selectedID = preview == "selected" ? "demo-deck" : nil
        } else {
            now = date
            access = Self.currentAccess()
        }
    }

    /// The Day view's layout for the current items and clock.
    var dayLayout: ScheduleDayLayout {
        ScheduleDayLayout(day: now, now: now, items: items)
    }

    var selectedItem: ScheduleItem? {
        selectedID.flatMap { id in items.first { $0.id == id } }
    }

    /// Why there's no timeline to show, or nil when there is one.
    var emptySituation: UpNextEmptyState.Situation? {
        switch access {
        case .notDetermined: .notAsked
        case .denied: .denied
        case .unavailable: .unavailable
        case .granted: nil
        }
    }

    /// Call from the panel's `onAppear` / `onDisappear`.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            if !isDemo { access = Self.currentAccess() }
            reload()
            startUpdates()
        } else {
            stopUpdates()
            if !isDemo { selectedID = nil }
        }
    }

    /// Asks for full calendar access (shows the system prompt the first time).
    func requestAccess() {
        guard !isDemo, access == .notDetermined else { return }
        Task {
            // The result is re-read from EventKit, which is the source of truth.
            _ = try? await eventStore.requestFullAccessToEvents()
            access = Self.currentAccess()
            reload()
            if isVisible { startUpdates() }
        }
    }

    func select(_ id: ScheduleItem.ID?) {
        selectedID = selectedID == id ? nil : id
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(Self.privacySettingsURL)
    }

    func openInternetAccounts() {
        NSWorkspace.shared.open(Self.internetAccountsURL)
    }

    func join(_ link: MeetingLink) {
        NSWorkspace.shared.open(link.url)
    }

    // MARK: Private

    private static func currentAccess() -> Access {
        guard ConnectionProbes.canAskForCalendar else { return .unavailable }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func reload() {
        if isDemo { return }
        now = Date()
        guard access == .granted else {
            items = []
            return
        }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        items = eventStore.events(matching: predicate).map(Self.item)
        if let selectedID, !items.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
        hasAccounts = eventStore.calendars(for: .event).contains { Self.syncsFromAccount($0.source) }
    }

    /// Local and birthday calendars live only on this Mac; subscribed ones
    /// are read-only feeds. Anything else came from an Internet Account.
    private static func syncsFromAccount(_ source: EKSource?) -> Bool {
        switch source?.sourceType {
        case .calDAV, .exchange, .mobileMe: true
        default: false
        }
    }

    private func startUpdates() {
        if changeObserver == nil, !isDemo, access == .granted {
            changeObserver = NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: eventStore)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.reload() } }
        }
        guard !isDemo else { return }
        scheduleTick()
    }

    private func stopUpdates() {
        ticker?.invalidate()
        ticker = nil
        changeObserver = nil
    }

    /// Fires just after the next whole minute, then reschedules itself, so
    /// the now-line moves in step with the clock.
    private func scheduleTick() {
        ticker?.invalidate()
        let interval = 60 - Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) + 0.05
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.reload()
                self.scheduleTick()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private static func item(from event: EKEvent) -> ScheduleItem {
        // Occurrences of a repeating event share an identifier, so add the start.
        let id = "\(event.calendarItemIdentifier)@\(event.startDate.timeIntervalSinceReferenceDate)"
        let color = event.calendar?.color?.usingColorSpace(.sRGB).map {
            EventColor(red: $0.redComponent, green: $0.greenComponent, blue: $0.blueComponent)
        }
        let upcoming = UpcomingEvent(
            id: id, title: event.title ?? "", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
            calendarColor: color,
            meetingLink: MeetingLink.detect(url: event.url, location: event.location, notes: event.notes)
        )
        return ScheduleItem(event: upcoming, notes: event.notes)
    }
}
