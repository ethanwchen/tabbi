import Foundation

/// Decides when the pet sips from its mug because the Mac started charging:
/// once per plug-in, when the power source switches from the battery to a
/// charger.
///
/// The first reading only sets the baseline, so launching on a charger
/// plays nothing, and a Mac without a battery never switches. A cable that
/// is wiggled in and out cheers once per `cooldown`, not once per contact.
public struct ChargingWatch: Equatable, Sendable {
    /// The shortest time between two sips.
    public static let cooldown: TimeInterval = 60

    /// The last reading, nil before the first one.
    private var onCharger: Bool?
    private var lastSip: Date?

    public init() {}

    /// Records whether the Mac draws power from a charger at `now`, and
    /// returns true when that is a plug-in worth a sip. `nil` (the power
    /// source can't be read) keeps the last reading.
    public mutating func update(onCharger reading: Bool?, at now: Date) -> Bool {
        guard let reading else { return false }
        defer { onCharger = reading }
        guard reading, onCharger == false else { return false }
        if let lastSip, now.timeIntervalSince(lastSip) < Self.cooldown, now >= lastSip { return false }
        lastSip = now
        return true
    }
}
