import Foundation
import Testing
import TabbiKitCore
@testable import TabbiPhone

/// The iPhone pays points exactly as the Mac does: the closet fixture's
/// points table, earned through the app's own engine, and sessions that
/// end while the app is suspended or killed paid once, from their dates.
@Suite struct StudyEngineTests {
    struct ClosetFile: Decodable {
        struct Rules: Decodable {
            let minimumMinutes: Int
            let completionBonus: Int
            let bonusMinutes: Int
            let pointsPerTypicalBlock: Int
        }

        struct Points: Decodable {
            let minutes: Int
            let completed: Bool
            let points: Int
        }

        let schema: String
        let rules: Rules
        let points: [Points]
    }

    static let closet: ClosetFile? = try? Fixtures.decode(ClosetFile.self, from: "closet")
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func closetFixtureLoads() throws {
        let file = try #require(Self.closet)
        #expect(file.schema == "tabbi.closet.golden")
        #expect(file.rules.pointsPerTypicalBlock == 35)
    }

    /// A Timer of `minutes` that runs out pays the fixture's points for a
    /// finished session, the moment it ends, even into an idle phase.
    @Test(arguments: (Self.closet?.points ?? []).filter { $0.completed && StudyTimerLength.range.contains($0.minutes) }
        .map { [$0.minutes, $0.points] })
    func finishedTimerPaysTheFixturePoints(_ pair: [Int]) {
        let (minutes, points) = (pair[0], pair[1])
        var engine = StudyEngine()
        engine.choose(.timer, at: Self.t0)
        engine.setTimer(StudyTimerLength(minutes: minutes), at: Self.t0)
        engine.primaryAction(at: Self.t0)
        let end = Self.t0.addingTimeInterval(TimeInterval(minutes * 60))
        let update = engine.catchUp(at: end.addingTimeInterval(1))
        #expect(update.ended.map(\.outcome) == [.completed])
        #expect(update.awards.map(\.points).reduce(0, +) == points)
        #expect(engine.closet.balance == points)
        #expect(engine.session.runState == .idle)
        // Paid once: catching up again, or relaunching, pays nothing.
        #expect(engine.catchUp(at: end.addingTimeInterval(60)).awards.isEmpty)
        var relaunched = StudyEngine(session: engine.session, closet: engine.closet, timer: engine.timer)
        #expect(relaunched.catchUp(at: end.addingTimeInterval(120)).awards.isEmpty)
    }

    /// Stopping a focus block after `minutes` pays the fixture's points for
    /// a session cut short: the minutes studied, without the bonus.
    @Test(arguments: (Self.closet?.points ?? []).filter { !$0.completed && $0.minutes < 52 }
        .map { [$0.minutes, $0.points] })
    func stoppedFocusPaysTheFixturePoints(_ pair: [Int]) {
        let (minutes, points) = (pair[0], pair[1])
        var engine = StudyEngine()
        engine.choose(.fiftyTwoSeventeen, at: Self.t0)
        engine.primaryAction(at: Self.t0)
        let update = engine.stop(at: Self.t0.addingTimeInterval(TimeInterval(minutes * 60) + 30))
        #expect(engine.closet.balance == points)
        #expect(update.awards.map(\.points).reduce(0, +) == points)
        #expect(engine.session.runState == .idle)
    }

    @Test func pomodoroBlockPaysWhenItsBreakStarts() {
        var engine = StudyEngine()
        #expect(engine.session.method.kind == .pomodoro)
        engine.primaryAction(at: Self.t0)
        let update = engine.catchUp(at: Self.t0.addingTimeInterval(25 * 60))
        #expect(update.phaseCompleted)
        #expect(update.awards.map(\.points) == [35])
        #expect(engine.session.phase == .shortBreak)
        #expect(engine.session.isRunning)
    }

    /// The app is killed a minute into a Pomodoro block and opened again
    /// an hour later: the block and its break both ended while it was gone,
    /// at their real times, and the block is paid once.
    @Test func killedMidBlockIsPaidOnceOnRelaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let persistence = StudyPersistence(folder: folder)

        var engine = persistence.load().engine
        engine.primaryAction(at: Self.t0)
        _ = engine.catchUp(at: Self.t0.addingTimeInterval(60))
        try persistence.save(engine, replacing: nil, unreadable: [])

        let reopened = Self.t0.addingTimeInterval(3600)
        var relaunched = persistence.load().engine
        let update = relaunched.catchUp(at: reopened)
        #expect(update.ended.map(\.phase) == [.focus, .shortBreak])
        #expect(update.ended.map(\.endedAt) == [Self.t0.addingTimeInterval(1500), Self.t0.addingTimeInterval(1800)])
        #expect(update.awards.map(\.points) == [35])
        #expect(relaunched.closet.balance == 35)
        #expect(relaunched.session.runState == .idle)
        #expect(relaunched.session.completedFocusCount == 1)
        try persistence.save(relaunched, replacing: nil, unreadable: [])

        // A second launch finds nothing left to pay.
        var again = persistence.load().engine
        #expect(again.catchUp(at: reopened.addingTimeInterval(600)).awards.isEmpty)
        #expect(again.closet.balance == 35)
        // The next block starts from the same count and pays on its own.
        again.primaryAction(at: reopened.addingTimeInterval(600))
        let next = again.catchUp(at: reopened.addingTimeInterval(600 + 1500))
        #expect(next.awards.map(\.points) == [35])
        #expect(again.closet.balance == 70)
    }

    /// Suspended in the middle of a paused block: no time passes while
    /// paused, however long the app is away.
    @Test func pausedSessionStaysPausedWhileSuspended() {
        var engine = StudyEngine()
        engine.primaryAction(at: Self.t0)
        engine.primaryAction(at: Self.t0.addingTimeInterval(600))
        #expect(engine.session.runState == .paused)
        let update = engine.catchUp(at: Self.t0.addingTimeInterval(86_400))
        #expect(update.isEmpty)
        #expect(engine.session.remaining(at: Self.t0.addingTimeInterval(86_400)) == 900)
    }

    @Test func choosingAnotherMethodMidBlockBanksTheMinutes() {
        var engine = StudyEngine()
        engine.primaryAction(at: Self.t0)
        let update = engine.choose(.ultradian, at: Self.t0.addingTimeInterval(10 * 60))
        #expect(update.awards.map(\.points) == [10])
        #expect(engine.session.method.kind == .ultradian)
        #expect(engine.session.runState == .idle)
    }

    @Test func theAnkiSprintIsNotOffered() {
        #expect(!StudyEngine.menu.offers(.ankiSprint))
        var engine = StudyEngine(session: StudySession(method: .preset(.ankiSprint)))
        #expect(engine.session.method.kind == StudyEngine.menu.startingKind)
        #expect(engine.choose(.ankiSprint, at: Self.t0) == StudyEngine.Update())
    }

    @Test func flowtimeStretchEndsIntoItsBreakAndPays() {
        var engine = StudyEngine()
        engine.choose(.flowtime, at: Self.t0)
        engine.primaryAction(at: Self.t0)
        let update = engine.primaryAction(at: Self.t0.addingTimeInterval(30 * 60))
        #expect(update.ended.map(\.outcome) == [.stopped])
        #expect(update.awards.map(\.points) == [40])
        #expect(engine.session.phase == .shortBreak)
    }

    /// The log keeps the study stretches, as on the Mac; breaks are not study time.
    @Test func theLogKeepsEveryStudyStretch() {
        var engine = StudyEngine()
        engine.primaryAction(at: Self.t0)
        engine.catchUp(at: Self.t0.addingTimeInterval(1800))
        #expect(engine.log.entries.map(\.minutes) == [25])
        let tally = engine.summary(on: Self.t0, calendar: Calendar(identifier: .gregorian))
        #expect(tally.points == 35)
    }
}
