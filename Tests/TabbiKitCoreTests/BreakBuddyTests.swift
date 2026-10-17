import XCTest
import TabbiKitCore

final class BreakMoveTests: XCTestCase {
    func testEveryMoveHasAClipALengthInRangeAndASymbol() {
        for move in BreakMove.allCases {
            XCTAssertTrue((20...60).contains(move.length), "\(move)")
            XCTAssertFalse(move.symbol.isEmpty)
            XCTAssertFalse(move.prompt.isEmpty)
            XCTAssertFalse(move.name.isEmpty)
            XCTAssertTrue(PetAnimation.allCases.contains(move.animation))
        }
        XCTAssertEqual(BreakMove.stretch.animation, .stretch)
        XCTAssertEqual(BreakMove.sip.animation, .sip)
        XCTAssertEqual(BreakMove.eyeRest.animation, .sit)
        XCTAssertEqual(BreakMove.breathe.animation, .breathe)
        XCTAssertEqual(BreakMove.standUp.animation, .walk)
    }

    func testTheStretchTitleUsesThePetsName() {
        XCTAssertEqual(BreakMove.stretch.title(petName: "Mochi"), "Stretch with Mochi")
        XCTAssertEqual(BreakMove.stretch.title(petName: nil), "Time for a stretch")
        XCTAssertEqual(BreakMove.sip.title(petName: "Mochi"), "Sip some water")
        XCTAssertEqual(BreakMove.eyeRest.title(petName: nil), "Look at something far away")
        XCTAssertEqual(BreakMove.breathe.title(petName: nil), "A slow breath in, and out")
        XCTAssertEqual(BreakMove.standUp.title(petName: nil), "Stand up for a moment")
    }

    func testAPetStillNamedAfterItsBreedGoesUnnamed() {
        let breedNamed = PetProfile(name: PetBreed.britishShorthair.displayName, breed: .britishShorthair)
        XCTAssertNil(BreakMove.buddyName(for: breedNamed))
        XCTAssertEqual(BreakMove.buddyName(for: PetProfile(name: "Mochi", breed: .orangeTabby)), "Mochi")
    }

    func testCopyHasNoEmDashes() {
        for move in BreakMove.allCases {
            for text in [move.title(petName: "Mochi"), move.prompt, move.name] {
                XCTAssertFalse(text.contains("\u{2014}"), text)
            }
        }
    }

    func testStandardPropsUseThePlainClipsAndASetCanSwapOne() {
        for move in BreakMove.allCases { XCTAssertEqual(BreakProps.standard.animation(for: move), move.animation) }
        let props = BreakProps(id: "mat", clips: [.stretch: .hop])
        XCTAssertEqual(props.animation(for: .stretch), .hop)
        XCTAssertEqual(props.animation(for: .sip), .sip)
    }
}

final class BreakMomentTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testRemainingProgressAndShowing() {
        let moment = BreakMoment(move: .breathe, source: .study, breakStartedAt: start, startedAt: start,
                                 endsAt: start.addingTimeInterval(30))
        XCTAssertEqual(moment.length, 30)
        XCTAssertEqual(moment.remaining(at: start.addingTimeInterval(12)), 18)
        XCTAssertEqual(moment.remaining(at: start.addingTimeInterval(40)), 0, "never negative")
        XCTAssertEqual(moment.progress(at: start.addingTimeInterval(15)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(moment.progress(at: start.addingTimeInterval(-5)), 0)
        XCTAssertEqual(moment.progress(at: start.addingTimeInterval(99)), 1)
        XCTAssertTrue(moment.isShowing(at: start))
        XCTAssertTrue(moment.isShowing(at: start.addingTimeInterval(29.9)))
        XCTAssertFalse(moment.isShowing(at: start.addingTimeInterval(30)))
        XCTAssertFalse(moment.isShowing(at: start.addingTimeInterval(-1)))
    }

    func testAnEndBeforeTheStartIsClamped() {
        let moment = BreakMoment(move: .sip, source: .focus, breakStartedAt: start, startedAt: start,
                                 endsAt: start.addingTimeInterval(-10))
        XCTAssertEqual(moment.endsAt, start)
        XCTAssertEqual(moment.progress(at: start), 1)
    }

    func testTheSampleIsAStretchPartWayIn() {
        let sample = BreakMoment.sample(at: start)
        XCTAssertEqual(sample.move, .stretch)
        XCTAssertTrue(sample.isShowing(at: start))
        XCTAssertEqual(sample.remaining(at: start), BreakMove.stretch.length - 12)
    }
}

final class BreakBuddyPlannerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func rest(_ minutes: Double, startedAt offset: TimeInterval = 0, source: ModuleID = .study)
        -> BreakBuddyPlanner.Break {
        BreakBuddyPlanner.Break(source: source, startedAt: start.addingTimeInterval(offset), length: minutes * 60)
    }

    /// Plans `count` five minute breaks in a row and returns their moves.
    private func run(_ count: Int, preferences: BreakBuddyPreferences = .init()) -> [BreakMove] {
        var preferences = preferences
        var moves: [BreakMove] = []
        for index in 0..<count {
            let offset = TimeInterval(index) * 3600
            guard let plan = BreakBuddyPlanner.plan(for: rest(5, startedAt: offset), preferences: preferences,
                                                     at: start.addingTimeInterval(offset)) else { continue }
            moves.append(plan.moment.move)
            preferences = plan.preferences
        }
        return moves
    }

    func testShortBreaksRotateWithASipEveryThirdBreak() {
        XCTAssertEqual(run(9), [.stretch, .eyeRest, .sip, .breathe, .stretch, .sip, .eyeRest, .breathe, .sip])
    }

    func testTheSamePlanEveryTime() {
        XCTAssertEqual(run(12), run(12))
    }

    func testALongBreakSuggestsStandingUp() throws {
        let plan = try XCTUnwrap(BreakBuddyPlanner.plan(for: rest(15), preferences: .init(), at: start))
        XCTAssertEqual(plan.moment.move, .standUp)
        XCTAssertEqual(plan.moment.length, BreakMove.standUp.length)
        XCTAssertNil(plan.preferences.lastMove, "standing up doesn't move the rotation on")
        XCTAssertEqual(plan.preferences.breaksSinceSip, 1)
    }

    func testTheMomentIsAtMostHalfTheBreak() throws {
        let plan = try XCTUnwrap(BreakBuddyPlanner.plan(for: rest(1), preferences: .init(), at: start))
        XCTAssertEqual(plan.moment.move, .stretch)
        XCTAssertEqual(plan.moment.length, 30, "a one minute break gets half of it, not the stretch's 40 s")
        XCTAssertEqual(plan.moment.startedAt, start)
        XCTAssertEqual(plan.moment.breakStartedAt, start)
        XCTAssertEqual(plan.moment.source, .study)
    }

    func testBreaksUnderFortySecondsGetNothing() {
        let short = BreakBuddyPlanner.Break(source: .focus, startedAt: start, length: 39)
        XCTAssertNil(BreakBuddyPlanner.plan(for: short, preferences: .init(), at: start))
        let justEnough = BreakBuddyPlanner.Break(source: .focus, startedAt: start, length: 40)
        XCTAssertEqual(BreakBuddyPlanner.plan(for: justEnough, preferences: .init(), at: start)?.moment.length, 20)
        // A five minute break with only 30 s left is too late for a moment.
        XCTAssertNil(BreakBuddyPlanner.plan(for: rest(5), preferences: .init(), at: start.addingTimeInterval(270)))
    }

    func testOffOrEveryMoveOffGivesNothing() {
        XCTAssertNil(BreakBuddyPlanner.plan(for: rest(5), preferences: .init(isOn: false), at: start))
        let allOff = BreakBuddyPreferences(disabledMoves: Set(BreakMove.allCases))
        XCTAssertNil(BreakBuddyPlanner.plan(for: rest(5), preferences: allOff, at: start))
    }

    func testABreakIsPlannedOnce() throws {
        let plan = try XCTUnwrap(BreakBuddyPlanner.plan(for: rest(5), preferences: .init(), at: start))
        XCTAssertEqual(plan.preferences.lastBreakKey, BreakBuddyPlanner.breakKey(rest(5)))
        XCTAssertNil(BreakBuddyPlanner.plan(for: rest(5), preferences: plan.preferences, at: start.addingTimeInterval(2)))
        XCTAssertNotNil(BreakBuddyPlanner.plan(for: rest(5, source: .focus), preferences: plan.preferences, at: start),
                        "another clock's break is another break")
    }

    func testDisabledMovesAreNeverPicked() {
        let noSip = BreakBuddyPreferences(disabledMoves: [.sip, .eyeRest])
        XCTAssertEqual(run(6, preferences: noSip), [.stretch, .breathe, .stretch, .breathe, .stretch, .breathe])
        let onlyStandUp = BreakBuddyPreferences(disabledMoves: [.stretch, .sip, .eyeRest, .breathe])
        XCTAssertEqual(run(3, preferences: onlyStandUp), [.standUp, .standUp, .standUp])
        let onlySip = BreakBuddyPreferences(disabledMoves: [.stretch, .eyeRest, .breathe, .standUp])
        XCTAssertEqual(run(2, preferences: onlySip), [.sip, .sip])
    }

    func testALongBreakWithStandingUpOffFallsBackToTheRotation() throws {
        let preferences = BreakBuddyPreferences(disabledMoves: [.standUp])
        XCTAssertEqual(try XCTUnwrap(BreakBuddyPlanner.plan(for: rest(15), preferences: preferences, at: start)).moment.move,
                       .stretch)
    }

    func testBreakFromTheSharedClock() throws {
        let endsAt = start.addingTimeInterval(300)
        let running = ProvidedFocus(source: .focus, phase: .rest, clock: .countdown(endsAt: endsAt), phaseLength: 300)
        let rest = try XCTUnwrap(BreakBuddyPlanner.Break(running))
        XCTAssertEqual(rest.startedAt, start)
        XCTAssertEqual(rest.length, 300)
        XCTAssertEqual(rest.source, .focus)
        XCTAssertNil(BreakBuddyPlanner.Break(ProvidedFocus(source: .focus, phase: .focus,
                                                           clock: .countdown(endsAt: endsAt), phaseLength: 300)))
        XCTAssertNil(BreakBuddyPlanner.Break(ProvidedFocus(source: .focus, phase: .rest, clock: .paused(shown: 200),
                                                           phaseLength: 300)))
        XCTAssertNil(BreakBuddyPlanner.Break(ProvidedFocus(source: .study, phase: .rest, clock: .countUp(since: start),
                                                           phaseLength: nil)), "nothing to size a moment by")
    }
}

final class BreakBuddyPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "BreakBuddyPreferencesTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaults() {
        let preferences = BreakBuddyPreferencesStorage(defaults: defaults).load()
        XCTAssertTrue(preferences.isOn)
        XCTAssertTrue(preferences.tracksWater)
        XCTAssertEqual(preferences.enabledMoves, BreakMove.allCases)
        XCTAssertNil(preferences.lastMove)
        XCTAssertEqual(preferences.breaksSinceSip, 0)
        XCTAssertNil(preferences.lastBreakKey)
    }

    func testSavedPreferencesSurviveARelaunch() {
        var preferences = BreakBuddyPreferences(isOn: false, tracksWater: false, lastMove: .eyeRest, breaksSinceSip: 2,
                                                lastBreakKey: "study@1")
        preferences.setEnabled(.standUp, false)
        BreakBuddyPreferencesStorage(defaults: defaults).save(preferences)
        XCTAssertEqual(BreakBuddyPreferencesStorage(defaults: defaults).load(), preferences)
    }

    func testSavedDocumentIsVersioned() throws {
        BreakBuddyPreferencesStorage(defaults: defaults).save(BreakBuddyPreferences())
        let data = try XCTUnwrap(defaults.data(forKey: BreakBuddyPreferencesStorage.key))
        XCTAssertEqual(BreakBuddyPreferencesStorage.key, "breakBuddy.preferences")
        XCTAssertEqual(VersionedJSON.version(of: data), 1)
    }

    func testUnreadableValuesKeepTheirDefaultsAndUnknownMovesAreSkipped() throws {
        let data = try BreakBuddyPreferencesStorage.schema.encode([
            "isOn": "sometimes", "disabledMoves": ["sip", "cartwheel"], "tracksWater": false,
            "lastMove": "cartwheel", "breaksSinceSip": -3,
        ] as [String: AnyEncodable])
        defaults.set(data, forKey: BreakBuddyPreferencesStorage.key)
        let preferences = BreakBuddyPreferencesStorage(defaults: defaults).load()
        XCTAssertTrue(preferences.isOn)
        XCTAssertEqual(preferences.disabledMoves, [.sip])
        XCTAssertFalse(preferences.tracksWater)
        XCTAssertNil(preferences.lastMove)
        XCTAssertEqual(preferences.breaksSinceSip, 0)
    }

    func testGarbageLoadsTheDefaults() {
        defaults.set(Data("not json".utf8), forKey: BreakBuddyPreferencesStorage.key)
        XCTAssertEqual(BreakBuddyPreferencesStorage(defaults: defaults).load(), BreakBuddyPreferences())
    }
}

/// A heterogenous value for building test documents.
private struct AnyEncodable: Encodable, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
                             ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral {
    let encode: @Sendable (Encoder) throws -> Void
    init(stringLiteral value: String) { encode = { var c = $0.singleValueContainer(); try c.encode(value) } }
    init(booleanLiteral value: Bool) { encode = { var c = $0.singleValueContainer(); try c.encode(value) } }
    init(integerLiteral value: Int) { encode = { var c = $0.singleValueContainer(); try c.encode(value) } }
    init(arrayLiteral elements: String...) { encode = { var c = $0.singleValueContainer(); try c.encode(elements) } }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}

final class WaterTallyTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testRecords() {
        let water = WaterTally.water(at: date(17, 10))
        XCTAssertEqual(water.kind.rawValue, "water.logged")
        XCTAssertEqual(water.source, .closet)
        XCTAssertEqual(water.quantity, 1)
        XCTAssertEqual(water.unit?.rawValue, "glass")
        let move = WaterTally.move(.breathe, at: date(17, 10))
        XCTAssertEqual(move.kind.rawValue, "break.move")
        XCTAssertEqual(move.subject, "breathe")
        XCTAssertEqual(move.source, .closet)
    }

    func testCountsTodayOnly() {
        let today = PlannerDayKey(date: date(17, 12), calendar: calendar)
        let records = [
            WaterTally.water(at: date(16, 23)), WaterTally.water(at: date(17, 0)), WaterTally.water(at: date(17, 9)),
            WaterTally.move(.stretch, at: date(17, 9)), WaterTally.move(.sip, at: date(17, 11)),
            WaterTally.move(.sip, at: date(16, 11)),
            ActivityRecord(source: .study, kind: WaterTally.waterKind, start: date(17, 9), quantity: 4),
            ActivityRecord(source: .focus, kind: .focusCompleted, start: date(17, 9), quantity: 25, unit: .minutes),
        ]
        XCTAssertEqual(WaterTally.glasses(in: records, on: today, calendar: calendar), 2,
                       "yesterday's glass and another module's record don't count")
        XCTAssertEqual(WaterTally.moves(in: records, on: today, calendar: calendar), [.stretch, .sip])
    }

    func testNeitherKindEarnsPointsOrKeepsAStreak() {
        let records = [WaterTally.water(at: date(17, 9)), WaterTally.move(.stretch, at: date(17, 9))]
        for record in records {
            XCTAssertFalse(WidgetState.isFocus(record), "streaks read only focus")
        }
        XCTAssertEqual(WidgetState.focusMinutes(in: records), 0)
        XCTAssertEqual(FocusTimer.sessionsDone(in: records, source: .closet), 0)
        let review = DayReviewer.review(of: PlannerDay(date: PlannerDayKey(date: date(17, 9), calendar: calendar)),
                                      activity: records, calendar: calendar)
        XCTAssertEqual(review.focusSessions, 0)
        XCTAssertEqual(review.focusMinutes, 0)
    }
}
