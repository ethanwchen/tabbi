import Foundation

/// What a pet-coach nudge is about. The UI picks buttons from this.
public enum PetCoachNudgeKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// A gentle "head back?" bubble after a while in a distracting app.
    case distraction
    /// The kind next step: offer to pause the timer (buttons: Pause / Back to it).
    case offerPause
    /// No input for a while. Reading looks idle, so only ask
    /// (buttons: Still studying / Pause).
    case idleCheck
    /// Away long enough that the app pauses the timer so the time isn't counted.
    case autoPause
}

/// One line the pet can say.
public struct PetCoachMessage: Codable, Hashable, Sendable, Identifiable {
    /// Stable id, used to avoid repeating recent lines.
    public var id: String
    public var kind: PetCoachNudgeKind
    public var text: String

    public init(id: String, kind: PetCoachNudgeKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

/// The pet's lines and a picker that keeps them varied.
///
/// Copy rules (from the research notes): short enough for a notch bubble,
/// warm, a little med-school flavored, and never shaming. No counting
/// slip-ups, no guilt, no "you should".
public enum PetCoachMessages {
    /// Longest line, in characters, that fits a notch speech bubble.
    public static let maxLength = 64

    public static let all: [PetCoachMessage] = [
        m("distraction.flashcards", .distraction, "Your flashcards miss you. Back for a few more?"),
        m("distraction.krebs", .distraction, "The Krebs cycle is saving your seat."),
        m("distraction.nextCard", .distraction, "Psst, the next card might be the one on the exam."),
        m("distraction.detour", .distraction, "Brains need detours too. Ready to head back?"),
        m("distraction.warm", .distraction, "Your study block is still warm. Pick it back up?"),
        m("distraction.residents", .distraction, "Even residents check their phones. Back when ready."),

        m("offerPause.breather", .offerPause, "A breather is part of the plan. Pause for now?"),
        m("offerPause.fresh", .offerPause, "Want me to pause the clock so you come back fresh?"),
        m("offerPause.taking5", .offerPause, "Taking five? I can pause the timer for you."),
        m("offerPause.realBreak", .offerPause, "Looks like a real break might help. Pause?"),
        m("offerPause.rounds", .offerPause, "Step off the wards for a bit? I'll hold your spot."),

        m("idleCheck.reading", .idleCheck, "Still studying? Reading counts too."),
        m("idleCheck.firstAid", .idleCheck, "Deep in First Aid? Just checking you're here."),
        m("idleCheck.vignette", .idleCheck, "Thinking through a vignette? Tap if you're here."),
        m("idleCheck.quiet", .idleCheck, "Quiet over here. Still with me?"),
        m("idleCheck.clock", .idleCheck, "Still going? Tap yes and I'll keep the clock running."),

        m("autoPause.away", .autoPause, "You stepped away, so I paused the clock. No rush."),
        m("autoPause.honest", .autoPause, "Timer paused so your stats stay honest. Resume anytime."),
        m("autoPause.hydrate", .autoPause, "Paused for now. Hydrate, stretch, then back at it."),
        m("autoPause.welcome", .autoPause, "Paused while you were away. Welcome back anytime."),
    ]

    public static func messages(for kind: PetCoachNudgeKind) -> [PetCoachMessage] {
        all.filter { $0.kind == kind }
    }

    /// Picks a line of `kind`, skipping ids in `recentIDs` while any other
    /// line is left. If every line was used recently, it still avoids the
    /// most recent one so the same line never shows twice in a row.
    public static func pick<G: RandomNumberGenerator>(
        _ kind: PetCoachNudgeKind,
        avoiding recentIDs: [String] = [],
        using generator: inout G
    ) -> PetCoachMessage {
        let pool = messages(for: kind)
        let recent = Set(recentIDs)
        var candidates = pool.filter { !recent.contains($0.id) }
        if candidates.isEmpty, let last = recentIDs.last {
            candidates = pool.filter { $0.id != last }
        }
        if candidates.isEmpty { candidates = pool }
        return candidates.randomElement(using: &generator)!
    }

    private static func m(_ id: String, _ kind: PetCoachNudgeKind, _ text: String) -> PetCoachMessage {
        PetCoachMessage(id: id, kind: kind, text: text)
    }
}
