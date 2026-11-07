import Foundation
import Testing
import TabbiKitCore
@testable import TabbiPhone

/// Replays every sequence in `shared/fixtures/study-session/study-session.json`
/// on the iPhone build of TabbiKitCore, so the phone's timer runs exactly
/// the Mac's sessions, and checks that the clock the iPhone pays points
/// from (`StudyEngine.observation`) is the Mac's shared focus clock.
@Suite struct StudySessionFixtureTests {
    static let file: StudySessionFile? = try? Fixtures.decode(StudySessionFile.self, from: "study-session")

    @Test func fixtureLoads() throws {
        let file = try #require(Self.file)
        #expect(file.schema == "tabbi.study-session.golden")
        #expect(file.version == 1)
        #expect(file.sequences.count >= 18)
    }

    @Test(arguments: (Self.file?.sequences ?? []).map(\.name))
    func replays(_ name: String) throws {
        let sequence = try #require(Self.file?.sequences.first { $0.name == name })
        let method = sequence.method.method
        var session = StudySession(method: method)
        for (index, step) in sequence.steps.enumerated() {
            let input = step.input
            let now = Fixtures.date(input.at)
            var ended: [StudyPhaseRecord] = []
            var taken: [StudyPhaseRecord] = []
            var accepted: Bool?
            switch input.action {
            case "start": session.start(at: now)
            case "pause": session.pause(at: now)
            case "skip": session.skip(at: now)
            case "stopFocus": accepted = session.stopFocus(at: now)
            case "reset": session.reset(at: now)
            case "switchMethod": session.switchMethod(to: input.method?.method ?? method, at: now)
            case "retune": accepted = session.retune(to: input.method?.method ?? method, at: now)
            case "reviewed": ended = session.recordReviewedToday(input.count ?? 0, at: now)
            case "advance": ended = session.advance(to: now)
            case "takeLog": taken = session.takeLog()
            default: Issue.record("Unknown action \(input.action)")
            }
            let where_ = "\(name) step \(index) (\(input.action))"
            check(ended, against: step.ended ?? [], where_)
            check(taken, against: step.taken ?? [], where_)
            if let expected = step.accepted { #expect(accepted == expected, "\(where_)") }
            check(session, at: now, against: step.state, where_)
            if let view = step.view, L10n.current == "en" {
                let readout = StudyTimerFormat.readout(session, at: now)
                #expect(readout.value == view.value, "\(where_)")
                #expect(readout.caption == view.caption, "\(where_)")
                #expect(StudyTimerFormat.primaryAction(session) == view.primaryAction, "\(where_)")
                #expect(StudyTimerFormat.roundLabel(session) == view.round, "\(where_)")
            }
            check(StudyEngine.observation(of: session, at: now), session: session, against: step.provided, where_)
        }
    }

    private func check(_ records: [StudyPhaseRecord], against expected: [StudySessionFile.Record], _ where_: String) {
        #expect(records.count == expected.count, "\(where_): ended count")
        for (record, golden) in zip(records, expected) {
            #expect(record.method.rawValue == golden.method, "\(where_)")
            #expect(record.phase.rawValue == golden.phase, "\(where_)")
            #expect(near(record.startedAt.timeIntervalSince1970, golden.startedAt), "\(where_)")
            #expect(near(record.endedAt.timeIntervalSince1970, golden.endedAt), "\(where_)")
            #expect(near(record.activeDuration, golden.activeDuration), "\(where_)")
            #expect(record.outcome.rawValue == golden.outcome, "\(where_)")
            #expect(record.cards == golden.cards, "\(where_)")
            let activity = record.activityRecord(source: StudyEngine.source)
            #expect(activity?.kind.rawValue == golden.activity?.kind, "\(where_)")
            #expect(near(activity?.quantity, golden.activity?.quantity), "\(where_)")
        }
    }

    private func check(_ session: StudySession, at now: Date, against state: StudySessionFile.State, _ where_: String) {
        #expect(session.phase.rawValue == state.phase, "\(where_)")
        #expect(session.runState.rawValue == state.run, "\(where_)")
        #expect(near(session.phaseDuration, state.phaseDuration), "\(where_)")
        #expect(session.completedFocusCount == state.completedFocusCount, "\(where_)")
        #expect(session.cardsDone == state.cardsDone, "\(where_)")
        #expect(near(session.lastFocusWorked, state.lastFocusWorked), "\(where_)")
        #expect(near(session.elapsed(at: now), state.elapsed), "\(where_)")
        #expect(near(session.remaining(at: now), state.remaining), "\(where_)")
        #expect(near(session.endsAt?.timeIntervalSince1970, state.endsAt), "\(where_)")
        #expect(near(session.runningSince?.timeIntervalSince1970, state.runningSince), "\(where_)")
        #expect(near(session.progress(at: now), state.progress), "\(where_)")
    }

    /// While the session is under way, the iPhone's crediting clock is the
    /// Mac's shared focus clock exactly; idle (where the Mac shares
    /// nothing) it still carries the count, so finished blocks are paid.
    private func check(_ focus: ProvidedFocus, session: StudySession, against provided: StudySessionFile.Provided?,
                       _ where_: String) {
        #expect(focus.completedFocusCount == session.completedFocusCount, "\(where_)")
        #expect(focus.source == StudyEngine.source, "\(where_)")
        #expect(focus.logsEarlyEnds, "\(where_)")
        guard let provided else {
            #expect(session.runState == .idle, "\(where_): only an idle session shares no clock")
            #expect(focus.clock == .idle, "\(where_)")
            return
        }
        #expect(focus.phase.rawValue == provided.phase, "\(where_)")
        #expect(focus.completedFocusCount == provided.completedFocusCount, "\(where_)")
        #expect(near(focus.phaseLength, provided.phaseLength), "\(where_)")
        #expect(near(focus.focusLength, provided.focusLength), "\(where_)")
        switch (focus.clock, provided.clock.kind) {
        case (.countdown(let end), "countdown"): #expect(near(end.timeIntervalSince1970, provided.clock.endsAt), "\(where_)")
        case (.countUp(let since), "countUp"): #expect(near(since.timeIntervalSince1970, provided.clock.since), "\(where_)")
        case (.paused(let shown), "paused"): #expect(near(shown, provided.clock.shown), "\(where_)")
        default: Issue.record("\(where_): clock \(focus.clock) is not \(provided.clock.kind)")
        }
    }
}

/// Numbers match within a microsecond (the README allows 1e-9 on
/// fractions; dates here are seconds since 1970); two absent
/// values match too.
func near(_ value: Double?, _ expected: Double?) -> Bool {
    switch (value, expected) {
    case (nil, nil): true
    case (let value?, let expected?): abs(value - expected) <= 1e-6
    default: false
    }
}
