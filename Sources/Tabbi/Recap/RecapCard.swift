import SwiftUI
import TabbiKit
import TabbiKitCore

/// The weekly recap card: the pet in its current outfit beside the week's
/// hours focused, a bar per day, the other numbers that week had and one
/// warm line. Designed for the open notch's panel canvas.
struct RecapCard: View {
    let recap: WeeklyRecap
    let cheer: RecapCheer
    /// The user's pet as it looks now; nil when the pet is turned off.
    let pet: PetProfile?
    var calendar: Calendar = .current

    /// A warm gold, the color of a well-earned week.
    static let accent = ModuleAccent(red: 0.98, green: 0.80, blue: 0.30)

    var body: some View {
        let accent = Theme.Palette.accent(Self.accent)
        HStack(spacing: Theme.Spacing.s) {
            RecapPetBadge(pet: pet, week: recap.week.title(calendar: calendar))
                .frame(width: 112)
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(cheer.line)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: Theme.Spacing.m) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(DurationFormat.minutes(recap.focusMinutes))
                                .font(Theme.Typography.metric)
                                .foregroundStyle(accent)
                                .lineLimit(1)
                            Text("focused")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.tertiaryText)
                        }
                        Spacer(minLength: 0)
                        RecapDayBars(recap: recap, calendar: calendar, accent: accent)
                    }
                    Spacer(minLength: 0)
                    RecapStatsRow(stats: recap.stats(calendar: calendar))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The pet, standing still in its outfit, above the week's dates.
private struct RecapPetBadge: View {
    let pet: PetProfile?
    let week: String

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            VStack(spacing: Theme.Spacing.xs) {
                Spacer(minLength: 0)
                if let pet {
                    RecapPet(profile: pet)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent(RecapCard.accent))
                        .frame(width: 64, height: 64)
                }
                if let pet {
                    Text(pet.name)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(week)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The pet, awake and still (64 pt at the default pixel size), so the card
/// and its exported image match.
struct RecapPet: View {
    let profile: PetProfile
    var pixelSize: CGFloat = 2
    @StateObject private var player: PetPlayer

    init(profile: PetProfile, pixelSize: CGFloat = 2) {
        self.profile = profile
        self.pixelSize = pixelSize
        // A fixed seed keeps snapshots stable.
        _player = StateObject(wrappedValue: PetPlayer(profile: profile, seed: 7))
    }

    var body: some View {
        PetView(player: player, pixelSize: pixelSize)
            .onChange(of: profile) { _, profile in player.update(profile: profile) }
    }
}

/// One bar per day, Monday first, the best day in full accent.
struct RecapDayBars: View {
    let recap: WeeklyRecap
    let calendar: Calendar
    let accent: Color
    var barWidth: CGFloat = 10
    var maxHeight: CGFloat = 40
    var spacing: CGFloat = Theme.Spacing.s

    var body: some View {
        let initials = RecapWeek.dayInitials(calendar: calendar)
        let best = recap.minutesByDay.max() ?? 0
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(0..<7, id: \.self) { index in
                let minutes = recap.minutesByDay[index]
                // Days tied for the best all light up.
                let isBest = best > 0 && minutes == best
                VStack(spacing: Theme.Spacing.xs) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isBest ? accent
                              : minutes > 0 ? accent.opacity(0.4) : Theme.Palette.stroke)
                        .frame(width: barWidth, height: height(minutes, best: best))
                    Text(initials[index])
                        .font(.system(size: 9, weight: .semibold, design: Theme.Typography.design))
                        .foregroundStyle(isBest ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
                }
                .help(DurationFormat.minutes(minutes))
            }
        }
    }

    /// Scaled to the week's best day; an empty day is a small stub.
    private func height(_ minutes: Int, best: Int) -> CGFloat {
        guard best > 0, minutes > 0 else { return 4 }
        return max(6, maxHeight * CGFloat(minutes) / CGFloat(best))
    }
}

/// The week's other numbers side by side, dropping the last ones on a
/// narrow panel rather than squeezing them.
private struct RecapStatsRow: View {
    let stats: [RecapStat]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: stats.count, through: 1, by: -1)), id: \.self) { count in
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(stats.prefix(count)) { stat in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(stat.value)
                                .font(Theme.Typography.metricSmall)
                                .foregroundStyle(Theme.Palette.primaryText)
                            Text(stat.label)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.tertiaryText)
                        }
                        .fixedSize()
                    }
                }
            }
        }
    }
}

/// The recap filling the open notch: "Your week" in the header, Done to
/// put it away, and the card in the panel canvas.
enum RecapViews {
    @MainActor
    static func takeover(recap: WeeklyRecap, cheer: RecapCheer, providers: ProviderHub,
                         done: @escaping () -> Void) -> NotchTakeover {
        NotchTakeover(
            leading: { AnyView(RecapTitle()) },
            trailing: { AnyView(RecapDoneButton(action: done)) },
            body: {
                AnyView(ModuleViews.StatusPetProvider(providers: providers) {
                    RecapMomentBody(recap: recap, cheer: cheer)
                })
            }
        )
    }
}

private struct RecapTitle: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent(RecapCard.accent))
            Text("Your week")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1)
        }
    }
}

private struct RecapDoneButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("Done")
                .font(Theme.Typography.caption)
                .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Put the recap away")
    }
}

private struct RecapMomentBody: View {
    let recap: WeeklyRecap
    let cheer: RecapCheer
    @Environment(\.statusPet) private var pet

    var body: some View {
        RecapCard(recap: recap, cheer: cheer, pet: pet)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
