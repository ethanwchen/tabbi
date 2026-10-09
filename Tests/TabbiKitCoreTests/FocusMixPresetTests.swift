import XCTest
import TabbiKitCore

final class FocusMixPresetTests: XCTestCase {
    private let rainyCafe = FocusMix([.init(sound: .rain), .init(sound: .cafe, level: 0.4)])
    private let brown = FocusMix.single(.brown)

    func testSavingFillsOnlyAnEmptySlotWithANamedPreset() {
        var presets = FocusMixPresets()
        XCTAssertTrue(presets.save(rainyCafe, into: 1))
        XCTAssertEqual(presets.slots[1], FocusMixPreset(name: "Rain +1", mix: rainyCafe))
        XCTAssertNil(presets.slots[0])

        XCTAssertFalse(presets.save(brown, into: 1), "a taken slot is never overwritten")
        XCTAssertEqual(presets.slots[1]?.mix, rainyCafe)
        XCTAssertFalse(presets.save(.off, into: 0), "silence is not a preset")
        XCTAssertFalse(presets.save(brown, into: 3))
        XCTAssertEqual(presets.slots.count, FocusMixPresets.slotCount)
    }

    func testDefaultNameIsTheLoudestSoundAndHowManyJoinIt() {
        XCTAssertEqual(FocusMixPreset.defaultName(for: brown), "Brown noise")
        let blend = FocusMix([.init(sound: .rain, level: 0.3), .init(sound: .fireplace), .init(sound: .cafe, level: 0.5)])
        XCTAssertEqual(FocusMixPreset.defaultName(for: blend), "Fireplace +2")
    }

    func testRenameTrimsCutsAndFallsBackToTheDefaultName() {
        var presets = FocusMixPresets()
        presets.save(rainyCafe, into: 0)
        presets.rename(0, to: "  Cozy  ")
        XCTAssertEqual(presets.slots[0]?.name, "Cozy")
        presets.rename(0, to: "A really long preset name here")
        XCTAssertEqual(presets.slots[0]?.name.count, FocusMixPreset.maxNameLength)
        presets.rename(0, to: "   ")
        XCTAssertEqual(presets.slots[0]?.name, "Rain +1")
        presets.rename(2, to: "Nothing here")
        XCTAssertNil(presets.slots[2])
    }

    func testDeleteLeavesTheOtherSlotsInPlace() {
        var presets = FocusMixPresets()
        presets.save(rainyCafe, into: 0)
        presets.save(brown, into: 1)
        presets.delete(0)
        XCTAssertNil(presets.slots[0])
        XCTAssertEqual(presets.slots[1]?.mix, brown)
        XCTAssertEqual(presets.slot(matching: brown), 1)
        XCTAssertTrue(presets.save(rainyCafe, into: 0), "a freed slot takes a new blend")
    }

    func testMatchingFindsTheExactBlendOnly() {
        var presets = FocusMixPresets()
        presets.save(rainyCafe, into: 2)
        XCTAssertEqual(presets.slot(matching: rainyCafe), 2)
        var nudged = rainyCafe
        nudged.setLevel(0.5, for: .cafe)
        XCTAssertNil(presets.slot(matching: nudged))
        XCTAssertNil(presets.slot(matching: .off))
    }

    func testApplyingAPresetSetsTheMixAndKeepsEverythingElse() {
        var settings = FocusSettings(mix: brown, volume: 0.3, doNotDisturb: true)
        settings.presets.save(rainyCafe, into: 0)
        settings.apply(preset: 0)
        XCTAssertEqual(settings.mix, rainyCafe)
        XCTAssertEqual(settings.volume, 0.3)
        XCTAssertTrue(settings.doNotDisturb)
        settings.apply(preset: 1)
        XCTAssertEqual(settings.mix, rainyCafe, "an empty slot changes nothing")
    }

    func testPresetsRoundTripThroughSettingsAndSurviveKits() throws {
        var settings = FocusSettings(mix: brown)
        settings.presets.save(rainyCafe, into: 0)
        settings.presets.rename(0, to: "Cozy")
        let decoded = try JSONDecoder().decode(FocusSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.presets, settings.presets)

        let kit = KitDefaults(moduleSettings: ["focus": ["sounds": [["sound": "white"]]]])
        XCTAssertEqual(settings.applying(kit).presets, settings.presets)
    }

    func testSettingsSavedBeforePresetsLoadWithNone() throws {
        let old = try JSONDecoder().decode(FocusSettings.self, from: Data("""
        {"mix": {"layers": [{"sound": "rain", "level": 1}]}, "volume": 0.4}
        """.utf8))
        XCTAssertEqual(old.presets, .empty)
        XCTAssertEqual(old.mix, .single(.rain))
    }

    func testDecodingKeepsGoodSlotsWhenOthersAreBroken() throws {
        let presets = try JSONDecoder().decode(FocusMixPresets.self, from: Data("""
        {"slots": [null, {"name": "Rain", "mix": {"layers": [{"sound": "rain", "level": 1}]}},
                   {"name": "Bad"}, {"name": "Extra", "mix": {"layers": [{"sound": "pink", "level": 1}]}}]}
        """.utf8))
        XCTAssertEqual(presets.slots, [nil, FocusMixPreset(name: "Rain", mix: .single(.rain)), nil])

        let empty = try JSONDecoder().decode(FocusMixPresets.self, from: Data("""
        {"slots": [{"name": "Silence", "mix": {"layers": []}}]}
        """.utf8))
        XCTAssertTrue(empty.isEmpty, "an Off preset is dropped")
    }
}
