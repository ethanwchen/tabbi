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
    /// A limited edition item not earned yet. Points cannot buy it.
    case unearned

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
    /// Nothing changed: a limited edition item that has to be earned.
    case notEarnedYet
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
        if let tint = save.profile.furTint, let replacement = PetCloset.retiredSwatches[tint] {
            self.save.profile.tintFur(replacement)
        }
    }

    public var profile: PetProfile { save.profile }
    public var balance: Int { save.ledger.balance }

    // MARK: Wardrobe

    /// The shop items the wardrobe grid shows, cheapest first, free
    /// starters included. "No outfit" is not a tile; tapping the worn outfit
    /// takes it off instead. Limited edition items are on `limitedShelf`.
    public static let wardrobe: [PetItem] = PetItem.shopItems.filter { $0 != .outfit(.none) }

    /// The limited edition items, in `PetLimitedEdition` order.
    public static let limitedShelf: [PetItem] = PetLimitedEdition.allCases.map(\.item)

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
        guard !item.isLimited else { return .unearned }
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
                // Can't happen: the state said the item is a shop item not owned yet.
                case .alreadyOwned, .notForSale: break
                }
            }
            save.profile = PetCloset.wearing(item, on: save.profile)
            return .boughtAndWore
        case .locked(let missing):
            return .needsPoints(missing: missing)
        case .unearned:
            return .notEarnedYet
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

    /// Changes the breed. The fur tint carries over and follows the new
    /// breed's `furTones`, so a picked color looks right on every breed.
    public mutating func setBreed(_ breed: PetBreed) {
        save.profile.breed = breed
    }

    // MARK: Colors

    /// Fur colors offered as swatches: warm orange, caramel, chocolate, a
    /// soft charcoal, silver gray, and cream, then two gentle pastels (lilac
    /// and sky). Each one is checked on every breed: the charcoal is light
    /// enough to keep faces readable without a rim, and the pastels avoid
    /// pink, which would swallow the pink nose and cheeks. `nil` (the
    /// breed's own colors) is offered separately.
    public static let furSwatches: [PetColor] = [
        "#F2A65A", "#C98B5B", "#8A5A3C", "#5E5856", "#A3A9B2", "#F3E2C4", "#B9A7D6", "#9EC3EC",
    ].compactMap(PetColor.init(hex:))

    /// The name shown for a swatch ("Caramel"), or nil for other colors.
    public static func name(ofSwatch color: PetColor) -> String? {
        let names = ["Orange", "Caramel", "Chocolate", "Charcoal", "Silver", "Cream", "Lilac", "Sky"]
        return furSwatches.firstIndex(of: color).map { names[$0] }
    }

    /// Swatches offered by earlier builds, paired with the swatch that took
    /// each one's place, so a pet tinted from a retired swatch keeps a
    /// selected swatch (the near-black charcoal and the pink are gone).
    static let retiredSwatches: [PetColor: PetColor] = {
        let pairs = [("#3B3434", "#5E5856"), ("#9AA3AD", "#A3A9B2"), ("#F4ECE0", "#F3E2C4"),
                     ("#E58FA8", "#B9A7D6"), ("#8FB8E8", "#9EC3EC")]
        return Dictionary(uniqueKeysWithValues: pairs.map { (PetColor(hex: $0.0)!, PetColor(hex: $0.1)!) })
    }()

    /// The picked fur color, or nil for the breed's own colors.
    public var furTint: PetColor? {
        profile.furTint
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

    // MARK: Streak

    /// The study streak on `today`, from the milestones' study days and the
    /// freezes this save has bought.
    public func streak(_ progress: PetMilestoneProgress, today: Date, calendar: Calendar = .current) -> StudyStreak {
        StudyStreak(studyDays: progress.studyDays, freezePurchases: save.ledger.streakFreezes,
                    today: today, calendar: calendar)
    }

    /// Buys an extra streak freeze with points (`StreakFreezeRules`).
    public mutating func buyStreakFreeze(_ progress: PetMilestoneProgress, at date: Date,
                                         calendar: Calendar = .current) throws(StreakFreezePurchaseError) {
        try save.ledger.buyStreakFreeze(for: streak(progress, today: date, calendar: calendar), at: date)
    }

    // MARK: Limited edition

    /// Grants the limited edition items whose milestones `progress` has
    /// reached and returns the ones that are new, for the celebration.
    @discardableResult
    public mutating func unlockMilestones(_ progress: PetMilestoneProgress,
                                          calendar: Calendar = .current) -> [PetItem] {
        PetLimitedEdition.allCases.compactMap { edition in
            guard let milestone = edition.milestone, progress.isReached(milestone, calendar: calendar),
                  save.ledger.grant(edition.item) else { return nil }
            return edition.item
        }
    }

    /// Applies the item ids the Tabbi server granted to this account (event
    /// items such as the launch week cap) and returns the ones that are new.
    /// Unknown ids (from a newer build) and shop items are ignored, and an
    /// item stays owned if a later sync no longer lists it.
    @discardableResult
    public mutating func applyGrants(_ ids: some Sequence<String>) -> [PetItem] {
        let items = Set(ids.compactMap(PetItem.init(id:)))
        return PetCloset.limitedShelf.filter { items.contains($0) && save.ledger.grant($0) }
    }
}

extension PetCloset {
    /// The `TABBI_DEMO=1` closet: a dressed cat a few sessions in, with
    /// the free starters and two buys owned, two items affordable, the rest
    /// still to earn, and the launch week cap granted (with the milestones
    /// part of the way, `PetMilestoneProgress.demo`).
    public static var demo: PetCloset {
        let ledger = PetPointsLedger(
            earned: 165, spent: 85,
            purchased: [.accessory(.beanie), .accessory(.roundGlasses)],
            granted: [PetLimitedEdition.launchWeekCap.item]
        )
        let profile = PetProfile(name: "Mochi", breed: .britishShorthair, accessories: [.scarf, .roundGlasses])
        return PetCloset(save: PetSave(profile: profile, ledger: ledger))
    }
}
