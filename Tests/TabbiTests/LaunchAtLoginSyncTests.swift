import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The "Launch at login" toggle follows the system's login item, which the
/// user can remove or approve in System Settings while Tabbi runs.
@MainActor
final class LaunchAtLoginSyncTests: XCTestCase {
    /// A login item the test changes the way System Settings would.
    private final class FakeLoginItem {
        var status: LaunchAtLogin.Status = .off

        var item: LaunchAtLogin {
            LaunchAtLogin(isAvailable: true, status: { self.status },
                          register: { self.status = .needsApproval },
                          unregister: { self.status = .off })
        }
    }

    private func makeSettings(_ login: FakeLoginItem) -> SettingsStore {
        SettingsStore(catalog: ModuleList.catalog(of: [TodayModule.self]), defaults: InMemoryDefaults(),
                      kitStore: nil, loginItem: login.item)
    }

    func testTurningOnShowsTheApprovalNoteUntilTheUserApproves() {
        let login = FakeLoginItem()
        let settings = makeSettings(login)
        settings.setLaunchAtLogin(true)
        XCTAssertTrue(settings.settings.launchAtLogin)
        XCTAssertTrue(settings.launchAtLoginNeedsApproval)

        login.status = .on // Approved in System Settings › Login Items.
        settings.refreshLaunchAtLogin()
        XCTAssertTrue(settings.settings.launchAtLogin)
        XCTAssertFalse(settings.launchAtLoginNeedsApproval)
    }

    func testRemovingTheItemInSystemSettingsTurnsTheToggleOff() {
        let login = FakeLoginItem()
        login.status = .on
        let settings = makeSettings(login)
        XCTAssertTrue(settings.settings.launchAtLogin)

        login.status = .off // Removed in System Settings › Login Items.
        settings.refreshLaunchAtLogin()
        XCTAssertFalse(settings.settings.launchAtLogin)
        XCTAssertFalse(settings.launchAtLoginNeedsApproval)
    }
}
