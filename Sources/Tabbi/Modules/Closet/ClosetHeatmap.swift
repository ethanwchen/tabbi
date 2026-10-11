import SwiftUI
import TabbiKitCore
import TabbiKit

private var accent: Color { ClosetModule.descriptor.accentColor }

/// The Closet's first section: a GitHub-style chart of the days studied
/// (`StudyHeatmap`), a column per week ending with today, with the last 30
/// days' total and the streak above it and a "More ... Less" key beside it.
/// The panel is wide but short, so everything but the chart shares one row
/// or sits to its side, leaving the squares the height to reach GitHub's
/// size. Hovering a day swaps the total for that day's date and time
/// studied, at once and in place, so nothing flickers or clips.
struct ClosetHeatmapSection: View {
    @ObservedObject var store: ClosetStore
    @State private var hovered: StudyHeatmap.Day?

    var body: some View {
        let summary = StudyHeatmap(minutesByDay: store.milestones.minutesByDay, weeks: 1, today: .now)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            header(summary)
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                ClosetHeatmapGrid(minutesByDay: store.milestones.minutesByDay, animatesIn: !store.isSnapshot,
                                  hovered: $hovered)
                ClosetHeatmapLegend()
                    .fixedSize()
                    .padding(.top, ClosetHeatmapGrid.monthRow + ClosetHeatmapGrid.monthGap)
            }
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
                    Text("Every focused minute fills in today's square", bundle: .tabbi)
                    Text("Focus to fill in today's square", bundle: .tabbi)
                }
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Spacer(minLength: 0)
            } else {
                // Longer languages ("in den letzten 30 Tagen") would cut the
                // caption off, so the streak first shortens to its flame and
                // count, and only then does the caption step aside.
                ViewThatFits(in: .horizontal) {
                    totalRow(summary, caption: true, shortStreak: false)
                    totalRow(summary, caption: true, shortStreak: true)
                    totalRow(summary, caption: false, shortStreak: false)
                }
            }
            if hovered != nil || summary.bestDay == nil {
                streakLabel(short: false)
            }
        }
        .lineLimit(1)
        .frame(height: 16)
        .help(bestDayHelp(summary))
        .accessibilityElement(children: .combine)
    }

    /// The last 30 days' total, its caption and the streak, at one width.
    private func totalRow(_ summary: StudyHeatmap, caption: Bool, shortStreak: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text(DurationFormat.minutes(summary.lastThirtyDaysMinutes))
                .font(Theme.Typography.bodyEmphasis.monospacedDigit())
                .foregroundStyle(Theme.Palette.primaryText)
                .contentTransition(.numericText())
            if caption {
                Text("in the last 30 days", bundle: .tabbi)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Spacer(minLength: Theme.Spacing.s)
            streakLabel(short: shortStreak)
        }
    }

    /// The streak with its flame; `short` keeps only the count, for the
    /// rare row too narrow for the words (the tooltip still says them).
    private func streakLabel(short: Bool) -> some View {
        let streak = store.streak
        return HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(streak.isActive ? accent : Theme.Palette.tertiaryText)
            Text(short && streak.isActive ? String(streak.length) : streakText(streak))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .monospacedDigit()
        }
        .fixedSize()
        .help(String(localized: "Your study streak: days in a row with at least \(Int(PetMilestoneProgress.minutesForStudyDay)) focused minutes", bundle: .tabbi))
    }

    private func bestDayHelp(_ summary: StudyHeatmap) -> String {
        guard hovered == nil, let best = summary.bestDay else { return "" }
        return String(localized: "Best day \(DurationFormat.minutes(best.minutes))", bundle: .tabbi) + " · "
            + String(localized: "Your most studied day: \(date(best.key, year: true))", bundle: .tabbi)
    }

    private func streakText(_ streak: StudyStreak) -> String {
        guard streak.isActive else { return String(localized: "No streak yet", bundle: .tabbi) }
        return String(localized: "\(streak.length)-day streak", bundle: .tabbi)
    }

    private func date(_ key: PlannerDayKey, year: Bool = false) -> String {
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        return key.startDate().formatted(year ? style.year() : style)
    }
}

// MARK: - Grid

/// The chart, laid out like GitHub's: squares a little taller than the
/// labels with gaps three tenths of a square, month names over the columns
/// where a month starts and Monday, Wednesday and Friday beside their rows,
/// both small and muted. The squares take all the height there is, up to
/// GitHub's proportions at most, and as many weeks as fit the width follow. Each column fades in a moment after the one before it
/// when the section appears, and today's cell pulses when a session moves it
/// up a level. Both stay still under Reduce Motion.
private struct ClosetHeatmapGrid: View {
    let minutesByDay: [PlannerDayKey: Double]
    let animatesIn: Bool
    @Binding var hovered: StudyHeatmap.Day?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    /// GitHub's gap, as a share of a cell (3 points beside a 10 point square).
    private let gapRatio: CGFloat = 0.3
    /// The largest cell, so the tallest panel still reads as GitHub's chart
    /// rather than a board of tiles.
    private let maxCell: CGFloat = 14
    /// The month names' row, and the space below it.
    static let monthRow: CGFloat = 10
    static let monthGap: CGFloat = 3
    private var monthRow: CGFloat { Self.monthRow }
    private var monthGap: CGFloat { Self.monthGap }
    /// The weekday names' column, and the space beside it. Left out when
    /// they would cost more than a few weeks.
    private let weekdayColumn: CGFloat = 20
    private let weekdayGap: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // Seven cells and six gaps of `gapRatio` fill the height, whole
            // points only so every square draws crisp.
            let cell = min(maxCell, max(4, ((size.height - monthRow - monthGap) / (7 + 6 * gapRatio)).rounded(.down)))
            let gap = max(2, (cell * gapRatio).rounded())
            let showsWeekdays = size.width >= 240
            let gridWidth = size.width - (showsWeekdays ? weekdayColumn + weekdayGap : 0)
            let count = max(1, Int((gridWidth + gap) / (cell + gap)))
            let grid = Metrics(cell: cell, gap: gap)
            let heatmap = StudyHeatmap(minutesByDay: minutesByDay, weeks: count, today: .now)
            // With the weekday names on the left, the grid ends at the right
            // edge, so both edges line up with the summary and the legend.
            HStack(alignment: .top, spacing: 0) {
                if showsWeekdays {
                    weekdayLabels(heatmap, pitch: grid.rowPitch)
                        .padding(.top, monthRow + monthGap)
                    Spacer(minLength: weekdayGap)
                }
                VStack(alignment: .leading, spacing: monthGap) {
                    monthLabels(heatmap, grid: grid)
                    cells(heatmap, grid: grid)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
        .onAppear { revealed = true }
        .onDisappear { hovered = nil }
    }

    /// A cell's side and the room between cells.
    private struct Metrics {
        let cell: CGFloat
        let gap: CGFloat
        var columnPitch: CGFloat { cell + gap }
        var rowPitch: CGFloat { cell + gap }
    }

    private func cells(_ heatmap: StudyHeatmap, grid: Metrics) -> some View {
        HStack(alignment: .top, spacing: grid.columnPitch - grid.cell) {
            ForEach(Array(heatmap.weeks.enumerated()), id: \.element.id) { index, week in
                column(week, grid: grid)
                    .opacity(revealed || !animatesIn ? 1 : 0)
                    .animation(entrance(index), value: revealed)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hovered = day(at: point, in: heatmap, grid: grid)
            case .ended: hovered = nil
            }
        }
    }

    /// Each month's short name over its first column, leaving out those
    /// that would run into the next one.
    private func monthLabels(_ heatmap: StudyHeatmap, grid: Metrics) -> some View {
        let pitch = grid.columnPitch
        let width = CGFloat(heatmap.weeks.count) * pitch - (pitch - grid.cell)
        return ZStack(alignment: .topLeading) {
            ForEach(heatmap.monthLabels(minimumWeeks: Int((26 / pitch).rounded(.up))), id: \.week) { label in
                Text(label.start.startDate().formatted(.dateTime.month(.abbreviated)))
                    .fixedSize()
                    .offset(x: CGFloat(label.week) * pitch)
            }
        }
        .font(ClosetHeatmapLabel.font)
        .foregroundStyle(Theme.Palette.secondaryText)
        .frame(width: width, height: monthRow, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// "Mon", "Wed" and "Fri" beside their rows, in the locale's names.
    private func weekdayLabels(_ heatmap: StudyHeatmap, pitch: CGFloat) -> some View {
        let symbols = Calendar.current.shortWeekdaySymbols
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(heatmap.weekdays.enumerated()), id: \.offset) { _, weekday in
                Text(StudyHeatmap.labeledWeekdays.contains(weekday) ? symbols[weekday - 1] : "")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: weekdayColumn, height: pitch, alignment: .leading)
            }
        }
        .font(ClosetHeatmapLabel.font)
        .foregroundStyle(Theme.Palette.secondaryText)
        .accessibilityHidden(true)
    }

    private func column(_ week: StudyHeatmap.Week, grid: Metrics) -> some View {
        let cell = grid.cell
        return VStack(spacing: grid.gap) {
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
    private func day(at point: CGPoint, in heatmap: StudyHeatmap, grid: Metrics) -> StudyHeatmap.Day? {
        let column = Int(point.x / grid.columnPitch), row = Int(point.y / grid.rowPitch)
        guard point.x >= 0, point.y >= 0, heatmap.weeks.indices.contains(column), (0..<7).contains(row) else {
            return hovered
        }
        return heatmap.weeks[column].days[row] ?? hovered
    }

    private func entrance(_ index: Int) -> Animation? {
        guard animatesIn, Motion.pace.isAnimated(reduceMotion: reduceMotion) else { return nil }
        return .easeOut(duration: Motion.pace.duration(MotionTokens.contentFadeIn))
            .delay(Motion.pace.duration(MotionTokens.stagger(index, step: 0.01, cap: 0.36)))
    }

    private func weekLabel(_ week: StudyHeatmap.Week) -> String {
        let start = week.start.startDate().formatted(.dateTime.month(.wide).day())
        guard week.minutes > 0 else { return String(localized: "Week of \(start): no study", bundle: .tabbi) }
        let days = String(localized: "\(week.studiedDays) days", bundle: .tabbi)
        return String(localized: "Week of \(start): \(DurationFormat.minutes(week.minutes)) studied over \(days)", bundle: .tabbi)
    }
}

/// The month and weekday names' type: small and muted, like GitHub's.
private enum ClosetHeatmapLabel {
    static var font: Font { .system(size: 9, weight: .medium, design: Theme.Typography.design) }
}

/// One day's square, shaded by its level, outlined while hovered and, more
/// faintly, when it is today.
private struct ClosetHeatmapCell: View {
    let day: StudyHeatmap.Day
    let size: CGFloat
    let isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(2, size * 0.25), style: .continuous)
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

/// GitHub's "Less ... More" key, stood on end beside the chart: "More" over
/// the darkest square down to "Less" under the faintest, in the month
/// names' small type.
private struct ClosetHeatmapLegend: View {
    static let cell: CGFloat = 8

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text("More", bundle: .tabbi).padding(.bottom, Theme.Spacing.xxs)
            ForEach((0..<StudyHeatmap.levelCount).reversed(), id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ClosetHeatmapLevel.color(level))
                    .frame(width: ClosetHeatmapLegend.cell, height: ClosetHeatmapLegend.cell)
            }
            Text("Less", bundle: .tabbi).padding(.top, Theme.Spacing.xxs)
        }
        .font(ClosetHeatmapLabel.font)
        .lineLimit(1)
        .foregroundStyle(Theme.Palette.tertiaryText)
        .help(String(localized: "No study, under \(StudyHeatmap.levelThresholds[0]) min, under \(StudyHeatmap.levelThresholds[1]) min, under \(StudyHeatmap.levelThresholds[2]) min, and \(StudyHeatmap.levelThresholds[2]) min or more", bundle: .tabbi))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Darker squares mean more time studied", bundle: .tabbi))
    }
}
