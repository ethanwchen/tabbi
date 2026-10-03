import XCTest
@testable import NotchKitCore

final class ModuleIDTests: XCTestCase {
    func testCodesAsABareString() throws {
        let data = try JSONEncoder().encode([ModuleID.planner, "anki"])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["planner","anki"]"#)
        XCTAssertEqual(try JSONDecoder().decode([ModuleID].self, from: data), [.planner, ModuleID("anki")])
    }
}

final class ModuleCatalogTests: XCTestCase {
    private let accent = ModuleAccent(red: 0, green: 0, blue: 0)

    func testUnknownIdsGetANeutralPlaceholder() {
        let catalog = ModuleCatalog([
            ModuleDescriptor(id: "study", title: "Study", symbol: "book", category: .study, accent: accent),
        ])
        let unknown = catalog.descriptor(for: "leetcode")
        XCTAssertFalse(catalog.contains("leetcode"))
        XCTAssertEqual(unknown.title, "leetcode")
        XCTAssertEqual(unknown.symbol, "square.dashed")
    }

    func testFirstDescriptorWinsOnDuplicateIds() {
        let catalog = ModuleCatalog([
            ModuleDescriptor(id: "a", title: "First", symbol: "1.circle", category: .study, accent: accent),
            ModuleDescriptor(id: "b", title: "B", symbol: "2.circle", category: .fun, accent: accent),
            ModuleDescriptor(id: "a", title: "Second", symbol: "3.circle", category: .media, accent: accent),
        ])
        XCTAssertEqual(catalog.ids, ["a", "b"])
        XCTAssertEqual(catalog.duplicateIDs, ["a"])
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

    func testCatalogOnlyLayoutTurnsEveryModuleOnInCatalogOrder() {
        let catalog = ModuleCatalog([
            ModuleDescriptor(id: "study", title: "Study", symbol: "book", category: .study, accent: accent),
            ModuleDescriptor(id: "anki", title: "Anki", symbol: "rectangle.stack", category: .study, accent: accent),
        ])
        let layout = ModuleLayout(catalog: catalog)
        XCTAssertEqual(layout.order, ["study", "anki"])
        XCTAssertEqual(layout.enabled, ["study", "anki"])
    }

    func testFocusClockOwnerIsTheFirstEnabledModuleWithItsOwnClock() {
        let catalog = ModuleCatalog([
            ModuleDescriptor(id: "today", title: "Today", symbol: "checklist", category: .productivity, accent: accent),
            ModuleDescriptor(id: "study", title: "Study", symbol: "timer", category: .study, accent: accent,
                             ownsFocusClock: true),
            ModuleDescriptor(id: "drill", title: "Drill", symbol: "bolt", category: .study, accent: accent,
                             ownsFocusClock: true),
        ])
        var layout = ModuleLayout(order: ["today", "drill", "study"], disabled: [], catalog: catalog)
        XCTAssertEqual(catalog.focusClockOwner(in: layout), "drill")
        XCTAssertTrue(layout.setEnabled("drill", false))
        XCTAssertEqual(catalog.focusClockOwner(in: layout), "study")
        XCTAssertTrue(layout.setEnabled("study", false))
        XCTAssertNil(catalog.focusClockOwner(in: layout), "with no such module on, the shared Pomodoro is the timer")
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
