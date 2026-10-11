import XCTest
import TabbiKitCore

final class SentencesTests: XCTestCase {
    func testSpacesLatinSentencesAndSkipsEmptyOnes() {
        XCTAssertEqual(Sentences.join(["Pay as you go.", "", "Your key stays in your Keychain."]),
                       "Pay as you go. Your key stays in your Keychain.")
        XCTAssertEqual(Sentences.join([" Kostenlos. ", "Sendet an Google."]), "Kostenlos. Sendet an Google.")
        XCTAssertEqual(Sentences.join([]), "")
    }

    func testAddsNoSpaceAfterAFullWidthStop() {
        XCTAssertEqual(Sentences.join(["無料で使えます。", "質問内容はGoogleに送信されます。"]),
                       "無料で使えます。質問内容はGoogleに送信されます。")
        XCTAssertEqual(Sentences.join(["免费使用。", "Sends to Google."]), "免费使用。Sends to Google.")
    }
}
