import SwiftUI
import NotchDeckCore

/// The Today panel: the checklist (date and progress header, items, add
/// field) on the left, swapped for the Plan My Day proposal while planning;
/// an "Up next" calendar card above a compact focus timer on the right. Keeps the notch pinned open while any field is focused
/// so it doesn't close under the cursor mid-typing.
struct PlannerPanel: View {
    @ObservedObject var store: PlannerStore
    @EnvironmentObject private var notch: NotchViewModel
    @FocusState private var focus: PlannerField?

    /// Width of the right column; the checklist keeps the remaining ~60%.
    static let sideColumnWidth: CGFloat = 200

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            PlannerMainColumn(plan: store.plan) {
                VStack(spacing: Theme.Spacing.s) {
                    PlannerHeader(store: store)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if store.canEdit {
                        HStack(spacing: Theme.Spacing.s) {
                            PlannerAddField(store: store, focus: $focus)
                            // Nothing to schedule until there's an open task.
                            if store.items.contains(where: { !$0.isDone }) {
                                PlannerPillButton(title: "Plan my day", symbol: "sparkles", height: 28,
                                                  help: "Let Claude fit your open tasks around today's calendar") {
                                    store.planMyDay()
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }
                        }
                    }
                }
            }
            VStack(spacing: Theme.Spacing.s) {
                UpNextCard(store: store.upNext)
                FocusCard(store: store.focus, items: store.items)
            }
            .frame(width: Self.sideColumnWidth)
        }
        .onAppear {
            store.refreshDay()
            store.upNext.setVisible(true)
            store.focus.setVisible(true)
        }
        .onChange(of: focus) { _, field in notch.isPinned = field != nil }
        .onDisappear {
            notch.isPinned = false
            store.upNext.setVisible(false)
            store.focus.setVisible(false)
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
        } else if store.items.isEmpty {
            PlannerMessage(
                symbol: "checklist",
                tint: Theme.Palette.accent(for: .planner),
                title: "A fresh day",
                detail: "Add a few things you want to get done today."
            )
        } else {
            PlannerList(store: store, focus: $focus)
        }
    }
}

/// The left column: the checklist, or the Plan My Day view while it's active.
/// Observes the plan on its own so planning doesn't re-render the panel.
private struct PlannerMainColumn<Checklist: View>: View {
    @ObservedObject var plan: DayPlanStore
    @ViewBuilder var checklist: Checklist

    var body: some View {
        ZStack {
            if plan.isActive {
                DayPlanView(plan: plan)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                checklist
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.Motion.content, value: plan.isActive)
    }
}

/// Which text field has keyboard focus.
enum PlannerField: Hashable {
    case add
    case rename(PlannerItem.ID)
}

// MARK: Header

private struct PlannerHeader: View {
    @ObservedObject var store: PlannerStore

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            PlannerProgressRing(progress: store.day.progress)
                .frame(width: 16, height: 16)
                .frame(width: 20)
            Text(store.day.date.startDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
            Spacer(minLength: Theme.Spacing.s)
            if store.problem == .saveFailed {
                Label("Not saved", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.warning)
                    .help("The last change couldn't be written to disk")
            }
            Text(store.day.progressSummary)
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.secondaryText)
                .contentTransition(.numericText())
            if store.day.doneCount > 0, store.canEdit {
                IconButton(symbol: "checkmark.circle.badge.xmark", size: 20, help: "Clear completed tasks") {
                    withAnimation(Theme.Motion.snappy) { store.clearCompleted() }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(height: 20)
        .padding(.horizontal, Theme.Spacing.s)
        .animation(Theme.Motion.snappy, value: store.day.doneCount)
    }
}

/// Small ring that fills in the module accent as tasks get done.
struct PlannerProgressRing: View {
    let progress: Double

    var body: some View {
        let accent = Theme.Palette.accent(for: .planner)
        ZStack {
            Circle().stroke(accent.opacity(0.22), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Theme.Motion.content, value: progress)
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
                .foregroundStyle(isFocused ? Theme.Palette.accent(for: .planner) : Theme.Palette.tertiaryText)
                .frame(width: 20)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Add a task…")
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
                        if withAnimation(Theme.Motion.snappy, { store.add(text) }) { text = "" }
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
                .strokeBorder(isFocused ? Theme.Palette.accent(for: .planner).opacity(0.5) : Theme.Palette.stroke,
                              lineWidth: isFocused ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = .add }
        .onHover { hovering = $0 }
        .help("Type a task and press Return to add it; Esc clears")
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.snappy, value: isFocused)
    }
}
