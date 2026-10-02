import XCTest
@testable import NotchKitCore

final class KitManifestDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> KitManifest {
        try KitManifest.decode(from: Data(json.utf8))
    }

    func testMinimalKitFillsOptionalFieldsWithDefaults() throws {
        let kit = try decode(#"{"formatVersion": 1, "id": "tiny", "name": "Tiny", "modules": ["planner"]}"#)
        XCTAssertEqual(kit.moduleIDs, [.planner])
        XCTAssertEqual(kit.summary, "")
        XCTAssertEqual(kit.defaults, KitDefaults())
        XCTAssertTrue(kit.onboarding.isEmpty)
        XCTAssertTrue(kit.starterTasks.isEmpty)
    }

    func testModuleEntriesAcceptBareIdsAndObjects() throws {
        let kit = try decode(#"""
        {"formatVersion": 1, "id": "k", "name": "K",
         "modules": ["planner", {"id": "system", "enabled": false}, {"id": "spotify"}]}
        """#)
        XCTAssertEqual(kit.modules, [KitModuleEntry(.planner), KitModuleEntry(.system, enabled: false),
                                     KitModuleEntry(.spotify)])
    }

    func testRoundTripsThroughJSON() throws {
        let kit = KitManifest(
            id: "round-trip", name: "Round trip", summary: "s", symbol: "star",
            modules: [KitModuleEntry(.planner), KitModuleEntry("anki", enabled: false)],
            defaults: KitDefaults(studyMethods: ["pomodoro"], focusSounds: [KitFocusSound(sound: "rain", level: 0.5)],
                                  pet: KitPetDefaults(breed: "corgi", name: "Biscuit"),
                                  moduleSettings: ["anki": .object(["deck": .string("Step 1"), "goal": .number(200)])]),
            onboarding: [KitQuestion(id: "q", prompt: "?", options: [KitAnswer(id: "a", label: "A", enables: ["anki"])])],
            starterTasks: ["Read"]
        )
        let data = try JSONEncoder().encode(kit)
        XCTAssertEqual(try KitManifest.decode(from: data), kit)
    }

    func testEnabledEntriesEncodeAsBareIds() throws {
        let data = try JSONEncoder().encode([KitModuleEntry(.planner), KitModuleEntry(.system, enabled: false)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["planner",{"id":"system","enabled":false}]"#)
    }

    func testRejectsNewerFormat() {
        XCTAssertThrowsError(try decode(#"{"formatVersion": 2, "id": "k", "name": "K", "modules": ["planner"]}"#)) {
            XCTAssertEqual($0 as? KitError, .unsupportedVersion(2))
        }
    }

    func testRejectsBadIdsNamesAndEmptyModuleLists() {
        XCTAssertThrowsError(try decode(#"{"formatVersion": 1, "id": "My Kit", "name": "K", "modules": ["planner"]}"#)) {
            XCTAssertEqual($0 as? KitError, .invalidID("My Kit"))
        }
        XCTAssertThrowsError(try decode(#"{"formatVersion": 1, "id": "k", "name": "  ", "modules": ["planner"]}"#)) {
            XCTAssertEqual($0 as? KitError, .emptyName)
        }
        XCTAssertThrowsError(try decode(#"{"formatVersion": 1, "id": "k", "name": "K", "modules": []}"#)) {
            XCTAssertEqual($0 as? KitError, .noModules)
        }
    }

    func testMalformedFilesExplainWhatIsWrong() {
        XCTAssertThrowsError(try decode("not json")) {
            XCTAssertEqual($0 as? KitError, .malformed("not valid JSON"))
        }
        XCTAssertThrowsError(try decode(#"{"formatVersion": 1, "id": "k", "modules": ["planner"]}"#)) {
            XCTAssertEqual($0 as? KitError, .malformed("missing \"name\""))
        }
        XCTAssertThrowsError(try decode(#"{"formatVersion": 1, "id": "k", "name": "K", "modules": [3]}"#)) {
            XCTAssertEqual($0 as? KitError, .malformed("unexpected value at modules.[0]"))
        }
    }
}

final class KitDefaultsTests: XCTestCase {
    func testResolvedValuesDropUnknownIds() {
        let defaults = KitDefaults(
            studyMethods: ["pomodoro", "telepathy", "flowtime", "pomodoro"],
            focusSounds: [KitFocusSound(sound: "rain", level: 2), KitFocusSound(sound: "whale")],
            ticker: ["focus", "weather"],
            pet: KitPetDefaults(breed: "dragon")
        )
        XCTAssertEqual(defaults.resolvedStudyMethods, [.pomodoro, .flowtime])
        XCTAssertEqual(defaults.resolvedFocusMix, FocusMix([FocusMix.Layer(sound: .rain, level: 1)]))
        XCTAssertEqual(defaults.resolvedTicker, [.focus])
        XCTAssertNil(defaults.pet?.resolvedBreed)
    }

    func testStartingMethodFallsBackToFirstOffered() {
        XCTAssertEqual(KitDefaults(studyMethods: ["ultradian"]).resolvedStudyMethod, .ultradian)
        XCTAssertEqual(KitDefaults(studyMethods: ["ultradian"], studyMethod: "flowtime").resolvedStudyMethod, .flowtime)
        XCTAssertNil(KitDefaults().resolvedStudyMethod)
    }

    func testAbsentValuesMeanKeepTheAppDefault() {
        let defaults = KitDefaults()
        XCTAssertNil(defaults.resolvedStudyMethods)
        XCTAssertNil(defaults.resolvedFocusMix)
        XCTAssertNil(defaults.resolvedTicker)
    }

    func testModulesDecodeTheirOwnSettings() throws {
        struct AnkiSettings: Decodable, Equatable { var deck: String; var goal: Int }
        let json = #"{"moduleSettings": {"anki": {"deck": "Step 1", "goal": 200}}}"#
        let defaults = try JSONDecoder().decode(KitDefaults.self, from: Data(json.utf8))
        XCTAssertEqual(try defaults.settings(for: "anki")?.decode(AnkiSettings.self), AnkiSettings(deck: "Step 1", goal: 200))
        XCTAssertEqual(defaults.settings(for: "anki")?["deck"]?.stringValue, "Step 1")
        XCTAssertNil(defaults.settings(for: .planner))
    }

    func testKitValueKeepsJSONTypes() throws {
        let json = #"[null, true, 1.5, "x", [false], {"k": 2}]"#
        let value = try JSONDecoder().decode(KitValue.self, from: Data(json.utf8))
        XCTAssertEqual(value, .array([.null, .bool(true), .number(1.5), .string("x"), .array([.bool(false)]),
                                      .object(["k": .number(2)])]))
    }
}

final class KitApplicationTests: XCTestCase {
    private let kit = KitManifest(
        id: "test", name: "Test", summary: "", symbol: "star",
        modules: [KitModuleEntry(.planner), KitModuleEntry("leetcode"), KitModuleEntry(.spotify),
                  KitModuleEntry(.system, enabled: false)],
        onboarding: [
            KitQuestion(id: "music", prompt: "Music?", options: [
                KitAnswer(id: "yes", label: "Yes", tasks: ["Make a playlist"]),
                KitAnswer(id: "no", label: "No", disables: [.spotify]),
            ]),
            KitQuestion(id: "extras", prompt: "Extras?", allowsMultiple: true, options: [
                KitAnswer(id: "stats", label: "Stats", enables: [.system], tasks: ["Check CPU", " "]),
                KitAnswer(id: "claude", label: "Claude", enables: [.claudeAsk], tasks: ["Make a playlist"]),
            ]),
        ],
        starterTasks: ["Plan the day"]
    )

    func testLayoutFollowsKitOrderAndParksOtherModulesSwitchedOff() {
        let layout = kit.layout()
        XCTAssertEqual(layout.order, [.planner, .spotify, .system, .claudeUsage, .claudeAsk])
        XCTAssertEqual(layout.enabled, [.planner, .spotify])
    }

    func testAnswersSwitchModulesOnAndOff() {
        let layout = kit.layout(answers: ["music": ["no"], "extras": ["stats", "claude"]])
        XCTAssertEqual(layout.enabled, [.planner, .system, .claudeAsk])
    }

    func testSingleChoiceQuestionsUseOnlyTheFirstPickedAnswer() {
        XCTAssertEqual(kit.chosenAnswers(["music": ["yes", "no"]]).map(\.id), ["yes"])
    }

    func testStarterTasksMergeAnswersWithoutBlanksOrDuplicates() {
        XCTAssertEqual(kit.starterTasks(answers: ["music": ["yes"], "extras": ["stats", "claude"]]),
                       ["Plan the day", "Make a playlist", "Check CPU"])
    }

    func testLayoutUsesTheGivenCatalog() {
        let accent = ModuleAccent(red: 0, green: 0, blue: 0)
        let catalog = ModuleCatalog([
            ModuleDescriptor(id: "leetcode", title: "LeetCode", symbol: "chevron.left", category: .study, accent: accent),
            ModuleDescriptor(id: .planner, title: "Today", symbol: "checklist", category: .productivity, accent: accent),
        ])
        XCTAssertEqual(kit.layout(catalog: catalog).order, [.planner, "leetcode"])
    }

    func testIssuesListUnknownValuesOnce() {
        var kit = kit
        kit.modules.append(KitModuleEntry(.planner))
        kit.defaults = KitDefaults(studyMethods: ["pomodoro", "telepathy"], studyMethod: "telepathy",
                                   focusSounds: [KitFocusSound(sound: "whale")], ticker: ["weather"],
                                   pet: KitPetDefaults(breed: "dragon"))
        kit.onboarding.append(KitQuestion(id: "music", prompt: "Again?", options: [
            KitAnswer(id: "x", label: "X", enables: ["chess"]),
        ]))
        XCTAssertEqual(kit.issues(), [
            .unknownModule("leetcode"), .duplicateModule(.planner), .unknownModule("chess"),
            .unknownStudyMethod("telepathy"), .unknownFocusSound("whale"), .unknownTickerKind("weather"),
            .unknownPetBreed("dragon"), .duplicateQuestion("music"),
        ])
    }
}

final class KitLibraryTests: XCTestCase {
    func testEveryBundledKitLoads() throws {
        for id in KitLibrary.bundledIDs {
            let kit = try KitLibrary.loadBundled(id)
            XCTAssertEqual(kit.id, id)
            XCTAssertFalse(kit.summary.isEmpty, id)
        }
        XCTAssertEqual(KitLibrary.bundled.kits.map(\.id), KitLibrary.bundledIDs)
    }

    func testProductivityKitReproducesTheOriginalTabs() throws {
        let kit = try XCTUnwrap(KitLibrary.bundled[KitLibrary.defaultKitID])
        XCTAssertEqual(kit.layout(), ModuleLayout.default)
        XCTAssertEqual(kit.issues(), [])
        XCTAssertNil(kit.defaults.resolvedTicker, "Productivity keeps every preview kind on")
    }

    func testBundledKitsOnlyUseKnownValues() throws {
        // Modules that aren't built yet are the only allowed gap.
        let planned: Set<ModuleID> = ["study", "anki", "party", "closet"]
        for kit in KitLibrary.bundled.kits {
            let unexpected = kit.issues().filter {
                if case .unknownModule(let id) = $0 { return !planned.contains(id) }
                return true
            }
            XCTAssertEqual(unexpected, [], kit.id)
            XCTAssertNotNil(kit.defaults.resolvedFocusMix, kit.id)
        }
    }

    func testMedicineKitStartsOnTheStudyTimerWithAnkiFirstClassMethods() throws {
        let kit = try XCTUnwrap(KitLibrary.bundled["medicine"])
        XCTAssertEqual(kit.moduleIDs, ["study", .planner, "anki", "party", .spotify, .claudeAsk, "closet"])
        XCTAssertEqual(kit.defaults.resolvedStudyMethod, .pomodoro)
        XCTAssertEqual(kit.defaults.resolvedStudyMethods?.contains(.ankiSprint), true)
        XCTAssertEqual(kit.defaults.pet?.resolvedBreed, .orangeTabby)
        XCTAssertEqual(kit.starterTasks(answers: ["stage": ["preclinical"]]).first, "Clear today's Anki reviews")
    }

    func testMissingKitFallsBackToTheDefault() {
        let library = KitLibrary.bundled
        XCTAssertEqual(library.kit("removed")?.id, KitLibrary.defaultKitID)
        XCTAssertEqual(library.kit(nil)?.id, KitLibrary.defaultKitID)
        XCTAssertEqual(library.kit("student")?.id, "student")
    }

    func testUpsertReplacesInPlaceAndDropsDuplicateIds() {
        let one = KitManifest(id: "one", name: "One", summary: "", symbol: "1.circle", modules: [KitModuleEntry(.planner)])
        let two = KitManifest(id: "two", name: "Two", summary: "", symbol: "2.circle", modules: [KitModuleEntry(.system)])
        var library = KitLibrary([one, two, one])
        XCTAssertEqual(library.kits.map(\.id), ["one", "two"])
        var renamed = one
        renamed.name = "Uno"
        library.upsert(renamed)
        XCTAssertEqual(library.kits.map(\.name), ["Uno", "Two"])
    }

    func testImportsAKitFromAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"formatVersion": 1, "id": "shared", "name": "Shared", "modules": ["planner"]}"#.utf8).write(to: url)
        XCTAssertEqual(try KitLibrary.load(from: url).id, "shared")
        XCTAssertThrowsError(try KitLibrary.load(from: url.appendingPathExtension("missing")))
    }
}
