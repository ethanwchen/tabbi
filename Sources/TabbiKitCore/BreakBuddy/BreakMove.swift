import Foundation

/// One short, healthy thing the pet models at the start of a study break,
/// for the user to copy: a stretch, a sip of water, resting the eyes on
/// something far away, a slow breath, or standing up for a moment.
///
/// Each move is cozy and optional. Nothing here is a health claim: the copy
/// only invites the user to do the move with the pet, and skipping it is
/// always fine.
public enum BreakMove: String, CaseIterable, Codable, Hashable, Sendable {
    case stretch
    case sip
    case eyeRest
    case breathe
    case standUp

    /// The clip the pet loops while it models the move. Resting the eyes has
    /// no clip of its own yet, so the pet sits still and looks out with you.
    /// Standing up reads as the pet up on four legs, trotting in place.
    public var animation: PetAnimation {
        switch self {
        case .stretch: .stretch
        case .sip: .sip
        case .eyeRest: .sit
        case .breathe: .breathe
        case .standUp: .walk
        }
    }

    /// How long the moment lasts when the break has room for it, in seconds
    /// (20 to 60). The planner shortens it to at most half the break.
    public var length: TimeInterval {
        switch self {
        case .stretch: 40
        case .sip: 20
        case .eyeRest: 20
        case .breathe: 30
        case .standUp: 60
        }
    }

    /// The SF Symbol for the move, beside its name in Settings.
    public var symbol: String {
        switch self {
        case .stretch: "figure.flexibility"
        case .sip: "drop.fill"
        case .eyeRest: "eye"
        case .breathe: "wind"
        case .standUp: "figure.stand"
        }
    }

    /// The invitation on the break card and in the closed notch's tooltip,
    /// e.g. "Stretch with Mochi". Without a name (`buddyName(for:)`), the
    /// stretch is "Time for a stretch".
    public func title(petName: String?) -> String {
        switch self {
        case .stretch:
            if let petName { String(localized: "Stretch with \(petName)", bundle: .tabbi) }
            else { String(localized: "Time for a stretch", bundle: .tabbi) }
        case .sip: String(localized: "Sip some water", bundle: .tabbi)
        case .eyeRest: String(localized: "Look at something far away", bundle: .tabbi)
        case .breathe: String(localized: "A slow breath in, and out", bundle: .tabbi)
        case .standUp: String(localized: "Stand up for a moment", bundle: .tabbi)
        }
    }

    /// One gentle line under the title saying how to do the move.
    public var prompt: String {
        switch self {
        case .stretch: String(localized: "Reach your arms up high, then roll your shoulders back.", bundle: .tabbi)
        case .sip: String(localized: "Grab your glass and take a few sips.", bundle: .tabbi)
        case .eyeRest: String(localized: "Let your eyes rest on something across the room or out the window.", bundle: .tabbi)
        case .breathe: String(localized: "Breathe in slowly, then let it all out.", bundle: .tabbi)
        case .standUp: String(localized: "Stand, shake out your legs, and sit back down when you like.", bundle: .tabbi)
        }
    }

    /// The pet's name for the break buddy's lines, or nil while it still goes
    /// by its breed's name ("Stretch with British Shorthair" reads oddly).
    public static func buddyName(for profile: PetProfile) -> String? {
        PetBreed.allCases.contains { $0.displayName == profile.name } ? nil : profile.name
    }

    /// The move's short name, for Settings' switches.
    public var name: String {
        switch self {
        case .stretch: String(localized: "Stretch", bundle: .tabbi)
        case .sip: String(localized: "Sip water", bundle: .tabbi)
        case .eyeRest: String(localized: "Rest your eyes", bundle: .tabbi)
        case .breathe: String(localized: "Slow breath", bundle: .tabbi)
        case .standUp: String(localized: "Stand up", bundle: .tabbi)
        }
    }
}
