import XCTest
@testable import TabbiKitCore

final class InstallHygieneTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/sam", isDirectory: true)

    private func location(_ path: String) -> InstallLocation {
        InstallLocation(bundleURL: URL(fileURLWithPath: path, isDirectory: true), home: home)
    }

    // MARK: Location

    func testClassifiesWhereTheAppRunsFrom() {
        XCTAssertEqual(location("/Applications/Tabbi.app"), .applications)
        XCTAssertEqual(location("/Applications/Utilities/Tabbi.app"), .applications)
        XCTAssertEqual(location("/Users/sam/Applications/Tabbi.app"), .userApplications)
        XCTAssertEqual(location("/Volumes/Tabbi/Tabbi.app"), .diskImage)
        XCTAssertEqual(location("/Users/sam/Downloads/Tabbi.app"), .downloads)
        XCTAssertEqual(location("/Users/sam/Desktop/Tabbi.app"), .elsewhere)
        XCTAssertEqual(location("/private/var/folders/xy/T/AppTranslocation/1A2B/d/Tabbi.app"), .translocated)
    }

    func testDevelopmentBuildsAreNeverMoved() {
        XCTAssertEqual(location("/Users/sam/code/Tabbi/build/debug/Tabbi.app"), .development)
        XCTAssertEqual(location("/Users/sam/code/Tabbi/.build/arm64-apple-macosx/debug"), .development)
        XCTAssertFalse(location("/Users/sam/code/Tabbi/build/release/Tabbi.app").shouldOfferMove)
    }

    func testAFolderNamedLikeApplicationsIsNotApplications() {
        XCTAssertEqual(location("/ApplicationsOld/Tabbi.app"), .elsewhere)
        XCTAssertEqual(location("/Users/sam/Downloads Archive/Tabbi.app"), .elsewhere)
    }

    func testOffersTheMoveOnlyOutsideApplications() {
        XCTAssertTrue(InstallLocation.translocated.shouldOfferMove)
        XCTAssertTrue(InstallLocation.diskImage.shouldOfferMove)
        XCTAssertTrue(InstallLocation.downloads.shouldOfferMove)
        XCTAssertTrue(InstallLocation.elsewhere.shouldOfferMove)
        XCTAssertFalse(InstallLocation.applications.shouldOfferMove)
        XCTAssertFalse(InstallLocation.userApplications.shouldOfferMove)
    }

    func testFindsTheDiskImageVolumeToEject() {
        XCTAssertEqual(InstallLocation.volume(of: URL(fileURLWithPath: "/Volumes/Tabbi 1.2/Tabbi.app"))?.path,
                       "/Volumes/Tabbi 1.2")
        XCTAssertNil(InstallLocation.volume(of: URL(fileURLWithPath: "/Users/sam/Downloads/Tabbi.app")))
        XCTAssertNil(InstallLocation.volume(of: URL(fileURLWithPath: "/Volumes")))
    }

    // MARK: Plan

    func testNewUserFromTheDiskImageIsOfferedTheMoveAndLoginWaits() {
        let plan = InstallHygienePlan(location: .diskImage, record: nil, runMode: .live, isReturningUser: false)
        XCTAssertTrue(plan.offerMove)
        XCTAssertFalse(plan.enableLaunchAtLogin, "a login item must not point into the disk image")
        XCTAssertEqual(plan.record, InstallRecord(), "the record is created so the moved copy knows it is new")
    }

    func testMovedCopyTurnsLaunchAtLoginOnOnce() {
        let afterMove = InstallHygienePlan(location: .applications, record: InstallRecord(),
                                           runMode: .live, isReturningUser: true)
        XCTAssertFalse(afterMove.offerMove)
        XCTAssertTrue(afterMove.enableLaunchAtLogin, "the record says new user, whatever onboarding did since")
        let saved = try? XCTUnwrap(afterMove.record)
        XCTAssertEqual(saved?.launchAtLoginDefaultApplied, true)

        let nextLaunch = InstallHygienePlan(location: .applications, record: saved,
                                            runMode: .live, isReturningUser: true)
        XCTAssertFalse(nextLaunch.enableLaunchAtLogin, "turning it off later must stick")
        XCTAssertNil(nextLaunch.record, "nothing new to save")
    }

    func testNewUserInstalledByDragTurnsLaunchAtLoginOn() {
        let plan = InstallHygienePlan(location: .userApplications, record: nil, runMode: .live, isReturningUser: false)
        XCTAssertTrue(plan.enableLaunchAtLogin)
        XCTAssertEqual(plan.record?.launchAtLoginDefaultApplied, true)
    }

    func testReturningUserKeepsTheirLoginItemChoice() {
        let plan = InstallHygienePlan(location: .applications, record: nil, runMode: .live, isReturningUser: true)
        XCTAssertFalse(plan.enableLaunchAtLogin)
        XCTAssertEqual(plan.record?.launchAtLoginDefaultApplied, true)
    }

    func testDontAskAgainStopsTheMoveOffer() {
        let plan = InstallHygienePlan(location: .downloads, record: InstallRecord(neverOfferMove: true),
                                      runMode: .live, isReturningUser: false)
        XCTAssertFalse(plan.offerMove)
    }

    func testDemoAndSnapshotRunsLeaveTheSystemAlone() {
        for mode in [RunMode.demo, RunMode(isSnapshot: true)] {
            let plan = InstallHygienePlan(location: .applications, record: nil, runMode: mode, isReturningUser: false)
            XCTAssertFalse(plan.offerMove)
            XCTAssertFalse(plan.enableLaunchAtLogin)
            XCTAssertNil(plan.record)
        }
    }

    func testDestinationPrefersTheSystemApplicationsFolder() {
        XCTAssertEqual(InstallHygienePlan.destinationFolder(home: home, systemApplicationsIsWritable: true).path,
                       "/Applications")
        XCTAssertEqual(InstallHygienePlan.destinationFolder(home: home, systemApplicationsIsWritable: false).path,
                       "/Users/sam/Applications")
    }

    // MARK: Record

    func testRecordRoundTripsThroughVersionedDefaults() throws {
        let defaults = try XCTUnwrap(MemoryDefaults(suiteName: nil))

        XCTAssertNil(InstallRecord.load(from: defaults))
        let record = InstallRecord(neverOfferMove: true, launchAtLoginDefaultApplied: true)
        record.save(to: defaults)
        XCTAssertEqual(InstallRecord.load(from: defaults), record)
        let data = try XCTUnwrap(defaults.data(forKey: InstallRecord.defaultsKey))
        XCTAssertEqual(VersionedJSON.version(of: data), InstallRecord.schema.current)
    }

    func testRecordMissingKeysFallsBackToDefaults() throws {
        let data = Data(#"{"schemaVersion":1}"#.utf8)
        XCTAssertEqual(try InstallRecord.schema.decode(InstallRecord.self, from: data), InstallRecord())
    }
}

/// Defaults kept in memory: a real suite leaves a plist in ~/Library/Preferences
/// on every run, even after its domain is removed.
private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}
