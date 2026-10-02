import XCTest
@testable import NotchKitCore

final class ModuleIDTests: XCTestCase {
    func testCodesAsABareString() throws {
        let data = try JSONEncoder().encode([ModuleID.planner, "anki"])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["planner","anki"]"#)
        XCTAssertEqual(try JSONDecoder().decode([ModuleID].self, from: data), [.planner, ModuleID("anki")])
    }

    func testKnownIdsReadTheirMetadataFromTheBuiltInCatalog() {
        XCTAssertEqual(ModuleID.planner.title, "Today")
        XCTAssertEqual(ModuleID.spotify.symbol, "music.note")
    }

    func testUnknownIdsGetANeutralPlaceholder() {
        let id = ModuleID("leetcode")
        XCTAssertEqual(id.title, "leetcode")
        XCTAssertEqual(id.symbol, "square.dashed")
        XCTAssertFalse(ModuleCatalog.builtIn.contains(id))
    }
}

final class ModuleCatalogTests: XCTestCase {
    private let accent = ModuleAccent(red: 0, green: 0, blue: 0)

    func testBuiltInKeepsTheShippedTabOrder() {
        XCTAssertEqual(ModuleCatalog.builtIn.ids, [.spotify, .system, .claudeUsage, .planner, .claudeAsk,
                                                   .study, .anki, .party, .closet])
    }

    func testBuiltInIdsAreUniqueAndDescribed() {
        let catalog = ModuleCatalog.builtIn
        XCTAssertEqual(Set(catalog.ids).count, catalog.descriptors.count)
        for descriptor in catalog.descriptors {
            XCTAssertFalse(descriptor.title.isEmpty)
            XCTAssertFalse(descriptor.symbol.isEmpty)
        }
    }

    func testClaudeModulesDeclareTheCLIRequirement() {
        XCTAssertTrue(ModuleCatalog.builtIn[.claudeAsk]?.permissions.contains(.claudeCLI) ?? false)
        XCTAssertTrue(ModuleCatalog.builtIn[.claudeUsage]?.permissions.contains(.claudeCLI) ?? false)
        XCTAssertEqual(ModuleCatalog.builtIn[.system]?.permissions, [])
    }

    func testFirstDescriptorWinsOnDuplicateIds() {
        let catalog = ModuleCatalog([
            ModuleDescriptor(id: "a", title: "First", symbol: "1.circle", category: .study, accent: accent),
            ModuleDescriptor(id: "b", title: "B", symbol: "2.circle", category: .fun, accent: accent),
            ModuleDescriptor(id: "a", title: "Second", symbol: "3.circle", category: .media, accent: accent),
        ])
        XCTAssertEqual(catalog.ids, ["a", "b"])
        XCTAssertEqual(catalog["a"]?.title, "First")
        XCTAssertNil(catalog["c"])
        XCTAssertEqual(catalog.descriptor(for: "c").title, "c")
    }

    func testLayoutNormalizesAgainstACustomCatalog() {
        let catalog = ModuleCatalog([
            ModuleDescriptor(id: "study", title: "Study", symbol: "book", category: .study, accent: accent),
            ModuleDescriptor(id: "anki", title: "Anki", symbol: "rectangle.stack", category: .study, accent: accent),
        ])
        let layout = ModuleLayout(order: ["anki", .spotify], disabled: [], catalog: catalog)
        XCTAssertEqual(layout.order, ["anki", "study"])
        XCTAssertEqual(layout.enabled, ["anki"])
    }
}

final class ClaudeCLITests: XCTestCase {
    func testOverrideWinsWhenExecutable() {
        let url = ClaudeCLI.locate(environment: [ClaudeCLI.overrideVariable: "/bin/sh"], loginShellLookup: { nil })
        XCTAssertEqual(url?.path, "/bin/sh")
    }

    func testNonExecutableOverrideFallsThroughToShellLookup() {
        let url = ClaudeCLI.locate(
            environment: [ClaudeCLI.overrideVariable: "/nonexistent/claude"],
            fileManager: EmptyFileManager(),
            loginShellLookup: { "/bin/sh" }
        )
        XCTAssertEqual(url?.path, "/bin/sh")
    }
}

/// Reports only real system binaries as executable, so home-dir candidates are skipped.
private final class EmptyFileManager: FileManager {
    override func isExecutableFile(atPath path: String) -> Bool {
        path.hasPrefix("/bin/") && super.isExecutableFile(atPath: path)
    }
}

final class ClaudeCLIPathOverrideTests: XCTestCase {
    func testSettingsOverrideBeatsEnvironmentOverride() {
        let url = ClaudeCLI.locate(
            pathOverride: "/bin/sh",
            environment: [ClaudeCLI.overrideVariable: "/bin/zsh"],
            loginShellLookup: { nil }
        )
        XCTAssertEqual(url?.path, "/bin/sh")
    }

    func testNonExecutableSettingsOverrideFallsBackToEnvironment() {
        let url = ClaudeCLI.locate(
            pathOverride: "/nonexistent/claude",
            environment: [ClaudeCLI.overrideVariable: "/bin/zsh"],
            loginShellLookup: { nil }
        )
        XCTAssertEqual(url?.path, "/bin/zsh")
    }

    func testUserPathOverrideIsTheDefault() {
        ClaudeCLI.userPathOverride = "/bin/sh"
        defer { ClaudeCLI.userPathOverride = nil }
        let url = ClaudeCLI.locate(environment: [ClaudeCLI.overrideVariable: "/bin/zsh"], loginShellLookup: { nil })
        XCTAssertEqual(url?.path, "/bin/sh")
    }
}
