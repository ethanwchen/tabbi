import XCTest
import TabbiKitCore

final class FeedbackLinkTests: XCTestCase {
    private func query(of url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testLinkCarriesExactlyVersionSystemAndEdition() {
        let environment = DiagnosticEnvironment(appVersion: "1.4.0 (52)", systemVersion: "15.1.0", edition: "tabbi")
        let url = FeedbackLink.url(for: environment)

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "tabbinotch.com")
        XCTAssertEqual(url.path, "/suggest")
        XCTAssertEqual(query(of: url), ["version": "1.4.0 (52)", "macos": "15.1.0", "edition": "tabbi"])
    }

    func testAppVersionComesFromTheBundle() {
        XCTAssertEqual(DiagnosticEnvironment.appVersion(infoDictionary: [
            "CFBundleShortVersionString": "1.4.0", "CFBundleVersion": "52",
        ]), "1.4.0 (52)")
        XCTAssertEqual(DiagnosticEnvironment.appVersion(infoDictionary: ["CFBundleShortVersionString": "1.4.0"]), "1.4.0")
        XCTAssertEqual(DiagnosticEnvironment.appVersion(infoDictionary: [
            "CFBundleShortVersionString": "1.4.0", "CFBundleVersion": "1.4.0",
        ]), "1.4.0")
        XCTAssertEqual(DiagnosticEnvironment.appVersion(infoDictionary: nil), "development")
    }

    func testSystemVersionComesFromItsNumbers() {
        let environment = DiagnosticEnvironment(
            infoDictionary: nil,
            system: OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 1),
            edition: "appstore"
        )
        XCTAssertEqual(environment, DiagnosticEnvironment(appVersion: "development", systemVersion: "14.6.1", edition: "appstore"))
    }

    func testOddValuesAreCleanedAndCapped() {
        let environment = DiagnosticEnvironment(
            appVersion: "1.0&name=Jane Doe\n<script>",
            systemVersion: String(repeating: "9", count: 100),
            edition: "\u{1F431}"
        )
        XCTAssertEqual(environment.appVersion, "1.0nameJane Doescript")
        XCTAssertEqual(environment.systemVersion.count, DiagnosticEnvironment.maxFieldLength)
        XCTAssertEqual(environment.edition, "unknown")

        let url = FeedbackLink.url(for: environment)
        XCTAssertEqual(Set(query(of: url).keys), ["version", "macos", "edition"])
    }
}
