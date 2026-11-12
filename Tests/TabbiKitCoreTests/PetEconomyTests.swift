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

    func testStudyToEarnSpeaksInBlocksThenDaysThenWeeks() {
        XCTAssertEqual(PetEconomy.studyToEarn(0), "")
        XCTAssertEqual(PetEconomy.studyToEarn(1), "1 focus block")
        XCTAssertEqual(PetEconomy.studyToEarn(35), "1 focus block")
        XCTAssertEqual(PetEconomy.studyToEarn(36), "2 focus blocks")
        XCTAssertEqual(PetEconomy.studyToEarn(105), "3 focus blocks", "a day's points stay in blocks")
        XCTAssertEqual(PetEconomy.studyToEarn(106), "about 2 study days")
        XCTAssertEqual(PetEconomy.studyToEarn(525), "about 5 study days")
        XCTAssertEqual(PetEconomy.studyToEarn(526), "about 2 weeks")
        XCTAssertEqual(PetEconomy.typicalWeeks(toEarn: 1050), 2)
        XCTAssertEqual(PetEconomy.studyToEarn(2100), "about 4 weeks", "the priciest showpiece takes about a month")
        XCTAssertEqual(PetEconomy.studyToEarn(6300), "about 12 weeks", "the priciest heirloom takes about three months")
    }

    func testTiersDoNotOverlapAndLeaveGaps() {
        let ranges = PetPriceTier.allCases.map(\.priceRange)
        for (lower, upper) in zip(ranges, ranges.dropFirst()) {
            XCTAssertLessThan(lower.upperBound, upper.lowerBound)
        }
        XCTAssertNil(PetPriceTier(cost: 150), "between a day and two days is no tier")
        XCTAssertNil(PetPriceTier(cost: 800), "between a week and two weeks is no tier")
        XCTAssertNil(PetPriceTier(cost: 2500), "between four and six weeks is no tier")
        XCTAssertNil(PetPriceTier(cost: 6301), "beyond twelve weeks is no tier")
        XCTAssertEqual(PetPriceTier.heirloom.priceRange, 3150...6300, "6 to 12 typical weeks")
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
            case .heirloom: XCTAssertTrue((30...60).contains(days), "\(item.id): 6 to 12 weeks of 5 days")
            }
        }
        XCTAssertEqual(PetItem.accessory(.graduationCap).tier, .showpiece)
        XCTAssertEqual(PetItem.accessory(.beanie).tier, .starter)
        XCTAssertEqual(PetItem.accessory(.fireflies).tier, .heirloom)
    }

    /// Heirlooms sit on a shelf of their own, after every theme shelf, so
    /// the wardrobe still lists cheaper tiers first; no other shelf holds one.
    func testHeirloomsHaveTheirOwnLastShelf() {
        for item in PetItem.shopItems where item != .outfit(.none) {
            XCTAssertEqual(item.theme == .heirloom, item.tier == .heirloom, item.id)
        }
        XCTAssertEqual(PetCloset.shelves.last?.theme, .heirloom)
        let order = PetCloset.shelves.flatMap(\.items).map(\.tier)
        XCTAssertEqual(Array(order.suffix(PetItemTheme.heirloom.items.count)), Array(repeating: .heirloom,
                                                                                    count: PetItemTheme.heirloom.items.count))
    }

    /// A Radiant upgrade is 5x its item's price and sits outside the tiers:
    /// it is no catalog price, so the tier rules above never count it, and
    /// even the cheapest takes longer than the Golden Laurel's 8 weeks.
    func testRadiantUpgradesCostFiveTimesTheirItemOutsideTheTiers() {
        for item in PetRadiant.eligibleItems {
            XCTAssertEqual(PetRadiant.price(of: item), 5 * item.cost, "\(item)")
            XCTAssertGreaterThan(PetRadiant.price(of: item), 8 * PetEconomy.pointsPerTypicalWeek, "\(item)")
        }
        XCTAssertEqual(PetRadiant.eligibleItems.map { PetRadiant.price(of: $0) }.min(), 5_250)
    }
}
