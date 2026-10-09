import Foundation

/// Why a kit file can't be used at all.
public enum KitError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Not JSON, or JSON missing required fields. Carries a short reason.
    case malformed(String)
    /// Written for a newer Tabbi.
    case unsupportedVersion(Int)
    /// `formatVersion` below 1, which no Tabbi ever wrote.
    case invalidFormatVersion(Int)
    /// The file is bigger than `KitLimits.maxFileBytes`.
    case tooLarge
    /// A list or text goes past one of `KitLimits`. Carries what, such as
    /// "more than 20 starter tasks".
    case exceedsLimit(String)
    /// An onboarding question with no answers to pick.
    case questionWithoutOptions(String)
    /// `requires.modules` names modules this build doesn't have.
    case missingRequiredModules([ModuleID])
    case invalidID(String)
    case emptyName
    case noModules
    /// An imported kit reuses a built-in kit's id, which would replace it.
    case reservedID(String)

    public var description: String {
        switch self {
        case .malformed(let reason): "This isn't a valid kit file (\(reason))."
        case .unsupportedVersion(let version):
            "This kit needs a newer Tabbi (format \(version), this version reads \(KitManifest.currentFormatVersion))."
        case .invalidFormatVersion(let version): "The kit's formatVersion \(version) isn't valid. Use 1."
        case .tooLarge: "The kit file is larger than \(KitLimits.maxFileBytes / 1024) KB."
        case .exceedsLimit(let what): "The kit has \(what)."
        case .questionWithoutOptions(let id): "Onboarding question \"\(id)\" has no answers."
        case .missingRequiredModules(let ids):
            "This kit needs a newer Tabbi with \(ids.map { "\"\($0)\"" }.joined(separator: ", "))."
        case .invalidID(let id): "The kit id \"\(id)\" must be lowercase letters, digits, and dashes."
        case .emptyName: "The kit has no name."
        case .noModules: "The kit doesn't list any modules."
        case .reservedID(let id): "The kit id \"\(id)\" belongs to a built-in kit. Give your kit its own id."
        }
    }
}

/// Something in a usable kit this build will skip, shown as a warning when
/// importing so kit authors can fix typos.
public enum KitIssue: Equatable, Sendable, CustomStringConvertible {
    case unknownModule(ModuleID)
    case duplicateModule(ModuleID)
    case unknownTickerKind(String)
    /// A `theme` this build doesn't have; the user's theme is kept.
    case unknownTheme(String)
    case duplicateQuestion(String)
    case duplicateAnswer(question: String, answer: String)
    /// A field the kit format doesn't read, such as a typo; ignored.
    case unknownField(String)
    /// A `moduleSettings` section for a module this build doesn't have.
    case unknownModuleSettings(ModuleID)
    /// A value in a module's `moduleSettings` section that doesn't match
    /// the module's `KitSettingsSchema`. Modules read their section
    /// leniently, so the value is skipped or kept in range.
    case invalidModuleSetting(path: String, expected: String)
    /// An old top-level field that now lives in a module's section. Still
    /// read for now (`KitLegacyField`), so the kit works as before.
    case legacyField(KitLegacyField)

    public var description: String {
        switch self {
        case .unknownModule(let id): "Unknown module \"\(id)\" will be skipped."
        case .duplicateModule(let id): "Module \"\(id)\" is listed more than once."
        case .unknownTickerKind(let kind): "Unknown preview \"\(kind)\" will be skipped."
        case .unknownTheme(let id): "Unknown theme \"\(id)\" will be ignored."
        case .duplicateQuestion(let id): "Onboarding question \"\(id)\" is listed more than once."
        case .duplicateAnswer(let question, let answer):
            "Answer \"\(answer)\" is listed more than once in question \"\(question)\"."
        case .unknownField(let path): "Unknown field \"\(path)\" will be ignored."
        case .unknownModuleSettings(let id): "Settings for unknown module \"\(id)\" will be ignored."
        case .invalidModuleSetting(let path, let expected):
            "\"\(path)\" should be \(expected); other values are skipped or kept in range."
        case .legacyField(let field):
            "\"\(field.oldPath)\" has moved to \"\(field.newPath)\". It still works for now."
        }
    }
}

public extension KitManifest {
    /// Decodes and checks a kit file. Throws only for problems that make the
    /// kit unusable; see `issues(catalog:)` for the rest.
    static func decode(from data: Data) throws -> KitManifest {
        guard data.count <= KitLimits.maxFileBytes else { throw KitError.tooLarge }
        let report = KitFieldReport()
        let decoder = JSONDecoder()
        decoder.userInfo[KitFieldReport.key] = report
        var manifest: KitManifest
        do {
            manifest = try decoder.decode(KitManifest.self, from: data)
            manifest.unknownFields = report.unknownFields
        } catch let error as DecodingError {
            throw KitError.malformed(Self.reason(for: error))
        } catch {
            throw KitError.malformed("unreadable JSON")
        }
        try manifest.validate()
        return manifest
    }

    /// Throws if the kit can't be used at all.
    func validate() throws {
        guard formatVersion >= 1 else { throw KitError.invalidFormatVersion(formatVersion) }
        guard formatVersion <= Self.currentFormatVersion else { throw KitError.unsupportedVersion(formatVersion) }
        guard Self.isValidID(id) else { throw KitError.invalidID(id) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KitError.emptyName }
        guard !modules.isEmpty else { throw KitError.noModules }
        if let question = onboarding.first(where: { $0.options.isEmpty }) {
            throw KitError.questionWithoutOptions(question.id)
        }
        if let exceeded = KitLimits.firstExceeded(by: self) { throw KitError.exceedsLimit(exceeded) }
    }

    /// Modules in `requires` that `catalog` doesn't have, in kit order.
    /// Importing refuses the kit when this isn't empty.
    func missingRequirements(catalog: ModuleCatalog) -> [ModuleID] {
        var seen = Set<ModuleID>()
        return requires.modules.filter { !catalog.contains($0) && seen.insert($0).inserted }
    }

    /// Values this build doesn't recognize, in the order they appear.
    /// Modules the edition leaves out (`ModuleCatalog.unavailableIDs`) are
    /// skipped quietly: the kit is fine, this edition just has no such tab.
    func issues(catalog: ModuleCatalog) -> [KitIssue] {
        var issues: [KitIssue] = []
        var seen = Set<ModuleID>()
        func isUnknown(_ id: ModuleID) -> Bool { !catalog.contains(id) && !catalog.isUnavailable(id) }
        for entry in modules {
            if !seen.insert(entry.id).inserted {
                issues.append(.duplicateModule(entry.id))
            } else if isUnknown(entry.id) {
                issues.append(.unknownModule(entry.id))
            }
        }
        let answerModules = onboarding.flatMap(\.options).flatMap { $0.enables + $0.disables }
            + [accent].compactMap { $0 }
        for id in answerModules where isUnknown(id) && seen.insert(id).inserted {
            issues.append(.unknownModule(id))
        }
        let previews = Set(TickerKind.all(in: catalog))
        issues += Self.unknown(defaults.ticker ?? []) {
            previews.contains(TickerKind(rawValue: $0)) || catalog.isUnavailable(ModuleID($0)) ? $0 : nil
        }
        .map(KitIssue.unknownTickerKind)
        if let theme = defaults.theme, ThemeCatalog.id(forKitValue: theme) == nil {
            issues.append(.unknownTheme(theme))
        }
        var questions = Set<String>()
        for question in onboarding {
            if !questions.insert(question.id).inserted { issues.append(.duplicateQuestion(question.id)) }
            var answers = Set<String>()
            for answer in question.options where !answers.insert(answer.id).inserted {
                issues.append(.duplicateAnswer(question: question.id, answer: answer.id))
            }
        }
        issues += unknownFields.map(KitIssue.unknownField)
        issues += defaults.legacyFields.map(KitIssue.legacyField)
        issues += moduleSettingsIssues(catalog: catalog)
        return issues
    }

    /// Checks each `moduleSettings` section against the schema its module
    /// declares. Modules without a schema read a free-form section.
    private func moduleSettingsIssues(catalog: ModuleCatalog) -> [KitIssue] {
        defaults.moduleSettings.keys.sorted().flatMap { key -> [KitIssue] in
            let id = ModuleID(rawValue: key)
            guard catalog.contains(id) else { return catalog.isUnavailable(id) ? [] : [.unknownModuleSettings(id)] }
            guard let schema = catalog.descriptor(for: id).kitSettings,
                  let section = defaults.moduleSettings[key] else { return [] }
            return schema.issues(in: section, at: "moduleSettings.\(key)")
        }
    }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= KitLimits.maxIDLength && id.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
    }

    private static func unknown<T>(_ raw: [String], _ make: (String) -> T?) -> [String] {
        var seen = Set<String>()
        return raw.filter { make($0) == nil && seen.insert($0).inserted }
    }

    private static func reason(for error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
            return keys.isEmpty ? "the top level" : keys.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, _): return "missing \"\(key.stringValue)\""
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "unexpected value at \(path(context))"
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty ? "not valid JSON" : "unexpected value at \(path(context))"
        @unknown default: return "unreadable JSON"
        }
    }
}

/// Caps on what a kit may contain, so a sloppy or hostile file can't flood
/// Today with tasks or break the picker's layout. Generous next to the
/// bundled kits; a kit over any of them is refused with the reason.
public enum KitLimits {
    public static let maxFileBytes = 64 * 1024
    public static let maxIDLength = 64
    /// Kit names and answer labels.
    public static let maxNameLength = 80
    /// Summaries and question prompts.
    public static let maxTextLength = 160
    public static let maxVersionLength = 32
    public static let maxTaskLength = 120
    /// More than the tab bar shows comfortably, with room for new modules.
    public static let maxModules = 16
    public static let maxQuestions = 10
    public static let maxOptions = 8
    /// Starter tasks of the kit, and of each answer.
    public static let maxTasks = 20

    /// A description of the first limit `kit` goes past, or nil.
    static func firstExceeded(by kit: KitManifest) -> String? {
        if kit.modules.count > maxModules { return "more than \(maxModules) modules" }
        if kit.onboarding.count > maxQuestions { return "more than \(maxQuestions) onboarding questions" }
        if let question = kit.onboarding.first(where: { $0.options.count > maxOptions }) {
            return "more than \(maxOptions) answers in question \"\(question.id)\""
        }
        if kit.starterTasks.count > maxTasks { return "more than \(maxTasks) starter tasks" }
        let answers = kit.onboarding.flatMap(\.options)
        if let answer = answers.first(where: { $0.tasks.count > maxTasks }) {
            return "more than \(maxTasks) tasks in answer \"\(answer.id)\""
        }
        let texts: [(String, String?, Int)] = [
            ("name", kit.name, maxNameLength),
            ("summary", kit.summary, maxTextLength),
            ("version", kit.version, maxVersionLength),
        ] + kit.onboarding.map { ("question prompt", $0.prompt, maxTextLength) }
            + answers.map { ("answer label", $0.label, maxNameLength) }
            + (kit.starterTasks + answers.flatMap(\.tasks)).map { ("task title", $0, maxTaskLength) }
        if let (what, _, limit) = texts.first(where: { ($0.1?.count ?? 0) > $0.2 }) {
            return "a \(what) longer than \(limit) characters"
        }
        return nil
    }
}
