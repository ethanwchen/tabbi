import XCTest
import NotchKitCore

/// Deterministic generator (SplitMix64) so line picks are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class PetCoachTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var rng = SeededGenerator(state: 42)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func input(
        _ seconds: TimeInterval,
        idle: TimeInterval = 0,
        app: CoachAppCategory = .neutral,
        study: PetCoachStudyState = .focusing,
        deep: Bool = false
    ) -> PetCoachInput {
        PetCoachInput(now: at(seconds), idleSeconds: idle, frontmost: app, study: study, deepFocus: deep)
    }

    private func eval(_ coach: inout PetCoach, _ input: PetCoachInput) -> PetCoachDecision {
        coach.evaluate(input, using: &rng)
    }

    /// Ticks the coach every `step` seconds over `range`, returning non-none decisions with their times.
    private func run(
        _ coach: inout PetCoach,
        from start: TimeInterval,
        to end: TimeInterval,
        step: TimeInterval = 5,
        make: (TimeInterval) -> PetCoachInput
    ) -> [(TimeInterval, PetCoachDecision)] {
        var out: [(TimeInterval, PetCoachDecision)] = []
        var t = start
        while t <= end {
            let decision = eval(&coach, make(t))
            if decision != .none { out.append((t, decision)) }
            t += step
        }
        return out
    }

    private func kinds(_ events: [(TimeInterval, PetCoachDecision)]) -> [String] {
        events.map { $0.1.nudge?.kind.rawValue ?? "lookOver" }
    }

    // MARK: App list

    func testAppListCategorisesByBundleIDIgnoringCase() {
        let list = CoachAppList(distracting: ["com.hnc.Discord"])
        XCTAssertEqual(list.category(of: "com.hnc.discord"), .distracting)
        XCTAssertEqual(list.category(of: " COM.HNC.DISCORD "), .distracting)
        XCTAssertEqual(list.category(of: "net.ankiweb.anki"), .focus)
        XCTAssertEqual(list.category(of: "net.ankiweb.dtop"), .focus)
        XCTAssertEqual(list.category(of: "com.apple.Safari"), .neutral)
        XCTAssertEqual(list.category(of: nil), .neutral)
        XCTAssertEqual(list.category(of: ""), .neutral)
    }

    func testDistractingListStartsEmptyAndSuggestionsAreUnique() {
        XCTAssertTrue(CoachAppList().distracting.isEmpty)
        let ids = CoachAppList.suggestedDistracting.map(\.bundleID)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertFalse(ids.isEmpty)
    }

    func testFocusWinsAndMarkingMovesBetweenLists() {
        var list = CoachAppList(focus: ["a.b"], distracting: ["A.B", "c.d"])
        XCTAssertEqual(list.category(of: "a.b"), .focus)
        list.markDistracting("a.b")
        XCTAssertEqual(list.category(of: "a.b"), .distracting)
        XCTAssertFalse(list.focus.contains("a.b"))
        list.markFocus("c.d")
        XCTAssertEqual(list.category(of: "c.d"), .focus)
        list.forget("c.d")
        XCTAssertEqual(list.category(of: "c.d"), .neutral)
    }

    func testAppListRoundTripsThroughCodable() throws {
        let list = CoachAppList(distracting: ["com.hnc.Discord"])
        let decoded = try JSONDecoder().decode(CoachAppList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(decoded, list)
    }

    // MARK: Distraction escalation

    func testDistractionEscalatesLookOverThenBubbleThenOfferPause() {
        var coach = PetCoach()
        let events = run(&coach, from: 0, to: 600) { self.input($0, app: .distracting) }
        XCTAssertEqual(kinds(events), ["lookOver", "distraction", "offerPause"])
        XCTAssertEqual(events.map(\.0), [30, 120, 300])
        XCTAssertEqual(coach.distractionStep, .offeredPause)
    }

    func testNothingFiresBeforeThirtySeconds() {
        var coach = PetCoach()
        let events = run(&coach, from: 0, to: 25) { self.input($0, app: .distracting) }
        XCTAssertTrue(events.isEmpty)
    }

    func testEscalationStepsOneAtATimeEvenWhenFirstSeenLate() {
        // The app only starts polling 6 minutes into the episode: still
        // a glance first, never straight to the offer.
        var coach = PetCoach()
        XCTAssertEqual(eval(&coach, input(0, app: .distracting)), .none)
        XCTAssertEqual(eval(&coach, input(400, app: .distracting)), .lookOver)
        XCTAssertEqual(eval(&coach, input(405, app: .distracting)).nudge?.kind, .distraction)
        // The offer waits for the escalation gap after the bubble.
        XCTAssertEqual(eval(&coach, input(410, app: .distracting)), .none)
        XCTAssertEqual(eval(&coach, input(525, app: .distracting)).nudge?.kind, .offerPause)
    }

    func testLeavingTheDistractingAppEndsTheEpisode() {
        var coach = PetCoach()
        _ = run(&coach, from: 0, to: 60) { self.input($0, app: .distracting) }
        XCTAssertEqual(coach.distractionStep, .lookedOver)
        XCTAssertEqual(eval(&coach, input(65, app: .neutral)), .none)
        XCTAssertNil(coach.distractionStartedAt)
        XCTAssertEqual(coach.distractionStep, .none)
        // A new episode starts its own 30 s clock.
        XCTAssertEqual(eval(&coach, input(70, app: .distracting)), .none)
        XCTAssertEqual(eval(&coach, input(95, app: .distracting)), .none)
        XCTAssertEqual(eval(&coach, input(100, app: .distracting)), .lookOver)
    }

    func testFocusAppsAreNeverDistracting() {
        var coach = PetCoach()
        let events = run(&coach, from: 0, to: 900) { self.input($0, app: .focus) }
        XCTAssertTrue(events.isEmpty)
    }

    func testNoNudgesOutsideFocusPhases() {
        for state in [PetCoachStudyState.onBreak, .paused, .notStudying] {
            var coach = PetCoach()
            let events = run(&coach, from: 0, to: 900) { self.input($0, idle: $0, app: .distracting, study: state) }
            XCTAssertTrue(events.isEmpty, "\(state)")
        }
    }

    func testBreakEndsTheEpisodeSoTheNextFocusStartsFresh() {
        var coach = PetCoach()
        _ = run(&coach, from: 0, to: 60) { self.input($0, app: .distracting) }
        _ = eval(&coach, input(65, app: .distracting, study: .onBreak))
        XCTAssertNil(coach.distractionStartedAt)
        XCTAssertEqual(eval(&coach, input(70, app: .distracting)), .none)
    }

    // MARK: Rate limiting

    func testNewEpisodeBubbleWaitsForTheTenMinuteCooldown() {
        var coach = PetCoach()
        _ = run(&coach, from: 0, to: 130) { self.input($0, app: .distracting) }
        XCTAssertEqual(coach.lastNudgeAt, at(120))
        _ = eval(&coach, input(135, app: .neutral))
        // Second episode from 140 s: glance at 170 s, but the bubble is held until 720 s.
        // The offer then waits the 2 minute escalation gap after that bubble.
        let events = run(&coach, from: 140, to: 900) { self.input($0, app: .distracting) }
        XCTAssertEqual(kinds(events), ["lookOver", "distraction", "offerPause"])
        XCTAssertEqual(events.map(\.0), [170, 720, 840])
    }

    func testHourlyCapSilencesThePetUntilTheWindowRolls() {
        var rules = PetCoachRules.standard
        rules.minimumNudgeInterval = 0
        rules.escalationGap = 0
        rules.maxNudgesPerHour = 2
        var coach = PetCoach(rules: rules)
        let events = run(&coach, from: 0, to: 3000) { t in
            // Hop in and out of a distracting app every 400 s.
            self.input(t, app: Int(t / 400) % 2 == 0 ? .distracting : .neutral)
        }
        let bubbles = events.filter { $0.1.nudge != nil }
        XCTAssertEqual(bubbles.count, 2)
        // After the first bubble rolls out of the hour, the pet may speak again.
        let later = run(&coach, from: 3700, to: 4200) { self.input($0, app: .distracting) }
        XCTAssertFalse(later.filter { $0.1.nudge != nil }.isEmpty)
    }

    // MARK: Idle

    func testIdleAsksThenAutoPauses() {
        var coach = PetCoach()
        let events = run(&coach, from: 0, to: 400) { self.input($0, idle: $0) }
        XCTAssertEqual(kinds(events), ["idleCheck", "autoPause"])
        XCTAssertEqual(events.map(\.0), [120, 300])
        XCTAssertEqual(events[1].1.nudge?.pausesTimer, true)
        XCTAssertEqual(events[0].1.nudge?.pausesTimer, false)
    }

    func testIdleEpisodeFiresEachStepOnce() {
        var coach = PetCoach()
        let events = run(&coach, from: 0, to: 2000) { self.input($0, idle: $0) }
        XCTAssertEqual(events.count, 2)
    }

    func testActivityEndsTheIdleEpisode() {
        var coach = PetCoach()
        _ = eval(&coach, input(0, idle: 130))
        XCTAssertEqual(coach.idleStep, .asked)
        _ = eval(&coach, input(10, idle: 1))
        XCTAssertEqual(coach.idleStep, .none)
    }

    func testDeepFocusWaitsMuchLongerBeforeIdleChecks() {
        var coach = PetCoach()
        let events = run(&coach, from: 0, to: 1500) { self.input($0, idle: $0, deep: true) }
        XCTAssertEqual(kinds(events), ["idleCheck", "autoPause"])
        XCTAssertEqual(events.map(\.0), [600, 1200])
    }

    func testAutoPauseIgnoresTheCooldownButIdleCheckDoesNot() {
        var coach = PetCoach()
        _ = run(&coach, from: 0, to: 130) { self.input($0, app: .distracting) }
        // Back in a neutral app but away from the keyboard right after a bubble.
        let events = run(&coach, from: 135, to: 500) { self.input($0, idle: $0 - 135) }
        XCTAssertEqual(kinds(events), ["autoPause"])
        XCTAssertEqual(events[0].0, 435)
    }

    func testIdleInADistractingAppCanStillAutoPause() {
        var rules = PetCoachRules.standard
        rules.offerPauseAfter = 10_000
        var coach = PetCoach(rules: rules)
        let events = run(&coach, from: 0, to: 400) { self.input($0, idle: $0, app: .distracting) }
        XCTAssertEqual(kinds(events), ["lookOver", "distraction", "autoPause"])
    }

    // MARK: Snooze and mute

    func testSnoozeSilencesEverythingUntilItEnds() {
        var coach = PetCoach()
        coach.snooze(for: 1800, at: t0)
        XCTAssertTrue(coach.isSnoozed(at: at(100)))
        let quiet = run(&coach, from: 0, to: 1795) { self.input($0, idle: $0, app: .distracting) }
        XCTAssertTrue(quiet.isEmpty)
        XCTAssertFalse(coach.isSnoozed(at: at(1800)))
        // The episode kept running under the snooze, but steps still come one by one.
        XCTAssertEqual(eval(&coach, input(1800, app: .distracting)), .lookOver)
        XCTAssertNil(coach.snoozedUntil)
    }

    func testEndSnoozeAndNegativeDuration() {
        var coach = PetCoach()
        coach.snooze(for: -50, at: t0)
        XCTAssertFalse(coach.isSnoozed(at: t0))
        coach.snooze(until: at(600))
        coach.endSnooze()
        XCTAssertFalse(coach.isSnoozed(at: at(1)))
    }

    func testDoNotNudgeSwitchSilencesTheCoach() {
        var coach = PetCoach(nudgesEnabled: false)
        let events = run(&coach, from: 0, to: 900) { self.input($0, idle: $0, app: .distracting) }
        XCTAssertTrue(events.isEmpty)
        coach.nudgesEnabled = true
        XCTAssertNotEqual(eval(&coach, input(905, idle: 905, app: .distracting)), .none)
    }

    // MARK: Persistence

    func testStateSurvivesRelaunchViaCodable() throws {
        var coach = PetCoach()
        _ = run(&coach, from: 0, to: 130) { self.input($0, app: .distracting) }
        coach.snooze(until: at(200))
        let restored = try JSONDecoder().decode(PetCoach.self, from: JSONEncoder().encode(coach))
        XCTAssertEqual(restored, coach)
        var resumed = restored
        // Cooldown remembered: a fresh episode right after relaunch only glances.
        _ = eval(&resumed, input(300, app: .neutral))
        let events = run(&resumed, from: 305, to: 600) { self.input($0, app: .distracting) }
        XCTAssertEqual(kinds(events), ["lookOver"])
    }

    // MARK: Messages

    func testEveryKindHasSeveralLinesWithUniqueIDs() {
        for kind in PetCoachNudgeKind.allCases {
            XCTAssertGreaterThanOrEqual(PetCoachMessages.messages(for: kind).count, 4, "\(kind)")
        }
        let ids = PetCoachMessages.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLinesFitTheBubbleAndNeverShame() {
        let banned = ["lazy", "fail", "distracted", "again", "procrastinat", "wasted", "waste", "should",
                      "disappoint", "shame", "guilt", "slack off", "!"]
        for message in PetCoachMessages.all {
            XCTAssertLessThanOrEqual(message.text.count, PetCoachMessages.maxLength, message.id)
            XCTAssertFalse(message.text.isEmpty)
            let lower = message.text.lowercased()
            for word in banned {
                XCTAssertFalse(lower.contains(word), "\(message.id) contains \(word)")
            }
        }
    }

    func testPickerAvoidsRecentLinesAndNeverRepeatsBackToBack() {
        let pool = PetCoachMessages.messages(for: .idleCheck)
        let allButOne = pool.dropLast().map(\.id)
        for seed in 0..<20 {
            var generator = SeededGenerator(state: UInt64(seed))
            XCTAssertEqual(PetCoachMessages.pick(.idleCheck, avoiding: allButOne, using: &generator).id, pool.last!.id)
            let everything = pool.map(\.id)
            let picked = PetCoachMessages.pick(.idleCheck, avoiding: everything, using: &generator)
            XCTAssertNotEqual(picked.id, everything.last)
            XCTAssertEqual(picked.kind, .idleCheck)
        }
    }

    func testCoachVariesItsLinesAcrossNudges() {
        var rules = PetCoachRules.standard
        rules.minimumNudgeInterval = 0
        rules.maxNudgesPerHour = 100
        var coach = PetCoach(rules: rules)
        var texts: [String] = []
        for episode in 0..<6 {
            let base = TimeInterval(episode) * 1000
            _ = eval(&coach, input(base, app: .neutral))
            let events = run(&coach, from: base + 5, to: base + 200) { self.input($0, app: .distracting) }
            texts += events.compactMap { $0.1.nudge?.kind == .distraction ? $0.1.nudge?.message.id : nil }
        }
        XCTAssertEqual(texts.count, 6)
        // Six distraction lines exist and memory covers the last eight picks: no repeats.
        XCTAssertEqual(Set(texts).count, 6)
        XCTAssertLessThanOrEqual(coach.recentMessageIDs.count, 8)
    }

    func testSeededGeneratorMakesPicksReproducible() {
        var a = SeededGenerator(state: 7), b = SeededGenerator(state: 7)
        let first = (0..<5).map { _ in PetCoachMessages.pick(.distraction, using: &a).id }
        let second = (0..<5).map { _ in PetCoachMessages.pick(.distraction, using: &b).id }
        XCTAssertEqual(first, second)
    }
}
