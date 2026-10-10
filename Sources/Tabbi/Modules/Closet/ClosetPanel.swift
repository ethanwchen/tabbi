import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Closet tab: the study pet large and animated on the left, and on the
/// right its wardrobe (wear, take off, or unlock items with study points),
/// its limited edition items, the study streak with its freezes, or its
/// look (species, breed, fur color).
struct ClosetPanel: View {
    @ObservedObject var store: ClosetStore

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ClosetPetCard(store: store)
                .frame(width: 164)
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    // The Compact panel has no room for "pts" beside the pills,
                    // nor for the titles of the sections not open.
                    ViewThatFits(in: .horizontal) {
                        header(showsUnit: true)
                        header(showsUnit: false)
                        header(showsUnit: false, titlesAll: false)
                    }
                    switch store.section {
                    case .wardrobe: ClosetWardrobe(store: store)
                    case .limited: ClosetLimited(store: store)
                    case .streak: ClosetStreak(store: store)
                    case .look: ClosetLook(store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func header(showsUnit: Bool, titlesAll: Bool = true) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            ClosetSectionPicker(selection: $store.section, titlesAll: titlesAll)
            Spacer(minLength: 0)
            ClosetPointsChip(balance: store.closet.balance, showsUnit: showsUnit)
        }
    }
}

enum ClosetSection: String, CaseIterable {
    case wardrobe = "Wardrobe"
    case limited = "Limited"
    case streak = "Streak"
    case look = "Look"

    var symbol: String {
        switch self {
        case .wardrobe: "tshirt.fill"
        case .limited: "sparkles"
        case .streak: "flame.fill"
        case .look: "paintpalette.fill"
        }
    }

    var help: String {
        switch self {
        case .wardrobe: "Outfits and accessories to unlock with study points"
        case .limited: "Limited edition items, earned by studying, never sold"
        case .streak: "Your study streak and the freezes that protect it"
        case .look: "Species, breed and fur color"
        }
    }
}

private var accent: Color { ClosetModule.descriptor.accentColor }

// MARK: - Pet

/// The pet large and animated, its name (click to rename), and its breed or
/// the item being tried on.
private struct ClosetPetCard: View {
    @ObservedObject var store: ClosetStore
    @State private var isRenaming = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        // The content is centered, so the slim padding changes nothing on a
        // roomy panel and keeps the 96 pt pet whole on a short one (Compact).
        Card(padding: Theme.Spacing.s) {
            VStack(spacing: Theme.Spacing.xs) {
                Spacer(minLength: 0)
                PetView(player: store.preview, pixelSize: 3)
                    .padding(.bottom, Theme.Spacing.xs)
                nameRow
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(store.tryingOn == nil ? Theme.Palette.tertiaryText : accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .motion(Theme.Motion.snappy, value: subtitle)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var subtitle: String {
        if let item = store.tryingOn { return "Trying on \(item.displayName)" }
        // A pet still called by its breed would show the breed twice.
        if store.profile.name == store.profile.breed.displayName {
            return "Give your \(store.profile.species.displayName.lowercased()) a name"
        }
        return store.profile.breed.displayName
    }

    @ViewBuilder private var nameRow: some View {
        if isRenaming {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
                .multilineTextAlignment(.center)
                .focused($nameFocused)
                .onAppear { nameFocused = true }
                .onSubmit(commit)
                .onExitCommand { isRenaming = false }
                .onChange(of: nameFocused) { _, focused in if !focused { commit() } }
                .padding(.horizontal, Theme.Spacing.s)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                        .fill(Theme.Palette.surfaceHover)
                )
        } else {
            ClosetNameButton(name: store.profile.name) {
                draft = store.profile.name
                isRenaming = true
            }
        }
    }

    private func commit() {
        guard isRenaming else { return }
        store.rename(draft)
        isRenaming = false
    }
}

/// The pet's name with a pencil that appears on hover; click to rename.
private struct ClosetNameButton: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                Image(systemName: "pencil")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(hovering ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(hovering ? Theme.Palette.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Rename your pet")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

// MARK: - Header

private struct ClosetSectionPicker: View {
    @Binding var selection: ClosetSection
    /// Off, only the open section shows its title; the others show their
    /// symbol, with the title in the tooltip.
    var titlesAll = true

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(ClosetSection.allCases, id: \.self) { section in
                ClosetPill(title: section.rawValue, symbol: section.symbol,
                           showsTitle: titlesAll || selection == section,
                           isSelected: selection == section,
                           help: section.help) {
                    withMotion(Theme.Motion.content) { selection = section }
                }
            }
        }
    }
}

/// A capsule toggle: accent-tinted when selected, with a hover state.
private struct ClosetPill: View {
    let title: String
    let symbol: String
    var showsTitle = true
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                if showsTitle { Text(title).lineLimit(1).fixedSize() }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(isSelected ? accent : hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
            // A symbol alone needs less room, which keeps four sections and
            // the balance on one line in the Compact panel.
            .padding(.horizontal, showsTitle ? Theme.Spacing.s + Theme.Spacing.xxs : Theme.Spacing.s)
            .frame(height: 22)
            .background(Capsule().fill(isSelected ? accent.opacity(0.16) : hovering ? Theme.Palette.surfaceHover : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(showsTitle ? help : "\(title): \(help)")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// The study-points balance.
private struct ClosetPointsChip: View {
    let balance: Int
    var showsUnit = true

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "star.fill").font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent)
            Text("\(balance)")
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.primaryText)
                .contentTransition(.numericText())
            if showsUnit {
                Text("pts")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: 22)
        .background(Capsule().fill(Theme.Palette.surface))
        .overlay(Capsule().strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
        .help("Points: 1 for every focused minute, plus a bonus for finishing a session")
        .motion(Theme.Motion.snappy, value: balance)
    }
}

// MARK: - Wardrobe

private struct ClosetWardrobe: View {
    @ObservedObject var store: ClosetStore
    @State private var hovered: PetItem?
    /// The tile the grid scrolls to when the footer's next unlock is clicked.
    @State private var shown: PetItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s - Theme.Spacing.xxs),
                                count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s - Theme.Spacing.xxs) {
            scrollingGrid
            footer
        }
        // A try-on started from the footer ends when the pointer leaves.
        .onHover { inside in
            guard !inside, hovered != nil else { return }
            hovered = nil
            store.tryOn(nil)
        }
        // Closing the notch or switching to Look mid-hover sends no hover
        // exit, so drop the try-on here or it would greet the next visit.
        .onDisappear {
            hovered = nil
            store.tryOn(nil)
        }
    }

    /// One shelf per theme: a small title, then its items cheapest first.
    private var grid: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(PetCloset.shelves, id: \.theme) { shelf in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ClosetShelfTitle(theme: shelf.theme)
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.s - Theme.Spacing.xxs) {
                        ForEach(shelf.items, id: \.id) { item in tile(item).id(item.id) }
                    }
                }
            }
        }
    }

    private func tile(_ item: PetItem) -> some View {
        ClosetItemTile(item: item, state: store.closet.state(of: item), isNew: store.closet.isNew(item),
                       model: thumbnailModel) {
            withMotion(Theme.Motion.snappy) { _ = store.tap(item) }
        } onHover: { inside in
            if inside { hovered = item } else if hovered == item { hovered = nil }
            store.tryOn(hovered)
        }
    }

    /// The wardrobe grows with every new item, so it scrolls, and the rows
    /// fade out at the bottom edge to say so. `ImageRenderer` draws a
    /// `ScrollView` blank, so snapshots show the top rows clipped.
    @ViewBuilder private var scrollingGrid: some View {
        Group {
            if RunMode.current.isSnapshot {
                Color.clear
                    .overlay(alignment: .top) { grid }
                    .clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) { grid }
                        .scrollIndicators(.automatic)
                        .scrollBounceBehavior(.basedOnSize)
                        .contentMargins(.bottom, Theme.Spacing.m, for: .scrollContent)
                        .onChange(of: shown) { _, item in
                            guard let item else { return }
                            withMotion(Theme.Motion.content) { proxy.scrollTo(item.id, anchor: .center) }
                            shown = nil
                        }
                }
            }
        }
        .edgeFade(.bottom)
    }

    /// Thumbnails show each item alone on the pet, so the item reads clearly.
    private var thumbnailModel: PetProfile {
        PetProfile(name: store.profile.name, breed: store.profile.breed,
                   paletteOverrides: store.profile.paletteOverrides, furTint: store.profile.furTint)
    }

    /// Names the hovered item, or points to the next unlock.
    private var footer: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let hovered {
                Text(hovered.displayName).foregroundStyle(Theme.Palette.secondaryText)
                Text(detail(for: hovered)).foregroundStyle(Theme.Palette.tertiaryText)
            } else if let next = store.closet.nextUnlock, store.closet.save.ledger.earned == 0 {
                // A brand-new pet: explain where points come from.
                Text("Focus to earn points").foregroundStyle(Theme.Palette.secondaryText)
                showButton(next.item) {
                    ViewThatFits(in: .horizontal) {
                        Text("\(next.item.displayName) unlocks after \(PetEconomy.studyToEarn(next.item.cost))")
                        Text("\(next.item.displayName) unlocks at \(next.item.cost)")
                    }
                    .foregroundStyle(Theme.Palette.tertiaryText)
                }
            } else if let next = store.closet.nextUnlock {
                // The Compact panel drops the "Next unlock" label, then the
                // study time, before the item name or its status would clip.
                showButton(next.item) {
                    ViewThatFits(in: .horizontal) {
                        nextUnlock(next, labeled: true, inStudyTime: true)
                        nextUnlock(next, labeled: false, inStudyTime: true)
                        nextUnlock(next, labeled: false, inStudyTime: false)
                    }
                }
            } else {
                Text("Everything unlocked. Dress up as you like.").foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .font(Theme.Typography.caption)
        .lineLimit(1)
        .frame(height: 12)
    }

    /// The next unlock can sit on a shelf out of view, so clicking it in
    /// the footer scrolls its tile into view and tries it on the pet.
    private func showButton(_ item: PetItem, @ViewBuilder label: () -> some View) -> some View {
        ClosetFooterLink(label: label(), help: "Show \(item.displayName) and try it on") {
            hovered = item
            store.tryOn(item)
            shown = item
        }
    }

    /// Says what the next item asks of you: the points still missing and,
    /// when there is room, the study that earns them at a typical pace.
    private func nextUnlock(_ next: (item: PetItem, missing: Int), labeled: Bool,
                            inStudyTime: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if labeled { Text("Next unlock").foregroundStyle(Theme.Palette.tertiaryText) }
            Text(next.item.displayName).foregroundStyle(Theme.Palette.secondaryText)
            Group {
                if next.missing == 0 {
                    Text("ready to unlock")
                } else if inStudyTime {
                    Text("\(next.missing) pts, \(PetEconomy.studyToEarn(next.missing)) to go")
                } else {
                    Text("\(next.missing) pts to go")
                }
            }
            .foregroundStyle(next.missing == 0 ? accent : Theme.Palette.tertiaryText)
            .monospacedDigit()
        }
        .help(next.missing == 0 ? "\(next.item.displayName) is ready to unlock"
              : "\(next.missing) more points: \(PetEconomy.studyToEarn(next.missing)) at a typical study pace")
    }

    private func detail(for item: PetItem) -> String {
        switch store.closet.state(of: item) {
        case .wearing: "Click to take off"
        case .owned: "Click to wear"
        case .affordable: "Unlock for \(item.cost) pts"
        case .locked(let missing): "\(item.cost) pts, \(PetEconomy.studyToEarn(missing)) to go"
        case .unearned: item.limitedEdition?.howToEarn ?? "Limited edition"
        }
    }
}

/// A footer line that acts as a quiet link: it brightens on hover.
private struct ClosetFooterLink<Label: View>: View {
    let label: Label
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            .brightness(hovering ? 0.25 : 0)
            .help(help)
            .onHover { hovering = $0 }
            .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// A shelf's theme name.
private struct ClosetShelfTitle: View {
    let theme: PetItemTheme

    var body: some View {
        Text(theme.displayName)
            .foregroundStyle(Theme.Palette.secondaryText)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .frame(height: 12)
            .padding(.leading, Theme.Spacing.xxs)
    }
}

private struct ClosetItemTile: View {
    let item: PetItem
    let state: PetClosetItemState
    /// Fresh in the catalog and not unlocked yet.
    let isNew: Bool
    let model: PetProfile
    let action: () -> Void
    let onHover: (Bool) -> Void
    @State private var hovering = false

    private var isLocked: Bool {
        if case .locked = state { true } else { false }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                PetSpriteView(profile: PetCloset.wearing(item, on: model))
                    .opacity(state.isOwned ? 1 : isLocked ? 0.35 : 0.6)
                    .saturation(isLocked ? 0.2 : 1)
                label
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .overlay(alignment: .topTrailing) {
                if isNew { ClosetNewBadge().padding(Theme.Spacing.xxs) }
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
        // The tile shows only a sprite and a price, so name the item for VoiceOver.
        .accessibilityLabel(item.displayName)
        .accessibilityValue(accessibilityState)
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
                Label("On", systemImage: "checkmark").foregroundStyle(accent)
            case .owned:
                Text("Owned").foregroundStyle(Theme.Palette.tertiaryText)
            case .affordable:
                Label("\(item.cost)", systemImage: "star.fill").foregroundStyle(accent)
            case .locked:
                Label("\(item.cost)", systemImage: "lock.fill").foregroundStyle(Theme.Palette.tertiaryText)
            case .unearned:
                Label("Limited", systemImage: "lock.fill").foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
        .labelStyle(ClosetTightLabelStyle())
        .frame(height: 12)
    }

    private var accessibilityState: String {
        switch state {
        case .wearing: "Wearing"
        case .owned: "Owned"
        case .affordable: "\(isNew ? "New, " : "")unlock for \(item.cost) points"
        case .locked(let missing): "\(isNew ? "New, " : "")\(item.cost) points, \(missing) more to go"
        case .unearned: "Limited edition, not earned yet. \(item.limitedEdition?.howToEarn ?? "")"
        }
    }

    private var help: String {
        switch state {
        case .wearing: "\(item.displayName): click to take off"
        case .owned: "\(item.displayName): click to wear"
        case .affordable: "\(isNew ? "New: " : "")\(item.displayName): unlock for \(item.cost) points"
        case .locked(let missing): "\(isNew ? "New: " : "")\(item.displayName): \(item.cost) points, \(missing) more to go (\(PetEconomy.studyToEarn(missing)))"
        case .unearned: "\(item.displayName), limited edition: \(item.limitedEdition?.howToEarn ?? "")"
        }
    }
}

/// A small accent dot on items fresh in the catalog, like an unread mark;
/// the tile's tooltip says "New".
private struct ClosetNewBadge: View {
    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: 6, height: 6)
            .padding(Theme.Spacing.xxs)
            .allowsHitTesting(false)
    }
}

/// Icon and title close together, for tiny tile labels.
private struct ClosetTightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            configuration.icon.font(.system(size: 8, weight: .bold))
            configuration.title
        }
    }
}

// MARK: - Limited

/// The limited edition items: never sold, earned from study milestones or
/// given at events. Each tile shows how far along its milestone is, and the
/// footer says how to earn the hovered item.
private struct ClosetLimited: View {
    @ObservedObject var store: ClosetStore
    @State private var hovered: PetItem?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s - Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.s - Theme.Spacing.xxs) {
                ForEach(PetCloset.limitedShelf, id: \.id) { item in tile(item) }
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .onDisappear {
            hovered = nil
            store.tryOn(nil)
        }
    }

    private func tile(_ item: PetItem) -> some View {
        let progress = item.limitedEdition.flatMap { store.milestones.progress(of: $0, today: .now) }
        return ClosetLimitedTile(item: item, state: store.closet.state(of: item), progress: progress,
                                 model: thumbnailModel) {
            withMotion(Theme.Motion.snappy) { _ = store.tap(item) }
        } onHover: { inside in
            if inside { hovered = item } else if hovered == item { hovered = nil }
            store.tryOn(hovered)
        }
    }

    private var thumbnailModel: PetProfile {
        PetProfile(name: store.profile.name, breed: store.profile.breed,
                   paletteOverrides: store.profile.paletteOverrides, furTint: store.profile.furTint)
    }

    /// How to earn the hovered item, or what the shelf is.
    private var footer: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let hovered, let edition = hovered.limitedEdition {
                Text(hovered.displayName).foregroundStyle(Theme.Palette.secondaryText)
                Text(store.closet.state(of: hovered).isOwned ? "Earned. Click to \(hint(for: hovered))."
                     : edition.howToEarn)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            } else {
                Text("Earned by studying, never sold").foregroundStyle(Theme.Palette.secondaryText)
                Text("\(earnedCount) of \(PetCloset.limitedShelf.count) earned")
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .monospacedDigit()
            }
        }
        .font(Theme.Typography.caption)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(height: 12)
    }

    private var earnedCount: Int {
        PetCloset.limitedShelf.filter { store.closet.state(of: $0).isOwned }.count
    }

    private func hint(for item: PetItem) -> String {
        store.closet.state(of: item) == .wearing ? "take off" : "wear"
    }
}

/// A limited edition tile: the item on the pet, a sparkle badge, and below
/// it either On, Owned, the milestone's progress with a thin bar, or Event.
private struct ClosetLimitedTile: View {
    let item: PetItem
    let state: PetClosetItemState
    let progress: PetLimitedProgress?
    let model: PetProfile
    let action: () -> Void
    let onHover: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                Spacer(minLength: 0)
                // Bigger than a wardrobe tile when the row has the room.
                ViewThatFits {
                    sprite(pixelSize: 2)
                    sprite(pixelSize: 1)
                }
                label
                bar
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(state.isOwned ? accent : Theme.Palette.tertiaryText)
                    .padding(Theme.Spacing.xs)
                    .allowsHitTesting(false)
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
        .onHover { inside in
            hovering = inside
            onHover(inside)
        }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private func sprite(pixelSize: CGFloat) -> some View {
        PetSpriteView(profile: PetCloset.wearing(item, on: model), pixelSize: pixelSize)
            .opacity(state.isOwned ? 1 : 0.45)
            .saturation(state.isOwned ? 1 : 0.3)
    }

    @ViewBuilder private var label: some View {
        Group {
            switch state {
            case .wearing:
                Label("On", systemImage: "checkmark").foregroundStyle(accent)
            case .owned:
                Text("Owned").foregroundStyle(Theme.Palette.secondaryText)
            default:
                if let progress {
                    Text(progress.label).foregroundStyle(Theme.Palette.secondaryText)
                } else {
                    Label("Event", systemImage: "calendar").foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
        .labelStyle(ClosetTightLabelStyle())
        .lineLimit(1)
        .frame(height: 12)
    }

    /// The milestone's progress; an empty slot of the same height otherwise,
    /// so every label in the row lines up.
    private var bar: some View {
        Capsule()
            .fill(Theme.Palette.surfaceHover)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(accent)
                        .frame(width: proxy.size.width * (progress?.fraction ?? 0))
                }
            }
            .frame(width: 40, height: 3)
            .opacity(!state.isOwned && progress != nil ? 1 : 0)
    }

    private var help: String {
        let howToEarn = item.limitedEdition?.howToEarn ?? ""
        return switch state {
        case .wearing: "\(item.displayName), limited edition: click to take off"
        case .owned: "\(item.displayName), limited edition: click to wear"
        default: "\(item.displayName), limited edition: \(howToEarn)"
        }
    }
}

// MARK: - Streak

/// Snowflakes mark frozen days in an icy blue that reads on every theme.
private let frostColor = Color(red: 0.56, green: 0.82, blue: 1.0)

/// The study streak: its length, the last seven days (a snowflake on each
/// day a freeze protected) and the freezes ready, with a button to buy an
/// extra one with points.
private struct ClosetStreak: View {
    @ObservedObject var store: ClosetStore

    var body: some View {
        let streak = store.streak
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            summary(streak)
            ClosetStreakStrip(days: streak.recentDays(7))
            Spacer(minLength: 0)
            footer(streak)
        }
    }

    private func summary(_ streak: StudyStreak) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text("\(streak.length)")
                .font(Theme.Typography.metric)
                .foregroundStyle(streak.isActive ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                .contentTransition(.numericText())
            Text(streak.length == 1 ? "day" : "days")
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text(status(streak))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, Theme.Spacing.xs)
        }
        .motion(Theme.Motion.snappy, value: streak.length)
    }

    private func status(_ streak: StudyStreak) -> String {
        if streak.studiedToday { return "Studied today" }
        if streak.isActive { return "Focus today to keep it going" }
        return "Focus \(Int(PetMilestoneProgress.minutesForStudyDay)) min to start one"
    }

    private func footer(_ streak: StudyStreak) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "snowflake")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(streak.freezesReady > 0 ? frostColor : Theme.Palette.tertiaryText)
            ViewThatFits(in: .horizontal) {
                Text(freezes(streak, short: false))
                Text(freezes(streak, short: true))
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.secondaryText)
            .lineLimit(1)
            .monospacedDigit()
            .help("A missed day uses a freeze, so the streak keeps going. "
                  + "You get one free freeze each week, and can hold \(StreakFreezeRules.maxHeld) extra.")
            Spacer(minLength: Theme.Spacing.s)
            ClosetBuyFreezeButton(streak: streak, balance: store.closet.balance) {
                withMotion(Theme.Motion.snappy) { _ = store.buyStreakFreeze() }
            }
        }
    }

    private func freezes(_ streak: StudyStreak, short: Bool) -> String {
        let free = streak.freeFreezeAvailable ? (short ? "1 free" : "1 free this week") : (short ? "Free used" : "Free freeze used")
        guard streak.extraFreezes > 0 else { return free }
        return "\(free), \(streak.extraFreezes) extra"
    }
}

/// The last days, oldest first: a filled dot for a study day, a snowflake
/// for a frozen one, a faint ring for a miss, and a dashed ring for today
/// while it is still open.
private struct ClosetStreakStrip: View {
    let days: [StreakDay]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.day) { index, day in
                if index > 0 { Spacer(minLength: Theme.Spacing.xs) }
                VStack(spacing: Theme.Spacing.xxs) {
                    mark(day.state)
                        .frame(width: 24, height: 24)
                    Text(letter(day.day))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(index == days.count - 1 ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
                        .frame(height: 12)
                }
                .help(help(day))
            }
        }
        .padding(.horizontal, Theme.Spacing.xxs)
    }

    @ViewBuilder private func mark(_ state: StreakDay.State) -> some View {
        switch state {
        case .studied:
            Circle().fill(accent)
                .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.Palette.background))
        case .frozen:
            Circle().fill(frostColor.opacity(0.18))
                .overlay(Circle().strokeBorder(frostColor.opacity(0.5), lineWidth: 1))
                .overlay(Image(systemName: "snowflake").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(frostColor))
        case .missed:
            Circle().strokeBorder(Theme.Palette.stroke, lineWidth: 1)
        case .today:
            Circle().strokeBorder(accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
        }
    }

    private func letter(_ day: PlannerDayKey) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return calendar.veryShortStandaloneWeekdaySymbols[weekday - 1]
    }

    private func help(_ day: StreakDay) -> String {
        let date = day.day.startDate().formatted(.dateTime.weekday(.wide).month().day())
        return switch day.state {
        case .studied: "\(date): studied"
        case .frozen: "\(date): missed, a streak freeze kept the streak"
        case .missed: "\(date): no study"
        case .today: "Today: no study yet"
        }
    }
}

/// Buys an extra streak freeze for its price in points. Disabled, with a
/// tooltip that says why, when the points are short or the most extras are
/// already held.
private struct ClosetBuyFreezeButton: View {
    let streak: StudyStreak
    let balance: Int
    let action: () -> Void
    @State private var hovering = false

    private var enabled: Bool { streak.canBuyFreeze && balance >= StreakFreezeRules.price }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Buy freeze")
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: "star.fill").font(.system(size: 8, weight: .bold))
                    Text("\(StreakFreezeRules.price)").monospacedDigit()
                }
                .foregroundStyle(enabled ? accent : Theme.Palette.tertiaryText)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(enabled ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
            .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xxs)
            .frame(height: 22)
            .background(Capsule().fill(enabled && hovering ? accent.opacity(0.24) : enabled ? accent.opacity(0.14)
                                       : Theme.Palette.surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private var help: String {
        if !streak.canBuyFreeze {
            return "You hold \(StreakFreezeRules.maxHeld) extra freezes, the most at once"
        }
        let missing = StreakFreezeRules.price - balance
        if missing > 0 {
            return "An extra freeze costs \(StreakFreezeRules.price) points: \(missing) more, "
                + "\(PetEconomy.studyToEarn(missing)) at a typical study pace"
        }
        return "Buy an extra freeze for \(StreakFreezeRules.price) points. It protects a missed day "
            + "once this week's free freeze is used."
    }
}

// MARK: - Look

private struct ClosetLook: View {
    @ObservedObject var store: ClosetStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            row("Pet") {
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(PetSpecies.allCases, id: \.self) { species in
                        ClosetPill(title: species.displayName,
                                   symbol: species == .cat ? "cat.fill" : "dog.fill",
                                   isSelected: store.profile.species == species,
                                   help: "Make your pet a \(species.displayName.lowercased())") {
                            withMotion(Theme.Motion.snappy) { store.setSpecies(species) }
                        }
                    }
                }
            }
            row("Breed") {
                HStack(spacing: Theme.Spacing.s) {
                    IconButton(symbol: "chevron.left", size: 22, help: "Previous breed") {
                        store.cycleBreed(by: -1)
                    }
                    Text(store.profile.breed.displayName)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(1)
                        .frame(width: 120)
                    IconButton(symbol: "chevron.right", size: 22, help: "Next breed") {
                        store.cycleBreed(by: 1)
                    }
                }
            }
            row("Fur") {
                HStack(spacing: Theme.Spacing.s - Theme.Spacing.xxs) {
                    ClosetSwatch(color: nil, isSelected: store.closet.furTint == nil) {
                        store.tintFur(nil)
                    }
                    ForEach(PetCloset.furSwatches, id: \.self) { color in
                        ClosetSwatch(color: color, isSelected: store.closet.furTint == color) {
                            store.tintFur(color)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .frame(width: 40, alignment: .leading)
            content()
        }
        .frame(height: 22)
    }
}

/// A round fur-color swatch; `nil` is the breed's own colors. Onboarding's
/// pet step shows the same swatches.
struct ClosetSwatch: View {
    let color: PetColor?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if let color {
                    Circle().fill(Color(red: Double(color.red) / 255, green: Double(color.green) / 255,
                                        blue: Double(color.blue) / 255))
                } else {
                    Circle().fill(Theme.Palette.surfaceHover)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
            .padding(2)
            .overlay(
                Circle().strokeBorder(isSelected ? accent : hovering ? Theme.Palette.secondaryText : .clear,
                                      lineWidth: 1.5)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.map { PetCloset.name(ofSwatch: $0) ?? "Fur color \($0.hex)" } ?? "Breed colors")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isSelected)
    }
}
