import Foundation
import XCTest
@testable import TabbiKitCore

/// Pins first-run onboarding (`OnboardingFlow`) to the golden fixture
/// `shared/fixtures/onboarding/onboarding.json`: which steps it shows and in
/// what order for different kits, catalogs and extras, how answers, tab
/// changes, Back, Start from Scratch and Finish move it, and the answers and
/// tabs it ends with, as sequences of inputs with the flow's state after each.
///
/// The Windows port replays the same inputs through its own onboarding and
/// compares with the recorded states, so both apps ask the same questions in
/// the same order. Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an
/// intended change.
final class OnboardingGoldenTests: XCTestCase {
    func testOnboardingMatchesGoldenFixture() throws {
        let url = OnboardingGoldenFixture.url
        let current = try OnboardingGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(OnboardingGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.setupSteps, current.setupSteps, "Setup steps or their ranks changed")
        XCTAssertEqual(stored.extras, current.extras, "Onboarding extras changed")
        XCTAssertEqual(stored.catalogs, current.catalogs, "Module catalogs changed")
        XCTAssertEqual(stored.kits, current.kits, "Kit sources changed")
        XCTAssertEqual(stored.runs.map(\.name), current.runs.map(\.name))
        for (old, new) in zip(stored.runs, current.runs) {
            XCTAssertEqual(old.setup, new.setup, "Run \(old.name): setup")
            XCTAssertEqual(old.initial, new.initial, "Run \(old.name): initial state")
            XCTAssertEqual(old.steps.count, new.steps.count, old.name)
            for (index, (oldStep, newStep)) in zip(old.steps, new.steps).enumerated() {
                XCTAssertEqual(oldStep, newStep, "Run \(old.name), step \(index) (\(oldStep.input.action))")
            }
        }
        XCTAssertEqual(stored, current, "Onboarding no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the kits,
    /// setups and inputs from the file gets the recorded states.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(OnboardingGoldenFixture.self, from: Data(contentsOf: OnboardingGoldenFixture.url))
        let kits = try OnboardingGoldenFixture.load(stored.kits)
        for run in stored.runs {
            let replayed = try OnboardingGoldenFixture.run(run.name, setup: run.setup, inputs: run.steps.map(\.input), kits: kits)
            XCTAssertEqual(replayed, run, run.name)
        }
    }
}

/// Onboarding runs: a starting setup and a list of inputs, each with the
/// flow's state after it.
struct OnboardingGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.onboarding.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/onboarding/onboarding.json")
    }

    enum Failure: Error {
        case missingBundledFile(String)
        case unknownCatalog(String)
        case unknownKit(String)
        case unknownExtra(String)
        case unknownAction(String)
    }

    /// An `OnboardingSetupStep`: lower `rank` runs first.
    struct SetupStep: Codable, Equatable {
        var id: String
        var rank: Int
    }

    /// An `OnboardingExtra`, shown only while `module` is on (always when absent).
    struct Extra: Codable, Equatable {
        var id: String
        var module: String?
    }

    /// A module catalog as data: ids in canonical order, each with the
    /// setup steps its descriptor declares.
    struct Catalog: Codable, Equatable {
        struct Module: Codable, Equatable {
            var id: String
            var setup: [String]
        }

        var name: String
        var modules: [Module]
        var unavailable: [String]

        init(name: String, catalog: ModuleCatalog) {
            self.name = name
            modules = catalog.descriptors.map { Module(id: $0.id.rawValue, setup: $0.setup.map(\.id)) }
            unavailable = catalog.unavailableIDs.map(\.rawValue).sorted()
        }
    }

    /// A kit the runs can pick, by `id`: a bundled `file` in
    /// `Sources/TabbiKitCore/Kits/Bundled`, or inline `json`.
    struct KitSource: Codable, Equatable {
        var id: String
        var file: String?
        var json: String?
    }

    /// How a run's flow starts: the catalog, the tabs (`order` and
    /// `disabled`, read like a saved layout), the preselected `kit` and its
    /// `answers`, whether it asks the name, and the extras it may mention.
    struct Setup: Codable, Equatable {
        var catalog: String
        var order: [String]
        var disabled: [String]
        var kit: String?
        var answers: [String: [String]]
        var asksName: Bool
        var extras: [String]
    }

    /// One user action: `choose` (`kit`), `startFromScratch`, `answer`
    /// (`answer`), `setEnabled` (`module`, `enabled`), `move` (`from`
    /// offsets into the layout order, `to` offset), `next`, `back` or `finish`.
    struct Input: Codable, Equatable {
        var action: String
        var kit: String?
        var answer: String?
        var module: String?
        var enabled: Bool?
        var from: [Int]?
        var to: Int?

        static func choose(_ kit: String) -> Input { Input(action: "choose", kit: kit) }
        static let startFromScratch = Input(action: "startFromScratch")
        static func answer(_ id: String) -> Input { Input(action: "answer", answer: id) }
        static func setEnabled(_ module: String, _ enabled: Bool) -> Input {
            Input(action: "setEnabled", module: module, enabled: enabled)
        }
        static func move(_ from: [Int], to: Int) -> Input { Input(action: "move", from: from, to: to) }
        static let next = Input(action: "next")
        static let back = Input(action: "back")
        static let finish = Input(action: "finish")
    }

    /// `OnboardingFlow.Stage`: `kind` is `name`, `kit`, `question` (with the
    /// question `id`), `modules`, `setup` (with the step `id`), `extras` or
    /// `finished`.
    struct Stage: Codable, Equatable {
        var kind: String
        var id: String?

        init(_ stage: OnboardingFlow.Stage) {
            switch stage {
            case .name: kind = "name"
            case .kit: kind = "kit"
            case .question(let question): kind = "question"; id = question
            case .modules: kind = "modules"
            case .setup(let step): kind = "setup"; id = step
            case .extras: kind = "extras"
            case .finished: kind = "finished"
            }
        }
    }

    struct State: Codable, Equatable {
        var stage: Stage
        var stages: [Stage]
        var stageIndex: Int
        var canGoBack: Bool
        var kit: String?
        var startedFromScratch: Bool
        var answers: [String: [String]]
        var order: [String]
        var enabled: [String]
        var setupSteps: [String]
        var currentExtras: [String]
        var currentQuestion: String?
        var currentSetupStep: String?
        /// What `setEnabled` returned (false when it refused to turn off
        /// the last tab); absent for every other action.
        var result: Bool?

        init(_ flow: OnboardingFlow, result: Bool? = nil) {
            stage = Stage(flow.stage)
            stages = flow.stages.map { Stage($0) }
            stageIndex = flow.stageIndex
            canGoBack = flow.canGoBack
            kit = flow.kit?.id
            startedFromScratch = flow.startedFromScratch
            answers = flow.answers.mapValues { $0.sorted() }
            order = flow.layout.order.map(\.rawValue)
            enabled = flow.layout.enabled.map(\.rawValue)
            setupSteps = flow.setupSteps.map(\.id)
            currentExtras = flow.currentExtras.map(\.id)
            currentQuestion = flow.currentQuestion?.id
            currentSetupStep = flow.currentSetupStep?.id
            self.result = result
        }
    }

    struct Step: Codable, Equatable {
        var input: Input
        var state: State
    }

    struct Run: Codable, Equatable {
        var name: String
        var setup: Setup
        var initial: State
        var steps: [Step]
    }

    var schema = Self.schemaName
    var version = 1
    /// Every setup step the built-in modules declare, by rank.
    var setupSteps: [SetupStep]
    /// Every extra, in the order the extras screen lists them.
    var extras: [Extra]
    var catalogs: [Catalog]
    var kits: [KitSource]
    var runs: [Run]

    // MARK: - Running

    static let catalogNames = ["builtIn", "appStore"]

    /// `builtIn` mirrors the modules Tabbi ships; `appStore` is the same
    /// list without the modules the App Store edition leaves out.
    static func catalog(named name: String) throws -> ModuleCatalog {
        switch name {
        case "builtIn": return .builtIn
        case "appStore": return ModuleCatalog.builtIn.excluding([ModuleID.claudeUsage, ModuleID.party])
        default: throw Failure.unknownCatalog(name)
        }
    }

    /// Reads every kit source: bundled files through the loader, inline
    /// kits through the decoder.
    static func load(_ sources: [KitSource]) throws -> [String: KitManifest] {
        var kits: [String: KitManifest] = [:]
        for source in sources {
            if let file = source.file {
                guard let url = KitLibrary.bundledFileURLs.first(where: { $0.lastPathComponent == file }) else {
                    throw Failure.missingBundledFile(file)
                }
                kits[source.id] = try KitLibrary.load(from: url)
            } else {
                kits[source.id] = try KitManifest.decode(from: Data((source.json ?? "").utf8))
            }
        }
        return kits
    }

    static func run(_ name: String, setup: Setup, inputs: [Input], kits: [String: KitManifest]) throws -> Run {
        let catalog = try Self.catalog(named: setup.catalog)
        let extras = try setup.extras.map { id in
            guard let extra = OnboardingExtra.all.first(where: { $0.id == id }) else { throw Failure.unknownExtra(id) }
            return extra
        }
        func kit(_ id: String?) throws -> KitManifest? {
            guard let id else { return nil }
            guard let kit = kits[id] else { throw Failure.unknownKit(id) }
            return kit
        }
        let preselected = try kit(setup.kit)
        var flow = OnboardingFlow(
            catalog: catalog,
            layout: ModuleLayout(orderRawValues: setup.order, disabledRawValues: setup.disabled, catalog: catalog),
            kit: preselected,
            answers: setup.answers.mapValues { Set($0) },
            asksName: setup.asksName,
            extras: extras
        )
        let initial = State(flow)
        var steps: [Step] = []
        for input in inputs {
            var result: Bool?
            switch input.action {
            case "choose":
                guard let chosen = try kit(input.kit) else { throw Failure.unknownKit("") }
                flow.choose(chosen)
            case "startFromScratch": flow.startFromScratch()
            case "answer": flow.answer(input.answer ?? "")
            case "setEnabled":
                result = flow.setEnabled(ModuleID(rawValue: input.module ?? ""), input.enabled ?? true)
            case "move": flow.move(fromOffsets: IndexSet(input.from ?? []), toOffset: input.to ?? 0)
            case "next": flow.next()
            case "back": flow.back()
            case "finish": flow.finish()
            default: throw Failure.unknownAction(input.action)
            }
            steps.append(Step(input: input, state: State(flow, result: result)))
        }
        return Run(name: name, setup: setup, initial: initial, steps: steps)
    }

    // MARK: - Inputs

    static let kitSources: [KitSource] = [
        KitSource(id: "essentials", file: "essentials.json"),
        KitSource(id: "medicine", file: "medicine.json"),
        KitSource(id: "tiny", json: #"{"formatVersion": 1, "id": "tiny", "name": "Tiny", "modules": ["planner"]}"#),
        KitSource(id: "no-setup", json: #"""
        {"formatVersion": 1, "id": "no-setup", "name": "No setup", "modules": ["system", "spotify", "claudeAsk"]}
        """#),
        KitSource(id: "mixer", json: #"""
        {"formatVersion": 1, "id": "mixer", "name": "Mixer",
         "modules": ["planner", {"id": "party", "enabled": false}, "spotify", "leetcode"],
         "onboarding": [
             {"id": "extras", "prompt": "Extras?", "allowsMultiple": true, "options": [
                 {"id": "party", "label": "Party", "enables": ["party"]},
                 {"id": "anki", "label": "Anki", "enables": ["anki"]},
                 {"id": "quiet", "label": "Quiet", "disables": ["party", "anki"]}]},
             {"id": "music", "prompt": "Music?", "options": [
                 {"id": "yes", "label": "Yes"},
                 {"id": "no", "label": "No", "disables": ["spotify"]}]}]}
        """#),
        KitSource(id: "repeats", json: #"""
        {"formatVersion": 1, "id": "repeats", "name": "Repeats", "modules": ["planner"],
         "onboarding": [
             {"id": "q", "prompt": "First?", "options": [{"id": "a", "label": "A"}]},
             {"id": "q", "prompt": "Again?", "options": [{"id": "b", "label": "B"}]}]}
        """#),
    ]

    /// Every module on, in catalog order.
    static func allOn(_ catalogName: String = "builtIn", kit: String? = nil, answers: [String: [String]] = [:],
                      asksName: Bool = false, extras: [String] = []) throws -> Setup {
        Setup(catalog: catalogName, order: try catalog(named: catalogName).ids.map(\.rawValue), disabled: [],
              kit: kit, answers: answers, asksName: asksName, extras: extras)
    }

    static func current() throws -> OnboardingGoldenFixture {
        let kits = try load(kitSources)
        let everyExtra = OnboardingExtra.all.map(\.id)
        let rerunAnswers = ["stage": ["clinical"]]
        guard let medicine = kits["medicine"] else { throw Failure.unknownKit("medicine") }
        let rerunLayout = medicine.layout(catalog: .builtIn, answers: rerunAnswers.mapValues { Set($0) })
        let builtIn = ModuleCatalog.builtIn
        let rerun = Setup(catalog: "builtIn", order: rerunLayout.order.map(\.rawValue),
                          disabled: builtIn.ids.filter { !rerunLayout.isEnabled($0) }.map(\.rawValue).sorted(),
                          kit: "medicine", answers: rerunAnswers, asksName: false, extras: [])
        let partlyOff = Setup(catalog: "builtIn", order: ["closet", "planner", "leetcode", "spotify"],
                              disabled: ["planner"], kit: nil, answers: [:], asksName: false, extras: [])

        let runs: [(String, Setup, [Input])] = [
            ("essentials-skip-everything", try allOn(), [
                .choose("essentials"), .next, .next, .next, .next, .next, .next,
            ]),
            ("medicine-answers", try allOn(), [
                .choose("medicine"), .answer("preclinical"), .answer("no"), .next, .next, .next, .next,
            ]),
            ("medicine-answer-toggles", try allOn(), [
                .choose("medicine"), .setEnabled("party", true), .answer("missing"), .answer("clinical"), .back,
                .answer("clinical"), .answer("other"),
                .back, .back, .answer("preclinical"), .answer("yes"), .answer("missing"),
            ]),
            ("essentials-multiple-choice", try allOn(), [
                .choose("essentials"), .answer("meetings"), .answer("code"), .answer("meetings"), .answer("missing"),
                .next, .setEnabled("anki", true), .setEnabled("planner", false), .next, .next, .back, .next, .next,
                .next, .next,
            ]),
            ("back-and-repick", try allOn(), [
                .choose("essentials"), .setEnabled("spotify", false), .move([3], to: 0), .back, .back,
                .choose("essentials"), .back, .choose("medicine"), .answer("clinical"), .back, .back,
                .choose("essentials"),
            ]),
            ("start-from-scratch", try allOn(), [
                .startFromScratch, .setEnabled("spotify", false), .setEnabled("party", true), .next, .back, .back,
                .startFromScratch, .setEnabled("anki", true), .back, .choose("essentials"), .back, .startFromScratch,
                .finish,
            ]),
            ("start-from-a-partial-layout", partlyOff, [
                .next, .back, .startFromScratch, .back, .choose("tiny"), .next, .next, .next,
            ]),
            ("asks-name", try allOn(asksName: true), [
                .next, .back, .back, .choose("essentials"), .back, .back, .back, .next, .startFromScratch,
            ]),
            ("asks-name-scratch-first", try allOn(asksName: true), [
                .startFromScratch, .back, .back, .next,
            ]),
            ("rerun-preselected-kit", rerun, [
                .choose("medicine"), .answer("clinical"), .answer("preclinical"), .back, .back, .choose("essentials"),
            ]),
            ("extras-with-party", try allOn(extras: everyExtra), [
                .choose("medicine"), .setEnabled("party", true), .next, .next, .next, .next, .next, .next, .next,
                .next, .next, .back, .next, .next, .back,
            ]),
            ("extras-for-one-tab", try allOn(extras: ["invites"]), [
                .choose("essentials"), .setEnabled("party", true), .setEnabled("party", false),
                .setEnabled("party", true), .next, .next, .next, .next, .next, .next,
            ]),
            ("app-store-catalog", try allOn("appStore", extras: everyExtra), [
                .choose("medicine"), .setEnabled("party", true), .setEnabled("closet", false), .answer("other"),
                .next, .next, .next, .next, .next, .next, .next,
            ]),
            ("mixer-answers", try allOn(), [
                .choose("mixer"), .answer("party"), .answer("anki"), .answer("quiet"), .answer("anki"), .next,
                .answer("no"), .answer("yes"), .next, .next, .next, .next,
            ]),
            ("setup-step-turned-off-while-on-it", try allOn(), [
                .choose("essentials"), .next, .next, .setEnabled("closet", false), .back, .next,
            ]),
            ("finish-from-anywhere", try allOn(), [
                .choose("medicine"), .finish, .back, .next, .choose("essentials"), .finish,
            ]),
            ("move-edge-cases", try allOn(), [
                .choose("essentials"), .move([99], to: 0), .move([0, 2], to: 5), .move([9], to: 0), .move([1], to: 1),
                .move([0], to: 99), .setEnabled("leetcode", true), .setEnabled("leetcode", false),
            ]),
            ("kit-without-questions", try allOn(extras: ["sync", "invites"]), [
                .choose("tiny"), .next, .next, .next, .next,
            ]),
            ("kit-without-setup-steps", try allOn(extras: everyExtra), [
                .choose("no-setup"), .next, .next,
            ]),
            ("duplicate-question-ids", try allOn(), [
                .choose("repeats"), .next, .next, .answer("a"), .answer("b"), .back, .finish,
            ]),
        ]
        return OnboardingGoldenFixture(
            setupSteps: [OnboardingSetupStep.pet, .anki, .calendar, .studyMethod, .party]
                .map { SetupStep(id: $0.id, rank: $0.rank) },
            extras: OnboardingExtra.all.map { Extra(id: $0.id, module: $0.module?.rawValue) },
            catalogs: try catalogNames.map { Catalog(name: $0, catalog: try catalog(named: $0)) },
            kits: kitSources,
            runs: try runs.map { try run($0.0, setup: $0.1, inputs: $0.2, kits: kits) }
        )
    }
}
