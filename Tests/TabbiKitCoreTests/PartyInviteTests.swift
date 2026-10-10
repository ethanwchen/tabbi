import XCTest
import TabbiKitCore

final class PartyInviteTests: XCTestCase {
    private func invite(_ text: String) -> PartyInvite? {
        URL(string: text).flatMap(PartyInvite.init(url:))
    }

    func testParsesAppLinks() {
        XCTAssertEqual(invite("tabbi://add/K7QW2MZD"), .addFriend(code: "K7QW2MZD"))
        XCTAssertEqual(invite("tabbi://join/AB3CDE"), .joinParty(code: "AB3CDE"))
        XCTAssertEqual(invite("tabbi://add/K7QW2MZD/"), .addFriend(code: "K7QW2MZD"))
    }

    func testParsesWebLinks() {
        XCTAssertEqual(invite("https://tabbinotch.com/add/K7QW2MZD"), .addFriend(code: "K7QW2MZD"))
        XCTAssertEqual(invite("https://www.tabbinotch.com/join/AB3CDE/"), .joinParty(code: "AB3CDE"))
        XCTAssertEqual(invite("https://TabbiNotch.com/ADD/K7QW2MZD?utm=x#top"), .addFriend(code: "K7QW2MZD"))
    }

    func testNormalizesHandTypedCodes() {
        XCTAssertEqual(invite("tabbi://add/k7qw-2mzd"), .addFriend(code: "K7QW2MZD"))
        XCTAssertEqual(invite("TABBI://JOIN/ab3-cde"), .joinParty(code: "AB3CDE"))
    }

    func testRejectsInvalidCodes() {
        XCTAssertNil(invite("tabbi://add/AB3CDE"), "a party code is too short for a friend")
        XCTAssertNil(invite("tabbi://join/K7QW2MZD"), "a friend code is too long for a party")
        XCTAssertNil(invite("tabbi://add/K7QW2MZ0"), "0 is not in the code alphabet")
        XCTAssertNil(invite("tabbi://add/K7QW%202MZD"), "percent-encoded codes are not handed out")
        XCTAssertNil(invite("tabbi://add/"))
        XCTAssertNil(invite("tabbi://add/K7QW2MZD/extra"))
    }

    func testRejectsOtherHostsSchemesAndActions() {
        XCTAssertNil(invite("http://tabbinotch.com/add/K7QW2MZD"))
        XCTAssertNil(invite("https://tabbinotch.com.evil.example/add/K7QW2MZD"))
        XCTAssertNil(invite("https://evil.example/add/K7QW2MZD"))
        XCTAssertNil(invite("https://tabbinotch.com:8443/add/K7QW2MZD"))
        XCTAssertNil(invite("https://tabbinotch.com/add/K7QW2MZD/more"))
        XCTAssertNil(invite("tabbi://remove/K7QW2MZD"))
        XCTAssertNil(invite("tabbi://open"))
        XCTAssertNil(invite("notabbi://add/K7QW2MZD"))
    }

    func testBuildsLinksThatRoundTrip() {
        let friend = PartyInvite.addFriend(code: "K7QW2MZD")
        XCTAssertEqual(friend.webURL.absoluteString, "https://tabbinotch.com/add/K7QW2MZD")
        XCTAssertEqual(friend.appURL.absoluteString, "tabbi://add/K7QW2MZD")
        let party = PartyInvite.joinParty(code: "AB3CDE")
        XCTAssertEqual(party.webURL.absoluteString, "https://tabbinotch.com/join/AB3CDE")
        XCTAssertEqual(party.code, "AB3CDE")
        for invite in [friend, party] {
            XCTAssertEqual(PartyInvite(url: invite.webURL), invite)
            XCTAssertEqual(PartyInvite(url: invite.appURL), invite)
        }
    }
}
