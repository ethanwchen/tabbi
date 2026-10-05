import SwiftUI
import TabbiKitCore
import TabbiKit

/// Today's items, after any rows other modules share. Scrolls only once they
/// outgrow the canvas. Checklist rows reorder by dragging: the others slide
/// aside live and the move is saved on release.
struct PlannerList: View {
    nonisolated static let rowHeight: CGFloat = 22
    private static let fadeHeight = Theme.Spacing.m

    @ObservedObject var store: PlannerStore
    /// Other modules' goals and tasks, shown first and not editable here.
    var shared: [SharedTodayItem] = []
    var focus: FocusState<PlannerField?>.Binding
    @State private var drag: RowDrag?

    /// A row being dragged and how far the pointer has moved.
    private struct RowDrag: Equatable {
        let id: PlannerItem.ID
        let from: Int
        var translation: CGFloat = 0

        func target(count: Int) -> Int {
            min(max(from + Int((translation / PlannerList.rowHeight).rounded()), 0), count - 1)
        }
    }

    var body: some View {
        // Plain stack while the rows fit, so nothing scrolls without need.
        ViewThatFits(in: .vertical) {
            rows
            scrollingRows
                // Fade the bottom edge so a cut-off row reads as "more below".
                .mask {
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.fadeHeight)
                    }
                }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// `ImageRenderer` draws a `ScrollView` blank, so snapshots show the
    /// top of an overflowing list clipped instead.
    private static var isSnapshot: Bool { RunMode.current.isSnapshot }

    @ViewBuilder
    private var scrollingRows: some View {
        if Self.isSnapshot {
            // Takes the space offered rather than the rows' full height.
            Color.clear
                .overlay(alignment: .top) { rows }
                .clipped()
        } else {
            ScrollView(.vertical) { rows }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
                // A margin as tall as the fade, so the last row can scroll clear of it.
                .contentMargins(.bottom, Self.fadeHeight, for: .scrollContent)
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(shared) { item in
                PlannerSharedRow(item: item)
            }
            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                let isDragged = drag?.id == item.id
                PlannerRow(item: item, store: store, focus: focus, isLifted: isDragged)
                    .offset(y: offset(at: index))
                    .zIndex(isDragged ? 1 : 0)
                    .animation(isDragged ? nil : Theme.Motion.snappy, value: drag)
                    .gesture(reorderGesture(for: item, at: index))
            }
        }
        .motion(Theme.Motion.snappy, value: store.items.map(\.id))
        .motion(Theme.Motion.snappy, value: shared)
    }

    /// The dragged row follows the pointer; rows between its old and new slot
    /// shift one row toward the gap.
    private func offset(at index: Int) -> CGFloat {
        guard let drag else { return 0 }
        if index == drag.from { return drag.translation }
        let target = drag.target(count: store.items.count)
        if drag.from < index, index <= target { return -Self.rowHeight }
        if target <= index, index < drag.from { return Self.rowHeight }
        return 0
    }

    private func reorderGesture(for item: PlannerItem, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard store.canEdit, focus.wrappedValue != .rename(item.id) else { return }
                if drag?.id != item.id { drag = RowDrag(id: item.id, from: index) }
                drag?.translation = value.translation.height
            }
            .onEnded { _ in
                guard let finished = drag else { return }
                let target = finished.target(count: store.items.count)
                withMotion(Theme.Motion.snappy) {
                    // Clear the offsets and apply the move together so rows settle in one motion.
                    drag = nil
                    if target != finished.from { store.move(finished.id, to: target) }
                }
            }
    }
}

/// One checklist row: checkbox, title (double-click to rename), and focus and
/// delete buttons that appear on hover. The focus target keeps a small scope
/// glyph so it's clear which task the timer is for.
private struct PlannerRow: View {
    let item: PlannerItem
    @ObservedObject var store: PlannerStore
    var focus: FocusState<PlannerField?>.Binding
    /// True while this row is being dragged to a new position.
    var isLifted = false
    @State private var hovering = false
    @State private var draft = ""
    /// Shows the rename field. Kept apart from focus because `FocusState`
    /// ignores a value until a field bound to it exists.
    @State private var isRenaming = false

    private var hasRenameFocus: Bool { focus.wrappedValue == .rename(item.id) }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            PlannerCheckbox(isOn: item.isDone) {
                withMotion(Theme.Motion.snappy) { store.toggle(item.id) }
            }
            .disabled(!store.canEdit)

            if isRenaming {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .focused(focus, equals: .rename(item.id))
                    .onAppear { focus.wrappedValue = .rename(item.id) }
                    .onSubmit { focus.wrappedValue = nil }
                    // Esc restores the title; the store ignores unchanged titles.
                    .onExitCommand { draft = item.title; focus.wrappedValue = nil }
            } else {
                Text(item.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(item.isDone ? Theme.Palette.secondaryText : Theme.Palette.primaryText)
                    .strikethrough(item.isDone, color: Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginRename() }
                    .help(item.title)
            }

            // Rows link to the Pomodoro, which isn't offered while another
            // module owns the timer.
            if !isRenaming, store.focusClockOwner == nil {
                PlannerFocusToggle(item: item, focusStore: store.focus,
                                   showsButton: hovering && store.canEdit)
            }

            if hovering, !isRenaming, store.canEdit {
                PlannerDeleteButton {
                    withMotion(Theme.Motion.snappy) { store.delete(item.id) }
                }
                .transition(.motionPop)
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: PlannerList.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(isLifted ? Theme.Palette.surfaceHover
                      : (hovering || isRenaming ? Theme.Palette.surface : .clear))
                .shadow(color: .black.opacity(isLifted ? 0.5 : 0), radius: 6, y: 2)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .onChange(of: hasRenameFocus) { hadFocus, hasFocus in
            // Every way out of the field (Return, Esc, clicking elsewhere) ends
            // here, so focus is cleared while the field still exists.
            if hadFocus, !hasFocus, isRenaming { commitRename() }
        }
    }

    private func beginRename() {
        guard store.canEdit else { return }
        draft = item.title
        isRenaming = true
    }

    /// Saves the draft once the field has lost focus. The store ignores blank
    /// or unchanged titles.
    private func commitRename() {
        isRenaming = false
        store.rename(item.id, to: draft)
        draft = ""
    }
}

/// A goal or task another module shares, pinned above the checklist, e.g.
/// "Anki reviews, 320 cards left". Its checkbox is a ring that fills in the
/// source module's accent as the work gets done and checks itself at zero,
/// since the work happens (and is counted) in that module, not here.
/// Clicking opens that module's tab and runs the item's one-click action,
/// if the module offered one (Anki opens the deck to study).
private struct PlannerSharedRow: View {
    let item: SharedTodayItem
    @EnvironmentObject private var notch: NotchViewModel
    @Environment(\.moduleCatalog) private var catalog
    @Environment(\.runModuleAction) private var runAction
    @State private var hovering = false

    private var help: String {
        let module = catalog.descriptor(for: item.source).title
        if let action = item.action { return "\(action.title) in \(module)" }
        return item.isDone ? "\(item.title) done for today. Open \(module)" : "Checks itself when done. Open \(module)"
    }

    var body: some View {
        Button {
            if let action = item.action { runAction(action, from: item.source) }
            notch.selected = item.source
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                PlannerSharedCheck(item: item)
                Text(item.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(item.isDone ? Theme.Palette.secondaryText : Theme.Palette.primaryText)
                    .strikethrough(item.isDone, color: Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail = item.detail {
                    Text(detail)
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
                    .frame(width: 12)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: PlannerList.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(hovering ? Theme.Palette.surface : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// The shared row's checkbox, the same size as `PlannerCheckbox`: the
/// source module's symbol inside a ring that fills with its progress, then
/// a filled check once the work is done.
private struct PlannerSharedCheck: View {
    let item: SharedTodayItem
    @Environment(\.moduleCatalog) private var catalog

    var body: some View {
        let source = catalog.descriptor(for: item.source)
        let accent = source.accentColor
        ZStack {
            Circle()
                .strokeBorder(accent.opacity(0.28), lineWidth: 1.5)
            Circle()
                .inset(by: 0.75)
                .trim(from: 0, to: item.fraction ?? 0)
                .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: source.symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(accent)
                .opacity(item.isDone ? 0 : 1)
            CheckGlyph(isOn: item.isDone, tint: accent, ring: nil)
        }
        .frame(width: 16, height: 16)
        .frame(width: 20, height: 20)
        .motion(Theme.Motion.content, value: item.fraction)
        .motion(Theme.Motion.snappy, value: item.isDone)
    }
}

/// Round checkbox whose check draws on with a small bounce, filled with the module accent.
private struct PlannerCheckbox: View {
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let accent = TodayModule.descriptor.accentColor
        Button(action: action) {
            CheckGlyph(isOn: isOn, tint: accent, ring: hovering ? accent : Theme.Palette.tertiaryText)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.tactile)
        .help(isOn ? "Mark as not done" : "Mark as done")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// The row's link to the focus timer. Observes `FocusStore` in its own view
/// so the timer's once-a-second tick doesn't re-render whole rows.
private struct PlannerFocusToggle: View {
    let item: PlannerItem
    @ObservedObject var focusStore: FocusStore
    /// True while the row is hovered and editable.
    let showsButton: Bool
    @State private var hovering = false

    private var isLinked: Bool { focusStore.timer.linkedItemID == item.id }

    var body: some View {
        let accent = TodayModule.descriptor.accentColor
        Group {
            if showsButton, isLinked || !item.isDone {
                Button {
                    withMotion(Theme.Motion.snappy) {
                        if isLinked { focusStore.link(nil) } else { focusStore.focus(on: item.id) }
                    }
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isLinked || hovering ? accent : Theme.Palette.tertiaryText)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(hovering ? accent.opacity(0.16) : .clear))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isLinked ? "Stop focusing on this task" : "Focus on this task")
                .onHover { hovering = $0 }
            } else if isLinked {
                Image(systemName: "scope")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 20, height: 20)
                    .help("The focus timer is on this task")
            }
        }
        .transition(.motionPop)
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

private struct PlannerDeleteButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? Theme.Palette.danger : Theme.Palette.tertiaryText)
                .frame(width: 20, height: 20)
                .background(Circle().fill(hovering ? Theme.Palette.danger.opacity(0.16) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Delete task")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}
