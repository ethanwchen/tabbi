import XCTest
import NotchKitCore

final class StudySoundChipTests: XCTestCase {
    private func selected(_ settings: FocusSettings) -> [StudySoundChip] {
        StudySoundChip.allCases.filter { $0.isSelected(in: settings) }
    }

    func testRowOffersOffFourSoundsMixAndPlaylist() {
        XCTAssertEqual(StudySoundChip.allCases.map(\.sound),
                       [nil, .brown, .rain, .fireplace, .cafe, nil, nil])
        XCTAssertEqual(StudySoundChip.allCases.filter(\.opensMixer), [.mix, .playlist])
    }

    func testOffIsSelectedForAnEmptyMix() {
        XCTAssertEqual(selected(FocusSettings()), [.off])
    }

    func testSingleSoundSelectsItsChipAtAnyLevel() {
        let settings = FocusSettings(mix: FocusMix([.init(sound: .rain, level: 0.3)]))
        XCTAssertEqual(selected(settings), [.rain])
    }

    func testBlendsAndSoundsWithoutAChipSelectMix() {
        XCTAssertEqual(selected(FocusSettings(mix: FocusMix([.init(sound: .rain), .init(sound: .cafe)]))), [.mix])
        XCTAssertEqual(selected(FocusSettings(mix: .single(.pink))), [.mix])
    }

    func testPlaylistIsSelectedAlongsideTheSound() {
        let settings = FocusSettings(mix: .single(.brown),
                                     playlistText: "https://open.spotify.com/playlist/0vvXsWCC9xrXsKd4FyS8kM")
        XCTAssertEqual(selected(settings), [.brown, .playlist])
        XCTAssertFalse(StudySoundChip.playlist.isSelected(in: FocusSettings(playlistText: "   ")))
    }

    func testSoundChipReplacesTheBlendAndKeepsTheRest() {
        let settings = FocusSettings(mix: FocusMix([.init(sound: .rain), .init(sound: .fireplace, level: 0.6)]),
                                     volume: 0.4, playlistText: "x", doNotDisturb: true)
        let next = StudySoundChip.cafe.applying(to: settings)
        XCTAssertEqual(next.mix, .single(.cafe))
        XCTAssertEqual(next.volume, 0.4)
        XCTAssertEqual(next.playlistText, "x")
        XCTAssertTrue(next.doNotDisturb)
        XCTAssertEqual(StudySoundChip.off.applying(to: settings).mix, .off)
    }

    func testMixerChipsLeaveSettingsAlone() {
        let settings = FocusSettings(mix: .single(.rain), playlistText: "x")
        XCTAssertEqual(StudySoundChip.mix.applying(to: settings), settings)
        XCTAssertEqual(StudySoundChip.playlist.applying(to: settings), settings)
    }

    func testLevelFromDragClampsToTheSlider() {
        XCTAssertEqual(StudySoundChip.level(atX: 50, width: 200), 0.25)
        XCTAssertEqual(StudySoundChip.level(atX: -10, width: 200), 0)
        XCTAssertEqual(StudySoundChip.level(atX: 400, width: 200), 1)
        XCTAssertEqual(StudySoundChip.level(atX: .nan, width: 200), 0)
        XCTAssertEqual(StudySoundChip.level(atX: 10, width: 0), 1)
    }
}
