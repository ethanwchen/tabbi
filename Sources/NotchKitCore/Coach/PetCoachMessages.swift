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
/// warm, and never shaming. No counting slip-ups, no guilt, no "you should".
/// The `standard` lines name no subject, so any kit can use them; a kit adds
/// its own flavor (cardiology, case law, LeetCode) through
/// `lines(kitSettings:)` instead of core hardcoding one field of study.
public enum PetCoachMessages {
    /// Longest line, in characters, that fits a notch speech bubble.
    public static let maxLength = 64

    /// Subject-free lines every kit gets.
    public static let standard: [PetCoachMessage] = [
        m("distraction.notes", .distraction, "Your notes miss you. Back for a few more minutes?"),
        m("distraction.seat", .distraction, "Your study spot is saving your seat."),
        m("distraction.nextPage", .distraction, "Psst, the next page might be the one that clicks."),
        m("distraction.detour", .distraction, "Brains need detours too. Ready to head back?"),
        m("distraction.warm", .distraction, "Your study block is still warm. Pick it back up?"),
        m("distraction.phones", .distraction, "Everyone checks their phone. Back when ready."),

        m("offerPause.breather", .offerPause, "A breather is part of the plan. Pause for now?"),
        m("offerPause.fresh", .offerPause, "Want me to pause the clock so you come back fresh?"),
        m("offerPause.taking5", .offerPause, "Taking five? I can pause the timer for you."),
        m("offerPause.realBreak", .offerPause, "Looks like a real break might help. Pause?"),

        m("idleCheck.reading", .idleCheck, "Still studying? Reading counts too."),
        m("idleCheck.thinking", .idleCheck, "Thinking something through? Tap if you're here."),
        m("idleCheck.quiet", .idleCheck, "Quiet over here. Still with me?"),
        m("idleCheck.clock", .idleCheck, "Still going? Let me know and I'll keep the clock running."),

        m("autoPause.away", .autoPause, "You stepped away, so I paused the clock. No rush."),
        m("autoPause.honest", .autoPause, "Timer paused so your stats stay honest. Resume anytime."),
        m("autoPause.hydrate", .autoPause, "Paused for now. Hydrate, stretch, then back at it."),
        m("autoPause.welcome", .autoPause, "Paused while you were away. Welcome back anytime."),
    ]

    /// The standard lines plus the kit's own, read from the pet module's
    /// kit settings (`moduleSettings.closet`):
    ///
    ///     { "coachLines": { "distraction": ["The Krebs cycle is saving your seat."] } }
    ///
    /// Keys are `PetCoachNudgeKind` raw values. Kit lines join the standard
    /// ones rather than replace them, so a kit with a few lines still varies.
    /// Unknown kinds, blank lines and lines longer than `maxLength` are
    /// skipped, so a hand-written kit can't break the bubble.
    public static func lines(kitSettings: KitValue?) -> [PetCoachMessage] {
        standard + kitLines(kitSettings)
    }

    /// Only the kit's valid lines, ids `kit.<kind>.<index>`.
    public static func kitLines(_ kitSettings: KitValue?) -> [PetCoachMessage] {
        guard let byKind = try? kitSettings?["coachLines"]?.decode([String: [String]].self) else { return [] }
        return PetCoachNudgeKind.allCases.flatMap { kind in
            (byKind[kind.rawValue] ?? []).enumerated().compactMap { index, raw -> PetCoachMessage? in
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, text.count <= maxLength else { return nil }
                return m("kit.\(kind.rawValue).\(index)", kind, text)
            }
        }
    }

    public static func messages(for kind: PetCoachNudgeKind, in lines: [PetCoachMessage] = standard) -> [PetCoachMessage] {
        let pool = lines.filter { $0.kind == kind }
        return pool.isEmpty ? standard.filter { $0.kind == kind } : pool
    }

    /// Picks a line of `kind` from `lines`, skipping ids in `recentIDs` while
    /// any other line is left. If every line was used recently, it still
    /// avoids the most recent one so the same line never shows twice in a row.
    public static func pick<G: RandomNumberGenerator>(
        _ kind: PetCoachNudgeKind,
        from lines: [PetCoachMessage] = standard,
        avoiding recentIDs: [String] = [],
        using generator: inout G
    ) -> PetCoachMessage {
        let pool = messages(for: kind, in: lines)
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
