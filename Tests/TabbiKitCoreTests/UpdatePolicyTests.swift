import XCTest
import TabbiKitCore

final class UpdatePolicyTests: XCTestCase {
    /// A real Ed25519 public key's shape: 32 bytes, base64.
    private let key = Data(repeating: 7, count: 32).base64EncodedString()
    private let feed = "https://github.com/ethanwchen/notchdeck/releases/latest/download/appcast.xml"

    private var releaseInfo: [String: Any] { ["SUFeedURL": feed, "SUPublicEDKey": key] }

    func testReleaseBuildsInstalledAnywhereWritableCheckForUpdates() {
        for location in [InstallLocation.applications, .userApplications, .downloads, .elsewhere, .development] {
            let policy = UpdatePolicy(info: releaseInfo, runMode: .live, location: location)
            XCTAssertEqual(policy, .active(UpdateFeed(info: releaseInfo)!), "\(location)")
            XCTAssertNil(policy.explanation(appName: "Tabbi"))
        }
        XCTAssertEqual(UpdateFeed(info: releaseInfo)?.url.absoluteString, feed)
        XCTAssertEqual(UpdateFeed(info: releaseInfo)?.publicKey, key)
    }

    func testDemoAndSnapshotRunsNeverCheckButLookLikeARelease() {
        for runMode in [RunMode.demo, RunMode(isSnapshot: true)] {
            let policy = UpdatePolicy(info: releaseInfo, runMode: runMode, location: .applications)
            XCTAssertEqual(policy, .off(.preview))
            XCTAssertFalse(policy.isActive)
            XCTAssertTrue(policy.isPreview)
            XCTAssertNil(policy.explanation(appName: "Tabbi"))
        }
        XCTAssertTrue(UpdatePolicy(info: [:], runMode: .demo, location: .development).isPreview)
    }

    func testDiskImagesAndTranslocatedCopiesCannotBeUpdatedInPlace() {
        for location in [InstallLocation.diskImage, .translocated] {
            let policy = UpdatePolicy(info: releaseInfo, runMode: .live, location: location)
            XCTAssertEqual(policy, .off(.notInstalled))
            XCTAssertEqual(policy.explanation(appName: "Tabbi"), "Move Tabbi to your Applications folder to get updates.")
        }
    }

    func testDevelopmentBuildsWithoutAFeedStayOff() {
        let policy = UpdatePolicy(info: [:], runMode: .live, location: .applications)
        XCTAssertEqual(policy, .off(.notConfigured))
        XCTAssertFalse(policy.isActive)
        XCTAssertNotNil(policy.explanation(appName: "Tabbi"))
    }

    func testAHalfConfiguredFeedTurnsUpdatesOff() {
        XCTAssertNil(UpdateFeed(info: ["SUFeedURL": feed]), "no key")
        XCTAssertNil(UpdateFeed(info: ["SUFeedURL": feed, "SUPublicEDKey": ""]), "empty key")
        XCTAssertNil(UpdateFeed(info: ["SUFeedURL": feed, "SUPublicEDKey": "not base64!"]), "garbage key")
        XCTAssertNil(UpdateFeed(info: ["SUFeedURL": feed, "SUPublicEDKey": Data(count: 16).base64EncodedString()]),
                     "wrong key length")
        XCTAssertNil(UpdateFeed(info: ["SUFeedURL": "http://example.com/appcast.xml", "SUPublicEDKey": key]),
                     "plain HTTP")
        XCTAssertNil(UpdateFeed(info: ["SUFeedURL": "", "SUPublicEDKey": key]), "empty URL")
        XCTAssertNil(UpdateFeed(info: ["SUPublicEDKey": key]), "no URL")
    }
}
