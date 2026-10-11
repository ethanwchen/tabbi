import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Today panel: the checklist (date and progress header, items, add
/// field) on the left, which the header's arrows step to yesterday or
/// tomorrow, swapped for the Plan My Day proposal or the
/// End-of-Day Review while one is open; an "Up next" calendar card above a
/// compact focus timer on the right. Keeps the notch pinned open while any
/// field is focused so it doesn't close under the cursor mid-typing.
struct PlannerPanel: View {
    @ObservedObject var store: PlannerStore
    @EnvironmentObject private var notch: NotchViewModel
    /// What other modules share, listed above the checklist.
    let providers: ProviderHub
    @FocusState private var focus: PlannerField?

    /// Width of the right column; the checklist keeps the remaining ~60%.
    static let sideColumnWidth: CGFloat = 200

    /// From 5 pm "Wrap up" is the panel's call to action and "Plan my day"
    /// moves to a small header button; during the day it's the other way round.
    /// `TABBI_PLANNER_PREVIEW=daytime|evening` pins either for demo snapshots.
    static func isWrapUpTime(_ date: Date) -> Bool {
        guard RunMode.current.isDemo else { return DayReviewer.isWrapUpTime(date) }
        return switch ProcessInfo.processInfo.environment["TABBI_PLANNER_PREVIEW"] {
        case "daytime": false
        case "evening": true
        default: DayReviewer.isWrapUpTime(date)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            PlannerMainColumn(plan: store.plan, review: store.review) {
                // Re-checks the hour each minute so "Wrap up" takes the lead at 5 pm on its own.
                TimelineView(.everyMinute) { context in
                    let isEvening = Self.isWrapUpTime(context.date)
                    let hasPlannableWork = store.hasPlannableWork
                    VStack(spacing: Theme.Spacing.s) {
                        PlannerHeader(store: store, providers: providers, isEvening: isEvening,
                                      hasPlannableWork: hasPlannableWork)
                        content(at: context.date)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if store.viewing == .yesterday {
                            PlannerLeftoversBar(store: store)
                        } else if store.viewing == .tomorrow, store.canEdit {
                            HStack(spacing: Theme.Spacing.s) {
                                PlannerAddField(store: store, focus: $focus)
                                if store.hasPlannableTomorrow {
                                    PlannerPillButton(title: PlannerViewedDay.tomorrow.planTitle, symbol: "sparkles",
                                                      isProminent: isEvening, height: 28,
                                                      help: store.planSettings.planMode.planHelp(for: .tomorrow)) {
                                        store.planTomorrow()
                                    }
                                    .transition(.motionPop)
                                }
                            }
                        } else if store.canEdit {
                            HStack(spacing: Theme.Spacing.s) {
                                PlannerAddField(store: store, focus: $focus)
                                if isEvening {
                                    PlannerPillButton(title: String(localized: "Wrap up", bundle: .tabbi), symbol: "moon.stars.fill", isProminent: true,
                                                      height: 28, help: String(localized: "Review today and see what carries over to tomorrow", bundle: .tabbi)) {
                                        store.wrapUp()
                                    }
                                    .transition(.motionPop)
                                } else if hasPlannableWork {
                                    // Nothing to schedule until there's an open task.
                                    PlannerPillButton(title: String(localized: "Plan my day", bundle: .tabbi), symbol: "sparkles", height: 28,
                                                      help: store.planSettings.planMode.planHelp) {
                                        store.planMyDay()
                                    }
                                    .transition(.motionPop)
                                }
                            }
                        }
                    }
                }
            }
            VStack(spacing: Theme.Spacing.s) {
                UpNextCard(store: store.upNext, upNextEvents: store.planSettings.upNextEvents)
                TodayTimerCard(store: store, focus: store.focus, providers: providers)
            }
            .frame(width: Self.sideColumnWidth)
        }
        .onAppear {
            store.refreshDay()
            store.upNext.setVisible(true)
            store.focus.setVisible(true, viewer: .today)
        }
        .task {
            // Opened by the global shortcut: the caret waits in "Add a task",
            // once the notch panel has become key.
            guard store.canEdit, notch.consumeKeyboardOpen() else { return }
            try? await Task.sleep(for: .milliseconds(80))
            focus = .add
        }
        .onChange(of: focus) { _, field in notch.isPinned = field != nil }
        .onDisappear {
            notch.isPinned = false
            // Today is what the panel opens on, unless a plan for tomorrow is waiting.
            store.panelClosed()
            store.upNext.setVisible(false)
            store.focus.setVisible(false, viewer: .today)
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        if case .unreadable(let fileName) = store.shownProblem {
            PlannerMessage(
                symbol: "exclamationmark.triangle.fill",
                tint: Theme.Palette.warning,
                title: unreadableTitle,
                detail: String(localized: "\(fileName) is damaged, so it's left untouched.", bundle: .tabbi)
            )
        } else {
            PlannerChecklist(store: store, providers: providers, focus: $focus, date: date)
        }
    }

    private var unreadableTitle: String {
        switch store.viewing {
        case .yesterday: String(localized: "Couldn't read yesterday's list", bundle: .tabbi)
        case .today: String(localized: "Couldn't read today's list", bundle: .tabbi)
        case .tomorrow: String(localized: "Couldn't read tomorrow's list", bundle: .tabbi)
        }
    }
}

extension TodayPlanSettings.PlanMode {
    /// What Plan my day does, for its tooltips.
    var planHelp: String { planHelp(for: .today) }

    /// What planning `day` does, for its tooltips.
    func planHelp(for day: PlannerViewedDay) -> String {
        let tomorrow = day == .tomorrow
        return switch self {
        case .local: tomorrow
            ? String(localized: "Fit your open tasks, reviews and breaks around tomorrow's calendar", bundle: .tabbi)
            : String(localized: "Fit your open tasks, reviews and breaks around today's calendar", bundle: .tabbi)
        case .claude: tomorrow
            ? String(localized: "Let your AI fit your open tasks around tomorrow's calendar", bundle: .tabbi)
            : String(localized: "Let your AI fit your open tasks around today's calendar", bundle: .tabbi)
        case .study: tomorrow
            ? String(localized: "Fit reviews, study blocks and breaks around tomorrow's calendar", bundle: .tabbi)
            : String(localized: "Fit reviews, study blocks and breaks around today's calendar", bundle: .tabbi)
        }
    }
}

/// The side column's timer: the clock of a module that owns one (Timer in
/// the bundled kits), so the layout has one timer, unless the Focus tab is
/// on too and its Pomodoro is under way, which then keeps its own card
/// rather than hiding behind "Start a timer". Observes the Pomodoro here so
/// its ticks don't re-render the panel.
private struct TodayTimerCard: View {
    @ObservedObject var store: PlannerStore
    @ObservedObject var focus: FocusStore
    let providers: ProviderHub

    var body: some View {
        if let owner = store.focusClockOwner, !store.isFocusTabOn || focus.timer.runState == .idle {
            SharedFocusCard(owner: owner, providers: providers)
        } else {
            FocusCard(store: focus, items: store.day.items)
        }
    }
}

/// The checklist with what other modules share for today (say, Anki
/// reviews) above it, or the fresh-day message while both are empty, which
/// greets the user by name when they gave one. Observes `ProviderHub` here
/// so its updates don't re-render the panel.
private struct PlannerChecklist: View {
    @ObservedObject var store: PlannerStore
    @ObservedObject var providers: ProviderHub
    var focus: FocusState<PlannerField?>.Binding
    /// Now, from the panel's minute timeline, so the greeting follows the hour.
    let date: Date

    var body: some View {
        // Other modules share what's on for today only.
        let shared = store.viewing == .today ? providers.snapshot.sharedTodayItems(excluding: .planner) : []
        if store.items.isEmpty, shared.isEmpty {
            switch store.viewing {
            case .yesterday:
                PlannerMessage(
                    symbol: "clock.arrow.circlepath",
                    tint: Theme.Palette.secondaryText,
                    title: String(localized: "Nothing listed yesterday", bundle: .tabbi),
                    detail: String(localized: "Each day's list shows up here the day after.", bundle: .tabbi)
                )
            case .today:
                PlannerMessage(
                    symbol: "checklist",
                    tint: TodayModule.descriptor.accentColor,
                    title: DisplayName.greeting(for: store.displayName, at: date) ?? String(localized: "A fresh day", bundle: .tabbi),
                    detail: String(localized: "Add a few things you want to get done today.", bundle: .tabbi)
                )
            case .tomorrow:
                PlannerMessage(
                    symbol: "sunrise.fill",
                    tint: TodayModule.descriptor.accentColor,
                    title: String(localized: "Plan tomorrow", bundle: .tabbi),
                    detail: String(localized: "Add what you want to get done. Today's unfinished tasks join them in the morning.", bundle: .tabbi)
                )
            }
        } else {
            PlannerList(store: store, shared: shared, focus: focus)
        }
    }
}

/// The left column: the checklist, or the Plan My Day view or End-of-Day
/// Review while one is active. Observes both on its own so they don't
/// re-render the panel.
private struct PlannerMainColumn<Checklist: View>: View {
    @ObservedObject var plan: DayPlanStore
    @ObservedObject var review: DayReviewStore
    @ViewBuilder var checklist: Checklist

    var body: some View {
        ZStack {
            if review.isActive {
                DayReviewView(store: review)
                    .transition(.motionSwap)
            } else if plan.isActive {
                DayPlanView(plan: plan)
                    .transition(.motionSwap)
            } else {
                checklist
                    .transition(.motionSwap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .motion(Theme.Motion.content, value: plan.isActive)
        .motion(Theme.Motion.content, value: review.isActive)
    }
}

/// Which text field has keyboard focus.
enum PlannerField: Hashable {
    case add
    case rename(PlannerItem.ID)
}

// MARK: Header

/// Date and progress for the whole day. Shared goals such as Anki reviews
/// count as items, so the ring and "N of M done" move when they finish too.
private struct PlannerHeader: View {
    @ObservedObject var store: PlannerStore
    @ObservedObject var providers: ProviderHub
    let isEvening: Bool
    let hasPlannableWork: Bool

    var body: some View {
        let isToday = store.viewing == .today
        let tally = TodayTally(day: store.shownDay,
                               shared: isToday ? providers.snapshot.sharedTodayItems(excluding: .planner) : [])
        HStack(spacing: Theme.Spacing.s) {
            PlannerProgressRing(progress: tally.progress)
                .frame(width: 16, height: 16)
                .frame(width: 20)
            // A narrow panel (Compact) shortens the date, then the count, instead of truncating them.
            // Demo mode shows no dates, so store screenshots never carry one.
            let styles = store.viewing.headerDateStyles(showsDates: !RunMode.current.isDemo)
            ViewThatFits(in: .horizontal) {
                if isToday {
                    dateAndCount(styles[0], tally.summary)
                    dateAndCount(styles[0], tally.shortSummary)
                    dateAndCount(styles[styles.count - 1], tally.shortSummary)
                } else {
                    // "Yesterday" names the day; its date is a quiet extra.
                    dateAndCount(styles[0], summary(tally))
                    dateAndCount(styles[0], shortSummary(tally))
                    dateAndCount(nil, summary(tally))
                    dateAndCount(nil, shortSummary(tally))
                }
            }
            if store.shownDay.doneCount > 0, store.canEdit {
                IconButton(symbol: "checkmark.circle.badge.xmark", size: 20, help: String(localized: "Clear completed tasks", bundle: .tabbi)) {
                    withMotion(Theme.Motion.snappy) { store.clearCompleted() }
                }
                .transition(.motionPop)
            }
            if isToday, store.canEdit {
                // The action that isn't the bottom row's pill right now.
                if isEvening {
                    if hasPlannableWork {
                        IconButton(symbol: "sparkles", size: 20,
                                   help: String(localized: "Plan my day: \(store.planSettings.planMode.planHelp.lowercased())", bundle: .tabbi)) {
                            store.planMyDay()
                        }
                    }
                } else {
                    IconButton(symbol: "moon.stars", size: 20,
                               help: String(localized: "Wrap up: review today and see what carries over", bundle: .tabbi)) {
                        store.wrapUp()
                    }
                }
            }
        }
        .frame(height: 20)
        .padding(.horizontal, Theme.Spacing.s)
        .motion(Theme.Motion.snappy, value: tally)
    }

    /// "3 of 5 done" for today and yesterday; tomorrow hasn't started, so
    /// it counts what's planned.
    private func summary(_ tally: TodayTally) -> String {
        store.viewing == .tomorrow && tally.doneCount == 0 ? tally.plannedSummary : tally.summary
    }

    private func shortSummary(_ tally: TodayTally) -> String {
        store.viewing == .tomorrow && tally.doneCount == 0 ? tally.plannedSummary : tally.shortSummary
    }

    /// The day stepper and the count. Today shows its date; yesterday and
    /// tomorrow say which they are, then the date while it fits (`date`
    /// nil drops it).
    private func dateAndCount(_ date: Date.FormatStyle?, _ count: String) -> some View {
        let day = store.shownDay.date.startDate()
        return HStack(spacing: Theme.Spacing.s) {
            DayStepper(viewing: store.viewing, show: { store.show($0) }) {
                HStack(spacing: Theme.Spacing.xs) {
                    if let title = store.viewing.title {
                        Text(title)
                            .foregroundStyle(Theme.Palette.primaryText)
                        if let date {
                            Text(day.formatted(date))
                                .foregroundStyle(Theme.Palette.tertiaryText)
                        }
                    } else if let date {
                        Text(day.formatted(date))
                            .foregroundStyle(Theme.Palette.primaryText)
                    }
                }
                .font(Theme.Typography.title)
                .fixedSize()
            }
            Spacer(minLength: Theme.Spacing.s)
            if store.shownProblem == .saveFailed {
                Label(String(localized: "Not saved", bundle: .tabbi), systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.warning)
                    .fixedSize()
                    .help(String(localized: "The last change couldn't be written to disk", bundle: .tabbi))
            }
            Text(count)
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize()
                .contentTransition(.numericText())
        }
    }
}

/// Small ring that fills in the module accent as tasks get done.
struct PlannerProgressRing: View {
    let progress: Double

    var body: some View {
        ProgressRing(progress: progress, tint: TodayModule.descriptor.accentColor)
    }
}

// MARK: Empty and error states

/// Icon, title, and detail centered in the checklist area, with an optional action below.
struct PlannerMessage<Action: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder var action: Action

    private var iconWidth: CGFloat { 24 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: iconWidth)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            action
                .padding(.leading, iconWidth + Theme.Spacing.m)
        }
        .padding(.horizontal, Theme.Spacing.s)
    }
}

extension PlannerMessage where Action == EmptyView {
    init(symbol: String, tint: Color, title: String, detail: String) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail) { EmptyView() }
    }
}

// MARK: Add field

private struct PlannerAddField: View {
    @ObservedObject var store: PlannerStore
    var focus: FocusState<PlannerField?>.Binding
    @State private var text = ""
    @State private var hovering = false

    var body: some View {
        let isFocused = focus.wrappedValue == .add
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isFocused ? TodayModule.descriptor.accentColor : Theme.Palette.tertiaryText)
                .frame(width: 20)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        if store.viewing == .tomorrow { Text("Add a task for tomorrow…", bundle: .tabbi) }
                        Text("Add a task…", bundle: .tabbi)
                        Text("Add…", bundle: .tabbi)
                    }
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .allowsHitTesting(false)
                }
                // Hidden until used: AppKit-backed fields don't render in
                // snapshots, and the placeholder above stands in for them.
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .focused(focus, equals: .add)
                    .opacity(isFocused || !text.isEmpty ? 1 : 0)
                    .onSubmit {
                        if withMotion(Theme.Motion.snappy, { store.add(text) }) { text = "" }
                    }
                    // Esc clears the draft; a second Esc leaves the field so the next one closes the notch.
                    .onExitCommand {
                        if text.isEmpty { focus.wrappedValue = nil } else { text = "" }
                    }
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(hovering || isFocused ? Theme.Palette.surfaceHover : Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .strokeBorder(isFocused ? TodayModule.descriptor.accentColor.opacity(0.5) : Theme.Palette.stroke,
                              lineWidth: isFocused ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = .add }
        .onHover { hovering = $0 }
        .help(String(localized: "Type a task and press Return to add it; Esc clears", bundle: .tabbi))
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isFocused)
    }
}
