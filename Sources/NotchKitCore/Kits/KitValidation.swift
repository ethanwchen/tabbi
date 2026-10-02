import Foundation

/// Why a kit file can't be used at all.
public enum KitError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Not JSON, or JSON missing required fields. Carries a short reason.
    case malformed(String)
    /// Written for a newer NotchDeck.
    case unsupportedVersion(Int)
    case invalidID(String)
    case emptyName
    case noModules
    /// An imported kit reuses a built-in kit's id, which would replace it.
    case reservedID(String)

    public var description: String {
        switch self {
        case .malformed(let reason): "This isn't a valid kit file (\(reason))."
        case .unsupportedVersion(let version):
            "This kit needs a newer NotchDeck (format \(version), this version reads \(KitManifest.currentFormatVersion))."
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
    case unknownStudyMethod(String)
    case unknownFocusSound(String)
    case unknownTickerKind(String)
    case unknownPetBreed(String)
    case duplicateQuestion(String)

    public var description: String {
        switch self {
        case .unknownModule(let id): "Unknown module \"\(id)\" will be skipped."
        case .duplicateModule(let id): "Module \"\(id)\" is listed more than once."
        case .unknownStudyMethod(let kind): "Unknown study method \"\(kind)\" will be skipped."
        case .unknownFocusSound(let sound): "Unknown focus sound \"\(sound)\" will be skipped."
        case .unknownTickerKind(let kind): "Unknown preview \"\(kind)\" will be skipped."
        case .unknownPetBreed(let breed): "Unknown pet breed \"\(breed)\" will be skipped."
        case .duplicateQuestion(let id): "Onboarding question \"\(id)\" is listed more than once."
        }
    }
}

public extension KitManifest {
    /// Decodes and checks a kit file. Throws only for problems that make the
    /// kit unusable; see `issues(catalog:)` for the rest.
    static func decode(from data: Data) throws -> KitManifest {
        let manifest: KitManifest
        do {
            manifest = try JSONDecoder().decode(KitManifest.self, from: data)
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
        guard formatVersion <= Self.currentFormatVersion else { throw KitError.unsupportedVersion(formatVersion) }
        guard Self.isValidID(id) else { throw KitError.invalidID(id) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KitError.emptyName }
        guard !modules.isEmpty else { throw KitError.noModules }
    }

    /// Values this build doesn't recognize, in the order they appear.
    func issues(catalog: ModuleCatalog = .builtIn) -> [KitIssue] {
        var issues: [KitIssue] = []
        var seen = Set<ModuleID>()
        for entry in modules {
            if !seen.insert(entry.id).inserted {
                issues.append(.duplicateModule(entry.id))
            } else if !catalog.contains(entry.id) {
                issues.append(.unknownModule(entry.id))
            }
        }
        let answerModules = onboarding.flatMap(\.options).flatMap { $0.enables + $0.disables }
        for id in answerModules where !catalog.contains(id) && seen.insert(id).inserted {
            issues.append(.unknownModule(id))
        }
        let methods = (defaults.studyMethods ?? []) + [defaults.studyMethod].compactMap { $0 }
        issues += Self.unknown(methods, StudyMethodKind.init(rawValue:)).map(KitIssue.unknownStudyMethod)
        issues += Self.unknown((defaults.focusSounds ?? []).map(\.sound), FocusSound.init(rawValue:))
            .map(KitIssue.unknownFocusSound)
        issues += Self.unknown(defaults.ticker ?? [], TickerKind.init(rawValue:)).map(KitIssue.unknownTickerKind)
        issues += Self.unknown([defaults.pet?.breed].compactMap { $0 }, PetBreed.init(rawValue:))
            .map(KitIssue.unknownPetBreed)
        var questions = Set<String>()
        for question in onboarding where !questions.insert(question.id).inserted {
            issues.append(.duplicateQuestion(question.id))
        }
        return issues
    }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { scalar in
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
