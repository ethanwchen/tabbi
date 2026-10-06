import XCTest
import TabbiKitCore

final class ClaudeAskPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "ClaudeAskPreferencesTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - When the large view opens

    func testAskEachTimeExpandsOnlyOnCommandReturn() {
        let mode = ClaudeAskLargeView.askEachTime
        XCTAssertFalse(mode.opensLarge(commandReturn: false))
        XCTAssertTrue(mode.opensLarge(commandReturn: true))
        XCTAssertTrue(mode.offersExpand)
    }

    func testAlwaysExpandsOnEverySend() {
        let mode = ClaudeAskLargeView.always
        XCTAssertTrue(mode.opensLarge(commandReturn: false))
        XCTAssertTrue(mode.opensLarge(commandReturn: true))
        XCTAssertTrue(mode.offersExpand, "The user can still collapse and expand again")
    }

    func testNeverStaysInTheNotchAndHidesExpand() {
        let mode = ClaudeAskLargeView.never
        XCTAssertFalse(mode.opensLarge(commandReturn: false))
        XCTAssertFalse(mode.opensLarge(commandReturn: true))
        XCTAssertFalse(mode.offersExpand)
    }

    func testSettingsListsTheThreeChoicesInOrder() {
        XCTAssertEqual(ClaudeAskLargeView.allCases.map(\.title), ["Ask each time", "Always", "Never"])
    }

    // MARK: - Storage

    func testDefaultsToAskEachTimeWhenNothingIsSaved() {
        XCTAssertEqual(ClaudeAskPreferencesStorage(defaults: defaults).load(), ClaudeAskPreferences())
        XCTAssertEqual(ClaudeAskPreferences().largeView, .askEachTime)
    }

    func testSavedChoiceSurvivesARelaunch() {
        ClaudeAskPreferencesStorage(defaults: defaults).save(ClaudeAskPreferences(largeView: .always))
        XCTAssertEqual(ClaudeAskPreferencesStorage(defaults: defaults).load().largeView, .always)
    }

    func testSavedDocumentIsVersioned() throws {
        ClaudeAskPreferencesStorage(defaults: defaults).save(ClaudeAskPreferences(largeView: .never))
        let data = try XCTUnwrap(defaults.data(forKey: ClaudeAskPreferencesStorage.key))
        XCTAssertEqual(VersionedJSON.version(of: data), ClaudeAskPreferencesStorage.schema.current)
    }

    func testUnknownChoiceFromANewerBuildKeepsTheDefault() {
        defaults.set(Data(#"{"schemaVersion": 2, "largeView": "sometimes"}"#.utf8), forKey: ClaudeAskPreferencesStorage.key)
        XCTAssertEqual(ClaudeAskPreferencesStorage(defaults: defaults).load().largeView, .askEachTime)
    }

    func testUnreadableDocumentFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: ClaudeAskPreferencesStorage.key)
        XCTAssertEqual(ClaudeAskPreferencesStorage(defaults: defaults).load(), ClaudeAskPreferences())
    }
}
