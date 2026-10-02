import SwiftUI
import NotchDeckCore

/// Today's items. Scrolls only once they outgrow the canvas. Rows reorder by
/// dragging: the others slide aside live and the move is saved on release.
struct PlannerList: View {
    static let rowHeight: CGFloat = 22
    private static let fadeHeight = Theme.Spacing.m

    @ObservedObject var store: PlannerStore
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
            ScrollView(.vertical) { rows }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
                // Fade the bottom edge so a cut-off row reads as "more below",
                // with a matching margin so the last row can scroll clear of it.
                .contentMargins(.bottom, Self.fadeHeight, for: .scrollContent)
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

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                let isDragged = drag?.id == item.id
                PlannerRow(item: item, store: store, focus: focus, isLifted: isDragged)
                    .offset(y: offset(at: index))
                    .zIndex(isDragged ? 1 : 0)
                    .animation(isDragged ? nil : Theme.Motion.snappy, value: drag)
                    .gesture(reorderGesture(for: item, at: index))
            }
        }
        .animation(Theme.Motion.snappy, value: store.items.map(\.id))
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
                withAnimation(Theme.Motion.snappy) {
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
                withAnimation(Theme.Motion.snappy) { store.toggle(item.id) }
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

            if !isRenaming {
                PlannerFocusToggle(item: item, focusStore: store.focus,
                                   showsButton: hovering && store.canEdit)
            }

            if hovering, !isRenaming, store.canEdit {
                PlannerDeleteButton {
                    withAnimation(Theme.Motion.snappy) { store.delete(item.id) }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
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
        .animation(Theme.Motion.snappy, value: hovering)
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

/// Round checkbox that springs a checkmark in, filled with the module accent.
private struct PlannerCheckbox: View {
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let accent = Theme.Palette.accent(for: .planner)
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(hovering ? accent : Theme.Palette.tertiaryText, lineWidth: 1.5)
                    .opacity(isOn ? 0 : 1)
                Circle()
                    .fill(accent)
                    .scaleEffect(isOn ? 1 : 0.4)
                    .opacity(isOn ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Theme.Palette.background)
                    .scaleEffect(isOn ? 1 : 0.2)
                    .opacity(isOn ? 1 : 0)
            }
            .frame(width: 16, height: 16)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Mark as not done" : "Mark as done")
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isOn)
        .animation(Theme.Motion.snappy, value: hovering)
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
        let accent = Theme.Palette.accent(for: .planner)
        Group {
            if showsButton, isLinked || !item.isDone {
                Button {
                    withAnimation(Theme.Motion.snappy) {
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
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .animation(Theme.Motion.snappy, value: hovering)
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
        .animation(Theme.Motion.snappy, value: hovering)
    }
}
