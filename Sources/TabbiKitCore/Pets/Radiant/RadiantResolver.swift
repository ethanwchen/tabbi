import Foundation

/// The Radiant items a pet shows and how strongly: worn, upgraded items
/// whose effect is on. What a profile turns into for drawing
/// (`PetProfile.radiantLook`), and what Party sends for a friend's pet.
public struct PetRadiantLook: Hashable, Sendable {
    public private(set) var intensities: [PetItem: PetRadiantIntensity]

    /// Items without an effect and effects turned off are dropped.
    public init(_ intensities: [PetItem: PetRadiantIntensity] = [:]) {
        self.intensities = intensities.filter { $0.value != .off && PetRadiant.isEligible($0.key) }
    }

    public static let none = PetRadiantLook()

    public var isEmpty: Bool { intensities.isEmpty }

    /// The look limited to what is worn.
    public func worn(outfit: PetOutfit, accessories: [PetAccessory]) -> PetRadiantLook {
        let wearable = PetAccessory.wearable(accessories)
        return PetRadiantLook(intensities.filter { item, _ in
            switch item {
            case .outfit(let o): o == outfit
            case .accessory(let a): wearable.contains(a)
            }
        })
    }
}

/// How the Radiant effects of the items worn together share the frame.
///
/// Each effect lists placements, its preferred one first: the zones its
/// particles may use (`RadiantZone`) and what it draws there. The resolver
/// gives every worn effect one placement so that no zone is used twice, by
/// slot priority (`RadiantArt.slotPriority`: the hat, then the outfit, then
/// the aura): the hat's effect gets its first placement that fits, then the
/// outfit's gets its first that fits beside it, and so on.
/// The chest is held by an outfit or neck item someone else wears, so an
/// effect that crosses it moves aside. Then, if the effects' measured
/// per-tick costs together pass the combined budget on any tick, they take
/// turns: each plays its loop in its own cycle while the others hold their
/// still, which always carries their shimmer.
///
/// Every effect ends on a placement with no zones (drawn on its item only),
/// so a layout always exists. The result depends only on the items worn and
/// their intensities, never on the breed or the frame, so the Mac and Windows
/// resolve every look the same way.
public struct RadiantLayout: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public let item: PetItem
        public let intensity: PetRadiantIntensity
        /// Index into the effect's placements.
        public let placement: Int
        /// The cycle of the Radiant loop this effect plays in, when the
        /// effects take turns; nil when it plays every cycle.
        public let turn: Int?
    }

    /// In drawing order (slot priority).
    public let entries: [Entry]
    /// Cycles of the Radiant loop before the layout repeats: 1, or one per
    /// effect when they take turns.
    public let cycles: Int

    /// Ticks of the item clock before the layout repeats.
    public var loop: Int { RadiantArt.shared.loop * cycles }

    public static func resolve(_ look: PetRadiantLook, outfit: PetOutfit, accessories: [PetAccessory]) -> RadiantLayout? {
        resolve(look, outfit: outfit, accessories: accessories, art: .shared, costs: RadiantArt.costs)
    }

    static func resolve(_ look: PetRadiantLook, outfit: PetOutfit, accessories: [PetAccessory], art: RadiantArt,
                        costs: RadiantCosts) -> RadiantLayout? {
        let worn = look.worn(outfit: outfit, accessories: accessories)
        let effects: [(PetItem, PetRadiantIntensity, RadiantEffectArt)] = worn.intensities.compactMap { item, intensity in
            art.item(item)?.effect(intensity).map { (item, intensity, $0) }
        }.sorted { priority($0.0, art) < priority($1.0, art) }
        guard !effects.isEmpty else { return nil }
        // Zones another worn item's art covers: an outfit or neck item fills the chest.
        let wearable = PetAccessory.wearable(accessories)
        func blocked(for item: PetItem) -> Set<RadiantZone> {
            let chestCovered = (outfit != .none && item != .outfit(outfit))
                || wearable.contains { $0.slot == .neck && item != .accessory($0) }
            return chestCovered ? [.chest] : []
        }
        // In slot priority, each effect takes its first placement whose zones
        // are free. The last placement uses no zones, so one always fits.
        var used = Set<RadiantZone>()
        let placements = effects.map { item, _, effect in
            let n = effect.placements.firstIndex { placement in
                placement.zones.isDisjoint(with: used) && placement.zones.isDisjoint(with: blocked(for: item))
            } ?? effect.placements.count - 1
            used.formUnion(effect.placements[n].zones)
            return n
        }
        // Take turns when the costs together pass the combined budget.
        let rows = zip(effects, placements).map { effect, placement in
            costs.cost(effect.0, effect.1, placement: placement) ?? Array(repeating: costs.perTickBudget, count: art.loop)
        }
        let together = (0..<art.loop).map { t in rows.reduce(0) { $0 + ($1[safeTick: t] ?? 0) } }
        let turns = effects.count > 1 && (together.max() ?? 0) > costs.combinedBudget
        let entries = zip(effects, placements).enumerated().map { n, pair in
            Entry(item: pair.0.0, intensity: pair.0.1, placement: pair.1, turn: turns ? n : nil)
        }
        return RadiantLayout(entries: entries, cycles: turns ? effects.count : 1)
    }

    /// Where an item's slot comes in `slotPriority` (an outfit counts as "outfit").
    static func priority(_ item: PetItem, _ art: RadiantArt) -> Int {
        let slot = switch item {
        case .outfit: "outfit"
        case .accessory(let accessory): String(describing: accessory.slot)
        }
        return art.slotPriority.firstIndex(of: slot) ?? art.slotPriority.count
    }

    /// The tick of each entry's own loop at layout tick `tick`: its loop
    /// tick in its turn, and its still (tick 0) in the others' turns.
    func ticks(at tick: Int, loop: Int) -> [Int] {
        let cycle = (tick / loop) % cycles
        return entries.map { entry in
            guard let turn = entry.turn else { return tick % loop }
            return turn == cycle ? tick % loop : 0
        }
    }
}

private extension Array where Element == Int {
    subscript(safeTick index: Int) -> Int? { indices.contains(index) ? self[index] : nil }
}

/// The Radiant upgrade rules.
public enum PetRadiant {
    /// The items that have a Radiant effect, in catalog order.
    public static var eligibleItems: [PetItem] { RadiantArt.shared.items.map(\.item) }

    public static func isEligible(_ item: PetItem) -> Bool {
        RadiantArt.shared.item(item) != nil
    }

    /// What upgrading `item` costs: `RadiantArt.upgradeMultiplier` times its
    /// price (5x). The upgrade sits outside the price tiers on purpose: it is
    /// a long goal for an item already owned, not a new item.
    public static func price(of item: PetItem) -> Int {
        item.cost * RadiantArt.shared.upgradeMultiplier
    }

    /// The effect's name ("Orbiting Orb") for an intensity, as written in
    /// `radiant.json`, or nil.
    public static func effectName(_ item: PetItem, _ intensity: PetRadiantIntensity) -> String? {
        RadiantArt.shared.item(item)?.effect(intensity)?.name
    }

    /// The effect's name in the user's language. The names stay English in
    /// `radiant.json`, which the Windows port reads too, and are looked up
    /// in the string catalog by that text (`LocalizationTests` checks each
    /// has a translation).
    public static func localizedEffectName(_ item: PetItem, _ intensity: PetRadiantIntensity) -> String? {
        effectName(item, intensity).map { Bundle.tabbi.localizedString(forKey: $0, value: $0, table: nil) }
    }
}
