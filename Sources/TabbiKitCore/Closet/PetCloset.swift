import Foundation

/// Where a costume item stands for the Closet tab's wardrobe grid.
public enum PetClosetItemState: Hashable, Sendable {
    /// Owned and on the pet right now.
    case wearing
    /// Owned, not worn.
    case owned
    /// Not owned yet, and the balance covers it.
    case affordable
    /// Not owned yet; `missing` more points are needed.
    case locked(missing: Int)

    public var isOwned: Bool { self == .wearing || self == .owned }
}

/// What a tap on a wardrobe tile did.
public enum PetClosetTapResult: Hashable, Sendable {
    case wore
    case tookOff
    /// Bought with points and put on right away.
    case boughtAndWore
    /// Nothing changed: `missing` more points are needed.
    case needsPoints(missing: Int)
}

/// The Closet tab's editing rules over one `PetSave`: renaming, switching
/// species and breed, recoloring fur from swatches, and one-tap wardrobe
/// tiles that wear, take off, or buy an item.
///
/// Every edit keeps the save valid (a pet only ever wears owned items), so
/// the app can persist `save` after any call without further checks.
public struct PetCloset: Hashable, Sendable {
    public internal(set) var save: PetSave

    public init(save: PetSave) {
        self.save = save
    }

    public var profile: PetProfile { save.profile }
    public var balance: Int { save.ledger.balance }

    // MARK: Wardrobe

    /// The items the wardrobe grid shows, cheapest first, free starters
    /// included. "No outfit" is not a tile; tapping the worn outfit takes it
    /// off instead.
    public static let wardrobe: [PetItem] = PetItem.allCases.filter { $0 != .outfit(.none) }

    /// The wardrobe grouped by theme in shelf order, each shelf cheapest
    /// first. Together the shelves hold every wardrobe item once.
    public static let shelves: [(theme: PetItemTheme, items: [PetItem])] =
        PetItemTheme.allCases.map { ($0, $0.items) }.filter { !$0.items.isEmpty }

    /// Whether the tile shows a "New" badge: fresh in the catalog and not
    /// owned yet, so the badge goes away once the item is unlocked.
    public func isNew(_ item: PetItem) -> Bool {
        item.isNew && !save.ledger.owns(item)
    }

    public func state(of item: PetItem) -> PetClosetItemState {
        if save.ledger.owns(item) {
            return profile.isWearing(item) ? .wearing : .owned
        }
        let missing = item.cost - balance
        return missing <= 0 ? .affordable : .locked(missing: missing)
    }

    /// One tap on a tile: owned items toggle on and off, affordable items are
    /// bought and worn, locked items change nothing.
    @discardableResult
    public mutating func tap(_ item: PetItem) -> PetClosetTapResult {
        switch state(of: item) {
        case .wearing:
            var profile = save.profile
            switch item {
            case .outfit: profile.outfit = .none
            case .accessory(let accessory): profile.takeOff(accessory)
            }
            save.profile = profile
            return .tookOff
        case .owned:
            save.profile = PetCloset.wearing(item, on: save.profile)
            return .wore
        case .affordable:
            do {
                try save.ledger.buy(item)
            } catch {
                switch error {
                case .notEnoughPoints(let missing): return .needsPoints(missing: missing)
                // Can't happen: the state said the item is not owned.
                case .alreadyOwned: break
                }
            }
            save.profile = PetCloset.wearing(item, on: save.profile)
            return .boughtAndWore
        case .locked(let missing):
            return .needsPoints(missing: missing)
        }
    }

    /// The profile with `item` put on, for hover previews ("try it on")
    /// as well as real changes. Ownership is not checked here.
    public static func wearing(_ item: PetItem, on profile: PetProfile) -> PetProfile {
        var profile = profile
        switch item {
        case .outfit(let outfit): profile.outfit = outfit
        case .accessory(let accessory): profile.wear(accessory)
        }
        return profile
    }

    // MARK: Identity

    public mutating func rename(_ name: String) {
        save.profile.rename(name)
    }

    /// Switches between cat and dog. The pet gets the species' first breed;
    /// a name that was only a default (the starter name or a breed name)
    /// follows the new species, while a name the user chose is kept. The fur
    /// tint carries over.
    public mutating func setSpecies(_ species: PetSpecies) {
        let current = profile
        guard current.species != species, let breed = PetBreed.breeds(of: species).first else { return }
        setBreed(breed)
        save.profile.rename(current.hasDefaultName ? PetProfile.defaultName(for: breed) : current.name)
    }

    /// Steps through the current species' breeds, wrapping at both ends.
    public mutating func cycleBreed(by offset: Int) {
        let breeds = PetBreed.breeds(of: profile.species)
        guard let index = breeds.firstIndex(of: profile.breed), !breeds.isEmpty else { return }
        let next = ((index + offset) % breeds.count + breeds.count) % breeds.count
        setBreed(breeds[next])
    }

    /// Changes the breed and re-derives the fur tint from the new breed's
    /// shading, so a picked color looks right on every breed.
    public mutating func setBreed(_ breed: PetBreed) {
        let tint = furTint
        var profile = save.profile
        profile.breed = breed
        profile.tintFur(tint)
        save.profile = profile
    }

    // MARK: Colors

    /// Fur colors offered as swatches: warm and cool naturals first, then a
    /// few playful ones. `nil` (the breed's own colors) is offered separately.
    public static let furSwatches: [PetColor] = [
        "#F2A65A", "#C98B5B", "#8A5A3C", "#3B3434", "#9AA3AD", "#F4ECE0", "#E58FA8", "#8FB8E8",
    ].compactMap(PetColor.init(hex:))

    /// The picked fur color, or nil for the breed's own colors. A tint makes
    /// the picked color the fur base, so that is where it is read back from.
    public var furTint: PetColor? {
        profile.paletteOverrides[.furBase]
    }

    public mutating func tintFur(_ color: PetColor?) {
        save.profile.tintFur(color)
    }

    // MARK: Points

    /// Credits a study session; see `PetPointsRules`.
    @discardableResult
    public mutating func recordStudy(minutes: Int, completed: Bool) -> Int {
        save.ledger.recordStudy(minutes: minutes, completed: completed)
    }

    /// The cheapest item not owned yet, and how many points it still needs
    /// (0 when it is already affordable).
    public var nextUnlock: (item: PetItem, missing: Int)? {
        save.ledger.nextUnlock.map { ($0, max(0, $0.cost - balance)) }
    }
}

extension PetCloset {
    /// The `TABBI_DEMO=1` closet: a dressed cat a few sessions in, with
    /// the free starters and two buys owned, two items affordable, and the
    /// rest still to earn.
    public static var demo: PetCloset {
        let ledger = PetPointsLedger(
            earned: 160, spent: 75,
            purchased: [.accessory(.beanie), .accessory(.roundGlasses)]
        )
        let profile = PetProfile(name: "Mochi", breed: .britishShorthair, accessories: [.scarf, .roundGlasses])
        return PetCloset(save: PetSave(profile: profile, ledger: ledger))
    }
}
