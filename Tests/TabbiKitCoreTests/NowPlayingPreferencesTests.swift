import XCTest
import TabbiKitCore

final class NowPlayingPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "NowPlayingPreferencesTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Followed players

    func testSoundCloudIsOffByDefault() {
        let sources = NowPlayingPreferences().followedSources(allowsBrowsers: true)
        XCTAssertEqual(sources, [.spotify, .music])
    }

    func testTurningSoundCloudOnFollowsBothBrowsersAfterTheApps() {
        let sources = NowPlayingPreferences(showsSoundCloud: true).followedSources(allowsBrowsers: true)
        XCTAssertEqual(sources, [.spotify, .music, .soundCloud(.safari), .soundCloud(.chrome)])
    }

    func testAnEditionThatCantScriptBrowsersNeverFollowsSoundCloud() {
        let sources = NowPlayingPreferences(showsSoundCloud: true).followedSources(allowsBrowsers: false)
        XCTAssertEqual(sources, [.spotify, .music])
    }

    // MARK: - Storage

    func testDefaultsWhenNothingIsSaved() {
        XCTAssertEqual(NowPlayingPreferencesStorage(defaults: defaults).load(), NowPlayingPreferences())
    }

    func testSavedChoiceSurvivesARelaunch() {
        NowPlayingPreferencesStorage(defaults: defaults).save(NowPlayingPreferences(showsSoundCloud: true))
        XCTAssertTrue(NowPlayingPreferencesStorage(defaults: defaults).load().showsSoundCloud)
    }

    func testSavedDocumentIsVersioned() throws {
        NowPlayingPreferencesStorage(defaults: defaults).save(NowPlayingPreferences(showsSoundCloud: true))
        let data = try XCTUnwrap(defaults.data(forKey: NowPlayingPreferencesStorage.key))
        XCTAssertEqual(VersionedJSON.version(of: data), NowPlayingPreferencesStorage.schema.current)
    }

    func testUnreadableValueKeepsTheDefault() throws {
        let data = try NowPlayingPreferencesStorage.schema.encode(["showsSoundCloud": "sometimes"])
        defaults.set(data, forKey: NowPlayingPreferencesStorage.key)
        XCTAssertFalse(NowPlayingPreferencesStorage(defaults: defaults).load().showsSoundCloud)
    }
}
