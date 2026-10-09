import AppKit
import Combine
import EventKit
import TabbiKitCore

/// Yesterday and the next seven days of calendar for the Schedule tab
/// (today in the Day view, which steps back to yesterday and ahead to
/// tomorrow, and the seven days from today in the Week view), read through
/// EventKit (Google and
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
/// `plan-refining` the day plan waiting for Claude, and `plan-week` or
/// `plan-week-selected` the Week view's.
///
/// Plan offers the rest of today planned on device (`ScheduleDraft`, no
/// Claude): other modules' open tasks and review goals, placed in the free
/// time, or all of tomorrow's working day when the Day view shows tomorrow,
/// so it can be planned the evening before. The blocks show on the
/// timeline until the user adds or skips them;
/// added ones are written to the default calendar as planned by Tabbi.
/// When the `claude` CLI is installed, Refine offers the day plan to Claude
/// for suggestions; that is optional and the local plan stays usable.
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
    /// The day the Day view shows. Today unless the user stepped away; it
    /// goes back to today when the panel closes.
    @Published private(set) var viewing: PlannerViewedDay = .today
    /// Events and planned blocks from yesterday through the next six days,
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
    /// Waiting for Claude's suggestions on the day plan; Add and Skip wait too.
    @Published private(set) var isRefining = false
    /// Claude's suggestions didn't come back usable; the local plan stays.
    @Published private(set) var refineFailed = false
    /// Whether the `claude` CLI was found the last time Plan ran.
    @Published private(set) var claudeFound = false

    /// Open tasks and goals other modules share, which Plan schedules.
    var sharedTasks: [ProvidedTask] = []
    var progress: [ProgressItem] = []
    /// Review sizing, buffer and end of day, from the kit's planner section.
    var planSettings = TodayPlanSettings()

    private let isDemo: Bool
    /// False in a build that can't run the `claude` CLI: Refine never shows.
    private let usesClaude: Bool
    private lazy var eventStore = EKEventStore()
    private var isVisible = false
    private var ticker: Timer?
    private var changeObserver: AnyCancellable?
    private var refineTask: Task<Void, Never>?

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
    static let internetAccountsURL = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!

    init(usesClaude: Bool = true, runMode: RunMode) {
        isDemo = runMode.isDemo
        self.usesClaude = usesClaude
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
            items = showsDay ? ScheduleSampleData.yesterdayItems(before: date) + ScheduleSampleData.weekItems(from: date)
                : []
            selectedID = preview == "selected" ? "demo-deck" : nil
            mode = preview?.hasPrefix("week") == true || preview?.hasPrefix("plan-week") == true ? .week : .day
            claudeFound = usesClaude
            if preview == "plan" || preview == "plan-selected" || preview == "plan-refining" {
                planDay()
                isRefining = preview == "plan-refining"
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

    /// True when the day plan on offer can get a second look from Claude.
    /// Claude's day prompt plans from now, so a plan for tomorrow stays local.
    var canRefine: Bool { claudeFound && viewing == .today && draft?.canRefine == true }

    /// The calendar plus any blocks on offer.
    var shownItems: [ScheduleItem] {
        items + (draft?.items ?? [])
    }

    /// Midnight of the day the Day view shows.
    var shownDay: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: viewing.rawValue, to: today) ?? today
    }

    /// The Day view's layout for the day shown and the current clock.
    /// Another day keeps the usual working hours, as the Week view does.
    var dayLayout: ScheduleDayLayout {
        ScheduleDayLayout(day: shownDay, now: now, items: shownItems,
                          preferences: planSettings.schedulePreferences(now: viewing == .today ? now : shownDay))
    }

    /// The Week view's layout: today and the six days after it.
    var weekLayout: ScheduleWeekLayout {
        ScheduleWeekLayout(now: now, days: Self.dayCount, items: shownItems,
                           preferences: planSettings.schedulePreferences(now: Calendar.current.startOfDay(for: now)))
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
            show(.today)
        }
    }

    /// Asks for full calendar access (shows the system prompt the first time).
    func requestAccess() {
        guard !isDemo, access == .notDetermined else { return }
        Task {
            // The result is re-read from EventKit, which is the source of truth.
            await ConnectionProbes.requestCalendarAccess(eventStore)
            access = Self.currentAccess()
            reload()
            if isVisible { startUpdates() }
        }
    }

    func show(_ mode: Mode) {
        selectedID = nil
        self.mode = mode
    }

    /// Steps the Day view to yesterday, today or tomorrow. A plan on offer
    /// belongs to the day it was made for, so it goes away.
    func show(_ day: PlannerViewedDay) {
        guard day != viewing else { return }
        discardPlan()
        viewing = day
    }

    /// Sets the day shown, and a plan on offer for it, for one snapshot.
    /// Without calendar access there is no stepper, so it stays on today.
    func showForSnapshot(_ day: PlannerViewedDay, planning: Bool = false) {
        show(emptySituation == nil ? day : .today)
        mode = .day
        selectedID = nil
        if planning, emptySituation == nil { planDay() } else { discardPlan() }
    }

    func select(_ id: ScheduleItem.ID?) {
        // Offered blocks may change while Claude refines them.
        if isRefining, let id, draft?.items.contains(where: { $0.id == id }) == true { return }
        selectedID = selectedID == id ? nil : id
    }

    /// Plans the rest of today (or all of tomorrow's working day, when the
    /// Day view shows tomorrow) around the calendar and shows the blocks on
    /// the timeline. Yesterday is over, so there is nothing to plan there.
    /// Demo mode plans its sample tasks around the demo day.
    func planDay() {
        guard viewing != .yesterday else { return }
        startPlanning()
        if !isDemo, viewing == .today { checkClaude() }
        draft = ScheduleDraft.plan(now: viewing == .today ? now : shownDay, items: items, sharedTasks: isDemo ? ScheduleSampleData.tasks : sharedTasks,
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
        guard !isRefining, var draft else { return }
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
        guard !isRefining, var draft else { return }
        draft.skip(id)
        settle(draft)
    }

    /// Drops the whole offer; nothing was written.
    func discardPlan() {
        cancelRefine()
        selectedID = nil
        writeFailed = false
        draft = nil
    }

    /// Asks Claude for suggestions on the day plan's blocks still on offer.
    /// Claude's answer is validated like any plan (never over an event or in
    /// the past) before it replaces them; on failure the local plan stays.
    func refine() {
        guard canRefine, !isRefining, let draft else { return }
        cancelRefine()
        isRefining = true
        selectedID = nil
        let blocks = draft.proposal.pending
        let context = draft.refineContext(now: isDemo ? now : Date(), items: items, settings: planSettings)
        refineTask = Task { [weak self, isDemo] in
            let refined: [PlanBlock]?
            if isDemo {
                // Demo mode never runs the CLI: Claude agrees with the sample plan.
                try? await Task.sleep(for: .seconds(1.2))
                refined = blocks
            } else {
                refined = await Self.refinedBlocks(blocks, context: context)
            }
            guard let self, !Task.isCancelled, var current = self.draft else { return }
            self.isRefining = false
            if let refined, !refined.isEmpty {
                current.refine(with: refined)
                self.draft = current
            } else {
                self.refineFailed = true
            }
        }
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
        cancelRefine()
        if !isDemo { now = Date() }
        selectedID = nil
        writeFailed = false
    }

    private func cancelRefine() {
        refineTask?.cancel()
        refineTask = nil
        isRefining = false
        refineFailed = false
    }

    /// Looks for the `claude` CLI off the main thread while the plan shows,
    /// so Refine only appears when it can work.
    private func checkClaude() {
        guard usesClaude else { return }
        Task { [weak self] in
            let found = await Task.detached(priority: .utility, operation: { ClaudeCLI.locate() }).value != nil
            self?.claudeFound = found
        }
    }

    /// Claude's refinement of `blocks`, or nil when Claude is missing or its
    /// answer isn't usable.
    private nonisolated static func refinedBlocks(_ blocks: [PlanBlock], context: DayPlanContext) async -> [PlanBlock]? {
        guard let executable = await Task.detached(priority: .userInitiated, operation: { ClaudeCLI.locate() }).value,
              let text = await DayPlanner.answer(executable: executable,
                                                prompt: DayPlanner.refinePrompt(for: context, plan: blocks))
        else { return nil }
        return try? DayPlanner.refinement(from: text, context: context, plan: blocks)
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
        guard let start = calendar.date(byAdding: .day, value: -1, to: startOfDay),
              let end = calendar.date(byAdding: .day, value: Self.dayCount, to: startOfDay) else { return }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
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
