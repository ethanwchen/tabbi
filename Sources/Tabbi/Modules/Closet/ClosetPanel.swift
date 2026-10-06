import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Closet tab: the study pet large and animated on the left, and on the
/// right either its wardrobe (wear, take off, or unlock items with study
/// points) or its look (species, breed, fur color).
struct ClosetPanel: View {
    @ObservedObject var store: ClosetStore

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ClosetPetCard(store: store)
                .frame(width: 164)
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        ClosetSectionPicker(selection: $store.section)
                        Spacer(minLength: 0)
                        ClosetPointsChip(balance: store.closet.balance)
                    }
                    switch store.section {
                    case .wardrobe: ClosetWardrobe(store: store)
                    case .look: ClosetLook(store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

enum ClosetSection: String, CaseIterable {
    case wardrobe = "Wardrobe"
    case look = "Look"

    var symbol: String {
        switch self {
        case .wardrobe: "tshirt.fill"
        case .look: "paintpalette.fill"
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
        Card {
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

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(ClosetSection.allCases, id: \.self) { section in
                ClosetPill(title: section.rawValue, symbol: section.symbol,
                           isSelected: selection == section,
                           help: section == .wardrobe ? "Outfits and accessories" : "Species, breed and fur color") {
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
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                Text(title).lineLimit(1)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(isSelected ? accent : hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xxs)
            .frame(height: 22)
            .background(Capsule().fill(isSelected ? accent.opacity(0.16) : hovering ? Theme.Palette.surfaceHover : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// The study-points balance.
private struct ClosetPointsChip: View {
    let balance: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "star.fill").font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent)
            Text("\(balance)")
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.primaryText)
                .contentTransition(.numericText())
            Text("pts")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s - Theme.Spacing.xxs),
                                count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s - Theme.Spacing.xxs) {
            scrollingGrid
            footer
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
                        ForEach(shelf.items, id: \.id) { item in tile(item) }
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

    /// The wardrobe grows with every new item, so it scrolls. `ImageRenderer`
    /// draws a `ScrollView` blank, so snapshots show the top rows clipped.
    @ViewBuilder private var scrollingGrid: some View {
        if RunMode.current.isSnapshot {
            Color.clear
                .overlay(alignment: .top) { grid }
                .clipped()
        } else {
            ScrollView(.vertical) { grid }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// Thumbnails show each item alone on the pet, so the item reads clearly.
    private var thumbnailModel: PetProfile {
        PetProfile(name: store.profile.name, breed: store.profile.breed,
                   paletteOverrides: store.profile.paletteOverrides)
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
                Text("\(next.item.displayName) unlocks at \(next.item.cost)")
                    .foregroundStyle(Theme.Palette.tertiaryText)
            } else if let next = store.closet.nextUnlock {
                Text("Next unlock").foregroundStyle(Theme.Palette.tertiaryText)
                Text(next.item.displayName).foregroundStyle(Theme.Palette.secondaryText)
                Text(next.missing == 0 ? "ready to unlock" : "\(next.missing) pts to go")
                    .foregroundStyle(next.missing == 0 ? accent : Theme.Palette.tertiaryText)
                    .monospacedDigit()
            } else {
                Text("Everything unlocked. Dress up as you like.").foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .font(Theme.Typography.caption)
        .lineLimit(1)
        .frame(height: 12)
    }

    private func detail(for item: PetItem) -> String {
        switch store.closet.state(of: item) {
        case .wearing: "Click to take off"
        case .owned: "Click to wear"
        case .affordable: "Unlock for \(item.cost) pts"
        case .locked(let missing): "\(item.cost) pts, \(missing) to go"
        }
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
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
        .labelStyle(ClosetTightLabelStyle())
        .frame(height: 12)
    }

    private var help: String {
        switch state {
        case .wearing: "\(item.displayName): click to take off"
        case .owned: "\(item.displayName): click to wear"
        case .affordable: "\(isNew ? "New: " : "")\(item.displayName): unlock for \(item.cost) points"
        case .locked(let missing): "\(isNew ? "New: " : "")\(item.displayName): \(item.cost) points, \(missing) more to go"
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
        .help(color.map { "Fur color \($0.hex)" } ?? "Breed colors")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isSelected)
    }
}
