import Foundation
import Testing
import TabbiKitCore
@testable import TabbiPhone

/// The pieces around the engine: the study methods match the Mac's
/// fixture, files round trip, notifications fall on the phase ends, and the
/// Live Activity carries the session's dates.
@Suite struct AppPlumbingTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    struct MethodsFile: Decodable {
        struct Method: Decodable {
            let kind: String
            let phaseSeconds: [String: Double]
        }

        let schema: String
        let methods: [Method]
        let timerMinMinutes: Int
        let timerMaxMinutes: Int
    }

    @Test func theMenuIsTheMacsMethodsWithoutTheSprint() throws {
        let file = try Fixtures.decode(MethodsFile.self, from: "study-methods")
        #expect(file.schema == "tabbi.study-methods.golden")
        let golden = file.methods.filter { $0.kind != StudyMethodKind.ankiSprint.rawValue }
        #expect(StudyEngine.menu.kinds.map(\.rawValue) == golden.map(\.kind))
        for method in golden {
            let preset = StudyMethod.preset(try #require(StudyMethodKind(rawValue: method.kind)))
            for phase in StudyPhaseKind.allCases {
                #expect(near(preset.duration(of: phase), method.phaseSeconds[phase.rawValue]), "\(method.kind) \(phase)")
            }
        }
        // The one-minute timer the end-to-end check runs is in range.
        #expect(file.timerMinMinutes == 1)
        #expect(StudyTimerLength.range == file.timerMinMinutes...file.timerMaxMinutes)
    }

    @Test @MainActor func theStoreSavesAndRestoresTheSession() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let persistence = StudyPersistence(folder: folder)
        let store = StudyStore(persistence: persistence, live: false, now: Self.t0)
        store.choose(.timer, at: Self.t0)
        store.setTimer(StudyTimerLength(minutes: 1), at: Self.t0)
        store.primaryAction(at: Self.t0)
        #expect(store.session.isRunning)

        // Each file carries its version, so later builds can migrate it.
        let study = try Data(contentsOf: persistence.studyURL)
        #expect(VersionedJSON.version(of: study) == 1)
        #expect(FileManager.default.fileExists(atPath: persistence.petURL.path))

        let reopened = StudyStore(persistence: persistence, live: false, now: Self.t0.addingTimeInterval(30))
        #expect(reopened.session.method.kind == .timer)
        #expect(reopened.engine.timer.minutes == 1)
        #expect(reopened.session.endsAt == Self.t0.addingTimeInterval(60))
        #expect(reopened.session.isRunning)
    }

    @Test func anUnreadableFileIsNeverOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let persistence = StudyPersistence(folder: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let garbage = Data("not json".utf8)
        try garbage.write(to: persistence.petURL)
        let loaded = persistence.load()
        #expect(loaded.unreadable == [persistence.petURL])
        var engine = loaded.engine
        engine.primaryAction(at: Self.t0)
        try persistence.save(engine, replacing: nil, unreadable: loaded.unreadable)
        #expect(try Data(contentsOf: persistence.petURL) == garbage)
        #expect(FileManager.default.fileExists(atPath: persistence.studyURL.path))
    }

    @Test func alertsFallOnEveryPhaseEndAhead() {
        var session = StudySession(method: .preset(.pomodoro))
        session.start(at: Self.t0)
        let alerts = PhaseAlert.upcoming(for: session)
        // The block runs into its break, which ends into an idle block.
        #expect(alerts.map(\.fireAt) == [Self.t0.addingTimeInterval(1500), Self.t0.addingTimeInterval(1800)])
        #expect(Set(alerts.map(\.id)).count == 2)
        if L10n.current == "en" {
            #expect(alerts.map(\.title) == ["Focus session done", "Break's over"])
            #expect(alerts.map(\.body) == ["Time for a 5-minute break.", "Ready for another 25-minute focus session?"])
        }

        var timer = StudySession(method: StudyTimerLength(minutes: 1).method)
        timer.start(at: Self.t0)
        #expect(PhaseAlert.upcoming(for: timer).map(\.fireAt) == [Self.t0.addingTimeInterval(60)])

        timer.pause(at: Self.t0.addingTimeInterval(10))
        #expect(PhaseAlert.upcoming(for: timer).isEmpty)
        #expect(PhaseAlert.upcoming(for: StudySession(method: .preset(.flowtime))).isEmpty)
    }

    @Test func theLiveActivityCarriesTheSessionsDates() throws {
        var session = StudySession(method: .preset(.pomodoro))
        #expect(StudyActivityAttributes.ContentState(session, at: Self.t0) == nil)

        session.start(at: Self.t0)
        let running = try #require(StudyActivityAttributes.ContentState(session, at: Self.t0.addingTimeInterval(100)))
        #expect(running.clock == .countdown(start: Self.t0, end: Self.t0.addingTimeInterval(1500)))
        #expect(running.endsAt == Self.t0.addingTimeInterval(1500))
        #expect(!running.isBreak)

        // Paused five minutes in and resumed later: the bar's start moves
        // so the countdown still ends 20 minutes after the resume.
        session.pause(at: Self.t0.addingTimeInterval(300))
        let paused = try #require(StudyActivityAttributes.ContentState(session, at: Self.t0.addingTimeInterval(400)))
        #expect(paused.clock == .paused(shown: 1200))
        #expect(paused.endsAt == nil)
        session.start(at: Self.t0.addingTimeInterval(1000))
        let resumed = try #require(StudyActivityAttributes.ContentState(session, at: Self.t0.addingTimeInterval(1000)))
        #expect(resumed.clock == .countdown(start: Self.t0.addingTimeInterval(700), end: Self.t0.addingTimeInterval(2200)))

        var flow = StudySession(method: .preset(.flowtime))
        flow.start(at: Self.t0)
        #expect(StudyActivityAttributes.ContentState(flow, at: Self.t0)?.clock == .countUp(since: Self.t0))

        // Its whole payload stays far inside ActivityKit's 4 KB.
        let attributes = StudyActivityAttributes(pet: .starter(.cat))
        let size = try JSONEncoder().encode(attributes).count + JSONEncoder().encode(running).count
        #expect(size < 4096)
    }
}
