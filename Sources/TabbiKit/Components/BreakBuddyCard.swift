import SwiftUI
import TabbiKitCore

/// The break buddy's card: the pet modeling a short break move inside a
/// ring that fills as the moment passes, what to do in a line or two, and
/// Done and Skip. With the water tally on, a chip shows today's glasses and
/// logs another one.
///
/// Presentational: the host (Study's or Focus' panel) hands it the moment,
/// the pet to draw and what each button does, and shows it in place of its
/// timer while the moment lasts. Skipping is always fine and nothing counts
/// against the user, so Skip is as plain as Done.
///
/// VoiceOver reads the move and its time left as one element, with the
/// line on how to do it as the hint, and the buttons on their own. The
/// countdown redraws once a second but is never announced on its own.
public struct BreakBuddyCard: View {
    let moment: BreakMoment
    @ObservedObject var pet: PetPlayer
    /// The pet's name for the lines, or nil (`BreakMove.buddyName(for:)`).
    let petName: String?
    let accent: Color
    /// Today's glasses of water, or nil when the water tally is off.
    let water: Int?
    /// True once Done was pressed, while the pet does its happy hop.
    let isFinishing: Bool
    let done: () -> Void
    let skip: () -> Void
    let addWater: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(moment: BreakMoment, pet: PetPlayer, petName: String?, accent: Color, water: Int?,
                isFinishing: Bool = false, done: @escaping () -> Void, skip: @escaping () -> Void,
                addWater: @escaping () -> Void) {
        self.moment = moment
        self.pet = pet
        self.petName = petName
        self.accent = accent
        self.water = water
        self.isFinishing = isFinishing
        self.done = done
        self.skip = skip
        self.addWater = addWater
    }

    /// Points per sprite pixel: a 96 pt pet, big enough to copy its move.
    static let petPixelSize: CGFloat = 3
    static let ringSize: CGFloat = 128
    static let ringWidth: CGFloat = 5

    private var title: String { moment.move.title(petName: petName) }

    public var body: some View {
        Card {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                ring
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    // A short panel (Compact, or a long translation) drops
                    // the how-to line before anything would be cut off; the
                    // ring's hint still reads it to VoiceOver.
                    ViewThatFits(in: .vertical) {
                        words(showsPrompt: true)
                        words(showsPrompt: false)
                    }
                    Spacer(minLength: 0)
                    buttons
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The pet inside the ring, with the move and its time left as one
    /// VoiceOver element.
    private var ring: some View {
        TimelineView(BreakCountdownSchedule(endsAt: moment.endsAt)) { context in
            ProgressRing(progress: moment.progress(at: context.date), tint: accent, lineWidth: Self.ringWidth) {
                PetView(player: pet, pixelSize: Self.petPixelSize)
                    // The sprite's art sits low in its frame (room for hops
                    // above), so lift it to look centered in the ring.
                    .offset(y: -Theme.Spacing.s)
            }
            .frame(width: Self.ringSize, height: Self.ringSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(title), \(TickerFormat.breakCountdown(moment.remaining(at: context.date))) left",
                                       bundle: .tabbi))
            .accessibilityHint(moment.move.prompt)
        }
        .help(title)
    }

    private func words(showsPrompt: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xs) {
                Label {
                    Text("Break buddy", bundle: .tabbi)
                } icon: {
                    Image(systemName: moment.move.symbol)
                        .font(.system(size: 9, weight: .semibold))
                }
                .labelStyle(BreakBuddyLabelStyle())
                .foregroundStyle(Theme.Palette.tertiaryText)
                .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                TimelineView(BreakCountdownSchedule(endsAt: moment.endsAt)) { context in
                    Text(TickerFormat.breakCountdown(moment.remaining(at: context.date)))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .fixedSize()
                }
            }
            .font(Theme.Typography.caption)
            .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            if showsPrompt {
                Text(moment.move.prompt)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let water {
                BreakWaterChip(count: water, tint: accent, action: addWater)
            }
            Spacer(minLength: 0)
            BreakCardButton(title: String(localized: "Skip", bundle: .tabbi), symbol: nil, tint: accent, isPrimary: false,
                            help: String(localized: "Skip this one; nothing is counted", bundle: .tabbi), action: skip)
            BreakCardButton(title: String(localized: "Done", bundle: .tabbi), symbol: "checkmark", tint: accent, isPrimary: true,
                            help: doneHelp, action: done)
        }
        .disabled(isFinishing)
        .opacity(isFinishing ? 0.5 : 1)
        .animation(Motion.adapted(Theme.Motion.snappy, reduceMotion: reduceMotion), value: isFinishing)
    }
}

private extension BreakBuddyCard {
    var doneHelp: String {
        if let petName { return String(localized: "Did it with \(petName)", bundle: .tabbi) }
        return String(localized: "Did it", bundle: .tabbi)
    }
}

/// A small icon tucked close to its text.
private struct BreakBuddyLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            configuration.icon
            configuration.title
        }
    }
}

/// Done (filled with the accent) or Skip (a quiet surface): a capsule
/// button with a hover state.
private struct BreakCardButton: View {
    let title: String
    let symbol: String?
    let tint: Color
    let isPrimary: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(Theme.Typography.bodyEmphasis)
                    .fixedSize()
            }
            .foregroundStyle(isPrimary ? Theme.Palette.background : Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: 28)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(.tactile(.pill))
        .help(help)
        .accessibilityHint(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private var background: Color {
        if isPrimary { return tint.opacity(hovering ? 1 : 0.88) }
        return hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface
    }
}

/// Today's glasses of water as a drop and a number; a click logs another.
private struct BreakWaterChip: View {
    let count: Int
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(count, format: .number)
                    .font(Theme.Typography.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.primaryText)
                    .contentTransition(.numericText())
                    .fixedSize()
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hovering ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 28)
            .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.tactile(.pill))
        .help(String(localized: "Log a glass of water", bundle: .tabbi))
        .accessibilityLabel(String(localized: "\(count) glasses of water today", bundle: .tabbi))
        .accessibilityHint(String(localized: "Log a glass of water", bundle: .tabbi))
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.content, value: count)
    }
}

/// The break moment's clock: the time left, digits only, redrawn once a
/// second (`BreakCountdownSchedule`). The closed notch shows it beside the
/// pet while it models a move.
public struct BreakCountdownText: View {
    let moment: BreakMoment

    public init(moment: BreakMoment) {
        self.moment = moment
    }

    public var body: some View {
        TimelineView(BreakCountdownSchedule(endsAt: moment.endsAt)) { context in
            Text(TickerFormat.breakCountdown(moment.remaining(at: context.date)))
                .fixedSize()
        }
    }
}

/// Redraws exactly when a countdown to `endsAt` (whole seconds, rounded up)
/// shows a new time, a hair late so rounding can't show the old one, and
/// stops once it runs out, so a countdown costs one redraw a second.
public struct BreakCountdownSchedule: TimelineSchedule {
    let endsAt: Date
    private static let lag: TimeInterval = 0.001

    public init(endsAt: Date) {
        self.endsAt = endsAt
    }

    public func entries(from startDate: Date, mode: Mode) -> AnyIterator<Date> {
        var next: Date? = startDate
        let endsAt = endsAt
        return AnyIterator {
            guard let date = next else { return nil }
            let left = endsAt.timeIntervalSince(date)
            next = left > 0 ? endsAt.addingTimeInterval(-(left.rounded(.up) - 1) + Self.lag) : nil
            return date
        }
    }
}
