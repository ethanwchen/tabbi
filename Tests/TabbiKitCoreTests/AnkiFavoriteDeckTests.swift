import XCTest
import TabbiKitCore

final class AnkiFavoriteDeckTests: XCTestCase {
    private func deck(_ id: Int64, _ name: String, due: Int = 0) -> AnkiDeckStats {
        AnkiDeckStats(deckID: id, name: name, newCount: due, learnCount: 0, reviewCount: 0, totalInDeck: 100)
    }

    func testBlankNameIsNoFavorite() {
        XCTAssertNil(AnkiFavoriteDeck(name: "  "))
        XCTAssertNil(AnkiFavoriteDeck(name: "::"))
    }

    func testNameIsNormalized() {
        XCTAssertEqual(AnkiFavoriteDeck(name: " Step 1 :: Cardio ")?.name, "Step 1::Cardio")
        XCTAssertEqual(AnkiFavoriteDeck(deck(2, "Step 1:: Cardio")).name, "Step 1::Cardio")
    }

    func testResolvesByIDThroughARename() throws {
        let favorite = AnkiFavoriteDeck(deck(2, "Step 1::Cardio"))
        let decks = [deck(1, "Step 1"), deck(2, "Step 1::Heart", due: 7)]
        XCTAssertEqual(favorite.resolve(in: decks)?.name, "Step 1::Heart")
        XCTAssertTrue(favorite.matches(decks[1]))
        XCTAssertFalse(favorite.matches(deck(9, "Step 1::Cardio")))
        let updated = try XCTUnwrap(favorite.updated(from: decks))
        XCTAssertEqual(updated.name, "Step 1::Heart")
        XCTAssertEqual(updated.deckID, 2)
    }

    func testFallsBackToTheNameWhenTheIDIsGone() throws {
        let favorite = AnkiFavoriteDeck(deck(2, "Step 1::Cardio"))
        let decks = [deck(1, "Step 1"), deck(42, "Step 1::Cardio", due: 3)]
        XCTAssertEqual(favorite.resolve(in: decks)?.deckID, 42)
        XCTAssertEqual(favorite.updated(from: decks)?.deckID, 42)
    }

    func testNameOnlyFavoriteLearnsItsID() throws {
        let favorite = try XCTUnwrap(AnkiFavoriteDeck(name: "Pathoma"))
        XCTAssertTrue(favorite.matches(deck(5, "Pathoma")))
        XCTAssertEqual(favorite.updated(from: [deck(5, "Pathoma")])?.deckID, 5)
    }

    func testSubdeckIsNotConfusedWithItsParent() {
        let favorite = AnkiFavoriteDeck(deck(2, "Step 1::Cardio"))
        XCTAssertNil(favorite.resolve(in: [deck(1, "Step 1"), deck(3, "Cardio")]))
    }

    func testUnchangedOrMissingFavoriteNeedsNoUpdate() {
        let favorite = AnkiFavoriteDeck(deck(2, "Step 1::Cardio"))
        XCTAssertNil(favorite.updated(from: [deck(2, "Step 1::Cardio")]))
        XCTAssertNil(favorite.updated(from: []))
    }

    func testRoundTripsThroughItsSchema() throws {
        let favorite = AnkiFavoriteDeck(deck(2, "Step 1::Cardio"))
        let data = try XCTUnwrap(favorite.encoded())
        XCTAssertEqual(VersionedJSON.version(of: data), 1)
        XCTAssertEqual(AnkiFavoriteDeck(encoded: data), favorite)
    }

    func testRejectsMissingCorruptOrBlankData() {
        XCTAssertNil(AnkiFavoriteDeck(encoded: nil))
        XCTAssertNil(AnkiFavoriteDeck(encoded: Data("not json".utf8)))
        XCTAssertNil(AnkiFavoriteDeck(encoded: Data(#"{"schemaVersion":1,"name":"  "}"#.utf8)))
    }

    func testReadsANameOnlyDocument() {
        let data = Data(#"{"schemaVersion":1,"name":"Pathoma"}"#.utf8)
        XCTAssertEqual(AnkiFavoriteDeck(encoded: data), AnkiFavoriteDeck(name: "Pathoma"))
    }
}
