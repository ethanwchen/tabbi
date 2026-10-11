import XCTest
@testable import TabbiKitCore

final class UnlockProgressTests: XCTestCase {
    func testAFirstSessionFillsTowardTheBeanie() throws {
        let progress = try XCTUnwrap(UnlockProgress(balance: 20, earned: 20, ledger: PetPointsLedger()))
        XCTAssertEqual(progress.item, .accessory(.beanie))
        XCTAssertEqual(progress.fractionBefore, 0)
        XCTAssertEqual(progress.fraction, 20.0 / 35.0, accuracy: 0.0001)
        XCTAssertEqual(progress.missing, 15)
        XCTAssertEqual(progress.sessionsLeft, 1)
        XCTAssertEqual(progress.line, "1 more session to \(PetItem.accessory(.beanie).displayName)")
    }

    func testASessionThatMakesAnItemAffordableFillsTheBarRatherThanJumpingAhead() throws {
        let progress = try XCTUnwrap(UnlockProgress(balance: 40, earned: 35, ledger: PetPointsLedger()))
        XCTAssertEqual(progress.item, .accessory(.beanie))
        XCTAssertTrue(progress.isReady)
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.sessionsLeft, 0)
        XCTAssertTrue(progress.line.hasPrefix("Enough for"))
    }

    func testOwnedAndAlreadyAffordableItemsAreSkipped() throws {
        let ledger = PetPointsLedger(earned: 35, spent: 35, purchased: [.accessory(.beanie)])
        // 60 points before the session: the glasses (50) were already
        // affordable, so the goal is the headband (65).
        let progress = try XCTUnwrap(UnlockProgress(balance: 64, earned: 4, ledger: ledger))
        XCTAssertEqual(progress.item, .accessory(.ninjaHeadband))
        XCTAssertEqual(progress.missing, 1)
    }

    func testSessionsLeftUseThePaceOfTheSessionJustDone() throws {
        let ledger = PetPointsLedger()
        let short = try XCTUnwrap(UnlockProgress(balance: 0, ledger: ledger, pointsPerSession: 15))
        XCTAssertEqual(short.sessionsLeft, 3)
        XCTAssertFalse(short.isNear)
        XCTAssertEqual(short.line, "3 more sessions to \(PetItem.accessory(.beanie).displayName)")
        let typical = try XCTUnwrap(UnlockProgress(balance: 0, ledger: ledger, pointsPerSession: 0))
        XCTAssertEqual(typical.pointsPerSession, PetEconomy.pointsPerTypicalBlock)
        XCTAssertEqual(typical.sessionsLeft, 1)
        XCTAssertTrue(typical.isNear)
    }

    func testNothingLeftToUnlockGivesNoProgress() {
        let everything = Set(PetItem.shopItems)
        XCTAssertNil(UnlockProgress(balance: 0, ledger: PetPointsLedger(purchased: everything)))
    }
}
