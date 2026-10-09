import XCTest
import TabbiKitCore

final class StudySoundLabelTests: XCTestCase {
    private let playlist = "https://open.spotify.com/playlist/0vvXsWCC9xrXsKd4FyS8kM"

    func testNothingPlayingReadsAsAQuietSoundButton() {
        let label = StudySoundLabel(FocusSettings())
        XCTAssertEqual(label.title, "Sound")
        XCTAssertEqual(label.symbolName, "speaker.slash")
        XCTAssertFalse(label.isOn)
        XCTAssertFalse(label.addsPlaylist)
        XCTAssertFalse(StudySoundLabel(FocusSettings(playlistText: "   ")).isOn)
    }

    func testASingleSoundShowsItsNameAndSymbolAtAnyLevel() {
        let label = StudySoundLabel(FocusSettings(mix: FocusMix([.init(sound: .rain, level: 0.3)])))
        XCTAssertEqual(label.title, "Rain")
        XCTAssertEqual(label.symbolName, FocusSound.rain.symbolName)
        XCTAssertTrue(label.isOn)
    }

    func testABlendCountsItsSounds() {
        let label = StudySoundLabel(FocusSettings(mix: FocusMix([.init(sound: .rain), .init(sound: .cafe)])))
        XCTAssertEqual(label.title, "2 sounds")
        XCTAssertTrue(label.isOn)
    }

    func testAPlaylistAloneOrBesideASound() {
        let alone = StudySoundLabel(FocusSettings(playlistText: playlist))
        XCTAssertEqual(alone.title, "Playlist")
        XCTAssertTrue(alone.isOn)
        XCTAssertFalse(alone.addsPlaylist)

        let beside = StudySoundLabel(FocusSettings(mix: .single(.brown), playlistText: playlist))
        XCTAssertEqual(beside.title, "Brown noise")
        XCTAssertTrue(beside.addsPlaylist)
    }

    func testHelpSaysWhatPlaysWithFocus() {
        XCTAssertEqual(StudySoundLabel.help(for: FocusSettings(), playlistName: nil),
                       "Pick a focus sound or a playlist")
        let settings = FocusSettings(mix: FocusMix([.init(sound: .rain), .init(sound: .fireplace)]),
                                     playlistText: playlist)
        XCTAssertEqual(StudySoundLabel.help(for: settings, playlistName: "Lofi Beats"),
                       "Plays Rain + Fireplace and Lofi Beats with focus. Click to change it")
        XCTAssertEqual(StudySoundLabel.help(for: FocusSettings(mix: .single(.cafe)), playlistName: nil),
                       "Plays Cafe murmur with focus. Click to change it")
    }

    func testLevelFromDragClampsToTheSlider() {
        XCTAssertEqual(StudySoundLabel.level(atX: 50, width: 200), 0.25)
        XCTAssertEqual(StudySoundLabel.level(atX: -10, width: 200), 0)
        XCTAssertEqual(StudySoundLabel.level(atX: 400, width: 200), 1)
        XCTAssertEqual(StudySoundLabel.level(atX: .nan, width: 200), 0)
        XCTAssertEqual(StudySoundLabel.level(atX: 10, width: 0), 1)
    }
}
