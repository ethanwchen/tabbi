import XCTest
@testable import TabbiKitCore

/// The App Store build's sandbox entitlements grant exactly what its
/// features use (docs/appstore.md, What differs), and nothing App Review
/// would question without a feature behind it.
final class AppStoreEntitlementsTests: XCTestCase {
    private func entitlements() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("packaging/Tabbi-AppStore.entitlements")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testTheSandboxIsOnWithTheNetworkForPartyAndSync() throws {
        let plist = try entitlements()
        XCTAssertEqual(plist["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.network.client"] as? Bool, true, "Party, sync, AI and crash reports")
        XCTAssertNil(plist["com.apple.security.network.server"], "nothing listens for connections")
    }

    func testDoNotDisturbRunsShortcutsThroughShortcutsEventsWithoutAnException() throws {
        let targets = try XCTUnwrap(try entitlements()["com.apple.security.scripting-targets"] as? [String: [String]])
        XCTAssertEqual(targets, [ShortcutsEventsScript.bundleIdentifier: [ShortcutsEventsScript.accessGroup]])
    }

    func testAIUsageReadsOnlyFoldersTheUserPicks() throws {
        let plist = try entitlements()
        XCTAssertEqual(plist["com.apple.security.files.user-selected.read-only"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
        XCTAssertNil(plist["com.apple.security.files.user-selected.read-write"], "AI Usage never writes")
        let exceptions = plist.keys.filter { $0.contains("temporary-exception.files") }
        XCTAssertEqual(exceptions, [], "no folder is reachable without the user picking it")
    }

    func testAppleEventsReachOnlyTheMusicApps() throws {
        // SoundCloud in Safari or Chrome stays in the direct download: it
        // would need an exception to run JavaScript in the user's browser.
        let apps = try XCTUnwrap(try entitlements()["com.apple.security.temporary-exception.apple-events"] as? [String])
        XCTAssertEqual(Set(apps), ["com.spotify.client", "com.apple.Music"])
    }

    /// The privacy manifest declares what the App Privacy answer sheet in
    /// docs/appstore.md declares: Party's name, friend list, pet, reports and
    /// presence, the account's ids, and crash and hang reports without an id.
    func testThePrivacyManifestDeclaresPartyAndCrashReports() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("packaging/PrivacyInfo-AppStore.xcprivacy")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        let types = try XCTUnwrap(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        var linked: [String: Bool] = [:]
        for type in types {
            let name = try XCTUnwrap(type["NSPrivacyCollectedDataType"] as? String)
            linked[name.replacingOccurrences(of: "NSPrivacyCollectedDataType", with: "")] = type["NSPrivacyCollectedDataTypeLinked"] as? Bool
            XCTAssertEqual(type["NSPrivacyCollectedDataTypeTracking"] as? Bool, false, name)
            XCTAssertEqual(type["NSPrivacyCollectedDataTypePurposes"] as? [String],
                           ["NSPrivacyCollectedDataTypePurposeAppFunctionality"], name)
        }
        XCTAssertEqual(linked, ["UserID": true, "DeviceID": true, "OtherUserContent": true, "ProductInteraction": true,
                                "Name": true, "Contacts": true, "CrashData": false, "PerformanceData": false])
        let apis = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let timestamps = apis.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryFileTimestamp" }
        XCTAssertEqual(Set(timestamps?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []), ["C617.1", "3B52.1"],
                       "AI Usage reads timestamps in the folder the user picked")
    }
}
