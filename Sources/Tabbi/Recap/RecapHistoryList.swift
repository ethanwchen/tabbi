import SwiftUI
import TabbiKit
import TabbiKitCore

/// The past weekly recaps as a tiny list, newest first: each week's dates
/// and hours focused, a star on the best one. Clicking a week shows its
/// card in the open notch again. Lives in the Closet beside the pet.
struct RecapHistoryList: View {
    @ObservedObject var store: RecapStore
    var calendar: Calendar = .current

    var body: some View {
        let recaps = store.archive.recaps
        if recaps.isEmpty {
            RecapHistoryEmpty()
        } else {
            let best = recaps.map(\.focusMinutes).max() ?? 0
            let rows = VStack(spacing: Theme.Spacing.xxs) {
                ForEach(recaps, id: \.week) { recap in
                    RecapHistoryRow(recap: recap, calendar: calendar,
                                    isBest: recaps.count > 1 && best > 0 && recap.focusMinutes == best) {
                        store.reopen(recap)
                    }
                }
            }
            // Two years of weeks scroll. `ImageRenderer` draws a `ScrollView`
            // blank, so snapshots show the top rows clipped instead.
            Group {
                if RunMode.current.isSnapshot {
                    Color.clear.overlay(alignment: .top) { rows }.clipped()
                } else {
                    ScrollView(.vertical) { rows }
                        .scrollIndicators(.automatic)
                        .scrollBounceBehavior(.basedOnSize)
                }
            }
            .edgeFade(.bottom)
        }
    }
}

/// One past week: its dates, its hours focused and a chevron to open it.
private struct RecapHistoryRow: View {
    let recap: WeeklyRecap
    let calendar: Calendar
    let isBest: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let title = recap.week.title(calendar: calendar)
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Text(title)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                if isBest {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Palette.accent(RecapCard.accent))
                        .help("Your best week")
                }
                Spacer(minLength: Theme.Spacing.s)
                Text(DurationFormat.minutes(recap.focusMinutes))
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(hovering ? Theme.Palette.surfaceHover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Open your recap for \(title)")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// Before the first Sunday evening: what will show up here, and when.
private struct RecapHistoryEmpty: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent(RecapCard.accent))
            Text("Your first recap arrives Sunday evening.")
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
            Text("Each week you focus shows up here.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
