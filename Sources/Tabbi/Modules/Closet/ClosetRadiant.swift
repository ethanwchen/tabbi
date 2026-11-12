import SwiftUI
import TabbiKit
import TabbiKitCore

// The Closet's Radiant upgrades: an owned showpiece bought a second time,
// for 5x its price, keeps its look and gains an animated effect
// (`PetRadiant`). The wardrobe tile wears a star pip once an item is
// Radiant; the pip (shown faded on hover for an item that can be upgraded)
// opens the Radiant sheet in place of the grid, where the upgrade is bought,
// pinned as a goal, or its effect set to Bold, Subtle or Off. A pinned goal
// shows its progress in the wardrobe's footer.

private var accent: Color { ClosetModule.descriptor.accentColor }

/// The Radiant marker (`RadiantMarkerArt`), a 9 by 9 pixel star drawn like
/// the Goals badges at 1.5 pt per pixel.
struct ClosetRadiantPip: View {
    var pixelSize: CGFloat = 1.5
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let scale = BadgeArt.scale(pixelSize: pixelSize, displayScale: displayScale)
        let side = CGFloat(RadiantMarkerArt.size) * pixelSize
        Group {
            if let image = RadiantMarkerArt.image(scale: scale) {
                Image(decorative: image, scale: CGFloat(scale) / pixelSize)
                    .interpolation(.none)
            } else {
                Color.clear
            }
        }
        .frame(width: side, height: side)
    }
}

/// The pip on a wardrobe tile: the marker on a Radiant item, or, while the
/// pointer is on an owned item that can be upgraded, a faded one that opens
/// the Radiant sheet.
struct ClosetRadiantTileButton: View {
    let item: PetItem
    let state: PetRadiantState
    let isTileHovered: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        if shows {
            Button(action: action) {
                ClosetRadiantPip()
                    .opacity(state.isRadiant || hovering ? 1 : 0.55)
                    .scaleEffect(hovering ? 1.15 : 1)
                    .padding(Theme.Spacing.xxs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
            .onHover { hovering = $0 }
            .motion(Theme.Motion.snappy, value: hovering)
        }
    }

    private var shows: Bool {
        switch state {
        case .radiant: true
        case .affordable, .locked: isTileHovered
        case .notEligible, .needsItem: false
        }
    }

    private var help: String {
        state.isRadiant ? String(localized: "Radiant \(item.displayName): set its effect", bundle: .tabbi)
            : String(localized: "Make \(item.displayName) Radiant", bundle: .tabbi)
    }
}

/// The Radiant sheet, in the wardrobe's place: the effect, previewed on the
/// big pet, and either the upgrade (with its price and a pin as goal) or,
/// once upgraded, how strongly it shows.
struct ClosetRadiantSheet: View {
    @ObservedObject var store: ClosetStore
    let item: PetItem

    /// How much of the description a panel has room for: the Compact
    /// panel keeps the effect's name, or only the choices, rather than clip.
    private enum Detail { case full, name, none }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(.full)
            content(.name)
            content(.none)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func content(_ detail: Detail) -> some View {
        let state = store.closet.radiantState(of: item)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s - Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xs) {
                ClosetRadiantPip()
                Text("Radiant \(item.displayName)", bundle: .tabbi)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Theme.Spacing.xs)
                IconButton(symbol: "xmark", help: String(localized: "Back to the wardrobe", bundle: .tabbi)) {
                    withMotion(Theme.Motion.content) { store.showRadiant(nil) }
                }
            }
            switch detail {
            case .full:
                // Two lines at most, so a long translation wraps instead of clipping.
                Text(description(state))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            case .name:
                Text(effectName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            case .none:
                EmptyView()
            }
            intensityRow(state)
            Spacer(minLength: 0)
            footer(state)
        }
    }

    private var effectName: String {
        PetRadiant.localizedEffectName(item, store.radiantPreview == .subtle ? .subtle : .bold) ?? ""
    }

    private func description(_ state: PetRadiantState) -> String {
        let effect = effectName
        if state.isRadiant {
            return String(localized: "\(effect). Pick how strongly it shows; Reduce Motion keeps it still.",
                          bundle: .tabbi)
        }
        return String(localized: "\(effect). Keeps its look and adds a loop of light.", bundle: .tabbi)
    }

    /// Bold, Subtle (and, once upgraded, Off): a preview before the upgrade,
    /// the setting after it.
    @ViewBuilder private func intensityRow(_ state: PetRadiantState) -> some View {
        let options: [PetRadiantIntensity] = state.isRadiant ? [.bold, .subtle, .off] : [.bold, .subtle]
        let selected: PetRadiantIntensity = if case .radiant(let current) = state { current } else { store.radiantPreview }
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(options, id: \.self) { intensity in
                ClosetRadiantChoice(title: Self.title(intensity), isSelected: selected == intensity,
                                    help: help(intensity, isRadiant: state.isRadiant)) {
                    withMotion(Theme.Motion.snappy) {
                        if state.isRadiant {
                            store.setRadiance(intensity, for: item)
                        } else {
                            store.previewRadiance(intensity)
                        }
                    }
                }
            }
        }
    }

    static func title(_ intensity: PetRadiantIntensity) -> String {
        switch intensity {
        case .bold: String(localized: "Bold", bundle: .tabbi)
        case .subtle: String(localized: "Subtle", bundle: .tabbi)
        case .off: String(localized: "Off", bundle: .tabbi)
        }
    }

    private func help(_ intensity: PetRadiantIntensity, isRadiant: Bool) -> String {
        switch (intensity, isRadiant) {
        case (.bold, false): String(localized: "Preview the Bold effect", bundle: .tabbi)
        case (.subtle, false): String(localized: "Preview the Subtle effect", bundle: .tabbi)
        case (.bold, true): String(localized: "Show the full effect", bundle: .tabbi)
        case (.subtle, true): String(localized: "Show a quieter effect", bundle: .tabbi)
        case (.off, _): String(localized: "Keep the upgrade but show the item as before", bundle: .tabbi)
        }
    }

    @ViewBuilder private func footer(_ state: PetRadiantState) -> some View {
        let price = PetRadiant.price(of: item)
        HStack(spacing: Theme.Spacing.s) {
            switch state {
            case .radiant:
                // The note shortens rather than clip in narrow panels.
                ViewThatFits(in: .horizontal) {
                    Text("Upgraded. Friends on Party see it too.", bundle: .tabbi).fixedSize()
                    Text("Upgraded", bundle: .tabbi).fixedSize()
                    Color.clear.frame(width: 0)
                }
                .foregroundStyle(Theme.Palette.tertiaryText)
                Spacer(minLength: Theme.Spacing.xs)
                ClosetRadiantButton(title: String(localized: "Done", bundle: .tabbi), isPrimary: true,
                                    help: String(localized: "Back to the wardrobe", bundle: .tabbi)) {
                    withMotion(Theme.Motion.content) { store.showRadiant(nil) }
                }
            case .affordable, .locked:
                ViewThatFits(in: .horizontal) {
                    priceLabel(price, long: true)
                    priceLabel(price, long: false)
                }
                Spacer(minLength: Theme.Spacing.xs)
                let pinned = store.closet.save.radiantGoal == item
                ClosetRadiantButton(title: pinned ? String(localized: "Unpin", bundle: .tabbi)
                                        : String(localized: "Pin as goal", bundle: .tabbi),
                                    isPrimary: false,
                                    help: pinned ? String(localized: "Stop showing this goal in the wardrobe", bundle: .tabbi)
                                        : String(localized: "Show your progress toward this upgrade in the wardrobe", bundle: .tabbi)) {
                    withMotion(Theme.Motion.snappy) { store.pinRadiantGoal(pinned ? nil : item) }
                }
                if case .locked(let missing) = state {
                    ClosetRadiantButton(title: String(localized: "\(missing.formatted()) to go", bundle: .tabbi),
                                        isPrimary: true, isEnabled: false,
                                        help: String(localized: "\(missing.formatted()) more points: \(PetEconomy.studyToEarn(missing)) at a typical study pace", bundle: .tabbi)) {}
                } else {
                    ClosetRadiantButton(title: String(localized: "Upgrade", bundle: .tabbi), isPrimary: true,
                                        help: String(localized: "Upgrade for \(price.formatted()) points", bundle: .tabbi)) {
                        withMotion(Theme.Motion.content) { _ = store.upgradeToRadiant(item) }
                    }
                }
            case .needsItem, .notEligible:
                EmptyView()
            }
        }
        .font(Theme.Typography.caption)
        .frame(height: 22)
    }

    private func priceLabel(_ price: Int, long: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: "star.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(accent)
            Text(price.formatted()).monospacedDigit().foregroundStyle(Theme.Palette.primaryText)
            if long {
                Text("pts, 5x its price", bundle: .tabbi).foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A capsule choice in the Radiant sheet, accent-tinted when selected.
private struct ClosetRadiantChoice: View {
    let title: String
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.caption)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? accent : hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xxs)
                .frame(height: 22)
                .background(Capsule().fill(isSelected ? accent.opacity(0.16)
                                           : hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// A capsule button in the Radiant sheet's footer.
private struct ClosetRadiantButton: View {
    let title: String
    let isPrimary: Bool
    var isEnabled = true
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.caption.weight(isPrimary ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(!isEnabled ? Theme.Palette.tertiaryText : isPrimary ? accent : Theme.Palette.primaryText)
                .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xxs)
                .frame(height: 22)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private var fill: Color {
        guard isEnabled else { return Theme.Palette.surface }
        if isPrimary { return accent.opacity(hovering ? 0.24 : 0.14) }
        return hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface
    }
}

/// The wardrobe footer's pinned goal: "Radiant Wizard Hat 4,210 of 5,750"
/// with a thin bar; it opens the Radiant sheet.
struct ClosetRadiantGoalLine: View {
    let goal: PetRadiantGoal
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            // Narrower panels and longer names drop "Radiant" (the pip says
            // it), then the bar, then the name, never cutting a word.
            ViewThatFits(in: .horizontal) {
                line(name: String(localized: "Radiant \(goal.item.displayName)", bundle: .tabbi), bar: true)
                line(name: goal.item.displayName, bar: true)
                line(name: goal.item.displayName, bar: false)
                line(name: nil, bar: true)
            }
            .brightness(hovering ? 0.2 : 0)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Your pinned goal: Radiant \(goal.item.displayName) for \(goal.price.formatted()) points", bundle: .tabbi))
        .accessibilityLabel(String(localized: "Your pinned goal: Radiant \(goal.item.displayName) for \(goal.price.formatted()) points", bundle: .tabbi))
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private func line(name: String?, bar: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ClosetRadiantPip(pixelSize: 1)
            if let name {
                Text(name).foregroundStyle(Theme.Palette.secondaryText).fixedSize()
            }
            Group {
                if goal.isReady {
                    Text("ready to upgrade", bundle: .tabbi).foregroundStyle(accent)
                } else {
                    Text("\(goal.have.formatted()) of \(goal.price.formatted())", bundle: .tabbi)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
            .monospacedDigit()
            .fixedSize()
            if bar {
                Capsule().fill(Theme.Palette.surface)
                    .frame(width: 44, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent).frame(width: max(4, 44 * goal.fraction), height: 4)
                    }
            }
        }
    }
}
