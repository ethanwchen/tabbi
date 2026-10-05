import XCTest
import TabbiKitCore
@testable import Tabbi

/// Onboarding's study method step is drawn by the Study module, the one
/// that declares it, and only while the Study tab is on.
@MainActor
final class StudyMethodSetupTests: XCTestCase {
    func testStudyDrawsOnboardingsMethodStep() throws {
        let types: [any NotchModule.Type] = [StudyModule.self, ClosetModule.self]
        let services = AppServices(settings: SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types)),
                                   moduleTypes: types, environment: ["TABBI_DEMO": "1"], arguments: [])
        XCTAssertNotNil(services.modules.setupView(for: .studyMethod, modules: [.closet, .study]) {})
        XCTAssertNil(services.modules.setupView(for: .studyMethod, modules: [.closet]) {}, "the Study tab is off")
        XCTAssertNil(try XCTUnwrap(services.modules.module(StudyModule.self)).makeSetupView(for: .pet) {})
    }
}
