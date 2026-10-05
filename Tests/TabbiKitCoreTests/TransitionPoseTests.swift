import XCTest
@testable import TabbiKitCore

final class TransitionPoseTests: XCTestCase {
    private let presets: [TransitionPose] = [.pop, .swap, .row(from: .top), .row(from: .bottom),
                                             .row(from: .leading), .row(from: .trailing)]

    func testInsertedViewIsNeutral() {
        for pose in presets {
            for reduce in [false, true] {
                let resolved = pose.resolved(isIdentity: true, reduceMotion: reduce)
                XCTAssertEqual(resolved, .init(scale: 1, offsetX: 0, offsetY: 0, opacity: 1))
            }
        }
    }

    func testReduceMotionOnlyFades() {
        for pose in presets {
            let resolved = pose.resolved(isIdentity: false, reduceMotion: true)
            XCTAssertEqual(resolved, .init(scale: 1, offsetX: 0, offsetY: 0, opacity: 0))
        }
    }

    func testOutsidePoseFadesAndMovesALittle() {
        for pose in presets {
            let resolved = pose.resolved(isIdentity: false, reduceMotion: false)
            XCTAssertEqual(resolved.opacity, 0)
            XCTAssertGreaterThanOrEqual(resolved.scale, 0.8)
            XCTAssertLessThanOrEqual(resolved.scale, 1)
            XCTAssertLessThanOrEqual(abs(resolved.offsetX), 8)
            XCTAssertLessThanOrEqual(abs(resolved.offsetY), 8)
        }
    }

    func testRowsComeFromTheirEdge() {
        XCTAssertLessThan(TransitionPose.row(from: .top).offsetY, 0)
        XCTAssertGreaterThan(TransitionPose.row(from: .bottom).offsetY, 0)
        XCTAssertLessThan(TransitionPose.row(from: .leading).offsetX, 0)
        XCTAssertGreaterThan(TransitionPose.row(from: .trailing).offsetX, 0)
        XCTAssertEqual(TransitionPose.row(from: .top).scale, 1)
    }

    func testSwapGrowsFromTheTop() {
        XCTAssertEqual(TransitionPose.swap.anchorY, 0)
        XCTAssertLessThan(TransitionPose.swap.scale, 1)
    }
}
