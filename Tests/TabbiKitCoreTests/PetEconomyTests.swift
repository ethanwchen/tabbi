import XCTest
@testable import TabbiKitCore

final class PetEconomyTests: XCTestCase {
    func testTypicalPaceFollowsThePointsRules() {
        XCTAssertEqual(PetEconomy.pointsPerTypicalBlock, 35, "25 focused minutes plus the completion bonus")
        XCTAssertEqual(PetEconomy.pointsPerTypicalDay, 105, "three blocks a day")
        XCTAssertEqual(PetEconomy.pointsPerTypicalWeek, 525, "five study days a week")
    }

    func testTimeToEarnRoundsUp() {
        XCTAssertEqual(PetEconomy.typicalDays(toEarn: 0), 0)
        XCTAssertEqual(PetEconomy.typicalDays(toEarn: -5), 0)
        XCTAssertEqual(PetEconomy.typicalDays(toEarn: 1), 1)
        XCTAssertEqual(PetEconomy.typicalDays(toEarn: 105), 1)
        XCTAssertEqual(PetEconomy.typicalDays(toEarn: 106), 2)
        XCTAssertEqual(PetEconomy.typicalBlocks(toEarn: 35), 1)
        XCTAssertEqual(PetEconomy.typicalBlocks(toEarn: 36), 2)
        XCTAssertEqual(PetEconomy.typicalBlocks(toEarn: 0), 0)
    }

    func testTiersDoNotOverlapAndLeaveGaps() {
        let ranges = PetPriceTier.allCases.map(\.priceRange)
        for (lower, upper) in zip(ranges, ranges.dropFirst()) {
            XCTAssertLessThan(lower.upperBound, upper.lowerBound)
        }
        XCTAssertNil(PetPriceTier(cost: 150), "between a day and two days is no tier")
        XCTAssertNil(PetPriceTier(cost: 800), "between a week and two weeks is no tier")
        XCTAssertNil(PetPriceTier(cost: 5000), "beyond four weeks is no tier")
    }

    func testEveryPriceSitsInsideATier() {
        for item in PetItem.shopItems {
            XCTAssertNotNil(PetPriceTier(cost: item.cost), "\(item.id) costs \(item.cost), outside every tier")
            XCTAssertEqual(item.tier, PetPriceTier(cost: item.cost), item.id)
        }
    }

    func testFirstFinishedBlockBuysAStarter() {
        let cheapest = PetItem.shopItems.filter { !$0.isFree }.map(\.cost).min()
        XCTAssertEqual(cheapest, PetEconomy.pointsPerTypicalBlock)
    }

    func testEveryTierHasSeveralItemsAndTheTiersRiseInShopOrder() {
        let tiers = PetItem.shopItems.map(\.tier)
        XCTAssertEqual(tiers, tiers.sorted(), "the shop lists cheaper tiers first")
        for tier in PetPriceTier.allCases {
            XCTAssertGreaterThanOrEqual(tiers.filter { $0 == tier }.count, 3, "\(tier) needs a few items to pick from")
        }
    }

    func testTimeToEarnEachTierAtTheTypicalPace() {
        for item in PetItem.shopItems {
            let days = PetEconomy.typicalDays(toEarn: item.cost)
            switch item.tier {
            case .free: XCTAssertEqual(days, 0, item.id)
            case .starter: XCTAssertEqual(days, 1, item.id)
            case .midTier: XCTAssertTrue((2...5).contains(days), item.id)
            case .showpiece: XCTAssertTrue((10...20).contains(days), "\(item.id): 2 to 4 weeks of 5 days")
            }
        }
        XCTAssertEqual(PetItem.accessory(.graduationCap).tier, .showpiece)
        XCTAssertEqual(PetItem.accessory(.beanie).tier, .starter)
    }
}
