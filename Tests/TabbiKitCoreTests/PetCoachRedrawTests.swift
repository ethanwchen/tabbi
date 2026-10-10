import XCTest
import TabbiKitCore

/// The coach overlay redraws only when its picture changes: every step of a
/// walk, but only on clip frame changes while the pet stands, talks or peeks.
final class PetCoachRedrawTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let clips = PetClipSet(profile: .starter(.cat))
    /// Redraws land a hair after each change so rounding can't show the old
    /// frame; samples sit between the clips' 10 ms frame boundaries.
    private let lateness: TimeInterval = 0.002

    /// What the overlay draws at `date` while the pet stands still: the
    /// phase and which clip frame shows (the same choice the view makes).
    private struct StandingPicture: Equatable {
        var phase: PetCoachStroll.Phase
        var animation: PetAnimation?
        var frame: Int?
    }

    private func picture(_ stroll: PetCoachStroll, arrival: PetAnimation, at date: Date) -> StandingPicture {
        let phase = stroll.phase(at: date)
        guard phase == .talking else { return StandingPicture(phase: phase) }
        let elapsed = date.timeIntervalSince(stroll.arrivesAt)
        let arrivalClip = clips[arrival]
        if elapsed < arrivalClip.duration {
            return StandingPicture(phase: phase, animation: arrival, frame: arrivalClip.frameIndex(at: elapsed))
        }
        return StandingPicture(phase: phase, animation: .idle,
                               frame: clips[.idle].frameIndex(at: elapsed - arrivalClip.duration))
    }

    private func redraws(_ stroll: PetCoachStroll, arrival: PetAnimation, from start: Date) -> [Date] {
        var dates: [Date] = []
        var next: Date? = start
        while let date = next, dates.count < 10_000 {
            dates.append(date)
            next = stroll.nextRedraw(after: date, clips: clips, arrival: arrival)
            if let next { XCTAssertGreaterThan(next, date) }
        }
        return dates
    }

    func testStandingPetRedrawsOnlyOnFrameChangesNotThirtyTimesASecond() {
        let stroll = PetCoachStroll(startedAt: t0)
        let dates = redraws(stroll, arrival: .alert, from: t0)
        let talking = dates.filter { stroll.phase(at: $0) == .talking }
        // Twelve seconds of talking at 30 fps would be 360 redraws.
        XCTAssertGreaterThan(talking.count, 3)
        XCTAssertLessThan(talking.count, 120)
        // Each redraw while talking shows something new.
        for (previous, date) in zip(talking, talking.dropFirst()) {
            XCTAssertNotEqual(picture(stroll, arrival: .alert, at: previous),
                              picture(stroll, arrival: .alert, at: date), "\(date.timeIntervalSince(t0))")
        }
    }

    func testNoFrameChangeIsMissedWhileThePetStands() {
        let stroll = PetCoachStroll(startedAt: t0, talkDuration: 8)
        for arrival in [PetAnimation.alert, .celebrate] {
            let dates = redraws(stroll, arrival: arrival, from: t0)
            var index = 0
            for step in stride(from: stroll.arrivesAt.timeIntervalSince(t0) + 0.005, to: 10, by: 0.01) {
                let date = t0.addingTimeInterval(step)
                while index + 1 < dates.count, dates[index + 1] <= date.addingTimeInterval(lateness) { index += 1 }
                XCTAssertEqual(picture(stroll, arrival: arrival, at: dates[index]),
                               picture(stroll, arrival: arrival, at: date),
                               "\(arrival) changed at \(step) s with no redraw")
            }
        }
    }

    func testWalkingPetMovesEveryFrameAndTheSceneEndsAtHome() {
        let stroll = PetCoachStroll(startedAt: t0)
        let dates = redraws(stroll, arrival: .alert, from: t0)
        for (previous, date) in zip(dates, dates.dropFirst()) where stroll.phase(at: previous) != .talking {
            XCTAssertLessThanOrEqual(date.timeIntervalSince(previous), 1 / PetCoachRedraw.walkFrameRate + 1e-6)
        }
        // It redraws on arrival and the moment it turns back, and stops once home.
        XCTAssertTrue(dates.contains { $0 >= stroll.arrivesAt && $0 < stroll.arrivesAt.addingTimeInterval(0.01) })
        XCTAssertTrue(dates.contains { $0 >= stroll.turnsBackAt && $0 < stroll.turnsBackAt.addingTimeInterval(0.01) })
        XCTAssertEqual(stroll.phase(at: dates.last!), .finished)
        XCTAssertNil(stroll.nextRedraw(after: stroll.endsAt, clips: clips, arrival: .alert))
    }

    func testBeforeTheStartItWaitsForThePetToSetOff() {
        let stroll = PetCoachStroll(startedAt: t0)
        let next = stroll.nextRedraw(after: t0.addingTimeInterval(-1), clips: clips, arrival: .alert)
        XCTAssertEqual(next?.timeIntervalSince(t0) ?? -1, 0, accuracy: 0.01)
    }

    func testDismissedPetTurnsBackRightAway() {
        var stroll = PetCoachStroll(startedAt: t0)
        let answered = stroll.arrivesAt.addingTimeInterval(2)
        stroll.dismiss(at: answered)
        let next = stroll.nextRedraw(after: answered.addingTimeInterval(-0.0005), clips: clips, arrival: .alert)
        XCTAssertNotNil(next)
        XCTAssertLessThanOrEqual(next!, answered.addingTimeInterval(0.01))
        // Walking home moves every frame again.
        let home = stroll.nextRedraw(after: answered.addingTimeInterval(0.1), clips: clips, arrival: .alert)
        XCTAssertEqual(home?.timeIntervalSince(answered) ?? -1, 0.1 + 1 / PetCoachRedraw.walkFrameRate, accuracy: 1e-6)
    }

    func testGlanceRedrawsOnPeekFramesAndHoldsStillWhileLooking() {
        let glance = PetCoachGlance(startedAt: t0, clips: clips)
        var dates: [Date] = []
        var next: Date? = t0.addingTimeInterval(-0.5)
        while let date = next, dates.count < 10_000 {
            dates.append(date)
            next = glance.nextRedraw(after: date, clips: clips)
        }
        // About one redraw per peek frame, nothing at 30 fps.
        let frames = clips[.peekIn].frames.count + clips[.peekOut].frames.count
        XCTAssertLessThanOrEqual(dates.count, frames + 4)
        // Nothing redraws during the hold, after peekIn's last frame shows.
        let holdStart = t0.addingTimeInterval(glance.enter + 0.01)
        let holdEnd = t0.addingTimeInterval(glance.enter + glance.hold)
        XCTAssertFalse(dates.contains { $0 > holdStart && $0 < holdEnd })
        // No frame change is missed.
        func shown(_ date: Date) -> String {
            guard let pose = glance.pose(at: date) else { return "hidden" }
            return "\(pose.animation)-\(clips[pose.animation].frameIndex(at: pose.elapsed))"
        }
        var index = 0
        for step in stride(from: -0.495, to: glance.duration + 0.5, by: 0.01) {
            let date = t0.addingTimeInterval(step)
            while index + 1 < dates.count, dates[index + 1] <= date.addingTimeInterval(lateness) { index += 1 }
            XCTAssertEqual(shown(dates[index]), shown(date), "changed at \(step) s with no redraw")
        }
        XCTAssertNil(glance.pose(at: dates.last!))
    }
}
