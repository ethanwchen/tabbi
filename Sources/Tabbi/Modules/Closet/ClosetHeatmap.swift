import SwiftUI
import TabbiKitCore
import TabbiKit

private var accent: Color { ClosetModule.descriptor.accentColor }

/// The Closet's first section: a GitHub-style chart of the days studied
/// (`StudyHeatmap`), a column per week ending with today, with the last 30
/// days' total and the best day above it, and the streak and a "Less ...
/// More" legend below. Hovering a day swaps the summary for that day's date
/// and time studied, at once and in place, so nothing flickers or clips.
struct ClosetHeatmapSection: View {
    @ObservedObject var store: ClosetStore
    @State private var hovered: StudyHeatmap.Day?

    var body: some View {
        let summary = StudyHeatmap(minutesByDay: store.milestones.minutesByDay, weeks: 1, today: .now)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            header(summary)
            ClosetHeatmapGrid(minutesByDay: store.milestones.minutesByDay, animatesIn: !store.isSnapshot,
                              hovered: $hovered)
            footer
        }
    }

    // MARK: Summary

    private func header(_ summary: StudyHeatmap) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            if let hovered {
                Text(date(hovered.key))
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(hovered.studiedLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(hovered.minutes > 0 ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
                    .monospacedDigit()
                Spacer(minLength: 0)
            } else if summary.bestDay == nil {
                ViewThatFits(in: .horizontal) {
                    Text("Every focused minute fills in today's square")
                    Text("Focus to fill in today's square")
                }
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Spacer(minLength: 0)
            } else {
                Text(DurationFormat.minutes(summary.lastThirtyDaysMinutes))
                    .font(Theme.Typography.bodyEmphasis.monospacedDigit())
                    .foregroundStyle(Theme.Palette.primaryText)
                    .contentTransition(.numericText())
                Text("in the last 30 days")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Spacer(minLength: Theme.Spacing.s)
                if let best = summary.bestDay {
                    Text("Best day \(DurationFormat.minutes(best.minutes))")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .help("Your most studied day: \(date(best.key, year: true))")
                }
            }
        }
        .lineLimit(1)
        .frame(height: 16)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        let streak = store.streak
        return HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(streak.isActive ? accent : Theme.Palette.tertiaryText)
            Text(streakText(streak))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .monospacedDigit()
            Spacer(minLength: Theme.Spacing.s)
            ClosetHeatmapLegend()
        }
        .frame(height: 12)
        .help("Your study streak: days in a row with at least \(Int(PetMilestoneProgress.minutesForStudyDay)) focused minutes")
    }

    private func streakText(_ streak: StudyStreak) -> String {
        guard streak.isActive else { return "No streak yet" }
        return streak.length == 1 ? "1-day streak" : "\(streak.length)-day streak"
    }

    private func date(_ key: PlannerDayKey, year: Bool = false) -> String {
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        return key.startDate().formatted(year ? style.year() : style)
    }
}

// MARK: - Grid

/// The chart's cells: as many week columns as fit the width, sized to the
/// height, each column fading in a moment after the one before it when the
/// section appears, and today's cell pulsing when a session moves it up a
/// level. Both stay still under Reduce Motion.
private struct ClosetHeatmapGrid: View {
    let minutesByDay: [PlannerDayKey: Double]
    let animatesIn: Bool
    @Binding var hovered: StudyHeatmap.Day?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    /// Room between cells, as on GitHub.
    private let gap: CGFloat = 2
    /// The largest cell, so a roomy panel shows more weeks, not huge squares.
    private let maxCell: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fitted = min(maxCell, max(4, (size.height - 6 * gap) / 7))
            let count = max(1, Int((size.width + gap) / (fitted + gap)))
            // The columns fill the width exactly, so the grid lines up with
            // the summary and legend at both edges.
            let cell = min(fitted, (size.width - CGFloat(count - 1) * gap) / CGFloat(count))
            let heatmap = StudyHeatmap(minutesByDay: minutesByDay, weeks: count, today: .now)
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(heatmap.weeks.enumerated()), id: \.element.id) { index, week in
                    column(week, cell: cell)
                        .opacity(revealed || !animatesIn ? 1 : 0)
                        .animation(entrance(index), value: revealed)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = day(at: point, in: heatmap, cell: cell)
                case .ended: hovered = nil
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { revealed = true }
        .onDisappear { hovered = nil }
    }

    private func column(_ week: StudyHeatmap.Week, cell: CGFloat) -> some View {
        VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                if let day = week.days[row] {
                    ClosetHeatmapCell(day: day, size: cell, isHovered: hovered?.key == day.key)
                } else {
                    Color.clear.frame(width: cell, height: cell)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weekLabel(week))
    }

    /// The day under the pointer, from one hover area over the whole grid,
    /// so moving between cells never flickers through "no day".
    private func day(at point: CGPoint, in heatmap: StudyHeatmap, cell: CGFloat) -> StudyHeatmap.Day? {
        let pitch = cell + gap
        let column = Int(point.x / pitch), row = Int(point.y / pitch)
        guard point.x >= 0, point.y >= 0, heatmap.weeks.indices.contains(column), (0..<7).contains(row) else {
            return hovered
        }
        return heatmap.weeks[column].days[row] ?? hovered
    }

    private func entrance(_ index: Int) -> Animation? {
        guard animatesIn, Motion.pace.isAnimated(reduceMotion: reduceMotion) else { return nil }
        return .easeOut(duration: Motion.pace.duration(MotionTokens.contentFadeIn))
            .delay(Motion.pace.duration(MotionTokens.stagger(index, step: 0.012, cap: 0.36)))
    }

    private func weekLabel(_ week: StudyHeatmap.Week) -> String {
        let start = week.start.startDate().formatted(.dateTime.month(.wide).day())
        guard week.minutes > 0 else { return "Week of \(start): no study" }
        let days = week.studiedDays == 1 ? "1 day" : "\(week.studiedDays) days"
        return "Week of \(start): \(DurationFormat.minutes(week.minutes)) studied over \(days)"
    }
}

/// One day's square, shaded by its level, outlined while hovered and, more
/// faintly, when it is today.
private struct ClosetHeatmapCell: View {
    let day: StudyHeatmap.Day
    let size: CGFloat
    let isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        shape
            .fill(ClosetHeatmapLevel.color(day.level))
            .overlay {
                if isHovered {
                    shape.strokeBorder(Theme.Palette.primaryText.opacity(0.9), lineWidth: 1)
                } else if day.isToday {
                    shape.strokeBorder(Theme.Palette.primaryText.opacity(0.45), lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
            // Today moving up a level after a session: a quick swell.
            .keyframeAnimator(initialValue: 1.0, trigger: day.isToday && !reduceMotion ? day.level : 0) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.45, duration: 0.18, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.32, spring: .bouncy)
            }
            .motion(Theme.Motion.snappy, value: day.level)
    }
}

/// The shades: a faint square for no study, then four steps of the Closet's
/// warm amber.
private enum ClosetHeatmapLevel {
    static func color(_ level: Int) -> Color {
        switch level {
        case ...0: Theme.Palette.primaryText.opacity(0.07)
        case 1: accent.opacity(0.28)
        case 2: accent.opacity(0.5)
        case 3: accent.opacity(0.75)
        default: accent
        }
    }
}

/// "Less", a square of each shade, "More", like GitHub's key.
private struct ClosetHeatmapLegend: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Text("Less").padding(.trailing, Theme.Spacing.xxs)
            ForEach(0..<StudyHeatmap.levelCount, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ClosetHeatmapLevel.color(level))
                    .frame(width: 8, height: 8)
            }
            Text("More").padding(.leading, Theme.Spacing.xxs)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.tertiaryText)
        .help("No study, under \(StudyHeatmap.levelThresholds[0]) min, under \(StudyHeatmap.levelThresholds[1]) min, "
              + "under \(StudyHeatmap.levelThresholds[2]) min, and \(StudyHeatmap.levelThresholds[2]) min or more")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Darker squares mean more time studied")
    }
}
