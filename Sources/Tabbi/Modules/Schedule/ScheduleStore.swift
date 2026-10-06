import AppKit
import Combine
import EventKit
import TabbiKitCore

/// The next seven days of calendar for the Schedule tab (today in the Day
/// view, all of them in the Week view), read through EventKit (Google and
/// other accounts come in through macOS Internet Accounts).
///
/// Calendar access is only requested from the panel, never at launch.
/// While the panel is visible the day reloads on every minute boundary (so
/// the now-line moves) and whenever the calendar database changes; while
/// it's hidden nothing runs.
///
/// In demo mode it shows `ScheduleSampleData` seen from 11:20 and never
/// touches EventKit; `TABBI_SCHEDULE_PREVIEW=notAsked|denied|freeDay` renders
/// the empty states instead, `selected` a block's details, `week` the Week
/// view, `plan` or `plan-selected` the Plan button's proposal, and
/// `plan-week` or `plan-week-selected` the Week view's.
///
/// Plan offers the rest of today planned on device (`ScheduleDraft`, no
/// Claude): other modules' open tasks and review goals, placed in the free
/// time. The blocks show on the timeline until the user adds or skips them;
/// added ones are written to the default calendar as planned by Tabbi.
/// Plan week spreads the same work over the free time of the next seven
/// days.
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

    /// The two ways to look at the calendar.
    enum Mode: String, CaseIterable {
        case day = "Day"
        case week = "Week"
    }

    @Published private(set) var access: Access
    @Published var mode: Mode = .day
    /// Events and planned blocks from today through the next six days,
    /// all-day ones included.
    @Published private(set) var items: [ScheduleItem] = []
    /// Whether any calendar syncs from an online account, so an empty day can
    /// suggest adding one.
    @Published private(set) var hasAccounts = true
    /// The moment the now-line marks; advances once a minute while visible.
    @Published private(set) var now: Date
    /// The item whose details show under the timeline.
    @Published var selectedID: ScheduleItem.ID?
    /// The plan on offer, from Plan until every block is added or skipped.
    @Published private(set) var draft: ScheduleDraft?
    /// True when the last Add didn't reach the calendar; the draft stays.
    @Published private(set) var writeFailed = false

    /// Open tasks and goals other modules share, which Plan schedules.
    var sharedTasks: [ProvidedTask] = []
    var progress: [ProgressItem] = []
    /// Review sizing, buffer and end of day, from the kit's planner section.
    var planSettings = TodayPlanSettings()

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
            let showsDay = preview != "notAsked" && preview != "denied" && preview != "freeDay"
            items = showsDay ? ScheduleSampleData.weekItems(from: date) : []
            selectedID = preview == "selected" ? "demo-deck" : nil
            mode = preview?.hasPrefix("week") == true || preview?.hasPrefix("plan-week") == true ? .week : .day
            if preview == "plan" || preview == "plan-selected" {
                planDay()
                if preview == "plan-selected" { selectedID = draft?.items.first?.id }
            }
            if preview?.hasPrefix("plan-week") == true {
                planWeek()
                if preview == "plan-week-selected" { selectedID = draft?.items.last?.id }
            }
        } else {
            now = date
            access = Self.currentAccess()
        }
    }

    /// The calendar plus any blocks on offer.
    var shownItems: [ScheduleItem] {
        items + (draft?.items ?? [])
    }

    /// The Day view's layout for the current items and clock.
    var dayLayout: ScheduleDayLayout {
        ScheduleDayLayout(day: now, now: now, items: shownItems)
    }

    /// The Week view's layout: today and the six days after it.
    var weekLayout: ScheduleWeekLayout {
        ScheduleWeekLayout(now: now, days: Self.dayCount, items: shownItems)
    }

    var selectedItem: ScheduleItem? {
        selectedID.flatMap { id in shownItems.first { $0.id == id } }
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

    func show(_ mode: Mode) {
        selectedID = nil
        self.mode = mode
    }

    func select(_ id: ScheduleItem.ID?) {
        selectedID = selectedID == id ? nil : id
    }

    /// Plans the rest of today around the calendar and shows the blocks on
    /// the timeline. Demo mode plans its sample tasks around the demo day.
    func planDay() {
        startPlanning()
        draft = ScheduleDraft.plan(now: now, items: items, sharedTasks: isDemo ? ScheduleSampleData.tasks : sharedTasks,
                                   progress: isDemo ? [] : progress, settings: planSettings)
    }

    /// Spreads the same work over the free time of today and the next six
    /// days, for the Week view. Demo mode plans a longer sample list.
    func planWeek() {
        startPlanning()
        draft = ScheduleDraft.planWeek(now: now, days: Self.dayCount, items: items,
                                       sharedTasks: isDemo ? ScheduleSampleData.weekTasks : sharedTasks,
                                       progress: isDemo ? [] : progress, settings: planSettings)
    }

    /// Writes one offered block (every one when `id` is nil) to the calendar.
    func add(_ id: ScheduleItem.ID? = nil) {
        guard var draft else { return }
        do {
            let written = try draft.add(id, now: isDemo ? now : Date(), events: items.map(\.upcomingEvent),
                                        writer: isDemo ? DryRunPlanWriter(logs: false) : EventKitPlanWriter(store: eventStore))
            if isDemo {
                // Nothing reloads in demo mode, so show the blocks as planned here.
                items += written.map {
                    ScheduleItem(id: "demo-added-\($0.start.timeIntervalSinceReferenceDate)", title: $0.title,
                                 start: $0.start, end: $0.end, kind: .planned)
                }
            }
            writeFailed = false
            settle(draft)
            reload()
        } catch {
            writeFailed = true
        }
    }

    /// Takes one offered block off the timeline.
    func skip(_ id: ScheduleItem.ID) {
        guard var draft else { return }
        draft.skip(id)
        settle(draft)
    }

    /// Drops the whole offer; nothing was written.
    func discardPlan() {
        selectedID = nil
        writeFailed = false
        draft = nil
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

    /// Days the store reads: the Week view's seven, the first one today.
    private static let dayCount = 7

    private func startPlanning() {
        if !isDemo { now = Date() }
        selectedID = nil
        writeFailed = false
    }

    private func settle(_ draft: ScheduleDraft) {
        if let selectedID, !draft.items.contains(where: { $0.id == selectedID }),
           !items.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        self.draft = draft.isSettled ? nil : draft
    }

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
        guard let end = calendar.date(byAdding: .day, value: Self.dayCount, to: startOfDay) else { return }
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: end, calendars: nil)
        items = eventStore.events(matching: predicate).map(Self.item)
        if let selectedID, !shownItems.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
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
