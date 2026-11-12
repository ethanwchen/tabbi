import SwiftUI
import TabbiKitCore
import TabbiKit

private var accent: Color { ClosetModule.descriptor.accentColor }

/// The Study Level at the top of the Goals section: the rank's emblem, the
/// level and rank, a bar toward the next level ("230 of 242 h to Level
/// 13"), what the next unlock is, and the nameplate colors to pick from
/// (the locked ones wait, dimmed, with the level that brings them). Calm
/// on purpose: the level only ever grows, and it pays no points.
/// docs/design/progression.md explains the curve.
struct ClosetLevelCard: View {
    @ObservedObject var store: ClosetStore

    private var progression: PetProgression { store.progression }
    private var level: StudyLevel { progression.studyLevel }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            StudyRankEmblem(level.rank, pixelSize: 1.5)
                .padding(.top, Theme.Spacing.xxs)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                titleLine
                progressLine
                ClosetNameplatePicker(store: store)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.s - Theme.Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 0.5)
        )
        .help(help)
        .motion(Theme.Motion.content, value: level)
    }

    /// "Level 12 Ember", and what the next unlock is where it fits.
    private var titleLine: some View {
        HStack(spacing: Theme.Spacing.xs) {
            (Text(level.label).foregroundStyle(Theme.Palette.primaryText)
                + Text(verbatim: "  \(level.rank.displayName)").foregroundStyle(Theme.Palette.secondaryText))
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: Theme.Spacing.xs)
            ViewThatFits(in: .horizontal) {
                Text(nextUnlock(labeled: true)).fixedSize()
                Text(nextUnlock(labeled: false)).fixedSize()
                Color.clear.frame(width: 0, height: 0)
            }
            .font(Theme.Typography.caption.monospacedDigit())
            .foregroundStyle(Theme.Palette.tertiaryText)
            .lineLimit(1)
        }
    }

    /// The bar and the hours toward the next level, shortened to bare
    /// numbers before anything would be cut off.
    private var progressLine: some View {
        HStack(spacing: Theme.Spacing.s) {
            Capsule()
                .fill(Theme.Palette.surfaceHover)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(accent)
                            .frame(width: proxy.size.width * level.fraction(focusMinutes: progression.focusMinutes))
                    }
                }
                .frame(minWidth: 40, maxWidth: 96)
                .frame(height: 3)
            ViewThatFits(in: .horizontal) {
                Text(hoursLine(labeled: true)).fixedSize()
                Text(hoursLine(labeled: false)).fixedSize()
            }
            .font(Theme.Typography.caption.monospacedDigit())
            .foregroundStyle(Theme.Palette.secondaryText)
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var hoursDone: Int { progression.focusMinutes / 60 }
    private var hoursGoal: Int { StudyLevel.hoursToReach(level.value + 1) }

    /// "230 of 242 h to Level 13", or "230/242 h".
    private func hoursLine(labeled: Bool) -> String {
        labeled ? String(localized: "\(hoursDone) of \(hoursGoal) h to Level \(level.value + 1)", bundle: .tabbi)
            : String(localized: "\(hoursDone)/\(hoursGoal) h", bundle: .tabbi)
    }

    /// The next thing a level brings: a rank, or else a nameplate color,
    /// whichever comes first (the rank when both come together).
    private var next: (level: Int, name: String) {
        let rank = level.rank.next
        if let nameplate = Nameplate.next(after: level), nameplate.unlockLevel < rank.firstLevel {
            return (nameplate.unlockLevel, String(localized: "\(nameplate.displayName) name color", bundle: .tabbi))
        }
        return (rank.firstLevel, rank.displayName)
    }

    /// "Next: Comet at Lv 20", or "Lv 20: Comet".
    private func nextUnlock(labeled: Bool) -> String {
        let next = next
        return labeled ? String(localized: "Next: \(next.name) at Lv \(next.level)", bundle: .tabbi)
            : String(localized: "Lv \(next.level): \(next.name)", bundle: .tabbi)
    }

    private var help: String {
        Sentences.join([
            StudyLevelLabel.help(progression.standing),
            String(localized: "Your Study Level grows with every hour you focus and never goes down.", bundle: .tabbi),
            String(localized: "Every 5 levels bring a name color and every 10 a new rank. Levels never give points.",
                   bundle: .tabbi),
        ])
    }
}

/// The nameplate colors as small dots: the unlocked ones to click and
/// wear, the picked one ringed, the locked ones dimmed until their level.
private struct ClosetNameplatePicker: View {
    @ObservedObject var store: ClosetStore

    var body: some View {
        // All thirteen where they fit; then closer and smaller; and in the
        // narrowest card the unlocked ones and the next, so no dot is ever
        // pushed out of the card.
        ViewThatFits(in: .horizontal) {
            dots(Nameplate.allCases, size: 10, spacing: Theme.Spacing.xs)
            dots(Nameplate.allCases, size: 10, spacing: Theme.Spacing.xxs)
            dots(Nameplate.allCases, size: 8, spacing: Theme.Spacing.xxs)
            dots(reachable, size: 8, spacing: Theme.Spacing.xxs)
        }
    }

    /// The unlocked colors and the next one to come.
    private var reachable: [Nameplate] {
        let level = store.progression.studyLevel
        return Nameplate.unlocked(at: level) + [Nameplate.next(after: level)].compactMap { $0 }
    }

    private func dots(_ nameplates: [Nameplate], size: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(nameplates, id: \.self) { nameplate in
                ClosetNameplateDot(nameplate: nameplate, level: store.progression.studyLevel,
                                   isPicked: store.progression.nameplate == nameplate, size: size) {
                    store.pick(nameplate)
                }
            }
        }
        .fixedSize()
    }
}

private struct ClosetNameplateDot: View {
    let nameplate: Nameplate
    let level: StudyLevel
    let isPicked: Bool
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    private var isUnlocked: Bool { nameplate.unlockLevel <= level.value }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isUnlocked {
                    Circle().fill(nameplate.tint)
                } else {
                    Circle().strokeBorder(nameplate.tint.opacity(0.45), lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
            .padding(2)
            .overlay(
                Circle().strokeBorder(isPicked ? accent : hovering && isUnlocked ? Theme.Palette.secondaryText : .clear,
                                      lineWidth: 1.5)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isPicked)
    }

    private var help: String {
        isUnlocked ? String(localized: "\(nameplate.displayName) name color", bundle: .tabbi)
            : String(localized: "\(nameplate.displayName) name color, unlocks at Level \(nameplate.unlockLevel)",
                     bundle: .tabbi)
    }
}

/// Every rank's emblem, the named ranks and Galaxy II and III, with the
/// level each starts at, for review sheets (`--snapshot` writes it as
/// `closet-rank-emblems.png` and `closet-rank-emblems-4x.png`).
struct ClosetRankSheet: View {
    static let ranks = StudyRank.Tier.allCases.map { StudyRank(tier: $0) }
        + [StudyRank(tier: .galaxy, numeral: 2), StudyRank(tier: .galaxy, numeral: 3)]

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                ForEach(Self.ranks, id: \.self) { rank in
                    VStack(spacing: Theme.Spacing.xs) {
                        StudyRankEmblem(rank, pixelSize: 2)
                        Text(rank.displayName)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                        Text(StudyLevel(rank.firstLevel).shortLabel)
                            .font(Theme.Typography.caption.monospacedDigit())
                            .foregroundStyle(Theme.Palette.tertiaryText)
                    }
                    .fixedSize()
                }
            }
        }
        .padding(16)
        .background(Theme.Palette.background)
    }
}

/// Every nameplate color on a pet's name, with the level that unlocks it,
/// for review sheets (`closet-nameplates.png`).
struct ClosetNameplateSheet: View {
    var body: some View {
        Card {
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.l, verticalSpacing: Theme.Spacing.s) {
                ForEach(Array(Nameplate.allCases.enumerated()), id: \.element) { index, nameplate in
                    if index.isMultiple(of: 2) {
                        GridRow {
                            entry(nameplate)
                            if index + 1 < Nameplate.allCases.count { entry(Nameplate.allCases[index + 1]) }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.Palette.background)
    }

    private func entry(_ nameplate: Nameplate) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(verbatim: "Mochi").font(Theme.Typography.title).nameplate(nameplate)
                .frame(width: 56, alignment: .leading)
            Text(nameplate.displayName).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.secondaryText)
            Text(StudyLevel(nameplate.unlockLevel).shortLabel).font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.tertiaryText)
        }
        .fixedSize()
    }
}
