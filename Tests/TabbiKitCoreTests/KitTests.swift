import XCTest
@testable import TabbiKitCore

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
            id: "round-trip", name: "Round trip", summary: "s", symbol: "star", accent: .planner,
            modules: [KitModuleEntry(.planner), KitModuleEntry("anki", enabled: false)],
            defaults: KitDefaults(ticker: ["focus"], theme: "notch", moduleSettings: [
                "study": ["methods": ["pomodoro"]], "closet": ["pet": ["breed": "corgi", "name": "Biscuit"]],
                "anki": ["deck": "Step 1", "goal": 200],
            ]),
            onboarding: [KitQuestion(id: "q", prompt: "?", options: [KitAnswer(id: "a", label: "A", enables: ["anki"])])],
            starterTasks: ["Read"]
        )
        let data = try JSONEncoder().encode(kit)
        XCTAssertEqual(try KitManifest.decode(from: data), kit)
    }

    func testEnabledEntriesEncodeAsBareIds() throws {
        // Sorted keys: JSONEncoder's default key order isn't stable across runs.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode([KitModuleEntry(.planner), KitModuleEntry(.system, enabled: false)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["planner",{"enabled":false,"id":"system"}]"#)
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
    func testResolvedTickerDropsUnknownPreviews() {
        XCTAssertEqual(KitDefaults(ticker: ["focus", "weather"]).resolvedTicker, [.focus])
        XCTAssertNil(KitDefaults().resolvedTicker, "absent keeps the app default")
    }

    func testOldTopLevelFieldsMoveIntoTheirModuleSections() throws {
        let json = #"""
        {"studyMethods": ["flowtime"], "studyMethod": "flowtime", "focusSounds": [{"sound": "rain"}],
         "pet": {"breed": "corgi"}, "moduleSettings": {"study": {"dailyGoalMinutes": 60}}}
        """#
        let defaults = try JSONDecoder().decode(KitDefaults.self, from: Data(json.utf8))
        XCTAssertEqual(defaults.moduleSettings, [
            "study": ["methods": ["flowtime"], "method": "flowtime", "dailyGoalMinutes": 60],
            "focus": ["sounds": [["sound": "rain"]]],
            "closet": ["pet": ["breed": "corgi"]],
        ])
        XCTAssertEqual(defaults.legacyFields.map(\.name), ["studyMethods", "studyMethod", "focusSounds", "pet"])
    }

    func testANewModuleSectionKeyWinsOverItsOldName() throws {
        let json = #"{"studyMethod": "flowtime", "moduleSettings": {"study": {"method": "ultradian"}}}"#
        let defaults = try JSONDecoder().decode(KitDefaults.self, from: Data(json.utf8))
        XCTAssertEqual(defaults.settings(for: .study), ["method": "ultradian"])
        XCTAssertEqual(defaults.legacyFields.map(\.name), ["studyMethod"], "still reported, so the author can drop it")
    }

    func testEncodingWritesOnlyTheModuleSections() throws {
        let json = #"{"focusSounds": [{"sound": "rain", "level": 0.5}]}"#
        let defaults = try JSONDecoder().decode(KitDefaults.self, from: Data(json.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(defaults), as: UTF8.self),
                       #"{"moduleSettings":{"focus":{"sounds":[{"level":0.5,"sound":"rain"}]}}}"#)
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
        XCTAssertEqual(layout.order, [.planner, .spotify, .system, .claudeUsage, .claudeAsk,
                                      .focus, .study, .anki, .party, .closet])
        XCTAssertEqual(layout.enabled, [.planner, .spotify])
    }

    func testAnswersSwitchModulesOnAndOff() {
        let layout = kit.layout(answers: ["music": ["no"], "extras": ["stats", "claude"]])
        XCTAssertEqual(layout.enabled, [.planner, .system, .claudeAsk])
    }

    func testSingleChoiceQuestionsUseOnlyTheFirstPickedAnswer() {
        XCTAssertEqual(kit.chosenAnswers(["music": ["yes", "no"]]).map(\.id), ["yes"])
    }

    func testSelectingASingleChoiceAnswerReplacesThePick() throws {
        let music = try XCTUnwrap(kit.onboarding.first { $0.id == "music" })
        XCTAssertEqual(music.selecting("yes", in: []), ["yes"])
        XCTAssertEqual(music.selecting("no", in: ["yes"]), ["no"])
        XCTAssertEqual(music.selecting("no", in: ["no"]), [], "clicking the pick again skips the question")
        XCTAssertEqual(music.selecting("maybe", in: ["yes"]), ["yes"], "unknown answers are ignored")
    }

    func testSelectingAMultipleChoiceAnswerTogglesIt() throws {
        let extras = try XCTUnwrap(kit.onboarding.first { $0.id == "extras" })
        XCTAssertEqual(extras.selecting("claude", in: ["stats"]), ["stats", "claude"])
        XCTAssertEqual(extras.selecting("stats", in: ["stats", "claude"]), ["claude"])
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

    func testAccentFallsBackToTheFirstEnabledTab() {
        var kit = kit
        XCTAssertEqual(kit.accentModule(), .planner)
        kit.accent = .spotify
        XCTAssertEqual(kit.accentModule(), .spotify)
        kit.accent = "chess"
        XCTAssertEqual(kit.accentModule(), .planner)
        XCTAssertEqual(kit.issues(), [.unknownModule("leetcode"), .unknownModule("chess")])
    }

    func testIssuesListUnknownValuesOnce() {
        var kit = kit
        kit.modules.append(KitModuleEntry(.planner))
        kit.defaults = KitDefaults(ticker: ["weather"])
        kit.onboarding.append(KitQuestion(id: "music", prompt: "Again?", options: [
            KitAnswer(id: "x", label: "X", enables: ["chess"]),
        ]))
        XCTAssertEqual(kit.issues(), [
            .unknownModule("leetcode"), .duplicateModule(.planner), .unknownModule("chess"),
            .unknownTickerKind("weather"), .duplicateQuestion("music"),
        ])
    }
}

final class KitLibraryTests: XCTestCase {
    func testEveryBundledKitFileLoadsUnderItsOwnName() throws {
        let files = KitLibrary.bundledFileURLs
        XCTAssertFalse(files.isEmpty, "the Bundled folder ships with the core resources")
        for url in files {
            let kit = try KitLibrary.load(from: url)
            XCTAssertEqual(kit.id, url.deletingPathExtension().lastPathComponent, "loadBundled finds a kit by file name")
            XCTAssertFalse(kit.summary.isEmpty, kit.id)
            XCTAssertNotNil(kit.pickerOrder, "\(kit.id) needs a pickerOrder so the picker order is stable")
        }
        XCTAssertEqual(KitLibrary.bundled.kits.count, files.count, "no bundled file is skipped or shadowed")
    }

    func testBundledKitsAreInPickerOrder() {
        XCTAssertEqual(KitLibrary.bundledIDs, ["productivity", "medicine", "student"])
        XCTAssertEqual(KitLibrary.bundled.kits.first?.id, KitLibrary.defaultKitID)
        let orders = KitLibrary.bundled.kits.compactMap(\.pickerOrder)
        XCTAssertEqual(Set(orders).count, orders.count, "picker orders are distinct")
    }

    func testPickerOrderDecodesAndIsOptional() throws {
        let ordered = try KitManifest.decode(from: Data(#"{"formatVersion": 1, "id": "k", "name": "K", "pickerOrder": 4, "modules": ["planner"]}"#.utf8))
        XCTAssertEqual(ordered.pickerOrder, 4)
        XCTAssertEqual(ordered.unknownFields, [])
        let unordered = try KitManifest.decode(from: Data(#"{"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner"]}"#.utf8))
        XCTAssertNil(unordered.pickerOrder)
    }

    func testBundledKitsHaveDistinctAccents() {
        let accents = KitLibrary.bundled.kits.compactMap { $0.accentModule() }
        XCTAssertEqual(Set(accents).count, KitLibrary.bundledIDs.count)
    }

    func testProductivityKitReproducesTheOriginalTabs() throws {
        let kit = try XCTUnwrap(KitLibrary.bundled[KitLibrary.defaultKitID])
        XCTAssertEqual(kit.layout(), ModuleLayout.default)
        XCTAssertEqual(kit.issues(), [])
        XCTAssertNil(kit.defaults.resolvedTicker, "Productivity keeps every preview kind on")
        XCTAssertNil(FocusSettings.kitMix(of: kit.defaults), "Productivity keeps the user's focus sound (Off by default)")
    }

    func testBundledKitsOnlyUseKnownValues() throws {
        for kit in KitLibrary.bundled.kits {
            XCTAssertEqual(kit.issues(), [], kit.id)
        }
    }

    func testMedicineKitStartsOnTheStudyTimerWithAnkiFirstClassMethods() throws {
        let kit = try XCTUnwrap(KitLibrary.bundled["medicine"])
        XCTAssertEqual(kit.name, "Med School", "the kit keeps its saved id but shows its new name")
        XCTAssertEqual(kit.moduleIDs, ["study", .planner, "anki", "party", .spotify, .claudeAsk, "closet"])
        let menu = StudyMethodMenu(kit: kit.defaults)
        XCTAssertEqual(menu.startingKind, .pomodoro)
        XCTAssertTrue(menu.offers(.ankiSprint))
        XCTAssertEqual(PetProfile.starter(kit: kit.defaults).breed, .orangeTabby)
        XCTAssertEqual(kit.starterTasks(answers: ["stage": ["preclinical"]]).first, "Clear today's Anki reviews")
    }

    func testStudyKitsShowOnlyTheirOwnTabs() throws {
        let medicine = try XCTUnwrap(KitLibrary.bundled["medicine"])
        XCTAssertEqual(medicine.layout().enabled, [.study, .planner, .anki, .party, .spotify, .claudeAsk, .closet])
        XCTAssertEqual(medicine.layout(answers: ["anki": ["no"]]).enabled,
                       [.study, .planner, .party, .spotify, .claudeAsk, .closet])
        let student = try XCTUnwrap(KitLibrary.bundled["student"])
        XCTAssertEqual(student.layout().enabled, [.study, .planner, .spotify, .claudeAsk, .closet])
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

final class KitSafetyTests: XCTestCase {
    private func decode(_ json: String) throws -> KitManifest {
        try KitManifest.decode(from: Data(json.utf8))
    }

    private func kit(_ fields: String = "") -> String {
        #"{"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner"]\#(fields)}"#
    }

    private func assertRefused(_ json: String, _ expected: KitError, line: UInt = #line) {
        XCTAssertThrowsError(try decode(json), line: line) { XCTAssertEqual($0 as? KitError, expected, line: line) }
    }

    func testRefusesFormatVersionsBelowOne() {
        assertRefused(#"{"formatVersion": 0, "id": "k", "name": "K", "modules": ["planner"]}"#, .invalidFormatVersion(0))
        assertRefused(#"{"formatVersion": -3, "id": "k", "name": "K", "modules": ["planner"]}"#, .invalidFormatVersion(-3))
    }

    func testRefusesFilesOverTheSizeLimit() {
        let padding = String(repeating: " ", count: KitLimits.maxFileBytes)
        assertRefused(kit() + padding, .tooLarge)
    }

    func testRefusesKitsPastTheCaps() {
        let modules = (0...KitLimits.maxModules).map { #""m\#($0)""# }.joined(separator: ",")
        assertRefused(#"{"formatVersion": 1, "id": "k", "name": "K", "modules": [\#(modules)]}"#,
                      .exceedsLimit("more than 16 modules"))
        let tasks = (0...KitLimits.maxTasks).map { #""Task \#($0)""# }.joined(separator: ",")
        assertRefused(kit(#", "starterTasks": [\#(tasks)]"#), .exceedsLimit("more than 20 starter tasks"))
        let longName = String(repeating: "x", count: KitLimits.maxNameLength + 1)
        assertRefused(#"{"formatVersion": 1, "id": "k", "name": "\#(longName)", "modules": ["planner"]}"#,
                      .exceedsLimit("a name longer than 80 characters"))
        let longTask = String(repeating: "x", count: KitLimits.maxTaskLength + 1)
        assertRefused(kit(#", "onboarding": [{"id": "q", "prompt": "?", "options": [{"id": "a", "label": "A", "tasks": ["\#(longTask)"]}]}]"#),
                      .exceedsLimit("a task title longer than 120 characters"))
        let options = (0...KitLimits.maxOptions).map { #"{"id": "a\#($0)", "label": "A"}"# }.joined(separator: ",")
        assertRefused(kit(#", "onboarding": [{"id": "q", "prompt": "?", "options": [\#(options)]}]"#),
                      .exceedsLimit(#"more than 8 answers in question "q""#))
        let longID = String(repeating: "a", count: KitLimits.maxIDLength + 1)
        assertRefused(#"{"formatVersion": 1, "id": "\#(longID)", "name": "K", "modules": ["planner"]}"#, .invalidID(longID))
    }

    func testBundledKitsStayWithinTheCaps() throws {
        for id in KitLibrary.bundledIDs {
            XCTAssertNil(KitLimits.firstExceeded(by: try KitLibrary.loadBundled(id)), id)
        }
    }

    func testRefusesQuestionsWithoutAnswers() {
        assertRefused(kit(#", "onboarding": [{"id": "q", "prompt": "?", "options": []}]"#), .questionWithoutOptions("q"))
    }

    func testWarnsAboutDuplicateAnswersAndOutOfRangeLevels() throws {
        let kit = try decode(kit(#"""
        , "defaults": {"moduleSettings": {"focus": {"sounds": [{"sound": "rain", "level": 1.5}, {"sound": "brown", "level": 0.5}]}}},
        "onboarding": [{"id": "q", "prompt": "?", "options": [{"id": "a", "label": "A"}, {"id": "a", "label": "B"}]}]
        """#))
        XCTAssertEqual(kit.issues(), [.duplicateAnswer(question: "q", answer: "a"),
                                      .invalidModuleSetting(path: "moduleSettings.focus.sounds[0].level",
                                                            expected: "a number from 0 to 1")])
    }

    func testWarnsAboutFieldsTheFormatDoesNotRead() throws {
        let kit = try decode(#"""
        {"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner", {"id": "system", "on": false}],
         "colour": "red",
         "defaults": {"tickers": ["focus"], "moduleSettings": {"anything": {"goes": true}}},
         "onboarding": [{"id": "q", "prompt": "?", "options": [{"id": "a", "label": "A", "lable": "B"}]}],
         "requires": {"modules": ["planner"], "app": "2.0"}}
        """#)
        XCTAssertEqual(kit.unknownFields, ["colour", "defaults.tickers", "modules[1].on",
                                           "onboarding[0].options[0].lable", "requires.app"])
        XCTAssertEqual(kit.issues().filter { if case .unknownField = $0 { true } else { false } }.count, 5)
    }

    func testOldTopLevelFieldsStillWorkWithAWarningAndAreCheckedByTheirModule() throws {
        let kit = try decode(#"""
        {"formatVersion": 1, "id": "k", "name": "K", "modules": ["study"],
         "defaults": {"studyMethods": ["pomodoro", "telepathy"], "pet": {"breed": "dragon", "nmae": "Biscuit"}}}
        """#)
        XCTAssertEqual(StudyMethodMenu(kit: kit.defaults).kinds, [.pomodoro], "the old name is still read")
        let methods = StudyMethodKind.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
        let breeds = PetBreed.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
        XCTAssertEqual(kit.issues(), [
            .legacyField(KitLegacyField.all[0]), .legacyField(KitLegacyField.all[3]),
            .invalidModuleSetting(path: "moduleSettings.closet.pet.breed", expected: "one of \(breeds)"),
            .unknownField("moduleSettings.closet.pet.nmae"),
            .invalidModuleSetting(path: "moduleSettings.study.methods[1]", expected: "one of \(methods)"),
        ])
        XCTAssertEqual(KitIssue.legacyField(KitLegacyField.all[0]).description,
                       #""defaults.studyMethods" has moved to "defaults.moduleSettings.study.methods". It still works for now."#)
    }

    func testAKitWithEveryKnownFieldHasNoIssues() throws {
        let kit = try decode(kit(#", "version": "1.3", "requires": {"modules": ["planner"]}, "summary": "s""#))
        XCTAssertEqual(kit.version, "1.3")
        XCTAssertEqual(kit.requires, KitRequirements(modules: [.planner]))
        XCTAssertEqual(kit.issues(), [])
        XCTAssertEqual(kit.missingRequirements(catalog: .builtIn), [])
        let roundTrip = try KitManifest.decode(from: JSONEncoder().encode(kit))
        XCTAssertEqual(roundTrip, kit)
    }

    func testMissingRequirementsListsUnknownModulesOnce() throws {
        let kit = try decode(kit(#", "requires": {"modules": ["leetcode", "planner", "leetcode"]}"#))
        XCTAssertEqual(kit.missingRequirements(catalog: .builtIn), ["leetcode"])
    }
}
