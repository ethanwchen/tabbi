import Foundation

/// The pet a kit starts someone on, from the Closet section of the kit
/// (`moduleSettings.closet.pet`: an optional `breed` and `name`), so the
/// Med School kit can hand out a tabby while another kit picks a corgi.
public extension PetProfile {
    /// The fresh pet for someone with no saved pet yet: the kit's breed
    /// and name when it sets them, otherwise the starter cat. An unknown
    /// breed is skipped, and a kit name without a breed names the cat.
    static func starter(kit: KitDefaults?) -> PetProfile {
        let section = kit?.settings(for: .closet)?["pet"]
        let breed = section?["breed"]?.stringValue.flatMap(PetBreed.init(rawValue:))
        var profile = breed.map { PetProfile(name: defaultName(for: $0), breed: $0) } ?? starter(.cat)
        if let name = section?["name"]?.stringValue { profile.rename(name) }
        return profile
    }

    /// How a kit writes the pet, for the Closet descriptor.
    static let kitSettingType = KitSettingType.object([
        "breed": .choice(PetBreed.allCases.map(\.rawValue)),
        "name": .text(maxLength: maxNameLength),
    ])
}
