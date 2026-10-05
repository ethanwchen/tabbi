import XCTest
import TabbiKitCore

final class CelebrationTests: XCTestCase {
    func testTheSameSeedAlwaysThrowsTheSameBurst() {
        let first = CelebrationBurst(tier: .burst, style: .confetti, seed: 7, paletteSize: 5)
        let again = CelebrationBurst(tier: .burst, style: .confetti, seed: 7, paletteSize: 5)
        let other = CelebrationBurst(tier: .burst, style: .confetti, seed: 8, paletteSize: 5)
        XCTAssertEqual(first, again)
        XCTAssertNotEqual(first, other)
    }

    func testEachTierThrowsItsParticlesAndStaysWithinItsTimeBudget() {
        for style in CelebrationStyle.allCases {
            for seed: UInt64 in 0..<20 {
                let burst = CelebrationBurst(tier: .burst, style: style, seed: seed, paletteSize: 6)
                XCTAssertEqual(burst.particles.count, 36)
                XCTAssertLessThanOrEqual(burst.duration, 1.5)
                let milestone = CelebrationBurst(tier: .milestone, style: style, seed: seed, paletteSize: 6)
                XCTAssertEqual(milestone.particles.count, 72)
                XCTAssertLessThan(milestone.duration, 2)
                XCTAssertGreaterThan(milestone.duration, burst.duration - 0.5)
            }
        }
    }

    func testParticlesUseEveryPaletteColorAndStayInRange() {
        let burst = CelebrationBurst(tier: .burst, style: .sparkles, seed: 3, paletteSize: 5)
        XCTAssertEqual(Set(burst.particles.map(\.colorIndex)), Set(0..<5))
        let single = CelebrationBurst(tier: .burst, style: .hearts, seed: 3, paletteSize: 0)
        XCTAssertEqual(Set(single.particles.map(\.colorIndex)), [0])
    }

    func testParticlesLaunchUpwardWithinTheSpreadThenFallAndFade() throws {
        let burst = CelebrationBurst(tier: .milestone, style: .confetti, seed: 42, paletteSize: 6)
        for particle in burst.particles {
            XCTAssertLessThanOrEqual(abs(particle.angle), CelebrationBurst.spread)
            XCTAssertNil(CelebrationBurst.state(of: particle, at: particle.delay - 0.01))
            let launch = try XCTUnwrap(CelebrationBurst.state(of: particle, at: particle.delay))
            XCTAssertEqual(launch.x, 0, accuracy: 1e-9)
            XCTAssertEqual(launch.y, 0, accuracy: 1e-9)
            XCTAssertEqual(launch.scale, CelebrationBurst.popScale, accuracy: 1e-9)
            XCTAssertEqual(launch.opacity, 1)

            let rising = try XCTUnwrap(CelebrationBurst.state(of: particle, at: particle.delay + 0.1))
            XCTAssertLessThan(rising.y, 0, "particles start by rising")
            XCTAssertEqual(rising.x.sign, particle.angle.sign == .minus ? .minus : .plus)

            let late = try XCTUnwrap(CelebrationBurst.state(of: particle, at: particle.delay + particle.lifetime * 0.99))
            XCTAssertGreaterThan(late.y, rising.y, "gravity brings them back down")
            XCTAssertLessThan(late.opacity, 0.05)
            XCTAssertEqual(late.scale, 1, accuracy: 1e-9)
            XCTAssertNil(CelebrationBurst.state(of: particle, at: particle.delay + particle.lifetime + 1e-6))
        }
    }

    func testOpacityHoldsThenFadesSmoothlyOverTheLastStretch() throws {
        let particle = try XCTUnwrap(CelebrationBurst(tier: .burst, style: .hearts, seed: 1, paletteSize: 3).particles.first)
        var previous = 1.0
        for step in 0..<100 {
            let elapsed = particle.delay + particle.lifetime * Double(step) / 100
            let state = try XCTUnwrap(CelebrationBurst.state(of: particle, at: elapsed))
            if Double(step) / 100 <= 1 - CelebrationBurst.fadeShare {
                XCTAssertEqual(state.opacity, 1)
            }
            XCTAssertLessThanOrEqual(state.opacity, previous)
            previous = state.opacity
        }
    }

    func testTheFallIsCappedByAirDrag() throws {
        let particle = try XCTUnwrap(CelebrationBurst(tier: .milestone, style: .confetti, seed: 9, paletteSize: 3).particles.first)
        let terminal = CelebrationBurst.gravity / CelebrationBurst.drag
        let dt = 0.01
        let end = particle.delay + particle.lifetime - dt
        let a = try XCTUnwrap(CelebrationBurst.state(of: particle, at: end - dt))
        let b = try XCTUnwrap(CelebrationBurst.state(of: particle, at: end))
        XCTAssertLessThan((b.y - a.y) / dt, terminal)
    }

    func testABurstIsFinishedOnceItsLastParticleIsGone() {
        let burst = CelebrationBurst(tier: .burst, style: .pawPrints, seed: 5, paletteSize: 4)
        XCTAssertFalse(burst.isFinished(at: 0))
        XCTAssertTrue(burst.isFinished(at: burst.duration))
        XCTAssertTrue(burst.particles.allSatisfy { CelebrationBurst.state(of: $0, at: burst.duration) == nil })
    }

    func testThePacerAllowsOneBurstEveryTenMinutes() {
        var pacer = CelebrationPacer()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        XCTAssertEqual(pacer.admit(.burst, at: start), .burst)
        XCTAssertNil(pacer.admit(.burst, at: start.addingTimeInterval(60)))
        XCTAssertNil(pacer.admit(.burst, at: start.addingTimeInterval(599)))
        XCTAssertEqual(pacer.admit(.burst, at: start.addingTimeInterval(600)), .burst)
    }

    func testTheFirstMilestoneOfADayAlwaysPlaysAndLaterOnesBecomeBursts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = Date(timeIntervalSinceReferenceDate: 800_000_000 - 800_000_000.truncatingRemainder(dividingBy: 86_400) + 9 * 3600)
        var pacer = CelebrationPacer()
        XCTAssertEqual(pacer.admit(.burst, at: morning, calendar: calendar), .burst)
        XCTAssertEqual(pacer.admit(.milestone, at: morning.addingTimeInterval(30), calendar: calendar), .milestone,
                       "a milestone isn't held back by a recent burst")
        XCTAssertNil(pacer.admit(.milestone, at: morning.addingTimeInterval(60), calendar: calendar))
        XCTAssertEqual(pacer.admit(.milestone, at: morning.addingTimeInterval(3600), calendar: calendar), .burst)
        XCTAssertEqual(pacer.admit(.milestone, at: morning.addingTimeInterval(86_400), calendar: calendar), .milestone)
    }
}
