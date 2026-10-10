import AppKit
import SwiftUI
import TabbiKit
import TabbiKitCore

/// The weekly recap drawn as an image to post: the pet, the warm line, the
/// hours focused, the week's bars and numbers, signed with the Tabbi brand
/// and tabbinotch.com. Laid out for one `RecapShareFormat` in points; the
/// export draws it at `RecapShareFormat.scale`.
struct RecapShareImage: View {
    let recap: WeeklyRecap
    let cheer: RecapCheer
    /// The user's pet as it looks now; nil when the pet is turned off.
    let pet: PetProfile?
    let format: RecapShareFormat
    var calendar: Calendar = .current

    private var isStory: Bool { format == .story }
    private var padding: CGFloat { isStory ? 32 : Theme.Spacing.xl }
    private var accent: Color { Theme.Palette.accent(RecapCard.accent) }

    var body: some View {
        let size = format.pointSize
        VStack(spacing: 0) {
            header
            Spacer(minLength: Theme.Spacing.m)
            if isStory { storyHero } else { squareHero }
            Spacer(minLength: Theme.Spacing.m)
            daysCard
            Spacer(minLength: Theme.Spacing.m)
            RecapShareStats(stats: recap.stats(calendar: calendar),
                            columnWidth: (size.width - 2 * padding) / 3)
            Spacer(minLength: Theme.Spacing.m)
            Text(RecapShareFormat.website)
                .font(.system(size: 11, weight: .medium, design: Theme.Typography.design))
                .foregroundStyle(Theme.Palette.tertiaryText)
        }
        .padding(padding)
        .frame(width: size.width, height: size.height)
        .background(background)
        .environment(\.colorScheme, .dark)
    }

    /// The brand on the left, the week's dates on the right.
    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
            Text(RecapShareFormat.brandName)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.primaryText)
            Spacer(minLength: Theme.Spacing.s)
            Text(recap.week.title(calendar: calendar))
                .font(.system(size: 12, weight: .medium, design: Theme.Typography.design))
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
        }
    }

    /// Square: the pet beside the line and the hours.
    private var squareHero: some View {
        HStack(spacing: Theme.Spacing.l) {
            petOrSparkles(pixelSize: 3)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                cheerLine(size: 17)
                hours(size: 34)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Story: a big pet over the line and the hours, all centered.
    private var storyHero: some View {
        VStack(spacing: Theme.Spacing.m) {
            petOrSparkles(pixelSize: 5)
            cheerLine(size: 22)
                .multilineTextAlignment(.center)
            hours(size: 48)
        }
    }

    @ViewBuilder
    private func petOrSparkles(pixelSize: CGFloat) -> some View {
        if let pet {
            RecapPet(profile: pet, pixelSize: pixelSize)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 14 * pixelSize, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 32 * pixelSize, height: 32 * pixelSize)
        }
    }

    private func cheerLine(size: CGFloat) -> some View {
        Text(cheer.line)
            .font(.system(size: size, weight: .semibold, design: Theme.Typography.design))
            .foregroundStyle(Theme.Palette.primaryText)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func hours(size: CGFloat) -> some View {
        VStack(alignment: isStory ? .center : .leading, spacing: Theme.Spacing.xxs) {
            Text(DurationFormat.minutes(recap.focusMinutes))
                .font(.system(size: size, weight: .bold, design: Theme.Typography.design).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(pet.map { "focused with \($0.name)" } ?? "focused this week")
                .font(.system(size: 12, weight: .medium, design: Theme.Typography.design))
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
        }
    }

    private var daysCard: some View {
        Card(padding: Theme.Spacing.m) {
            RecapDayBars(recap: recap, calendar: calendar, accent: accent,
                         barWidth: isStory ? 18 : 14, maxHeight: isStory ? 72 : 40,
                         spacing: isStory ? Theme.Spacing.l : Theme.Spacing.m)
                .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Black like the notch, warming to gold at the bottom.
    private var background: some View {
        ZStack {
            Theme.Palette.background
            RadialGradient(colors: [accent.opacity(0.22), .clear],
                           center: .bottom, startRadius: 0, endRadius: format.pointSize.height * 0.8)
        }
    }
}

/// The week's other numbers, three to a row, so none is dropped. A short
/// last row stays centered on the same column width.
private struct RecapShareStats: View {
    let stats: [RecapStat]
    let columnWidth: CGFloat

    var body: some View {
        let rows = stride(from: 0, to: stats.count, by: 3).map { Array(stats[$0..<min($0 + 3, stats.count)]) }
        VStack(spacing: Theme.Spacing.m) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 0) {
                    ForEach(rows[index]) { stat in
                        VStack(spacing: Theme.Spacing.xxs) {
                            Text(stat.value)
                                .font(.system(size: 17, weight: .semibold, design: Theme.Typography.design)
                                    .monospacedDigit())
                                .foregroundStyle(Theme.Palette.primaryText)
                            Text(stat.label)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.tertiaryText)
                        }
                        .lineLimit(1)
                        .frame(width: columnWidth)
                    }
                }
            }
        }
    }
}

extension RecapShareImage {
    /// The image as PNG data at the format's full pixel size, or nil if it
    /// could not be drawn.
    @MainActor
    func png() -> Data? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = RecapShareFormat.scale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
