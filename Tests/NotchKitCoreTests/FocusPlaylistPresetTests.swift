import XCTest
import NotchKitCore

final class FocusPlaylistPresetTests: XCTestCase {
    func testEveryPresetParsesAndIsUnique() {
        let presets = FocusPlaylistPreset.all
        XCTAssertFalse(presets.isEmpty)
        for preset in presets {
            XCTAssertNotNil(preset.playlist, "\(preset.name) has an unparseable link")
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertFalse(preset.curator.isEmpty)
        }
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
        XCTAssertEqual(Set(presets.compactMap(\.playlist).map(String.init(describing:))).count, presets.count)
    }

    func testPresetsCoverBothApps() {
        let sources = Set(FocusPlaylistPreset.all.map(\.source))
        XCTAssertEqual(sources, [.spotify, .music])
    }

    func testMatchingRecognizesAPresetHoweverItWasPasted() throws {
        let deepFocus = try XCTUnwrap(FocusPlaylistPreset.all.first { $0.name == "Deep Focus" })
        XCTAssertEqual(FocusPlaylistPreset.matching(deepFocus.link), deepFocus)
        XCTAssertEqual(FocusPlaylistPreset.matching(" spotify:playlist:37i9dQZF1DWZeKCadgRdKQ "), deepFocus)
        XCTAssertEqual(FocusPlaylistPreset.matching(deepFocus.link + "?si=abc"), deepFocus)

        let pureFocus = try XCTUnwrap(FocusPlaylistPreset.all.first { $0.name == "Pure Focus" })
        XCTAssertEqual(FocusPlaylistPreset.matching(pureFocus.link), pureFocus)
    }

    func testMatchingIgnoresOtherText() {
        XCTAssertNil(FocusPlaylistPreset.matching(""))
        XCTAssertNil(FocusPlaylistPreset.matching("Deep Focus"), "a library name is the user's own playlist")
        XCTAssertNil(FocusPlaylistPreset.matching("https://open.spotify.com/playlist/0000000000000000000000"))
    }

    func testMatchingUsesTheGivenList() {
        let custom = FocusPlaylistPreset(name: "Mine", curator: "Me", link: "spotify:album:4aawyAB9vmqN3uQ7FjRGTy")
        XCTAssertEqual(FocusPlaylistPreset.matching("https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy", in: [custom]),
                       custom)
    }
}
