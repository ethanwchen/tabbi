import Foundation

/// A short moment where the pet beside the closed notch celebrates a real
/// event: a little dance with a sparkle burst when a focus session
/// finishes, a tiny crown when a goal for today is reached, or a sip from
/// its mug when the Mac starts charging.
///
/// It takes the closed notch over for `length` (a few seconds), even
/// when the ticker was showing something else, and then the ticker carries
/// on where it was. It is a value, so the ticker can tell when it is over
/// without a timer of its own.
public struct PetCheer: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// A focus session finished: two happy hops with sparkles.
        case dance
        /// A goal for today was reached (Anki reviews, a daily focus time
        /// goal): one hop, wearing a tiny crown while the cheer lasts.
        case crown
        /// The Mac started charging: one hop, then a sip from the tiny mug
        /// while a charging bolt shows beside the notch.
        case sip
    }

    public let kind: Kind
    /// Grows with each cheer, so two cheers in a row are still two changes.
    public let id: Int
    public let startedAt: Date

    public init(kind: Kind, id: Int, startedAt: Date) {
        self.kind = kind
        self.id = id
        self.startedAt = startedAt
    }

    /// How long a cheer holds the closed notch: long enough for two hops
    /// and the burst, short enough never to get in the way.
    public static let duration: TimeInterval = 2.2
    /// How long a sip holds the closed notch: the hop, then the mug's
    /// steam and the sip itself (the coffee clip raises the mug about three
    /// seconds in), ending on the pet's happy eyes.
    public static let sipDuration: TimeInterval = 4.6

    /// How long this cheer holds the closed notch.
    public var length: TimeInterval { kind == .sip ? Self.sipDuration : Self.duration }

    /// When the pet goes back to what it was doing.
    public var endsAt: Date { startedAt.addingTimeInterval(length) }

    /// Whether the cheer is on screen at `date`. A clock set back before the
    /// start shows nothing rather than a cheer that never ends.
    public func isShowing(at date: Date) -> Bool {
        date >= startedAt && date < endsAt
    }
}

public extension TickerSources {
    /// The closed-notch item while `cheer` plays at `now`: the pet in its
    /// current mood, cheering (for `.crown` wearing the Closet's Tiny Crown
    /// in place of its hat, for `.sip` holding its mug). Nil when the cheer is over or there is no
    /// pet to show (the Closet is off or the user hid the pet preview), so
    /// the ticker's normal rotation keeps the notch.
    func cheering(_ cheer: PetCheer?, at now: Date, enabled: (TickerKind) -> Bool) -> TickerItem? {
        guard let cheer, cheer.isShowing(at: now), enabled(.pet),
              case .pet(var pet) = items(at: now, enabled: [.pet]).first else { return nil }
        pet.cheer = cheer
        switch cheer.kind {
        case .dance: break
        case .crown: pet.profile.wear(.tinyCrown)
        case .sip: pet.mood = .onBreak
        }
        return .pet(pet)
    }
}
