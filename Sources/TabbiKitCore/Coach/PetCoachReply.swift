import Foundation

/// A button on the coach's speech bubble. Every answer sends the pet home;
/// what else happens is up to the app (pause or resume the timer, snooze).
public enum PetCoachReply: String, Codable, CaseIterable, Hashable, Sendable {
    /// "Back to it": the user is heading back. Nothing else changes.
    case backToIt
    /// "Still here": answers an idle check; the timer keeps running.
    case stillHere
    /// Pause the study timer.
    case pause
    /// Resume a timer the coach paused.
    case resume
    /// Silence the coach for `PetCoachReply.snoozeDuration`.
    case snooze
    /// "Yay!": closes a celebration bubble. Nothing else changes.
    case thanks

    /// How long "Snooze" keeps the pet quiet.
    public static let snoozeDuration: TimeInterval = 15 * 60

    /// The button's label, short enough for a small bubble.
    public var title: String {
        switch self {
        case .backToIt: "Back to it"
        case .stillHere: "Still here"
        case .pause: "Pause"
        case .resume: "Resume"
        case .snooze: "Snooze 15 min"
        case .thanks: "Yay!"
        }
    }

    /// The tooltip, saying exactly what the click does.
    public var help: String {
        switch self {
        case .backToIt, .thanks: "Send your pet back to the notch"
        case .stillHere: "Keep the timer running"
        case .pause: "Pause the study timer"
        case .resume: "Resume the study timer"
        case .snooze: "No nudges for the next 15 minutes"
        }
    }

    /// Whether the app should pause the study timer on this answer.
    public var pausesTimer: Bool { self == .pause }
    /// Whether the app should resume the study timer on this answer.
    public var resumesTimer: Bool { self == .resume }
}

extension PetCoachNudgeKind {
    /// The bubble's buttons, the kind default first. Snooze is always last
    /// and always there, so the user can quiet the pet from any bubble.
    public var replies: [PetCoachReply] {
        switch self {
        case .distraction: [.backToIt, .snooze]
        case .offerPause: [.pause, .backToIt, .snooze]
        case .idleCheck: [.stillHere, .pause, .snooze]
        case .autoPause: [.resume, .snooze]
        }
    }
}

extension PetCoach {
    /// Applies the coach's part of `reply`: snooze silences every nudge for
    /// `PetCoachReply.snoozeDuration`. Timer changes are the app's job.
    public mutating func handle(_ reply: PetCoachReply, at now: Date) {
        if reply == .snooze { snooze(for: PetCoachReply.snoozeDuration, at: now) }
    }
}
