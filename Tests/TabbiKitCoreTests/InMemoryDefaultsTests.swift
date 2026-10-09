import XCTest
@testable import TabbiKitCore

final class InMemoryDefaultsTests: XCTestCase {
    func testTypedValuesRoundTrip() {
        let defaults = InMemoryDefaults()
        defaults.set(true, forKey: "bool")
        defaults.set(3, forKey: "int")
        defaults.set(2.5, forKey: "double")
        defaults.set("kit", forKey: "string")
        defaults.set(["a", "b"], forKey: "strings")
        defaults.set(["a": ["b"]], forKey: "dictionary")
        defaults.set(Data([1, 2]), forKey: "data")

        XCTAssertTrue(defaults.bool(forKey: "bool"))
        XCTAssertEqual(defaults.object(forKey: "bool") as? Bool, true)
        XCTAssertEqual(defaults.integer(forKey: "int"), 3)
        XCTAssertEqual(defaults.double(forKey: "double"), 2.5)
        XCTAssertEqual(defaults.string(forKey: "string"), "kit")
        XCTAssertEqual(defaults.stringArray(forKey: "strings"), ["a", "b"])
        XCTAssertEqual(defaults.dictionary(forKey: "dictionary") as? [String: [String]], ["a": ["b"]])
        XCTAssertEqual(defaults.data(forKey: "data"), Data([1, 2]))

        defaults.removeObject(forKey: "string")
        XCTAssertNil(defaults.string(forKey: "string"))
        XCTAssertFalse(defaults.bool(forKey: "missing"))
    }

    /// Two instances never see each other's values, unlike two opens of
    /// one named suite.
    func testInstancesAreIndependent() {
        let first = InMemoryDefaults()
        first.set("medicine", forKey: "settings.kit")
        XCTAssertNil(InMemoryDefaults().string(forKey: "settings.kit"))
    }

    /// Settings saved and loaded through the repository survive in memory.
    func testSettingsRepositoryRoundTrips() {
        let defaults = InMemoryDefaults()
        let catalog = ModuleCatalog([
            ModuleDescriptor(id: "a", title: "A", symbol: "a.circle", category: .fun,
                             accent: ModuleAccent(red: 1, green: 0, blue: 0)),
        ])
        let repository = SettingsRepository(defaults: defaults, catalog: catalog)
        var settings = repository.load()
        settings.displayName = "Sam"
        settings.openOnHover = !settings.openOnHover
        repository.save(settings)
        XCTAssertEqual(repository.load().displayName, "Sam")
        XCTAssertEqual(repository.load().openOnHover, settings.openOnHover)
    }
}
