import SwiftUI
import TabbiKitCore
import TabbiKit

/// The header's day title between two small arrows that step to yesterday
/// and tomorrow. Clicking the title of another day goes back to today. An
/// arrow with nowhere to go stays in place, dimmed, so the title never shifts.
/// Today steps its checklist with it and Schedule its Day view.
struct DayStepper<Title: View>: View {
    let viewing: PlannerViewedDay
    /// Tooltips of the arrows that leave today, naming what they show.
    var yesterdayHelp = "Show yesterday's list"
    var tomorrowHelp = "Plan tomorrow"
    let show: (PlannerViewedDay) -> Void
    @ViewBuilder var title: Title

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            arrow("chevron.left", to: viewing.previous, help: yesterdayHelp)
            if viewing == .today {
                title
            } else {
                Button { step(to: .today) } label: { title }
                    .buttonStyle(.plain)
                    .help("Back to today")
            }
            arrow("chevron.right", to: viewing.next, help: tomorrowHelp)
        }
    }

    private func arrow(_ symbol: String, to day: PlannerViewedDay?, help: String) -> some View {
        DayStepArrow(symbol: symbol, help: day == .today ? "Back to today" : help) {
            if let day { step(to: day) }
        }
        .disabled(day == nil)
    }

    private func step(to day: PlannerViewedDay) {
        withMotion(Theme.Motion.snappy) { show(day) }
    }
}

/// A chevron with a round hover background, quieter than `IconButton` so it
/// reads as part of the title.
private struct DayStepArrow: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .opacity(isEnabled ? 1 : 0.35)
                .frame(width: 16, height: 20)
                .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isEnabled ? help : "")
        .onHover { hovering = $0 && isEnabled }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// Yesterday's bottom row: one click moves every unfinished task that isn't
/// on today's list yet, or a quiet note once there's nothing left to move.
struct PlannerLeftoversBar: View {
    @ObservedObject var store: PlannerStore

    var body: some View {
        let count = store.leftovers.count
        HStack(spacing: Theme.Spacing.s) {
            if count > 0 {
                Text(count == 1 ? "1 task left unfinished" : "\(count) tasks left unfinished")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                PlannerPillButton(title: "Move to today", symbol: "arrow.uturn.forward", isProminent: true,
                                  height: 28, help: "Add the unfinished tasks to the end of today's list") {
                    withMotion(Theme.Motion.snappy) { store.moveToToday() }
                }
                .transition(.motionPop)
            } else if !store.items.isEmpty {
                Label(store.shownDay.doneCount == store.items.count ? "All done" : "Everything unfinished is on today",
                      systemImage: "checkmark.circle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        // Text lines up with the header; the pill ends flush like the add row's.
        .padding(.leading, Theme.Spacing.s)
        .frame(height: 28)
        .motion(Theme.Motion.snappy, value: count)
    }
}
