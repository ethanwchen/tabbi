import Foundation
import XCTest
@testable import TabbiKitCore

/// Pins how kits are read, checked and applied to the golden fixture
/// `shared/fixtures/kits/kits.json`: every bundled kit read through the real
/// loader, plus malformed and edge-case kits written inline, each with the
/// decoded kit or the error that refuses it, the warnings `issues(catalog:)`
/// reports, and the tabs, previews, theme, starter tasks and change preview
/// that applying it with sample onboarding answers produces.
///
/// The Windows port replays the same kit files and answers through its own
/// loader and compares with the recorded results, so a kit imported on
/// either app is refused, warned about and applied the same way.
/// Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an intended change.
final class KitGoldenTests: XCTestCase {
    func testKitsMatchGoldenFixture() throws {
        let url = KitGoldenFixture.url
        let current = try KitGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(KitGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.limits, current.limits, "Kit limits changed")
        XCTAssertEqual(stored.catalogs.map(\.name), current.catalogs.map(\.name))
        for (old, new) in zip(stored.catalogs, current.catalogs) {
            XCTAssertEqual(old, new, "Catalog \(old.name) changed")
        }
        XCTAssertEqual(stored.library, current.library, "The bundled kit library changed")
        XCTAssertEqual(stored.bases, current.bases, "Base settings changed")
        XCTAssertEqual(stored.cases.map(\.name), current.cases.map(\.name))
        for (old, new) in zip(stored.cases, current.cases) {
            XCTAssertEqual(old.source, new.source, "Kit \(old.name): source")
            XCTAssertEqual(old.error, new.error, "Kit \(old.name): error")
            XCTAssertEqual(old.decoded, new.decoded, "Kit \(old.name): decoded kit")
            XCTAssertEqual(old.validation, new.validation, "Kit \(old.name): issues")
            XCTAssertEqual(old.applied.count, new.applied.count, "Kit \(old.name): applications")
            for (index, (oldApplied, newApplied)) in zip(old.applied, new.applied).enumerated() {
                XCTAssertEqual(oldApplied, newApplied, "Kit \(old.name), application \(index)")
            }
        }
        XCTAssertEqual(stored, current, "Kit loading no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the kit
    /// sources, catalogs, bases and answers from the file gets the recorded
    /// outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(KitGoldenFixture.self, from: Data(contentsOf: KitGoldenFixture.url))
        for base in stored.bases {
            let settings = try KitGoldenFixture.settings(from: base)
            let catalog = try KitGoldenFixture.catalog(named: base.catalog)
            XCTAssertEqual(KitGoldenFixture.Base(base.name, catalog: base.catalog, settings: settings, in: catalog), base,
                           "Base \(base.name) does not round-trip")
        }
        for recorded in stored.cases {
            let replayed = try KitGoldenFixture.evaluate(recorded, bases: stored.bases)
            XCTAssertEqual(replayed, recorded, recorded.name)
        }
    }
}

/// Kits with their decoded form or error, their warnings for a module
/// catalog, and what applying them to sample settings gives.
struct KitGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.kits.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/kits/kits.json")
    }

    enum Failure: Error {
        case missingBundledFile(String)
        case unknownCatalog(String)
        case unknownBase(String)
    }

    /// `KitLimits` and the newest format this build reads.
    struct Limits: Codable, Equatable {
        var currentFormatVersion: Int
        var maxFileBytes: Int
        var maxIDLength: Int
        var maxNameLength: Int
        var maxTextLength: Int
        var maxVersionLength: Int
        var maxTaskLength: Int
        var maxModules: Int
        var maxQuestions: Int
        var maxOptions: Int
        var maxTasks: Int
    }

    /// One `KitSettingType`: `type` is `bool`, `number` (`minimum` to
    /// `maximum`), `text` (`maxLength`), `choice` (`values`), `lines`
    /// (`maxLength`, `maxCount`), `object` (`fields`) or `list` (`item`,
    /// `maxCount`).
    final class SettingNode: Codable, Equatable, Sendable {
        let type: String
        let minimum: Double?
        let maximum: Double?
        let maxLength: Int?
        let maxCount: Int?
        let values: [String]?
        let fields: [String: SettingNode]?
        let item: SettingNode?

        init(type: String, minimum: Double? = nil, maximum: Double? = nil, maxLength: Int? = nil,
             maxCount: Int? = nil, values: [String]? = nil, fields: [String: SettingNode]? = nil,
             item: SettingNode? = nil) {
            self.type = type
            self.minimum = minimum
            self.maximum = maximum
            self.maxLength = maxLength
            self.maxCount = maxCount
            self.values = values
            self.fields = fields
            self.item = item
        }

        convenience init(_ setting: KitSettingType) {
            switch setting {
            case .bool:
                self.init(type: "bool")
            case .number(let range):
                self.init(type: "number", minimum: range.lowerBound, maximum: range.upperBound)
            case .text(let maxLength):
                self.init(type: "text", maxLength: maxLength)
            case .choice(let values):
                self.init(type: "choice", values: values)
            case .lines(let maxLength, let maxCount):
                self.init(type: "lines", maxLength: maxLength, maxCount: maxCount)
            case .object(let fields):
                self.init(type: "object", fields: fields.mapValues { SettingNode($0) })
            case .list(let item, let maxCount):
                self.init(type: "list", maxCount: maxCount, item: SettingNode(item))
            }
        }

        static func == (lhs: SettingNode, rhs: SettingNode) -> Bool {
            lhs.type == rhs.type && lhs.minimum == rhs.minimum && lhs.maximum == rhs.maximum
                && lhs.maxLength == rhs.maxLength && lhs.maxCount == rhs.maxCount && lhs.values == rhs.values
                && lhs.fields == rhs.fields && lhs.item == rhs.item
        }
    }

    struct Network: Codable, Equatable {
        var host: String
        var purpose: String
        var isLocal: Bool

        init(_ access: ModuleNetworkAccess) {
            host = access.host
            purpose = access.purpose
            isLocal = access.isLocal
        }
    }

    /// A module catalog the kits are checked against, as data: the module
    /// ids in canonical order with what validation and the change preview
    /// read from each descriptor.
    struct Catalog: Codable, Equatable {
        struct Module: Codable, Equatable {
            var id: String
            var permissions: [String]
            var network: [Network]
            /// Whether the module has closed-notch highlights (a ticker kind
            /// named after the module).
            var highlights: Bool
            /// The schema its `moduleSettings` section is checked against;
            /// absent means a free-form section.
            var kitSettings: SettingNode?
        }

        var name: String
        var modules: [Module]
        /// Ids the edition leaves out: kits naming them are not warned about.
        var unavailable: [String]
        /// `TickerKind.all(in:)`, the preview kinds in rotation order.
        var tickerKinds: [String]

        init(name: String, catalog: ModuleCatalog) {
            self.name = name
            modules = catalog.descriptors.map { descriptor in
                Module(id: descriptor.id.rawValue,
                       permissions: ModulePermission.allCases.filter(descriptor.permissions.contains).map(\.rawValue),
                       network: descriptor.network.map { Network($0) },
                       highlights: descriptor.highlightTitle != nil,
                       kitSettings: descriptor.kitSettings.map { SettingNode(.object($0.fields)) })
            }
            unavailable = catalog.unavailableIDs.map(\.rawValue).sorted()
            tickerKinds = TickerKind.all(in: catalog).map(\.rawValue)
        }
    }

    /// `KitLibrary.bundled` and its fallbacks.
    struct Library: Codable, Equatable {
        struct Lookup: Codable, Equatable {
            var id: String?
            var kit: String?
        }

        /// File names in `Sources/TabbiKitCore/Kits/Bundled`, sorted.
        var bundledFiles: [String]
        /// Kit ids in picker order (`pickerOrder`, then id).
        var bundledIDs: [String]
        var defaultKitID: String
        var retiredKitIDs: [String: String]
        /// `KitLibrary.kit(_:)` for an id (absent means nil): the kit, the
        /// default kit when it is gone, or the first kit.
        var lookups: [Lookup]
    }

    /// The settings a kit is applied to. `order` and `disabled` are read
    /// like a saved layout (unknown ids dropped, missing ones appended off).
    struct Base: Codable, Equatable {
        var name: String
        var catalog: String
        var kitID: String
        var kitAnswers: [String: [String]]
        var order: [String]
        var disabled: [String]
        var disabledPreviews: [String]
        var themeID: String

        init(_ name: String, catalog catalogName: String, settings: AppSettings, in catalog: ModuleCatalog) {
            self.name = name
            self.catalog = catalogName
            kitID = settings.kitID
            kitAnswers = KitGoldenFixture.encodeAnswers(settings.kitAnswers)
            order = settings.modules.order.map(\.rawValue)
            disabled = catalog.ids.filter { !settings.modules.isEnabled($0) }.map(\.rawValue).sorted()
            disabledPreviews = settings.notchPreview.disabledKinds.map(\.rawValue).sorted()
            themeID = settings.themeID.rawValue
        }
    }

    /// Where a kit's bytes come from: a bundled `file` read with
    /// `KitLibrary.load(from:)`, or inline `json` read with
    /// `KitManifest.decode(from:)`, padded with spaces to `padToBytes`.
    struct Source: Codable, Equatable {
        var file: String?
        var json: String?
        var padToBytes: Int?
    }

    struct ApplicationInput: Codable, Equatable {
        /// The name of a `bases` entry.
        var base: String
        var answers: [String: [String]]
    }

    /// `KitError`, with its fields and the message the import sheet shows.
    struct ErrorRecord: Codable, Equatable {
        var kind: String
        var reason: String?
        var version: Int?
        var value: String?
        var modules: [String]?
        var message: String

        init(_ error: KitError) {
            message = error.description
            switch error {
            case .malformed(let reason): kind = "malformed"; self.reason = reason
            case .unsupportedVersion(let version): kind = "unsupportedVersion"; self.version = version
            case .invalidFormatVersion(let version): kind = "invalidFormatVersion"; self.version = version
            case .tooLarge: kind = "tooLarge"
            case .exceedsLimit(let what): kind = "exceedsLimit"; value = what
            case .questionWithoutOptions(let id): kind = "questionWithoutOptions"; value = id
            case .missingRequiredModules(let ids): kind = "missingRequiredModules"; modules = ids.map(\.rawValue)
            case .invalidID(let id): kind = "invalidID"; value = id
            case .emptyName: kind = "emptyName"
            case .noModules: kind = "noModules"
            case .reservedID(let id): kind = "reservedID"; value = id
            }
        }
    }

    /// `KitIssue`, with its fields and the warning text.
    struct Issue: Codable, Equatable {
        var kind: String
        var module: String?
        var value: String?
        var path: String?
        var expected: String?
        var question: String?
        var answer: String?
        var message: String

        init(_ issue: KitIssue) {
            message = issue.description
            switch issue {
            case .unknownModule(let id): kind = "unknownModule"; module = id.rawValue
            case .duplicateModule(let id): kind = "duplicateModule"; module = id.rawValue
            case .unknownTickerKind(let raw): kind = "unknownTickerKind"; value = raw
            case .unknownTheme(let raw): kind = "unknownTheme"; value = raw
            case .duplicateQuestion(let id): kind = "duplicateQuestion"; question = id
            case .duplicateAnswer(let question, let answer):
                kind = "duplicateAnswer"; self.question = question; self.answer = answer
            case .unknownField(let path): kind = "unknownField"; self.path = path
            case .unknownModuleSettings(let id): kind = "unknownModuleSettings"; module = id.rawValue
            case .invalidModuleSetting(let path, let expected):
                kind = "invalidModuleSetting"; self.path = path; self.expected = expected
            case .legacyField(let field):
                kind = "legacyField"; value = field.name; module = field.module.rawValue; path = field.newPath
            }
        }
    }

    /// The kit as decoded, before any catalog is involved. Absent optional
    /// fields have already taken their defaults, and legacy fields have
    /// moved into `moduleSettings`.
    struct Decoded: Codable, Equatable {
        struct Entry: Codable, Equatable {
            var id: String
            var enabled: Bool
        }

        struct Answer: Codable, Equatable {
            var id: String
            var label: String
            var symbol: String?
            var enables: [String]
            var disables: [String]
            var tasks: [String]
        }

        struct Question: Codable, Equatable {
            var id: String
            var prompt: String
            var allowsMultiple: Bool
            var options: [Answer]
        }

        var formatVersion: Int
        var version: String?
        var id: String
        var name: String
        var summary: String
        var symbol: String
        var accent: String?
        var pickerOrder: Int?
        var requires: [String]
        var modules: [Entry]
        var moduleIDs: [String]
        var ticker: [String]?
        var theme: String?
        /// `theme` resolved against the theme catalog ("notch" is Midnight);
        /// absent for an unknown theme.
        var resolvedTheme: String?
        var moduleSettings: [String: KitValue]
        var legacyFields: [String]
        var unknownFields: [String]
        var onboarding: [Question]
        var starterTasks: [String]

        init(_ kit: KitManifest) {
            formatVersion = kit.formatVersion
            version = kit.version
            id = kit.id
            name = kit.name
            summary = kit.summary
            symbol = kit.symbol
            accent = kit.accent?.rawValue
            pickerOrder = kit.pickerOrder
            requires = kit.requires.modules.map(\.rawValue)
            modules = kit.modules.map { Entry(id: $0.id.rawValue, enabled: $0.enabled) }
            moduleIDs = kit.moduleIDs.map(\.rawValue)
            ticker = kit.defaults.ticker
            theme = kit.defaults.theme
            resolvedTheme = kit.defaults.theme.flatMap(ThemeCatalog.id(forKitValue:))?.rawValue
            moduleSettings = kit.defaults.moduleSettings
            legacyFields = kit.defaults.legacyFields.map(\.name)
            unknownFields = kit.unknownFields
            onboarding = kit.onboarding.map { question in
                Question(id: question.id, prompt: question.prompt, allowsMultiple: question.allowsMultiple,
                         options: question.options.map { answer in
                             Answer(id: answer.id, label: answer.label, symbol: answer.symbol,
                                    enables: answer.enables.map(\.rawValue), disables: answer.disables.map(\.rawValue),
                                    tasks: answer.tasks)
                         })
            }
            starterTasks = kit.starterTasks
        }
    }

    /// What the kit's catalog makes of it.
    struct Validation: Codable, Equatable {
        var issues: [Issue]
        /// `requires.modules` the catalog lacks; importing refuses the kit
        /// with `missingRequiredModules` when this is not empty.
        var missingRequirements: [String]
        /// Whether the id is a bundled kit's; importing refuses the kit with
        /// `reservedID` (checked before `missingRequirements`).
        var reservedID: Bool
        var accentModule: String?
        /// `defaults.ticker` without kinds the catalog cannot show, in
        /// rotation order; absent keeps the user's previews.
        var resolvedTicker: [String]?
    }

    struct Layout: Codable, Equatable {
        var order: [String]
        var enabled: [String]

        init(_ layout: ModuleLayout) {
            order = layout.order.map(\.rawValue)
            enabled = layout.enabled.map(\.rawValue)
        }
    }

    /// The settings after `AppSettings.apply(_:answers:catalog:)`, besides the
    /// layout.
    struct Settings: Codable, Equatable {
        var kitID: String
        var hasChosenKit: Bool
        var kitAnswers: [String: [String]]
        var disabledPreviews: [String]
        var themeID: String
    }

    /// `KitChangePreview` from the base to the applied settings.
    struct Preview: Codable, Equatable {
        var tabs: [String]
        var turnsOn: [String]
        var turnsOff: [String]
        var newPermissions: [String]
        var newNetworkAccess: [Network]
        var starterTasks: [String]
        var changesNotchPreviews: Bool
        var isEmpty: Bool

        init(_ preview: KitChangePreview) {
            tabs = preview.tabs.map(\.rawValue)
            turnsOn = preview.turnsOn.map(\.rawValue)
            turnsOff = preview.turnsOff.map(\.rawValue)
            newPermissions = preview.newPermissions.map(\.rawValue)
            newNetworkAccess = preview.newNetworkAccess.map { Network($0) }
            starterTasks = preview.starterTasks
            changesNotchPreviews = preview.changesNotchPreviews
            isEmpty = preview.isEmpty
        }
    }

    struct Application: Codable, Equatable {
        /// Ids of `chosenAnswers(_:)`, in question and option order.
        var chosenAnswers: [String]
        var layout: Layout
        var starterTasks: [String]
        var settings: Settings
        /// `usesDefaults(of:catalog:)` on the base, before applying.
        var baseUsesDefaults: Bool
        var preview: Preview
    }

    /// One kit. Inputs: `name`, `catalog`, `source`, `applications`.
    /// Outputs: `error` when the kit is refused, otherwise `decoded`,
    /// `validation` and one `applied` per application.
    struct Case: Codable, Equatable {
        var name: String
        var catalog: String
        var source: Source
        var applications: [ApplicationInput]
        var error: ErrorRecord?
        var decoded: Decoded?
        var validation: Validation?
        var applied: [Application] = []

        init(_ name: String, catalog: String = "builtIn", source: Source, applications: [ApplicationInput] = []) {
            self.name = name
            self.catalog = catalog
            self.source = source
            self.applications = applications
        }
    }

    var schema = Self.schemaName
    var version = 1
    var limits: Limits
    var catalogs: [Catalog]
    var library: Library
    var bases: [Base]
    var cases: [Case]

    // MARK: - Building

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

    static func encodeAnswers(_ answers: KitAnswers) -> [String: [String]] {
        answers.mapValues { $0.sorted() }
    }

    static func decodeAnswers(_ answers: [String: [String]]) -> KitAnswers {
        answers.mapValues { Set($0) }
    }

    static func settings(from base: Base) throws -> AppSettings {
        let catalog = try Self.catalog(named: base.catalog)
        return AppSettings(
            kitID: base.kitID,
            kitAnswers: decodeAnswers(base.kitAnswers),
            modules: ModuleLayout(orderRawValues: base.order, disabledRawValues: base.disabled, catalog: catalog),
            notchPreview: NotchPreviewSettings(disabledKinds: Set(base.disabledPreviews.map(TickerKind.init(rawValue:)))),
            themeID: ThemeID(rawValue: base.themeID)
        )
    }

    static func bundledURL(_ file: String) throws -> URL {
        guard let url = KitLibrary.bundledFileURLs.first(where: { $0.lastPathComponent == file }) else {
            throw Failure.missingBundledFile(file)
        }
        return url
    }

    /// Reads a source the way the app does: bundled files through the
    /// loader, inline kits through the decoder.
    static func load(_ source: Source) throws -> KitManifest {
        if let file = source.file {
            return try KitLibrary.load(from: bundledURL(file))
        }
        var data = Data((source.json ?? "").utf8)
        if let size = source.padToBytes, data.count < size {
            data += Data(repeating: 0x20, count: size - data.count)
        }
        return try KitManifest.decode(from: data)
    }

    /// Computes every output of `input` from its inputs alone.
    static func evaluate(_ input: Case, bases: [Base]) throws -> Case {
        var result = Case(input.name, catalog: input.catalog, source: input.source, applications: input.applications)
        let catalog = try Self.catalog(named: input.catalog)
        let kit: KitManifest
        do {
            kit = try load(input.source)
        } catch let error as KitError {
            result.error = ErrorRecord(error)
            return result
        }
        result.decoded = Decoded(kit)
        result.validation = Validation(
            issues: kit.issues(catalog: catalog).map { Issue($0) },
            missingRequirements: kit.missingRequirements(catalog: catalog).map(\.rawValue),
            reservedID: KitLibrary.bundledIDs.contains(kit.id),
            accentModule: kit.accentModule(catalog: catalog)?.rawValue,
            resolvedTicker: kit.defaults.resolvedTicker(catalog: catalog).map { kinds in
                TickerKind.all(in: catalog).filter(kinds.contains).map(\.rawValue)
            }
        )
        result.applied = try input.applications.map { application in
            guard let baseRecord = bases.first(where: { $0.name == application.base }) else {
                throw Failure.unknownBase(application.base)
            }
            let base = try settings(from: baseRecord)
            let answers = decodeAnswers(application.answers)
            var next = base
            next.apply(kit, answers: answers, catalog: catalog)
            return Application(
                chosenAnswers: kit.chosenAnswers(answers).map(\.id),
                layout: Layout(next.modules),
                starterTasks: kit.starterTasks(answers: answers),
                settings: Settings(kitID: next.kitID, hasChosenKit: next.hasChosenKit,
                                   kitAnswers: encodeAnswers(next.kitAnswers),
                                   disabledPreviews: next.notchPreview.disabledKinds.map(\.rawValue).sorted(),
                                   themeID: next.themeID.rawValue),
                baseUsesDefaults: base.usesDefaults(of: kit, catalog: catalog),
                preview: Preview(KitChangePreview(applying: kit, answers: answers, to: base, catalog: catalog))
            )
        }
        return result
    }

    static func current() throws -> KitGoldenFixture {
        let bases = try makeBases()
        let library = KitLibrary.bundled
        return KitGoldenFixture(
            limits: Limits(
                currentFormatVersion: KitManifest.currentFormatVersion, maxFileBytes: KitLimits.maxFileBytes,
                maxIDLength: KitLimits.maxIDLength, maxNameLength: KitLimits.maxNameLength,
                maxTextLength: KitLimits.maxTextLength, maxVersionLength: KitLimits.maxVersionLength,
                maxTaskLength: KitLimits.maxTaskLength, maxModules: KitLimits.maxModules,
                maxQuestions: KitLimits.maxQuestions, maxOptions: KitLimits.maxOptions, maxTasks: KitLimits.maxTasks
            ),
            catalogs: try catalogNames.map { Catalog(name: $0, catalog: try catalog(named: $0)) },
            library: Library(
                bundledFiles: KitLibrary.bundledFileURLs.map(\.lastPathComponent),
                bundledIDs: KitLibrary.bundledIDs,
                defaultKitID: KitLibrary.defaultKitID,
                retiredKitIDs: KitLibrary.retiredKitIDs,
                lookups: ["essentials", "medicine", "removed", "student", "productivity", nil].map {
                    Library.Lookup(id: $0, kit: library.kit($0)?.id)
                }
            ),
            bases: bases,
            cases: try inputs().map { try evaluate($0, bases: bases) }
        )
    }

    // MARK: - Inputs

    /// Fresh settings (every module on), settings after applying the
    /// Essentials kit, and a hand-tuned setup, for the built-in catalog;
    /// fresh settings for the App Store catalog.
    static func makeBases() throws -> [Base] {
        let builtIn = ModuleCatalog.builtIn
        let appStore = try catalog(named: "appStore")
        let fresh = AppSettings(modules: ModuleLayout(catalog: builtIn))
        let essentialsKit = try KitLibrary.loadBundled("essentials")
        var essentials = fresh
        essentials.apply(essentialsKit, catalog: builtIn)
        let custom = AppSettings(
            kitID: "medicine",
            kitAnswers: ["stage": ["clinical"]],
            modules: ModuleLayout(order: [.closet, .planner, .focus, .spotify, .system],
                                  disabled: [.spotify, .system], catalog: builtIn),
            notchPreview: NotchPreviewSettings(disabledKinds: [.pet, TickerKind.highlights(from: .claudeUsage)]),
            themeID: "graphite"
        )
        return [
            Base("fresh", catalog: "builtIn", settings: fresh, in: builtIn),
            Base("essentials", catalog: "builtIn", settings: essentials, in: builtIn),
            Base("custom", catalog: "builtIn", settings: custom, in: builtIn),
            Base("fresh-appStore", catalog: "appStore", settings: AppSettings(modules: ModuleLayout(catalog: appStore)),
                 in: appStore),
        ]
    }

    private static func apply(_ base: String, _ answers: [String: [String]] = [:]) -> ApplicationInput {
        ApplicationInput(base: base, answers: answers)
    }

    private static func inline(_ json: String, padTo size: Int? = nil) -> Source {
        Source(json: json, padToBytes: size)
    }

    /// A small valid kit with `extra` (starting with a comma) appended.
    private static func kit(id: String = "k", name: String = "K", modules: String = #"["planner"]"#,
                            _ extra: String = "") -> String {
        #"{"formatVersion": 1, "id": "\#(id)", "name": "\#(name)", "modules": \#(modules)\#(extra)}"#
    }

    private static func list(_ items: [String]) -> String {
        "[" + items.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
    }

    private static func questions(_ count: Int, options: Int = 1) -> String {
        let questions = (0..<count).map { question in
            let answers = (0..<options).map { #"{"id": "a\#($0)", "label": "A\#($0)"}"# }.joined(separator: ", ")
            return #"{"id": "q\#(question)", "prompt": "Q\#(question)?", "options": [\#(answers)]}"#
        }
        return "[" + questions.joined(separator: ", ") + "]"
    }

    private static func text(_ count: Int) -> String { String(repeating: "x", count: count) }

    static func inputs() throws -> [Case] {
        var cases: [Case] = []
        let all = ["fresh", "essentials", "custom"]

        // Every bundled kit through the real loader: no answers, the first
        // answer to every question, every answer to every question, and on
        // the App Store catalog.
        for url in KitLibrary.bundledFileURLs {
            let file = url.lastPathComponent
            let kit = try KitLibrary.load(from: url)
            let first = Dictionary(kit.onboarding.compactMap { question in
                question.options.first.map { (question.id, [$0.id]) }
            }, uniquingKeysWith: { earlier, _ in earlier })
            let every = Dictionary(kit.onboarding.map { ($0.id, $0.options.map(\.id)) },
                                   uniquingKeysWith: { earlier, _ in earlier })
            cases.append(Case("bundled-\(kit.id)", source: Source(file: file),
                              applications: all.map { apply($0) } + [apply("fresh", first), apply("fresh", every)]))
            cases.append(Case("bundled-\(kit.id)-appStore", catalog: "appStore", source: Source(file: file),
                              applications: [apply("fresh-appStore"), apply("fresh-appStore", every)]))
        }
        cases.append(Case("bundled-medicine-answers", source: Source(file: "medicine.json"), applications: [
            apply("fresh", ["stage": ["preclinical"], "anki": ["no"]]),
            apply("essentials", ["stage": ["clinical", "other"], "anki": ["yes"]]),
            apply("custom", ["stage": ["clinical"]]),
            apply("fresh", ["nope": ["x"], "stage": ["missing"]]),
        ]))

        // Usable kits.
        cases.append(Case("minimal", source: inline(kit(id: "tiny", name: "Tiny")),
                          applications: all.map { apply($0) }))
        cases.append(Case("every-field", source: inline(#"""
        {"formatVersion": 1, "version": "1.3", "requires": {"modules": ["planner"]}, "id": "every-field",
         "name": "Every field", "summary": "All of it", "symbol": "star", "accent": "study", "pickerOrder": 7,
         "modules": ["study", {"id": "planner", "enabled": false}, {"id": "anki"}, {"id": "spotify", "enabled": true}],
         "defaults": {"ticker": ["focus", "pet"], "theme": "cozy",
                      "moduleSettings": {"study": {"method": "pomodoro", "dailyGoalMinutes": 90}}},
         "onboarding": [{"id": "plan", "prompt": "Plan your day?", "allowsMultiple": true, "options": [
             {"id": "yes", "label": "Yes", "symbol": "checklist", "enables": ["planner"], "tasks": ["  Plan the day  ", ""]},
             {"id": "music", "label": "Music", "disables": ["spotify"], "tasks": ["Read"]}]}],
         "starterTasks": ["  Read  ", "", "Read", "Plan", "   "]}
        """#), applications: [apply("fresh"), apply("custom", ["plan": ["yes", "music"]]),
                              apply("essentials", ["plan": ["music"]])]))
        cases.append(Case("unknown-values", source: inline(#"""
        {"formatVersion": 1, "id": "unknown-values", "name": "Unknown values", "accent": "chess",
         "modules": ["planner", "leetcode", "planner", {"id": "spotify", "enabled": false}, "leetcode", "anki"],
         "defaults": {"ticker": ["focus", "weather", "weather", "claudeUsage", "nowPlaying", "planner"], "theme": "sunset"},
         "onboarding": [
             {"id": "q", "prompt": "One?", "options": [
                 {"id": "a", "label": "A", "enables": ["chess", "spotify", "party"]},
                 {"id": "a", "label": "A again"},
                 {"id": "b", "label": "B", "disables": ["leetcode", "anki"]}]},
             {"id": "q", "prompt": "Again?", "options": [{"id": "c", "label": "C", "enables": ["go"]}]}]}
        """#), applications: [apply("fresh"), apply("fresh", ["q": ["a"]]), apply("custom", ["q": ["b", "c"]])]))
        cases.append(Case("legacy-theme-and-empty-ticker", source: inline(kit(id: "legacy-theme",
                          #", "defaults": {"theme": "notch", "ticker": []}"#)),
                          applications: [apply("custom"), apply("fresh")]))
        cases.append(Case("unknown-fields", source: inline(#"""
        {"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner", {"id": "system", "on": false}],
         "colour": "red",
         "defaults": {"tickers": ["focus"], "moduleSettings": {"anything": {"goes": true}}},
         "onboarding": [{"id": "q", "prompt": "?", "opts": [], "options": [{"id": "a", "label": "A", "lable": "B"}]}],
         "requires": {"modules": ["planner"], "app": "2.0"}}
        """#), applications: [apply("fresh")]))
        cases.append(Case("legacy-fields", source: inline(#"""
        {"formatVersion": 1, "id": "k", "name": "K", "modules": ["study", "focus", "closet"],
         "defaults": {"studyMethods": ["pomodoro", "telepathy"], "studyMethod": "flowtime",
                      "focusSounds": [{"sound": "rain", "level": 0.5}], "pet": {"breed": "dragon", "nmae": "Biscuit"},
                      "moduleSettings": {"study": {"method": "ultradian"}}}}
        """#), applications: [apply("fresh")]))
        let coachLine = text(300)
        let blockTitle = text(KitLimits.maxTaskLength + 1)
        let upNext = text(KitLimits.maxNameLength)
        cases.append(Case("bad-setting-values", source: inline(#"""
        {"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner", "focus", "study", "closet"],
         "defaults": {"moduleSettings": {
             "focus": {"sounds": [{"sound": "thunder", "level": 1.5}, {"sound": "brown", "level": -0.1, "pan": 1},
                                  "rain", {"sound": "rain", "level": 1}]},
             "planner": {"planMode": "cram", "reviewsFirst": "yes", "eventBufferMinutes": 241, "secondsPerCard": 0.5,
                         "studyBlockTitle": "\#(blockTitle)", "upNextEvents": "\#(upNext)", "dayEndHour": 30,
                         "sampleDay": "dentistry", "colour": "red"},
             "study": {"methods": ["pomodoro", "telepathy", 3], "method": 3, "dailyGoalMinutes": 721},
             "closet": {"pet": {"breed": "corgi", "name": 7},
                        "coachLines": {"distraction": ["\#(coachLine)"], "idleCheck": "One line", "unknownKind": ["x"]}},
             "leetcode": {"anything": true},
             "claudeUsage": {"free": "form"}}}}
        """#), applications: [apply("fresh")]))
        let manyMethods = list(Array(repeating: "pomodoro", count: 30))
        cases.append(Case("setting-shapes", source: inline(kit(#"""
        , "defaults": {"moduleSettings": {"focus": 3, "planner": [], "closet": null,
                                          "study": {"methods": "pomodoro", "dailyGoalMinutes": "60"}}}
        """#)), applications: [apply("fresh")]))
        cases.append(Case("setting-list-too-long", source: inline(kit(
            #", "defaults": {"moduleSettings": {"study": {"methods": \#(manyMethods)}}}"#)), applications: [apply("fresh")]))
        cases.append(Case("requires-missing", source: inline(kit(
            #", "requires": {"modules": ["leetcode", "planner", "leetcode", "chess"]}"#)), applications: [apply("fresh")]))
        cases.append(Case("reserved-id", source: inline(kit(id: "medicine", name: "My medicine")),
                          applications: [apply("fresh")]))
        cases.append(Case("only-module-off", source: inline(kit(modules: #"[{"id": "planner", "enabled": false}]"#)),
                          applications: [apply("fresh"), apply("custom")]))
        cases.append(Case("only-unknown-modules", source: inline(kit(modules: #"["leetcode", "chess"]"#)),
                          applications: [apply("fresh"), apply("custom")]))
        cases.append(Case("answers-conflict", source: inline(#"""
        {"formatVersion": 1, "id": "answers", "name": "Answers", "modules": ["planner", "spotify", {"id": "system", "enabled": false}],
         "onboarding": [
             {"id": "music", "prompt": "Music?", "options": [
                 {"id": "yes", "label": "Yes", "enables": ["spotify"], "tasks": ["Make a playlist"]},
                 {"id": "no", "label": "No", "disables": ["spotify"]}]},
             {"id": "extras", "prompt": "Extras?", "allowsMultiple": true, "options": [
                 {"id": "stats", "label": "Stats", "enables": ["system"], "tasks": ["Check CPU", " "]},
                 {"id": "quiet", "label": "Quiet", "disables": ["system", "planner"]},
                 {"id": "claude", "label": "Claude", "enables": ["claudeAsk", "planner"], "tasks": ["Make a playlist"]}]}],
         "starterTasks": ["Plan the day"]}
        """#), applications: [
            apply("fresh", ["extras": ["stats", "quiet"]]),
            apply("fresh", ["extras": ["quiet", "claude"]]),
            apply("fresh", ["music": ["no"], "extras": ["claude"]]),
            apply("fresh", ["music": ["yes", "no"], "extras": ["stats", "claude"]]),
            apply("fresh", ["music": ["no"], "extras": ["quiet"]]),
            apply("essentials", ["music": ["yes"]]),
        ]))
        let edition = #"""
        {"formatVersion": 1, "id": "edition", "name": "Edition", "accent": "party",
         "modules": ["planner", "claudeUsage", "party", "leetcode"],
         "defaults": {"ticker": ["party", "claudeUsage", "focus", "weather"],
                      "moduleSettings": {"party": {"server": "x"}, "claudeUsage": {}, "leetcode": {}}},
         "onboarding": [{"id": "q", "prompt": "Party?", "options": [{"id": "yes", "label": "Yes", "enables": ["party", "chess"]}]}]}
        """#
        cases.append(Case("unavailable-modules-appStore", catalog: "appStore", source: inline(edition),
                          applications: [apply("fresh-appStore"), apply("fresh-appStore", ["q": ["yes"]])]))
        cases.append(Case("unavailable-modules-builtIn", source: inline(edition),
                          applications: [apply("fresh"), apply("fresh", ["q": ["yes"]])]))
        let builtInIDs = ModuleCatalog.builtIn.ids.map(\.rawValue)
        let sixteen = list(builtInIDs + (1...(KitLimits.maxModules - builtInIDs.count)).map { "extra-\($0)" })
        cases.append(Case("at-every-limit", source: inline(#"""
        {"formatVersion": 1, "version": "\#(text(KitLimits.maxVersionLength))", "id": "\#(String(repeating: "a", count: KitLimits.maxIDLength))",
         "name": "\#(text(KitLimits.maxNameLength))", "summary": "\#(text(KitLimits.maxTextLength))", "modules": \#(sixteen),
         "onboarding": \#(questions(KitLimits.maxQuestions, options: KitLimits.maxOptions)),
         "starterTasks": \#(list((1...KitLimits.maxTasks).map { "Task \($0)" }))}
        """#), applications: [apply("fresh", ["q0": ["a0", "a1"], "q9": ["a7"]])]))
        cases.append(Case("legacy-field-of-the-wrong-type", source: inline(kit(#", "defaults": {"studyMethods": 3}"#)),
                          applications: [apply("fresh")]))
        cases.append(Case("long-task-at-limit", source: inline(kit(#", "starterTasks": ["\#(text(KitLimits.maxTaskLength))"]"#)),
                          applications: [apply("fresh")]))
        let combining = String(repeating: #"é"#, count: KitLimits.maxNameLength)
        cases.append(Case("combining-marks-at-limit", source: inline(kit(name: combining))))
        cases.append(Case("padded-to-size-limit", source: inline(kit(), padTo: KitLimits.maxFileBytes)))

        // Refused kits, roughly in the order the checks run.
        let refused: [(String, String, Int?)] = [
            ("padded-past-size-limit", kit(), KitLimits.maxFileBytes + 1),
            ("not-json", "not json", nil),
            ("empty-file", "", nil),
            ("top-level-array", "[]", nil),
            ("truncated", #"{"formatVersion": 1, "id": "k""#, nil),
            ("missing-format-version", #"{"id": "k", "name": "K", "modules": ["planner"]}"#, nil),
            ("missing-id", #"{"formatVersion": 1, "name": "K", "modules": ["planner"]}"#, nil),
            ("missing-name", #"{"formatVersion": 1, "id": "k", "modules": ["planner"]}"#, nil),
            ("missing-modules", #"{"formatVersion": 1, "id": "k", "name": "K"}"#, nil),
            ("format-version-as-string", #"{"formatVersion": "1", "id": "k", "name": "K", "modules": ["planner"]}"#, nil),
            ("format-version-fraction", #"{"formatVersion": 1.5, "id": "k", "name": "K", "modules": ["planner"]}"#, nil),
            ("null-name", #"{"formatVersion": 1, "id": "k", "name": null, "modules": ["planner"]}"#, nil),
            ("module-not-a-string", kit(modules: #"["planner", 3]"#), nil),
            ("module-object-without-id", kit(modules: #"[{"enabled": false}]"#), nil),
            ("question-without-prompt", kit(#", "onboarding": [{"id": "q", "options": [{"id": "a", "label": "A"}]}]"#), nil),
            ("answer-without-label", kit(#", "onboarding": [{"id": "q", "prompt": "?", "options": [{"id": "a"}]}]"#), nil),
            ("ticker-not-a-list", kit(#", "defaults": {"ticker": "focus"}"#), nil),
            ("format-version-0", #"{"formatVersion": 0, "id": "k", "name": "K", "modules": ["planner"]}"#, nil),
            ("format-version-negative", #"{"formatVersion": -3, "id": "k", "name": "K", "modules": ["planner"]}"#, nil),
            ("format-version-2", #"{"formatVersion": 2, "id": "k", "name": "K", "modules": ["planner"]}"#, nil),
            ("format-version-2-with-bad-id", #"{"formatVersion": 2, "id": "My Kit", "name": "", "modules": []}"#, nil),
            ("id-with-space", kit(id: "My Kit"), nil),
            ("id-empty", kit(id: ""), nil),
            ("id-uppercase", kit(id: "Kit"), nil),
            ("id-underscore", kit(id: "my_kit"), nil),
            ("id-accented", kit(id: #"café"#), nil),
            ("id-too-long", kit(id: String(repeating: "a", count: KitLimits.maxIDLength + 1)), nil),
            ("blank-name", kit(name: #"  \n\t"#), nil),
            ("no-modules", kit(modules: "[]"), nil),
            ("blank-name-and-no-modules", kit(name: " ", modules: "[]"), nil),
            ("question-without-options", kit(#", "onboarding": [{"id": "q", "prompt": "?", "options": []}]"#), nil),
            ("too-many-modules", kit(modules: list((0...KitLimits.maxModules).map { "m\($0)" })), nil),
            ("too-many-questions", kit(#", "onboarding": \#(questions(KitLimits.maxQuestions + 1))"#), nil),
            ("too-many-answers", kit(#", "onboarding": \#(questions(1, options: KitLimits.maxOptions + 1))"#), nil),
            ("too-many-starter-tasks", kit(#", "starterTasks": \#(list((0...KitLimits.maxTasks).map { "Task \($0)" }))"#), nil),
            ("too-many-answer-tasks", kit(#"""
            , "onboarding": [{"id": "q", "prompt": "?", "options": [{"id": "a", "label": "A", "tasks": \#(list((0...KitLimits.maxTasks).map { "Task \($0)" }))}]}]
            """#), nil),
            ("name-too-long", kit(name: text(KitLimits.maxNameLength + 1)), nil),
            ("combining-marks-too-long", kit(name: combining + "e"), nil),
            ("summary-too-long", kit(#", "summary": "\#(text(KitLimits.maxTextLength + 1))""#), nil),
            ("version-too-long", kit(#", "version": "\#(text(KitLimits.maxVersionLength + 1))""#), nil),
            ("prompt-too-long", kit(#", "onboarding": [{"id": "q", "prompt": "\#(text(KitLimits.maxTextLength + 1))", "options": [{"id": "a", "label": "A"}]}]"#), nil),
            ("label-too-long", kit(#", "onboarding": [{"id": "q", "prompt": "?", "options": [{"id": "a", "label": "\#(text(KitLimits.maxNameLength + 1))"}]}]"#), nil),
            ("starter-task-too-long", kit(#", "starterTasks": ["\#(text(KitLimits.maxTaskLength + 1))"]"#), nil),
            ("answer-task-too-long", kit(#", "onboarding": [{"id": "q", "prompt": "?", "options": [{"id": "a", "label": "A", "tasks": ["\#(text(KitLimits.maxTaskLength + 1))"]}]}]"#), nil),
            ("first-limit-wins", kit(modules: list((0...KitLimits.maxModules).map { "m\($0)" }),
                                     #", "starterTasks": \#(list((0...KitLimits.maxTasks).map { "Task \($0)" }))"#), nil),
        ]
        cases += refused.map { Case($0.0, source: inline($0.1, padTo: $0.2)) }
        return cases
    }
}
