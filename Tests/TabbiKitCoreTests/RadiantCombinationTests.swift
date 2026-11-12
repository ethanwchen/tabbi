import Foundation
import XCTest
@testable import TabbiKitCore

/// Radiant items worn together: every pair and triple that can be worn at
/// once (their slots differ), all Bold and all Subtle on every body shape in
/// the animations that cover every stance, and with
/// `TABBI_RADIANT_EXHAUSTIVE=1` every mix of Bold and Subtle on all 19
/// breeds in every animation, every frame and tick, at full size and under the
/// closed notch's ceiling. The resolver lays them out so no effect draws on
/// or beside another's pixels (no collisions at all), none covers an eye or
/// the face, all stay inside the margin and below the ceiling, and the
/// pixels they change together from one tick to the next stay within the
/// combined Radiant budget.
final class RadiantCombinationTests: XCTestCase {
    func testThereAreTwentySevenCombinations() {
        XCTAssertEqual(RadiantAudit.combinations.count, 27)
        XCTAssertEqual(RadiantAudit.combinations.filter { $0.count == 2 }.count, 17)
        XCTAssertEqual(RadiantAudit.combinations.filter { $0.count == 3 }.count, 10)
    }

    private func check(_ index: Int) throws {
        let items = RadiantAudit.combinations[index]
        let (outfit, accessories) = RadiantAudit.wearing(items)
        let budget = RadiantArt.costs.combinedBudget
        // Every mix of Bold and Subtle exhaustively; otherwise all Bold (the
        // default) and all Subtle.
        let mixes = RadiantAudit.isExhaustive ? Array(0..<(1 << items.count)) : [0, (1 << items.count) - 1]
        for mix in mixes {
            var look: [PetItem: PetRadiantIntensity] = [:]
            for (n, item) in items.enumerated() { look[item] = (mix >> n) & 1 == 0 ? .bold : .subtle }
            let layout = try XCTUnwrap(RadiantLayout.resolve(PetRadiantLook(look), outfit: outfit, accessories: accessories))
            XCTAssertEqual(layout.entries.count, items.count)
            for breed in RadiantAudit.breeds {
                let result = RadiantAudit.audit(items, layout: layout, breed: breed)
                let label = "\(look.map { "\($0.key) \($0.value)" }.sorted()) on \(breed)"
                XCTAssertEqual(result.collisions, 0, "effects collide: \(label)")
                XCTAssertEqual(result.eyeHits, 0, "covers an eye: \(label)")
                XCTAssertEqual(result.faceHits, 0, "covers the face: \(label)")
                XCTAssertEqual(result.marginHits, 0, "outside the margin: \(label)")
                XCTAssertEqual(result.ceilingHits, 0, "above the notch ceiling: \(label)")
                XCTAssertLessThanOrEqual(result.maxChange.max() ?? 0, budget, "over the combined budget: \(label)")
            }
        }
    }

    func testCombination00() throws { try check(0) }
    func testCombination01() throws { try check(1) }
    func testCombination02() throws { try check(2) }
    func testCombination03() throws { try check(3) }
    func testCombination04() throws { try check(4) }
    func testCombination05() throws { try check(5) }
    func testCombination06() throws { try check(6) }
    func testCombination07() throws { try check(7) }
    func testCombination08() throws { try check(8) }
    func testCombination09() throws { try check(9) }
    func testCombination10() throws { try check(10) }
    func testCombination11() throws { try check(11) }
    func testCombination12() throws { try check(12) }
    func testCombination13() throws { try check(13) }
    func testCombination14() throws { try check(14) }
    func testCombination15() throws { try check(15) }
    func testCombination16() throws { try check(16) }
    func testCombination17() throws { try check(17) }
    func testCombination18() throws { try check(18) }
    func testCombination19() throws { try check(19) }
    func testCombination20() throws { try check(20) }
    func testCombination21() throws { try check(21) }
    func testCombination22() throws { try check(22) }
    func testCombination23() throws { try check(23) }
    func testCombination24() throws { try check(24) }
    func testCombination25() throws { try check(25) }
    func testCombination26() throws { try check(26) }
}
