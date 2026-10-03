import XCTest
import TabbiKitCore

final class ClaudeExecutableResolverTests: XCTestCase {
    /// Mutable test state shared with the resolver's `@Sendable` closures.
    private final class Fixture: @unchecked Sendable {
        var override: String?
        var installed: Set<String> = ["/auto/claude"]
        var lookups: [String?] = []

        func locate(_ override: String?) -> URL? {
            lookups.append(override)
            if let override, installed.contains(override) { return URL(fileURLWithPath: override) }
            return installed.contains("/auto/claude") ? URL(fileURLWithPath: "/auto/claude") : nil
        }

        func makeResolver() -> ClaudeExecutableResolver {
            ClaudeExecutableResolver(
                locate: { self.locate($0) },
                currentOverride: { self.override },
                isExecutable: { self.installed.contains($0) }
            )
        }
    }

    func testReusesTheLocatedBinaryWhileTheOverrideIsUnchanged() {
        let fixture = Fixture()
        let resolver = fixture.makeResolver()
        XCTAssertEqual(resolver.resolve()?.path, "/auto/claude")
        XCTAssertEqual(resolver.resolve()?.path, "/auto/claude")
        XCTAssertEqual(fixture.lookups.count, 1)
    }

    func testANewOverrideTakesEffectOnTheNextResolve() {
        let fixture = Fixture()
        fixture.installed.insert("/custom/claude")
        let resolver = fixture.makeResolver()
        XCTAssertEqual(resolver.resolve()?.path, "/auto/claude")

        fixture.override = "/custom/claude"
        XCTAssertEqual(resolver.resolve()?.path, "/custom/claude")

        fixture.override = nil
        XCTAssertEqual(resolver.resolve()?.path, "/auto/claude")
        XCTAssertEqual(fixture.lookups, [nil, "/custom/claude", nil])
    }

    func testLocatesAgainWhenTheCachedBinaryDisappears() {
        let fixture = Fixture()
        fixture.installed.insert("/custom/claude")
        fixture.override = "/custom/claude"
        let resolver = fixture.makeResolver()
        XCTAssertEqual(resolver.resolve()?.path, "/custom/claude")

        fixture.installed.remove("/custom/claude")
        XCTAssertEqual(resolver.resolve()?.path, "/auto/claude")
    }

    func testMissesAreNotCachedSoALaterInstallIsFound() {
        let fixture = Fixture()
        fixture.installed = []
        let resolver = fixture.makeResolver()
        XCTAssertNil(resolver.resolve())

        fixture.installed = ["/auto/claude"]
        XCTAssertEqual(resolver.resolve()?.path, "/auto/claude")
    }
}
