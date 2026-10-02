import Foundation

/// Everything the user chose about their study buddy: who it is (name,
/// breed), how it is colored, and what it wears.
///
/// The species is derived from the breed so the two can never disagree.
/// Decoding is forgiving on purpose: a profile saved by a newer build (an
/// unknown accessory, a new palette role) or edited by hand still loads, and
/// anything invalid is dropped instead of failing the whole file.
public struct PetProfile: Hashable, Codable, Sendable {
    /// Longest name shown under the pet; longer names are cut, not rejected.
    public static let maxNameLength = 16

    public private(set) var name: String
    public var breed: PetBreed
    /// User colors layered over the breed palette. Only
    /// `PetPaletteRole.userEditable` roles are kept.
    public private(set) var paletteOverrides: [PetPaletteRole: PetColor]
    public var outfit: PetOutfit
    /// Always wearable: at most one per slot, in drawing order.
    public private(set) var accessories: [PetAccessory]

    public var species: PetSpecies { breed.species }

    public init(
        name: String,
        breed: PetBreed,
        paletteOverrides: [PetPaletteRole: PetColor] = [:],
        outfit: PetOutfit = .none,
        accessories: [PetAccessory] = []
    ) {
        self.name = PetProfile.cleanName(name, breed: breed)
        self.breed = breed
        self.paletteOverrides = paletteOverrides.filter { PetPaletteRole.userEditable.contains($0.key) }
        self.outfit = outfit
        self.accessories = PetAccessory.wearable(accessories)
    }

    /// A fresh, undressed pet for someone who just picked a species.
    public static func starter(_ species: PetSpecies) -> PetProfile {
        switch species {
        case .cat: PetProfile(name: "Mochi", breed: .orangeTabby)
        case .dog: PetProfile(name: "Biscuit", breed: .goldenRetriever)
        }
    }

    // MARK: Editing

    public mutating func rename(_ newName: String) {
        name = PetProfile.cleanName(newName, breed: breed)
    }

    /// Recolors one role, or clears the override with `nil`. Fixed roles
    /// (eyes, outline, effects) are ignored so every pet stays readable.
    public mutating func setColor(_ color: PetColor?, for role: PetPaletteRole) {
        guard PetPaletteRole.userEditable.contains(role) else { return }
        paletteOverrides[role] = color
    }

    public mutating func resetColors() {
        paletteOverrides = [:]
    }

    /// Puts an accessory on, replacing whatever was in the same slot.
    public mutating func wear(_ accessory: PetAccessory) {
        accessories = PetAccessory.wearable(accessories + [accessory])
    }

    public mutating func takeOff(_ accessory: PetAccessory) {
        accessories.removeAll { $0 == accessory }
    }

    public func isWearing(_ item: PetItem) -> Bool {
        switch item {
        case .outfit(let outfit): self.outfit == outfit
        case .accessory(let accessory): accessories.contains(accessory)
        }
    }

    // MARK: Rendering

    /// The colors to render with: breed defaults, then user overrides, then
    /// the warm rim for dark fur so a recolored black pet never vanishes.
    public var palette: PetPalette {
        breed.palette.applying(paletteOverrides).withVisibleRim()
    }

    /// The pet sitting in its current outfit and accessories.
    public func sittingCanvas() -> PetCanvas {
        PetComposer.sitting(breed, outfit: outfit, accessories: accessories)
    }

    /// A copy with anything the ledger does not own taken off, so a profile
    /// can never show an item the user has not unlocked.
    public func restricted(to ledger: PetPointsLedger) -> PetProfile {
        var copy = self
        if !ledger.owns(.outfit(outfit)) { copy.outfit = .none }
        copy.accessories = accessories.filter { ledger.owns(.accessory($0)) }
        return copy
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case name, breed, paletteOverrides, outfit, accessories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The breed is the one field we cannot guess; everything else falls
        // back to a sensible default.
        let breed = try container.decode(PetBreed.self, forKey: .breed)
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let rawColors = try container.decodeIfPresent([String: PetColor].self, forKey: .paletteOverrides) ?? [:]
        var overrides: [PetPaletteRole: PetColor] = [:]
        for (key, color) in rawColors {
            if let role = PetPaletteRole(rawValue: key) { overrides[role] = color }
        }
        let rawOutfit = try container.decodeIfPresent(String.self, forKey: .outfit) ?? ""
        let rawAccessories = try container.decodeIfPresent([String].self, forKey: .accessories) ?? []
        self.init(
            name: name,
            breed: breed,
            paletteOverrides: overrides,
            outfit: PetOutfit(rawValue: rawOutfit) ?? .none,
            accessories: rawAccessories.compactMap(PetAccessory.init(rawValue:))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(breed, forKey: .breed)
        try container.encode(
            Dictionary(uniqueKeysWithValues: paletteOverrides.map { ($0.key.rawValue, $0.value) }),
            forKey: .paletteOverrides
        )
        try container.encode(outfit, forKey: .outfit)
        try container.encode(accessories, forKey: .accessories)
    }

    /// Trims whitespace, collapses inner runs, and caps the length. An empty
    /// name falls back to the breed name so the pet is never nameless.
    static func cleanName(_ raw: String, breed: PetBreed) -> String {
        let words = raw.split(whereSeparator: \.isWhitespace)
        let joined = words.joined(separator: " ")
        let capped = String(joined.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? breed.displayName : capped
    }
}
