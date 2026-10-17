import Foundation

extension TickerSources {
    /// The pet item while it models a break move (`TickerPet.breakMoment`),
    /// which takes the closed notch for the moment like a cheer does, so
    /// the user sees what to copy; nil when no moment shows or the pet's
    /// preview is off. A cheer playing still comes first.
    public func guiding(at now: Date, enabled: (TickerKind) -> Bool) -> TickerItem? {
        guard enabled(.pet), let moment = pet?.breakMoment, moment.isShowing(at: now),
              case .pet(let pet) = items(at: now, enabled: [.pet]).first, pet.breakMoment != nil else { return nil }
        return .pet(pet)
    }
}
