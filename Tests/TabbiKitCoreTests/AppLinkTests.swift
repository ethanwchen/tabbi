import XCTest
import TabbiKitCore

final class AppLinkTests: XCTestCase {
    private func link(_ text: String) -> AppLink? {
        URL(string: text).flatMap(AppLink.init(url:))
    }

    func testOpensTheNotch() {
        XCTAssertEqual(link("tabbi://open"), .open)
        XCTAssertEqual(link("TABBI://Open/"), .open)
    }

    func testReadsInvites() {
        XCTAssertEqual(link("tabbi://add/k7qw-2mzd"), .invite(.addFriend(code: "K7QW2MZD")))
        XCTAssertEqual(link("tabbi://join/AB3CDE"), .invite(.joinParty(code: "AB3CDE")))
        XCTAssertEqual(link("https://tabbinotch.com/add/K7QW2MZD"), .invite(.addFriend(code: "K7QW2MZD")))
    }

    func testIgnoresEverythingElse() {
        XCTAssertNil(link("tabbi://open/settings"))
        XCTAssertNil(link("tabbi://settings"))
        XCTAssertNil(link("tabbi://add/NOTACODE0"))
        XCTAssertNil(link("tabbi:open"))
        XCTAssertNil(link("https://tabbinotch.com/open"))
        XCTAssertNil(link("notabbi://open"))
    }
}
