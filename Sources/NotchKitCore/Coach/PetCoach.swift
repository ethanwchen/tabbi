import Foundation

/// Where the study timer is, as far as the coach cares.
public enum PetCoachStudyState: String, Codable, CaseIterable, Hashable, Sendable {
    /// A focus or review phase is running. The only state the coach nudges in.
    case focusing
    /// A break is running. Distracting apps are exactly what breaks are for.
    case onBreak
    case paused
    case notStudying
}

/// One reading of the world, taken by the app every few seconds while a
/// session runs (idle seconds from `CGEventSource`, the frontmost app from
/// `NSWorkspace`; neither needs a permission prompt).
public struct PetCoachInput: Hashable, Sendable {
    public var now: Date
    /// Seconds since the last keyboard, mouse, or trackpad event.
    public var idleSeconds: TimeInterval
    public var frontmost: CoachAppCategory
    public var study: PetCoachStudyState
    /// The user is in deep focus (a long uninterrupted block, or flagged by
    /// the UI). Long reading stretches are expected, so idle checks wait
    /// much longer.
    public var deepFocus: Bool

    public init(
        now: Date,
        idleSeconds: TimeInterval,
        frontmost: CoachAppCategory,
        study: PetCoachStudyState,
        deepFocus: Bool = false
    ) {
        self.now = now
        self.idleSeconds = idleSeconds
        self.frontmost = frontmost
        self.study = study
        self.deepFocus = deepFocus
    }
}

/// Timing for the coach. `standard` follows the research notes: the pet looks
/// over after 30 s in a distracting app, says something at 2 min, offers to
/// pause at 5 min; asks "still studying?" after 2 idle minutes and pauses the
/// timer after 5; at most one new nudge every 10 minutes.
public struct PetCoachRules: Codable, Hashable, Sendable {
    public var lookOverAfter: TimeInterval
    public var distractionNudgeAfter: TimeInterval
    public var offerPauseAfter: TimeInterval
    public var idleCheckAfter: TimeInterval
    public var idleAutoPauseAfter: TimeInterval
    public var deepFocusIdleCheckAfter: TimeInterval
    public var deepFocusIdleAutoPauseAfter: TimeInterval
    /// Minimum gap before the first bubble of a new episode.
    public var minimumNudgeInterval: TimeInterval
    /// Minimum gap before the next, kinder step within the same episode.
    public var escalationGap: TimeInterval
    /// Speech bubbles allowed in any rolling hour. Past this the pet goes
    /// quiet rather than nag. An auto-pause always happens but still counts.
    public var maxNudgesPerHour: Int

    public init(
        lookOverAfter: TimeInterval = 30,
        distractionNudgeAfter: TimeInterval = 2 * 60,
        offerPauseAfter: TimeInterval = 5 * 60,
        idleCheckAfter: TimeInterval = 2 * 60,
        idleAutoPauseAfter: TimeInterval = 5 * 60,
        deepFocusIdleCheckAfter: TimeInterval = 10 * 60,
        deepFocusIdleAutoPauseAfter: TimeInterval = 20 * 60,
        minimumNudgeInterval: TimeInterval = 10 * 60,
        escalationGap: TimeInterval = 2 * 60,
        maxNudgesPerHour: Int = 3
    ) {
        self.lookOverAfter = lookOverAfter
        self.distractionNudgeAfter = distractionNudgeAfter
        self.offerPauseAfter = offerPauseAfter
        self.idleCheckAfter = idleCheckAfter
        self.idleAutoPauseAfter = idleAutoPauseAfter
        self.deepFocusIdleCheckAfter = deepFocusIdleCheckAfter
        self.deepFocusIdleAutoPauseAfter = deepFocusIdleAutoPauseAfter
        self.minimumNudgeInterval = minimumNudgeInterval
        self.escalationGap = escalationGap
        self.maxNudgesPerHour = maxNudgesPerHour
    }

    public static let standard = PetCoachRules()
}

/// A speech bubble the pet should show.
public struct PetCoachNudge: Codable, Hashable, Sendable {
    public var kind: PetCoachNudgeKind
    public var message: PetCoachMessage

    /// The app should pause the study timer along with this bubble.
    public var pausesTimer: Bool { kind == .autoPause }

    public init(kind: PetCoachNudgeKind, message: PetCoachMessage) {
        self.kind = kind
        self.message = message
    }
}

/// What the pet does after an evaluation.
public enum PetCoachDecision: Hashable, Sendable {
    /// Nothing.
    case none
    /// A silent glance toward the user. No bubble, no sound.
    case lookOver
    case nudge(PetCoachNudge)

    public var nudge: PetCoachNudge? {
        if case .nudge(let nudge) = self { return nudge }
        return nil
    }
}

/// Decides when the study pet nudges, and with what.
///
/// Feed it a `PetCoachInput` every few seconds while a session runs. It
/// tracks two kinds of episodes: time in a distracting app (look over, then a
/// bubble, then an offer to pause) and time without input (ask, then pause
/// the timer). Each step fires once per episode and steps up one at a time,
/// so the tone only ever gets kinder: the last step is always an offer to
/// rest, never a scolding. Rate limits keep it rare, and snooze or the
/// per-session "don't nudge" switch silence it completely.
///
/// Idle never means distracted; it only triggers a question. Codable so
/// cooldowns and snooze survive relaunch. Open episodes are not saved: they
/// describe the focus phase that was running, and carrying them into the
/// next one would skip its grace period (a glance and a bubble right away).
public struct PetCoach: Codable, Hashable, Sendable {
    public var rules: PetCoachRules
    /// The per-session "Do not nudge" switch.
    public var nudgesEnabled: Bool
    public private(set) var snoozedUntil: Date?
    public private(set) var lastNudgeAt: Date?
    /// When each bubble in the last hour was shown, oldest first.
    public private(set) var recentNudges: [Date]
    /// Ids of recently used lines, oldest first, so lines don't repeat.
    public private(set) var recentMessageIDs: [String]
    /// When the current distracting-app episode began, if one is going.
    public private(set) var distractionStartedAt: Date? = nil
    public private(set) var distractionStep: DistractionStep = .none
    public private(set) var idleStep: IdleStep = .none

    private enum CodingKeys: String, CodingKey {
        case rules, nudgesEnabled, snoozedUntil, lastNudgeAt, recentNudges, recentMessageIDs
    }

    /// How far a distracting-app episode has gone.
    public enum DistractionStep: Int, Codable, Comparable, Sendable {
        case none, lookedOver, nudged, offeredPause
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How far an idle episode has gone.
    public enum IdleStep: Int, Codable, Comparable, Sendable {
        case none, asked, paused
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How many line ids to remember for variety.
    static let messageMemory = 8

    public init(rules: PetCoachRules = .standard, nudgesEnabled: Bool = true) {
        self.rules = rules
        self.nudgesEnabled = nudgesEnabled
        self.snoozedUntil = nil
        self.lastNudgeAt = nil
        self.recentNudges = []
        self.recentMessageIDs = []
    }

    // MARK: Snooze

    public mutating func snooze(for duration: TimeInterval, at now: Date) {
        snooze(until: now.addingTimeInterval(max(0, duration)))
    }

    public mutating func snooze(until date: Date) {
        snoozedUntil = date
    }

    public mutating func endSnooze() {
        snoozedUntil = nil
    }

    public func isSnoozed(at now: Date) -> Bool {
        guard let snoozedUntil else { return false }
        return now < snoozedUntil
    }

    // MARK: Evaluation

    /// Updates episodes from `input` and returns what the pet should do now.
    /// Bubbles pick from `lines`, e.g. `PetCoachMessages.lines(kitSettings:)`
    /// for the active kit's flavor.
    public mutating func evaluate(
        _ input: PetCoachInput,
        lines: [PetCoachMessage] = PetCoachMessages.standard
    ) -> PetCoachDecision {
        var generator = SystemRandomNumberGenerator()
        return evaluate(input, lines: lines, using: &generator)
    }

    /// Same as `evaluate(_:lines:)` with an injected generator for line picking.
    public mutating func evaluate<G: RandomNumberGenerator>(
        _ input: PetCoachInput,
        lines: [PetCoachMessage] = PetCoachMessages.standard,
        using generator: inout G
    ) -> PetCoachDecision {
        let now = input.now
        recentNudges.removeAll { now.timeIntervalSince($0) >= 3600 }
        if let snoozedUntil, now >= snoozedUntil { self.snoozedUntil = nil }

        guard input.study == .focusing else {
            endEpisodes()
            return .none
        }

        if input.frontmost == .distracting {
            if distractionStartedAt == nil { distractionStartedAt = now }
        } else {
            distractionStartedAt = nil
            distractionStep = .none
        }
        let idle = idleThresholds(deepFocus: input.deepFocus)
        if input.idleSeconds < idle.check { idleStep = .none }

        guard nudgesEnabled, !isSnoozed(at: now) else { return .none }

        if let decision = distractionDecision(at: now, lines: lines, using: &generator) {
            return decision
        }
        return idleDecision(input.idleSeconds, thresholds: idle, at: now, lines: lines, using: &generator)
    }

    private mutating func distractionDecision<G: RandomNumberGenerator>(
        at now: Date,
        lines: [PetCoachMessage],
        using generator: inout G
    ) -> PetCoachDecision? {
        guard let start = distractionStartedAt else { return nil }
        let elapsed = now.timeIntervalSince(start)
        let target: DistractionStep
        switch elapsed {
        case rules.offerPauseAfter...: target = .offeredPause
        case rules.distractionNudgeAfter...: target = .nudged
        case rules.lookOverAfter...: target = .lookedOver
        default: target = .none
        }
        guard target > distractionStep,
              let next = DistractionStep(rawValue: distractionStep.rawValue + 1) else { return nil }

        switch next {
        case .none:
            return nil
        case .lookedOver:
            distractionStep = .lookedOver
            return .lookOver
        case .nudged:
            guard canNudge(at: now, gap: rules.minimumNudgeInterval) else { return nil }
            distractionStep = .nudged
            return .nudge(makeNudge(.distraction, at: now, lines: lines, using: &generator))
        case .offeredPause:
            guard canNudge(at: now, gap: rules.escalationGap) else { return nil }
            distractionStep = .offeredPause
            return .nudge(makeNudge(.offerPause, at: now, lines: lines, using: &generator))
        }
    }

    private mutating func idleDecision<G: RandomNumberGenerator>(
        _ idleSeconds: TimeInterval,
        thresholds: (check: TimeInterval, pause: TimeInterval),
        at now: Date,
        lines: [PetCoachMessage],
        using generator: inout G
    ) -> PetCoachDecision {
        if idleSeconds >= thresholds.pause, idleStep < .paused {
            // Not rate limited: pausing keeps the user's stats honest, and
            // any input (including answering) ends the idle episode anyway.
            idleStep = .paused
            return .nudge(makeNudge(.autoPause, at: now, lines: lines, using: &generator))
        }
        if idleSeconds >= thresholds.check, idleStep < .asked,
           canNudge(at: now, gap: rules.minimumNudgeInterval) {
            idleStep = .asked
            return .nudge(makeNudge(.idleCheck, at: now, lines: lines, using: &generator))
        }
        return .none
    }

    private func idleThresholds(deepFocus: Bool) -> (check: TimeInterval, pause: TimeInterval) {
        deepFocus
            ? (rules.deepFocusIdleCheckAfter, rules.deepFocusIdleAutoPauseAfter)
            : (rules.idleCheckAfter, rules.idleAutoPauseAfter)
    }

    private func canNudge(at now: Date, gap: TimeInterval) -> Bool {
        guard recentNudges.count < rules.maxNudgesPerHour else { return false }
        guard let lastNudgeAt else { return true }
        return now.timeIntervalSince(lastNudgeAt) >= gap
    }

    private mutating func makeNudge<G: RandomNumberGenerator>(
        _ kind: PetCoachNudgeKind,
        at now: Date,
        lines: [PetCoachMessage],
        using generator: inout G
    ) -> PetCoachNudge {
        let message = PetCoachMessages.pick(kind, from: lines, avoiding: recentMessageIDs, using: &generator)
        recentMessageIDs.append(message.id)
        if recentMessageIDs.count > Self.messageMemory {
            recentMessageIDs.removeFirst(recentMessageIDs.count - Self.messageMemory)
        }
        lastNudgeAt = now
        recentNudges.append(now)
        return PetCoachNudge(kind: kind, message: message)
    }

    /// Forgets any open distraction or idle episode, e.g. when the app stops
    /// watching mid-phase, so the next focus phase starts with its full
    /// grace period. Cooldowns and snooze are kept.
    public mutating func endEpisodes() {
        distractionStartedAt = nil
        distractionStep = .none
        idleStep = .none
    }
}
