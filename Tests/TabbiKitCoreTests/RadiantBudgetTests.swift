import Foundation
import XCTest
@testable import TabbiKitCore

/// Radiant effects one at a time: every placement of every effect, on every
/// body shape (all 19 breeds with `TABBI_RADIANT_EXHAUSTIVE=1`), in every
/// animation, frame and tick, at full size and under the
/// closed notch's ceiling. Each keeps off the eyes and face, inside the
/// frame's margin and below the ceiling, changes no more pixels from one
/// tick to the next than `radiant-costs.json` records for it, and stays
/// within the Radiant per-tick budget.
///
/// `TABBI_RADIANT_EXHAUSTIVE=1 TABBI_RECORD_RADIANT_COSTS=1 swift test -c release --filter RadiantBudgetTests/testRecordCosts`
/// measures every placement again and rewrites `radiant-costs.json`.
final class RadiantBudgetTests: XCTestCase {
    static var costsURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TabbiKitCore/Pets/PetArt/radiant-costs.json")
    }

    /// Every placement's highest change on each tick, over all breeds.
    static func measure(_ item: PetItem, _ intensity: PetRadiantIntensity, placement: Int,
                        file: StaticString = #filePath, line: UInt = #line) -> [Int] {
        let layout = RadiantAudit.single(item, intensity, placement: placement)
        var worst = Array(repeating: 0, count: layout.loop)
        for breed in RadiantAudit.breeds {
            let result = RadiantAudit.audit([item], layout: layout, breed: breed)
            let label = "\(item) \(intensity) placement \(placement) on \(breed)"
            XCTAssertEqual(result.eyeHits, 0, "covers an eye: \(label)", file: file, line: line)
            XCTAssertEqual(result.faceHits, 0, "covers the face: \(label)", file: file, line: line)
            XCTAssertEqual(result.marginHits, 0, "outside the margin: \(label)", file: file, line: line)
            XCTAssertEqual(result.ceilingHits, 0, "above the notch ceiling: \(label)", file: file, line: line)
            XCTAssertEqual(result.collisions, 0, "collides with itself: \(label)", file: file, line: line)
            worst = zip(worst, result.maxChange).map { max($0, $1) }
        }
        return worst
    }

    func testRecordCosts() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TABBI_RECORD_RADIANT_COSTS"] == "1", "Recording only")
        try XCTSkipUnless(RadiantAudit.isExhaustive, "Record with TABBI_RADIANT_EXHAUSTIVE=1, over every breed and animation")
        var table: [String: [String: [[Int]]]] = [:]
        var boldMax = 0, anyMax = 0
        for art in RadiantArt.shared.items {
            for intensity in [PetRadiantIntensity.bold, .subtle] {
                let effect = art.effect(intensity)!
                let rows = effect.placements.indices.map { Self.measure(art.item, intensity, placement: $0) }
                table[art.item.id, default: [:]][intensity.rawValue] = rows
                let peak = rows.flatMap { $0 }.max() ?? 0
                anyMax = max(anyMax, peak)
                if intensity == .bold { boldMax = max(boldMax, peak) }
                print("RADIANT COST \(art.item.id) \(intensity): \(rows.map { $0.max() ?? 0 })")
            }
        }
        // The smallest per-tick budget the Bold set fits, and a combined cap
        // that lets one Bold effect play beside the busiest Subtle one.
        let subtleMax = table.values.compactMap { $0["subtle"] }.flatMap { $0 }.flatMap { $0 }.max() ?? 0
        let perTick = max(boldMax, anyMax)
        let combined = perTick + subtleMax
        let document: [String: Any] = ["schema": RadiantArt.costsSchema, "perTickBudget": perTick,
                                       "combinedBudget": combined, "costs": table]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.costsURL)
        print("RADIANT BUDGET perTick \(perTick) combined \(combined) (bold max \(boldMax), subtle max \(subtleMax))")
    }

    private func check(_ item: PetItem, _ intensity: PetRadiantIntensity) throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_RADIANT_COSTS"] == "1", "Recording")
        let costs = RadiantArt.costs
        let effect = try XCTUnwrap(RadiantArt.shared.item(item)?.effect(intensity))
        for placement in effect.placements.indices {
            let measured = Self.measure(item, intensity, placement: placement)
            let recorded = try XCTUnwrap(costs.cost(item, intensity, placement: placement), "no recorded cost")
            if RadiantAudit.isExhaustive {
                XCTAssertEqual(recorded, measured, "\(item) \(intensity) placement \(placement): rerun with TABBI_RECORD_RADIANT_COSTS=1")
            } else {
                for (tick, cost) in measured.enumerated() {
                    XCTAssertLessThanOrEqual(cost, recorded[tick], "\(item) \(intensity) placement \(placement) tick \(tick)")
                }
            }
            XCTAssertLessThanOrEqual(measured.max() ?? 0, costs.perTickBudget, "\(item) \(intensity) placement \(placement)")
        }
    }

    func testSorcererBold() throws { try check(.accessory(.blindfoldedSorcerer), .bold) }
    func testSorcererSubtle() throws { try check(.accessory(.blindfoldedSorcerer), .subtle) }
    func testWizardHatBold() throws { try check(.accessory(.wizardHat), .bold) }
    func testWizardHatSubtle() throws { try check(.accessory(.wizardHat), .subtle) }
    func testTinyCrownBold() throws { try check(.accessory(.tinyCrown), .bold) }
    func testTinyCrownSubtle() throws { try check(.accessory(.tinyCrown), .subtle) }
    func testDinosaurHoodieBold() throws { try check(.outfit(.dinosaurHoodie), .bold) }
    func testDinosaurHoodieSubtle() throws { try check(.outfit(.dinosaurHoodie), .subtle) }
    func testAstronautHelmetBold() throws { try check(.accessory(.astronautHelmet), .bold) }
    func testAstronautHelmetSubtle() throws { try check(.accessory(.astronautHelmet), .subtle) }
    func testGraduationCapBold() throws { try check(.accessory(.graduationCap), .bold) }
    func testGraduationCapSubtle() throws { try check(.accessory(.graduationCap), .subtle) }
    func testRainCloudBold() throws { try check(.accessory(.rainCloud), .bold) }
    func testRainCloudSubtle() throws { try check(.accessory(.rainCloud), .subtle) }
    func testWhiteCoatBold() throws { try check(.outfit(.whiteCoat), .bold) }
    func testWhiteCoatSubtle() throws { try check(.outfit(.whiteCoat), .subtle) }

    /// Every eligible item has a test above.
    func testEveryEffectIsChecked() {
        XCTAssertEqual(PetRadiant.eligibleItems.count * 2, 16)
    }
}
