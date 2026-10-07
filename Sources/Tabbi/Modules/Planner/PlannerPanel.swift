import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Today panel: the checklist (date and progress header, items, add
/// field) on the left, swapped for the Plan My Day proposal or the
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
                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if store.canEdit {
                            HStack(spacing: Theme.Spacing.s) {
                                PlannerAddField(store: store, focus: $focus)
                                if isEvening {
                                    PlannerPillButton(title: "Wrap up", symbol: "moon.stars.fill", isProminent: true,
                                                      height: 28, help: "Review today and see what carries over to tomorrow") {
                                        store.wrapUp()
                                    }
                                    .transition(.motionPop)
                                } else if hasPlannableWork {
                                    // Nothing to schedule until there's an open task.
                                    PlannerPillButton(title: "Plan my day", symbol: "sparkles", height: 28,
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
                if let owner = store.focusClockOwner {
                    SharedFocusCard(owner: owner, providers: providers)
                } else {
                    FocusCard(store: store.focus, items: store.items)
                }
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
            store.upNext.setVisible(false)
            store.focus.setVisible(false, viewer: .today)
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .unreadable(let fileName) = store.problem {
            PlannerMessage(
                symbol: "exclamationmark.triangle.fill",
                tint: Theme.Palette.warning,
                title: "Couldn't read today's list",
                detail: "\(fileName) is damaged, so it's left untouched."
            )
        } else {
            PlannerChecklist(store: store, providers: providers, focus: $focus)
        }
    }
}

/// The checklist with what other modules share for today (say, Anki
/// reviews) above it, or the fresh-day message while both are empty.
/// Observes `ProviderHub` here so its updates don't re-render the panel.
extension TodayPlanSettings.PlanMode {
    /// What Plan my day does, for its tooltips.
    var planHelp: String {
        switch self {
        case .local: "Fit your open tasks, reviews and breaks around today's calendar"
        case .claude: "Let Claude fit your open tasks around today's calendar"
        case .study: "Fit reviews, study blocks and breaks around today's calendar"
        }
    }
}

private struct PlannerChecklist: View {
    @ObservedObject var store: PlannerStore
    @ObservedObject var providers: ProviderHub
    var focus: FocusState<PlannerField?>.Binding

    var body: some View {
        let shared = providers.snapshot.sharedTodayItems(excluding: .planner)
        if store.items.isEmpty, shared.isEmpty {
            PlannerMessage(
                symbol: "checklist",
                tint: TodayModule.descriptor.accentColor,
                title: "A fresh day",
                detail: "Add a few things you want to get done today."
            )
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
        let tally = TodayTally(day: store.day, shared: providers.snapshot.sharedTodayItems(excluding: .planner))
        HStack(spacing: Theme.Spacing.s) {
            PlannerProgressRing(progress: tally.progress)
                .frame(width: 16, height: 16)
                .frame(width: 20)
            // A narrow panel (Compact) shortens the date, then the count, instead of truncating them.
            ViewThatFits(in: .horizontal) {
                dateAndCount(.dateTime.weekday(.abbreviated).month(.abbreviated).day(), tally.summary)
                dateAndCount(.dateTime.weekday(.abbreviated).month(.abbreviated).day(), tally.shortSummary)
                dateAndCount(.dateTime.weekday(.abbreviated).day(), tally.shortSummary)
            }
            if store.day.doneCount > 0, store.canEdit {
                IconButton(symbol: "checkmark.circle.badge.xmark", size: 20, help: "Clear completed tasks") {
                    withMotion(Theme.Motion.snappy) { store.clearCompleted() }
                }
                .transition(.motionPop)
            }
            if store.canEdit {
                // The action that isn't the bottom row's pill right now.
                if isEvening {
                    if hasPlannableWork {
                        IconButton(symbol: "sparkles", size: 20,
                                   help: "Plan my day: \(store.planSettings.planMode.planHelp.lowercased())") {
                            store.planMyDay()
                        }
                    }
                } else {
                    IconButton(symbol: "moon.stars", size: 20,
                               help: "Wrap up: review today and see what carries over") {
                        store.wrapUp()
                    }
                }
            }
        }
        .frame(height: 20)
        .padding(.horizontal, Theme.Spacing.s)
        .motion(Theme.Motion.snappy, value: tally)
    }

    private func dateAndCount(_ date: Date.FormatStyle, _ count: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(store.day.date.startDate().formatted(date))
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
                .fixedSize()
            Spacer(minLength: Theme.Spacing.s)
            if store.problem == .saveFailed {
                Label("Not saved", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.warning)
                    .fixedSize()
                    .help("The last change couldn't be written to disk")
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
                        Text("Add a task…")
                        Text("Add…")
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
        .help("Type a task and press Return to add it; Esc clears")
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isFocused)
    }
}
