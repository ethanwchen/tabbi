import SwiftUI
import NotchDeckCore

/// The Today panel: a header with the date and progress, today's checklist,
/// and an add field. Keeps the notch pinned open while any field is focused
/// so it doesn't close under the cursor mid-typing.
struct PlannerPanel: View {
    @ObservedObject var store: PlannerStore
    @EnvironmentObject private var notch: NotchViewModel
    @FocusState private var focus: PlannerField?

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            PlannerHeader(store: store)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if store.canEdit {
                PlannerAddField(store: store, focus: $focus)
            }
        }
        .onAppear { store.refreshDay() }
        .onChange(of: focus) { _, field in notch.isPinned = field != nil }
        .onDisappear { notch.isPinned = false }
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

private struct PlannerMessage: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
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
