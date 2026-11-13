import SwiftUI
import TabbiKitCore
import TabbiKit

private var accent: Color { ClosetModule.descriptor.accentColor }

/// The Closet's Goals section: the Study Level (`ClosetLevelCard`), this
/// month's quests, the mastery outfits
/// (earned from badge tiers, never sold) and the badge collection, from
/// the pet's `PetProgression`. Like the Wardrobe and Limited sections it
/// scrolls and fades out at the bottom, and the footer details whatever the
/// pointer rests on. docs/design/progression.md explains the goals.
struct ClosetGoals: View {
    @ObservedObject var store: ClosetStore
    /// The tile or medallion under the pointer, for the footer.
    @State private var hovered: Hover?
    /// Badge tiers reached since the section was last open, captured as it
    /// appears so they keep their dot while it shows.
    @State private var fresh: Set<ProgressBadge> = []
    @Environment(\.closetSnapshotShowsEnd) private var showsEndForSnapshot

    private enum Hover: Hashable {
        case outfit(PetItem)
        case badge(ProgressTrack)
        case quest(MonthlyQuestProgress)
    }

    private let tileColumns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s - Theme.Spacing.xxs),
                                    count: 5)
    private let badgeColumns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s - Theme.Spacing.xxs) {
            scrollingContent
            footer
        }
        .onAppear {
            fresh = store.progression.unseen
            store.markGoalsSeen()
        }
        .onHover { inside in
            guard !inside, hovered != nil else { return }
            hovered = nil
            store.tryOn(nil)
        }
        .onDisappear {
            hovered = nil
            store.tryOn(nil)
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ClosetLevelCard(store: store)
            ClosetQuestBanner(month: Date.now, quests: store.progression.quests(at: .now)) { quest in
                hovered = quest.map(Hover.quest)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ClosetGoalsShelfTitle(title: String(localized: "Outfits to earn", bundle: .tabbi),
                                      help: String(localized: "Mastery outfits: each unlocks with a badge tier, never with points",
                                                   bundle: .tabbi))
                LazyVGrid(columns: tileColumns, spacing: Theme.Spacing.s - Theme.Spacing.xxs) {
                    ForEach(PetCloset.masteryShelf, id: \.id) { item in outfitTile(item) }
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ClosetGoalsShelfTitle(title: String(localized: "Badges", bundle: .tabbi),
                                      help: String(localized: "One badge for each habit, from Bronze to Starlight", bundle: .tabbi))
                LazyVGrid(columns: badgeColumns, spacing: Theme.Spacing.s) {
                    ForEach(ProgressTrack.allCases, id: \.self) { track in badge(track) }
                }
            }
        }
    }

    /// The shelves outgrow the panel, so they scroll and fade at the
    /// bottom. `ImageRenderer` draws a `ScrollView` blank, so snapshots
    /// show the top rows clipped.
    @ViewBuilder private var scrollingContent: some View {
        Group {
            if RunMode.current.isSnapshot {
                // From the end, the last row keeps the scroll view's bottom
                // margin, the edge fade's length, so it shows whole and unfaded.
                Color.clear
                    .overlay(alignment: showsEndForSnapshot ? .bottom : .top) {
                        content.padding(.bottom, showsEndForSnapshot ? Theme.Spacing.m : 0)
                    }
                    .clipped()
            } else {
                ScrollView(.vertical) { content }
                    .scrollIndicators(.automatic)
                    .scrollBounceBehavior(.basedOnSize)
                    .contentMargins(.bottom, Theme.Spacing.m, for: .scrollContent)
            }
        }
        .edgeFade(.bottom)
    }

    private func outfitTile(_ item: PetItem) -> some View {
        let badge = item.limitedEdition?.masteryBadge
        let state = store.closet.state(of: item)
        return ClosetGoalTile(item: item, state: state,
                              progress: badge.map { store.progression.progress(of: $0) },
                              badge: badge, isFresh: badge.map(fresh.contains) ?? false, model: thumbnailModel) {
            withMotion(Theme.Motion.snappy) { _ = store.tap(item) }
        } onHover: { inside in
            if inside {
                hovered = .outfit(item)
                store.tryOn(item)
            } else if hovered == .outfit(item) {
                hovered = nil
                store.tryOn(nil)
            }
        }
    }

    private func badge(_ track: ProgressTrack) -> some View {
        ClosetBadgeMedallion(track: track, progression: store.progression,
                             isFresh: fresh.contains { $0.track == track }) { inside in
            if inside { hovered = .badge(track) } else if hovered == .badge(track) { hovered = nil }
        }
    }

    /// Thumbnails show each outfit alone on the pet, like the wardrobe.
    private var thumbnailModel: PetProfile {
        PetProfile(name: store.profile.name, breed: store.profile.breed,
                   paletteOverrides: store.profile.paletteOverrides, furTint: store.profile.furTint)
    }

    /// What the hovered tile or badge asks for, or the counts.
    private var footer: some View {
        HStack(spacing: Theme.Spacing.xs) {
            switch hovered ?? store.tryingOn.flatMap({ $0.limitedEdition?.isMastery == true ? .outfit($0) : nil }) {
            case .outfit(let item):
                ClosetFooterDetail(name: item.displayName, detail: outfitDetail(item))
            case .badge(let track):
                ClosetFooterDetail(name: track.displayName, detail: ClosetBadgeMedallion.detail(track, store.progression))
            case .quest(let quest):
                ClosetFooterDetail(name: quest.quest.title, detail: questDetail(quest))
            case nil:
                // The counts never cut off: the line first drops the words
                // before them, then shortens them to bare numbers.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Earned by studying, never sold", bundle: .tabbi)
                            .foregroundStyle(Theme.Palette.secondaryText)
                        Text(counts).foregroundStyle(Theme.Palette.tertiaryText)
                    }
                    .fixedSize()
                    Text(counts).foregroundStyle(Theme.Palette.tertiaryText).fixedSize()
                    Text(shortCounts).foregroundStyle(Theme.Palette.tertiaryText).fixedSize()
                }
                .monospacedDigit()
                .help(String(localized: "Earned by studying, never sold", bundle: .tabbi) + " " + counts)
                Spacer(minLength: 0)
            }
        }
        .font(Theme.Typography.caption)
        .lineLimit(1)
        .frame(height: 12)
    }

    private var ownedOutfits: Int {
        PetCloset.masteryShelf.filter { store.closet.state(of: $0).isOwned }.count
    }

    private var counts: String {
        let outfitLine = String(localized: "\(ownedOutfits) of \(PetCloset.masteryShelf.count) outfits", bundle: .tabbi)
        let badgeLine = String(localized: "\(store.progression.reachedCount) of \(ProgressBadge.allCases.count) badges",
                               bundle: .tabbi)
        return "\(outfitLine) · \(badgeLine)"
    }

    /// The counts as bare numbers with symbols, for the narrowest panel.
    private var shortCounts: String {
        "\(ownedOutfits)/\(PetCloset.masteryShelf.count) · \(store.progression.reachedCount)/\(ProgressBadge.allCases.count)"
    }

    private func outfitDetail(_ item: PetItem) -> String {
        switch store.closet.state(of: item) {
        case .wearing: return String(localized: "Earned. Click to take off.", bundle: .tabbi)
        case .owned: return String(localized: "Earned. Click to wear.", bundle: .tabbi)
        default:
            guard let badge = item.limitedEdition?.masteryBadge else { return "" }
            let progress = store.progression.progress(of: badge)
            return String(localized: "\(badge.howToEarn) \(progress.label) so far.", bundle: .tabbi)
        }
    }

    private func questDetail(_ quest: MonthlyQuestProgress) -> String {
        quest.isDone ? String(localized: "Done this month.", bundle: .tabbi)
            : String(localized: "\(quest.label) this month.", bundle: .tabbi)
    }
}

// MARK: - Quests

/// This month's three quests at the top of the Goals section: the month,
/// how many are done, the next one to do, and a ring for each quest that
/// fills with this month's progress (a check once done). Gentle on purpose:
/// it never counts what is left of the month or what was missed.
private struct ClosetQuestBanner: View {
    let month: Date
    let quests: [MonthlyQuestProgress]
    let onHover: (MonthlyQuestProgress?) -> Void

    private var done: Int { quests.filter(\.isDone).count }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                // Each line shortens before it would scroll: the title drops
                // "quests", the next quest its "Next:".
                ViewThatFits(in: .horizontal) {
                    titleLine(String(localized: "\(monthName) quests", bundle: .tabbi), count: countText)
                    titleLine(monthName, count: countText)
                    titleLine(monthName, count: "\(done)/\(quests.count)")
                    HStack(spacing: Theme.Spacing.xs) {
                        MarqueeText(monthName, help: help).font(.system(size: 10, weight: .semibold, design: .rounded))
                        Text(verbatim: "\(done)/\(quests.count)").font(Theme.Typography.caption.monospacedDigit())
                            .foregroundStyle(Theme.Palette.tertiaryText).fixedSize()
                    }
                }
                .foregroundStyle(Theme.Palette.primaryText)
                ViewThatFits(in: .horizontal) {
                    Text(nextLine(labeled: true)).fixedSize()
                    Text(nextLine(labeled: false)).fixedSize()
                    Text(nextTitle).fixedSize()
                    MarqueeText(nextTitle, help: help)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
            }
            .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xs)
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(quests, id: \.quest) { quest in
                    ClosetQuestRing(quest: quest, onHover: onHover)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: 36)
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
    }

    private var countText: String {
        String(localized: "\(done) of \(quests.count) done", bundle: .tabbi)
    }

    /// The month (or its quests) and how many are done, at full width.
    private func titleLine(_ title: String, count: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title).font(.system(size: 10, weight: .semibold, design: .rounded))
            Text(count).font(Theme.Typography.caption.monospacedDigit()).foregroundStyle(Theme.Palette.tertiaryText)
        }
        .fixedSize()
    }

    /// "November", in the user's language.
    private var monthName: String {
        month.formatted(.dateTime.month(.wide))
    }

    /// The next quest's title alone, for the narrowest banner: the ring
    /// beside it shows the progress.
    private var nextTitle: String {
        quests.first { !$0.isDone }?.quest.title ?? String(localized: "All done", bundle: .tabbi)
    }

    /// The first quest not done yet ("Next: Study on 10 days, 6/10", or
    /// without "Next:" where room is short), or a word once all three are.
    private func nextLine(labeled: Bool) -> String {
        guard let next = quests.first(where: { !$0.isDone }) else {
            let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
            let start = Calendar.current.dateInterval(of: .month, for: nextMonth)?.start ?? nextMonth
            let day = start.formatted(.dateTime.month(.abbreviated).day())
            return labeled ? String(localized: "All done. New quests on \(day).", bundle: .tabbi)
                : String(localized: "All done", bundle: .tabbi)
        }
        return labeled ? String(localized: "Next: \(next.quest.title), \(next.label)", bundle: .tabbi)
            : String(localized: "\(next.quest.title), \(next.label)", bundle: .tabbi)
    }

    private var help: String {
        Sentences.join([
            String(localized: "Three small goals each month. They are optional, and a month you miss costs nothing.",
                   bundle: .tabbi),
            String(localized: "Finish all three to count the month toward the Monthly quests badge.", bundle: .tabbi),
        ])
    }
}

/// One quest's ring: its track's symbol inside a ring that fills with this
/// month's progress, filled with a check once the quest is done.
private struct ClosetQuestRing: View {
    let quest: MonthlyQuestProgress
    let onHover: (MonthlyQuestProgress?) -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            if quest.isDone {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Theme.Palette.onAccent)
            } else {
                ProgressRing(progress: quest.fraction, tint: accent, track: Theme.Palette.surfaceHover, lineWidth: 2)
                Image(systemName: quest.quest.track.symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
            }
        }
        .frame(width: 20, height: 20)
        .padding(Theme.Spacing.xxs)
        .background(Circle().fill(hovering ? Theme.Palette.surfaceHover : .clear))
        .contentShape(Circle())
        .help(quest.isDone ? String(localized: "\(quest.quest.title): done this month", bundle: .tabbi)
              : String(localized: "\(quest.quest.title): \(quest.label) this month", bundle: .tabbi))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quest.quest.title)
        .accessibilityValue(quest.isDone ? String(localized: "Done", bundle: .tabbi) : quest.label)
        .onHover { inside in
            hovering = inside
            onHover(inside ? quest : nil)
        }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

// MARK: - Outfits

/// A shelf's title on the Goals section.
private struct ClosetGoalsShelfTitle: View {
    let title: String
    let help: String

    var body: some View {
        Text(title)
            .foregroundStyle(Theme.Palette.secondaryText)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .frame(height: 12)
            .padding(.leading, Theme.Spacing.xxs)
            .help(help)
    }
}

/// A mastery outfit's tile: the outfit on the pet (greyed until earned),
/// a rosette badge in the color of the tier that unlocks it, and below it
/// On, Owned, or the goal's progress with a thin bar.
private struct ClosetGoalTile: View {
    let item: PetItem
    let state: PetClosetItemState
    let progress: PetLimitedProgress?
    let badge: ProgressBadge?
    /// Unlocked since the Goals section was last open.
    let isFresh: Bool
    let model: PetProfile
    let action: () -> Void
    let onHover: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                PetSpriteView(profile: PetCloset.wearing(item, on: model))
                    .opacity(state.isOwned ? 1 : 0.45)
                    .saturation(state.isOwned ? 1 : 0.3)
                label
                bar
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "rosette")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(badge.map { $0.tier.color.opacity(state.isOwned ? 1 : 0.55) }
                                     ?? Theme.Palette.tertiaryText)
                    .padding(Theme.Spacing.xs)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if isFresh && state.isOwned { ClosetGoalsNewDot().padding(Theme.Spacing.xs) }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(state == .wearing ? accent.opacity(0.14)
                          : hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .strokeBorder(state == .wearing ? accent.opacity(0.7) : Theme.Palette.stroke,
                                  lineWidth: state == .wearing ? 1 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(accessibilityValue)
        .onHover { inside in
            hovering = inside
            onHover(inside)
        }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    @ViewBuilder private var label: some View {
        Group {
            switch state {
            case .wearing:
                Label(String(localized: "On", bundle: .tabbi), systemImage: "checkmark").foregroundStyle(accent)
            case .owned:
                Text("Owned", bundle: .tabbi).foregroundStyle(Theme.Palette.secondaryText)
            default:
                Label(progress?.label ?? "", systemImage: badge?.track.symbol ?? "lock.fill")
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
        .labelStyle(ClosetTightLabelStyle())
        .lineLimit(1)
        // A goal ("4210/10k") is a count, so in the Compact panel's narrow
        // tiles it shrinks a little rather than cut off.
        .minimumScaleFactor(0.7)
        .padding(.horizontal, Theme.Spacing.xxs)
        .frame(height: 12)
    }

    /// The goal's progress; an empty slot of the same height once earned,
    /// so every label in the row lines up.
    private var bar: some View {
        Capsule()
            .fill(Theme.Palette.surfaceHover)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(accent).frame(width: proxy.size.width * (progress?.fraction ?? 0))
                }
            }
            .frame(width: 40, height: 3)
            .opacity(state.isOwned ? 0 : 1)
    }

    private var help: String {
        switch state {
        case .wearing: return String(localized: "\(item.displayName), earned: click to take off", bundle: .tabbi)
        case .owned: return String(localized: "\(item.displayName), earned: click to wear", bundle: .tabbi)
        default:
            guard let badge else { return item.displayName }
            return String(localized: "\(item.displayName) unlocks with \(badge.displayName). \(badge.howToEarn)",
                          bundle: .tabbi)
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .wearing: String(localized: "Wearing", bundle: .tabbi)
        case .owned: String(localized: "Owned", bundle: .tabbi)
        default: [badge?.howToEarn, progress?.label].compactMap { $0 }.joined(separator: " ")
        }
    }
}

// MARK: - Badges

/// A badge: the track's sprite in its tier's frame (`ClosetBadgeArt`) over
/// four pips for the tiers earned. The progress to the next tier is in the
/// footer and the tooltip, never on the badge itself.
private struct ClosetBadgeMedallion: View {
    let track: ProgressTrack
    let progression: PetProgression
    let isFresh: Bool
    let onHover: (Bool) -> Void
    @State private var hovering = false

    private var tier: ProgressTier? { progression.tier(of: track) }
    private var next: ProgressTier? { progression.nextTier(of: track) }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ClosetBadgeArt(track: track, tier: tier, hovering: hovering)
            .overlay(alignment: .topTrailing) {
                if isFresh { ClosetGoalsNewDot().offset(x: -2, y: 2) }
            }
            HStack(spacing: Theme.Spacing.xxs) {
                ForEach(ProgressTier.allCases, id: \.self) { pip in
                    Circle()
                        .fill(progression.isReached(ProgressBadge(track, pip)) ? pip.color : Theme.Palette.surfaceHover)
                        .frame(width: 3, height: 3)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .help(Self.help(track, progression))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(track.displayName)
        .accessibilityValue(Self.detail(track, progression))
        .onHover { inside in
            hovering = inside
            onHover(inside)
        }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    /// The footer line: the tier and what the next asks.
    static func detail(_ track: ProgressTrack, _ progression: PetProgression) -> String {
        let tier = progression.tier(of: track)
        guard let next = progression.nextTier(of: track) else {
            return String(localized: "Starlight, every tier earned", bundle: .tabbi)
        }
        let progress = progression.progress(of: ProgressBadge(track, next))
        guard let tier else {
            return String(localized: "\(progress.label) to \(next.displayName)", bundle: .tabbi)
        }
        return String(localized: "\(tier.displayName), \(progress.label) to \(next.displayName)", bundle: .tabbi)
    }

    static func help(_ track: ProgressTrack, _ progression: PetProgression) -> String {
        guard let next = progression.nextTier(of: track) else {
            return String(localized: "\(track.displayName): Starlight, every tier earned", bundle: .tabbi)
        }
        return Sentences.join([
            String(localized: "\(track.displayName): \(detail(track, progression))", bundle: .tabbi),
            track.howToReach(track.goal(for: next)),
        ])
    }
}

/// A badge as a sprite (`BadgeArt`): the tier's frame with the track's
/// glyph, drawn through the pet's renderer at a whole number of device
/// pixels per sprite pixel (1.5 pt per pixel, which the large panel's
/// content scale takes to 2 pt), never interpolated. A badge with no tier
/// yet is the quiet gray coin. Starlight's sparkle blinks slowly; it holds
/// still under Reduce Motion and in snapshots.
struct ClosetBadgeArt: View {
    let track: ProgressTrack
    let tier: ProgressTier?
    var hovering = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rendersToImage) private var rendersToImage
    @Environment(\.displayScale) private var displayScale
    @Environment(\.panelScale) private var panelScale

    /// The art box: 28 sprite pixels at 1.5 pt (42 pt), or at 2 pt (56 pt)
    /// once the large panel's content scale has been applied.
    static let size = CGFloat(BadgeArt.size) * BadgeArt.regularPixelSize

    /// Points per sprite pixel as the panel shows them.
    private var shownPixelSize: CGFloat { panelScale > 1 ? BadgeArt.largePixelSize : BadgeArt.regularPixelSize }

    private var state: BadgeArt.State { BadgeArt.State(tier) }

    var body: some View {
        Group {
            if state == .tier(.starlight), !reduceMotion, !rendersToImage {
                TimelineView(.periodic(from: .now, by: BadgeArt.twinkleInterval)) { context in
                    let tick = Int(context.date.timeIntervalSinceReferenceDate / BadgeArt.twinkleInterval)
                    sprite(twinkle: tick.isMultiple(of: 2))
                }
            } else {
                sprite(twinkle: false)
            }
        }
        .frame(width: CGFloat(BadgeArt.size) * shownPixelSize / panelScale,
               height: CGFloat(BadgeArt.size) * shownPixelSize / panelScale)
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(Theme.Motion.snappy, value: hovering)
        .accessibilityHidden(true)
    }

    private func sprite(twinkle: Bool) -> some View {
        // Whole device pixels per sprite pixel once the panel's content
        // scale is applied; a 1x display draws 1 pt per sprite pixel,
        // centered, rather than a fractional scale.
        let scale = BadgeArt.scale(pixelSize: shownPixelSize, displayScale: displayScale)
        let pixelSize = CGFloat(scale) / displayScale / panelScale
        let side = CGFloat(BadgeArt.size) * pixelSize
        return Group {
            if let image = BadgeArt.image(track: track, state: state, twinkle: twinkle, scale: scale) {
                Image(decorative: image, scale: displayScale)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: side, height: side)
            }
        }
    }
}

/// Every badge at every state side by side, as the Goals section draws
/// them, for review sheets (`--snapshot` writes it as
/// `closet-badge-tiers.png`, once per theme).
struct ClosetBadgeTierSheet: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: 0) {
                    Text(verbatim: "").frame(width: 110)
                    ForEach([String(localized: "Not yet", bundle: .tabbi)] + ProgressTier.allCases.map(\.displayName), id: \.self) {
                        Text($0).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.secondaryText).frame(width: 56)
                    }
                }
                ForEach(ProgressTrack.allCases, id: \.self) { track in
                    HStack(spacing: 0) {
                        Text(track.displayName).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.secondaryText)
                            .frame(width: 110, alignment: .leading)
                        ClosetBadgeArt(track: track, tier: nil).frame(width: 56)
                        ForEach(ProgressTier.allCases, id: \.self) { tier in
                            ClosetBadgeArt(track: track, tier: tier).frame(width: 56)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.Palette.background)
    }
}

/// A small accent dot on what was earned since the Goals section was last
/// open, like an unread mark.
private struct ClosetGoalsNewDot: View {
    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: 6, height: 6)
            .allowsHitTesting(false)
    }
}

extension ProgressTier {
    /// The medallion color: warm bronze, cool silver, gold, and a soft
    /// starlight violet, each light enough to read on the black notch and
    /// on every theme's card.
    var color: Color {
        switch self {
        case .bronze: Color(red: 0.85, green: 0.58, blue: 0.36)
        case .silver: Color(red: 0.78, green: 0.82, blue: 0.87)
        case .gold: Color(red: 0.95, green: 0.76, blue: 0.31)
        case .starlight: Color(red: 0.74, green: 0.66, blue: 1.0)
        }
    }
}

extension ProgressTrack {
    /// The SF Symbol for the track's badge and quests.
    var symbol: String {
        switch self {
        case .focusHours: "clock.fill"
        case .studyDays: "calendar"
        case .gentleStreak: "flame.fill"
        case .sessions: "timer"
        case .cards: "rectangle.stack.fill"
        case .tasks: "checklist"
        case .breakMoves: "figure.cooldown"
        case .party: "person.2.fill"
        case .methods: "books.vertical.fill"
        case .steadyWeeks: "calendar.badge.checkmark"
        case .water: "drop.fill"
        case .monthlyQuests: "moon.stars.fill"
        }
    }
}

private struct ClosetSnapshotShowsEndKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Snapshot runs only: the Goals section and the Wardrobe draw their
    /// shelves from the end, so the badges and the Heirloom shelf below the
    /// fold can be reviewed in a still image.
    var closetSnapshotShowsEnd: Bool {
        get { self[ClosetSnapshotShowsEndKey.self] }
        set { self[ClosetSnapshotShowsEndKey.self] = newValue }
    }
}
