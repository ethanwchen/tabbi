import AppKit
import Combine
import EventKit
import NotchKitCore

/// Today's remaining calendar events for the Today panel's "Up next" card.
///
/// Calendar access is only requested when the user asks for it from the panel,
/// never at launch. While the panel is visible the list refreshes on every
/// minute boundary (so "in 12 min" badges stay true) and whenever the calendar
/// database changes. The closed-notch meeting preview keeps it refreshing the
/// same way while it's on; while neither needs events nothing runs.
///
/// With `NOTCHDECK_DEMO=1` it shows `UpcomingEvent.samples` and never touches
/// EventKit.
@MainActor
final class UpNextStore: ObservableObject {
    enum Access: Equatable {
        /// Never asked; the card offers a "Show calendar" button.
        case notDetermined
        /// Denied, restricted, or write-only; the card links to System Settings.
        case denied
        /// This build can't ask (no usage description, e.g. `swift run`).
        case unavailable
        case granted
    }

    @Published private(set) var access: Access
    /// Up to three events still ahead today, soonest first.
    @Published private(set) var events: [UpcomingEvent] = []
    /// The moment badges are measured against; advances once a minute while visible.
    @Published private(set) var now = Date()

    private let isDemo: Bool
    private let demoEvents: [UpcomingEvent]
    private lazy var eventStore = EKEventStore()
    private var isVisible = false
    private var isPreviewWatching = false
    /// True while the panel or the closed-notch preview needs fresh events.
    private var isWatched: Bool { isVisible || isPreviewWatching }
    private var ticker: Timer?
    private var changeObserver: AnyCancellable?

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    init() {
        isDemo = ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1"
        if isDemo {
            let start = Date()
            access = .granted
            demoEvents = UpcomingEvent.samples(now: start)
            now = start
            events = UpcomingEvent.upNext(from: demoEvents, at: start)
        } else {
            demoEvents = []
            access = Self.currentAccess()
        }
    }

    /// Call from the panel's `onAppear` / `onDisappear`.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        let wasWatched = isWatched
        isVisible = visible
        watchedDidChange(from: wasWatched)
    }

    /// Call while the closed-notch preview can show a meeting, so it learns
    /// about events added since the panel was last open.
    func setPreviewWatching(_ watching: Bool) {
        guard watching != isPreviewWatching else { return }
        let wasWatched = isWatched
        isPreviewWatching = watching
        watchedDidChange(from: wasWatched)
    }

    /// Asks for full calendar access (shows the system prompt the first time).
    func requestAccess() {
        guard !isDemo, access == .notDetermined else { return }
        Task { _ = await ensureAccess() }
    }

    /// Every event today (not just the next few), for Plan My Day. Empty
    /// without calendar access.
    func todayEvents() -> [UpcomingEvent] {
        if isDemo { return demoEvents }
        guard access == .granted else { return [] }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        return eventStore.events(matching: predicate).map(Self.upcomingEvent)
    }

    /// Asks for calendar access when it was never requested, then reports
    /// the result. Plan My Day needs it to see meetings and add blocks.
    func ensureAccess() async -> Access {
        if !isDemo { access = Self.currentAccess() }
        guard !isDemo, access == .notDetermined else { return access }
        // The result is re-read from EventKit, which is the source of truth.
        _ = try? await eventStore.requestFullAccessToEvents()
        access = Self.currentAccess()
        reload()
        if isWatched { startUpdates() }
        return access
    }

    /// The writer for accepted plan blocks: EventKit on the shared store,
    /// or one that never touches the calendar in demo mode and dry runs.
    func makePlanWriter() -> PlanCalendarWriting {
        if isDemo { return DryRunPlanWriter(logs: false) }
        if isPlanDryRun { return DryRunPlanWriter(logs: true) }
        return EventKitPlanWriter(store: eventStore)
    }

    /// `NOTCHDECK_PLAN_DRY_RUN=1`: plan blocks are printed, never written.
    var isPlanDryRun: Bool { ProcessInfo.processInfo.environment["NOTCHDECK_PLAN_DRY_RUN"] == "1" }

    func openPrivacySettings() {
        NSWorkspace.shared.open(Self.privacySettingsURL)
    }

    func join(_ link: MeetingLink) {
        NSWorkspace.shared.open(link.url)
    }

    // MARK: Private

    private func watchedDidChange(from wasWatched: Bool) {
        guard isWatched != wasWatched else { return }
        if isWatched {
            if !isDemo { access = Self.currentAccess() }
            reload()
            startUpdates()
        } else {
            stopUpdates()
        }
    }

    private static func currentAccess() -> Access {
        // Without a usage description macOS terminates the app on request.
        guard Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil else {
            return .unavailable
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func reload() {
        now = Date()
        if isDemo {
            events = UpcomingEvent.upNext(from: demoEvents, at: now)
            return
        }
        guard access == .granted else {
            events = []
            return
        }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let today = eventStore.events(matching: predicate).map(Self.upcomingEvent)
        events = UpcomingEvent.upNext(from: today, at: now)
    }

    private func startUpdates() {
        if changeObserver == nil, !isDemo, access == .granted {
            changeObserver = NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: eventStore)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.reload() } }
        }
        scheduleTick()
    }

    private func stopUpdates() {
        ticker?.invalidate()
        ticker = nil
        changeObserver = nil
    }

    /// Fires just after the next whole minute, then reschedules itself, so the
    /// badges change in step with the clock instead of drifting.
    private func scheduleTick() {
        ticker?.invalidate()
        let interval = 60 - Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) + 0.05
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isWatched else { return }
                self.reload()
                self.scheduleTick()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private static func upcomingEvent(from event: EKEvent) -> UpcomingEvent {
        // Occurrences of a repeating event share an identifier, so add the start.
        let baseID = event.calendarItemIdentifier
        return UpcomingEvent(
            id: "\(baseID)@\(event.startDate.timeIntervalSinceReferenceDate)",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarColor: event.calendar.flatMap { eventColor($0.color) },
            meetingLink: MeetingLink.detect(url: event.url, location: event.location, notes: event.notes)
        )
    }

    private static func eventColor(_ color: NSColor?) -> EventColor? {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return nil }
        return EventColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}
