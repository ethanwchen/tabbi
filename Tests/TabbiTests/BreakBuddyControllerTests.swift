import XCTest
@testable import TabbiKit
import TabbiKitCore
@testable import Tabbi

/// The break buddy follows the shared focus clock: a fresh switch into a
/// break plans one move, a break already under way does not, the moment
/// ends with its break, and only Done and water are logged.
@MainActor
final class BreakBuddyControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var log: ActivityLog!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let profile = PetProfile(name: "Mochi", breed: .orangeTabby)

    override func setUp() async throws {
        defaults = InMemoryDefaults()
        log = ActivityLog(repository: nil)
    }

    private func buddy(_ runMode: RunMode = .live) -> BreakBuddyController {
        BreakBuddyController(runMode: runMode, activityLog: log, profile: profile, defaults: defaults,
                             clock: { [unowned self] in now })
    }

    private func focus(at date: Date, source: ModuleID = .focus) -> ProvidedFocus {
        ProvidedFocus(source: source, phase: .focus, clock: .countdown(endsAt: date.addingTimeInterval(600)),
                      phaseLength: 1500)
    }

    /// A break of `length` that began at `startedAt`.
    private func rest(startedAt: Date, length: TimeInterval = 300, source: ModuleID = .focus) -> ProvidedFocus {
        ProvidedFocus(source: source, phase: .rest, clock: .countdown(endsAt: startedAt.addingTimeInterval(length)),
                      phaseLength: length)
    }

    func testAFreshBreakGetsAMove() throws {
        let buddy = buddy()
        buddy.observe(focus(at: now), at: now)
        buddy.observe(rest(startedAt: now), at: now)
        let moment = try XCTUnwrap(buddy.moment)
        XCTAssertEqual(buddy.cardMoment, moment)
        XCTAssertEqual(moment.move, .stretch)
        XCTAssertEqual(moment.source, .focus)
        XCTAssertEqual(moment.startedAt, now)
        XCTAssertNotNil(buddy.cardPet)
        XCTAssertEqual(buddy.preferences.lastMove, .stretch, "the rotation moved on")
        XCTAssertEqual(BreakBuddyPreferencesStorage(defaults: defaults).load(), buddy.preferences, "and was saved")
    }

    func testABreakAlreadyUnderWayAtLaunchGetsNone() {
        let buddy = buddy()
        buddy.observe(rest(startedAt: now), at: now)
        XCTAssertNil(buddy.moment, "the first clock seen may have run before launch")
        let stale = buddy
        stale.observe(nil, at: now)
        stale.observe(rest(startedAt: now.addingTimeInterval(-120)), at: now)
        XCTAssertNil(stale.moment, "a break restored minutes in is not fresh")
    }

    func testResumingAPausedBreakIsNotANewOne() {
        let buddy = buddy()
        buddy.observe(focus(at: now), at: now)
        buddy.observe(rest(startedAt: now), at: now)
        buddy.skip()
        buddy.observe(ProvidedFocus(source: .focus, phase: .rest, clock: .paused(shown: 297), phaseLength: 300), at: now)
        now += 5
        buddy.observe(rest(startedAt: now.addingTimeInterval(-3)), at: now)
        XCTAssertNil(buddy.moment)
    }

    func testStartingAnIdleBreakByHandCountsAsFresh() {
        let buddy = buddy()
        buddy.observe(ProvidedFocus(source: .study, phase: .rest, clock: .idle, phaseLength: 300), at: now)
        buddy.observe(rest(startedAt: now, source: .study), at: now)
        XCTAssertEqual(buddy.moment?.source, .study)
    }

    func testTheMomentEndsWithItsBreak() {
        let buddy = buddy()
        buddy.observe(focus(at: now), at: now)
        buddy.observe(rest(startedAt: now), at: now)
        XCTAssertNotNil(buddy.moment)
        now += 10
        buddy.observe(focus(at: now), at: now)
        XCTAssertNil(buddy.moment, "the next focus began")
        XCTAssertNil(buddy.cardPet)
    }

    func testPausingTheBreakKeepsTheMoment() {
        let buddy = buddy()
        buddy.observe(focus(at: now), at: now)
        buddy.observe(rest(startedAt: now), at: now)
        buddy.observe(ProvidedFocus(source: .focus, phase: .rest, clock: .paused(shown: 290), phaseLength: 300), at: now)
        XCTAssertNotNil(buddy.moment)
    }

    func testShortBreaksAndTurningItOffGetNone() {
        let buddy = buddy()
        buddy.observe(focus(at: now), at: now)
        buddy.observe(rest(startedAt: now, length: 30), at: now)
        XCTAssertNil(buddy.moment)
        buddy.setOn(false)
        buddy.observe(focus(at: now), at: now)
        now += 1
        buddy.observe(rest(startedAt: now), at: now)
        XCTAssertNil(buddy.moment)
    }

    func testTurningItOffEndsAMoment() {
        let buddy = buddy()
        buddy.observe(focus(at: now), at: now)
        buddy.observe(rest(startedAt: now), at: now)
        buddy.setOn(false)
        XCTAssertNil(buddy.moment)
    }

    func testDoneLogsTheMoveAndHopsBeforeTheMomentGoes() throws {
        let buddy = buddy()
        var logged: [ActivityRecord] = []
        let subscription = log.recorded.sink { logged.append($0) }
        defer { subscription.cancel() }
        buddy.observe(focus(at: now), at: now)
        buddy.observe(rest(startedAt: now), at: now)
        buddy.done()
        XCTAssertTrue(buddy.isFinishing)
        XCTAssertNotNil(buddy.moment, "the card stays for the hop")
        buddy.done()
        XCTAssertEqual(logged.count, 1, "once")
        let record = try XCTUnwrap(logged.first)
        XCTAssertEqual(record.kind, WaterTally.moveKind)
        XCTAssertEqual(record.subject, BreakMove.stretch.rawValue)
    }

    func testSkipLogsNothing() {
        let buddy = buddy()
        var logged: [ActivityRecord] = []
        let subscription = log.recorded.sink { logged.append($0) }
        defer { subscription.cancel() }
        buddy.observe(focus(at: now), at: now)
        buddy.observe(rest(startedAt: now), at: now)
        buddy.skip()
        XCTAssertNil(buddy.moment)
        XCTAssertTrue(logged.isEmpty)
    }

    func testWaterIsCountedForToday() {
        let buddy = buddy()
        XCTAssertEqual(buddy.waterToday, 0)
        buddy.addWater()
        buddy.addWater()
        XCTAssertEqual(buddy.waterToday, 2)
        XCTAssertEqual(buddy.shownWater, 2)
        buddy.setTracksWater(false)
        XCTAssertNil(buddy.shownWater)
        XCTAssertEqual(self.buddy(.live).waterToday, 2, "read back from the log")
    }

    func testMovesCanBeTurnedOff() {
        let buddy = buddy()
        buddy.setMove(.stretch, enabled: false)
        buddy.observe(focus(at: now), at: now)
        buddy.observe(rest(startedAt: now), at: now)
        XCTAssertEqual(buddy.moment?.move, .eyeRest)
        XCTAssertFalse(BreakBuddyPreferencesStorage(defaults: defaults).load().isEnabled(.stretch))
    }

    func testSnapshotRunsPlanAndSaveNothing() {
        let buddy = buddy(RunMode(isSnapshot: true))
        buddy.observe(focus(at: now), at: now)
        buddy.observe(rest(startedAt: now), at: now)
        XCTAssertNil(buddy.moment)
        buddy.setOn(false)
        XCTAssertNil(defaults.data(forKey: BreakBuddyPreferencesStorage.key))
        buddy.showForSnapshot(.sample(at: now))
        XCTAssertEqual(buddy.moment?.move, .stretch)
        XCTAssertEqual(buddy.cardMoment, buddy.moment, "a shot's moment shows on the card")
        buddy.observe(focus(at: now), at: now)
        XCTAssertNotNil(buddy.moment, "a shot's moment stays")
        buddy.addWater()
        XCTAssertEqual(buddy.waterToday, 0)
    }

    func testDemoRunsStartWithASampleMoment() {
        let buddy = buddy(.demo)
        XCTAssertEqual(buddy.moment?.move, .stretch)
        XCTAssertNil(buddy.cardMoment, "the open tabs keep the demo's timer")
        buddy.observe(focus(at: now), at: now)
        XCTAssertNotNil(buddy.moment, "the sample outlives the demo's clock")
        XCTAssertNil(defaults.data(forKey: BreakBuddyPreferencesStorage.key))
    }

    func testTheCardUsesThePetsOwnNameOnly() {
        XCTAssertEqual(buddy().petName, "Mochi")
        let unnamed = BreakBuddyController(runMode: .live, activityLog: log,
                                           profile: PetProfile(name: PetBreed.corgi.displayName, breed: .corgi),
                                           defaults: defaults)
        XCTAssertNil(unnamed.petName)
    }
}
