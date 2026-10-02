import Foundation

/// A kit: a declarative, human-editable bundle of modules and defaults for one
/// audience (Productivity, Medicine, Student, ...).
///
/// Kits are plain JSON so the community can write and share them without
/// code (the format is documented in docs/kits.md). Decoding is strict about
/// structure but lenient about values: an id this build doesn't know (a
/// module, sound, or pet breed from a newer version) is kept as written,
/// reported by `issues(catalog:)`, and skipped when the kit is applied.
public struct KitManifest: Codable, Equatable, Sendable, Identifiable {
    /// The newest format this build reads. Bump it only for changes older
    /// builds would misread; adding optional fields doesn't need a bump.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    /// Stable slug (`[a-z0-9-]+`), e.g. "medicine". Saved in settings, so it
    /// must never change once shipped.
    public var id: String
    public var name: String
    /// One line shown under the name in the kit picker.
    public var summary: String
    /// SF Symbol shown in the kit picker.
    public var symbol: String
    /// The module whose accent color tints the kit's symbol, so kits that
    /// open on the same tab still look different in the picker. Nil uses
    /// the first tab.
    public var accent: ModuleID?
    /// The tabs, in order. Entries may be switched off by default.
    public var modules: [KitModuleEntry]
    public var defaults: KitDefaults
    /// Questions the first-run setup asks to tailor the kit.
    public var onboarding: [KitQuestion]
    /// Tasks added to Today the first time the kit is applied.
    public var starterTasks: [String]

    public init(
        formatVersion: Int = currentFormatVersion,
        id: String,
        name: String,
        summary: String,
        symbol: String,
        accent: ModuleID? = nil,
        modules: [KitModuleEntry],
        defaults: KitDefaults = KitDefaults(),
        onboarding: [KitQuestion] = [],
        starterTasks: [String] = []
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.accent = accent
        self.modules = modules
        self.defaults = defaults
        self.onboarding = onboarding
        self.starterTasks = starterTasks
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, summary, symbol, accent, modules, defaults, onboarding, starterTasks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        accent = try container.decodeIfPresent(ModuleID.self, forKey: .accent)
        modules = try container.decode([KitModuleEntry].self, forKey: .modules)
        defaults = try container.decodeIfPresent(KitDefaults.self, forKey: .defaults) ?? KitDefaults()
        onboarding = try container.decodeIfPresent([KitQuestion].self, forKey: .onboarding) ?? []
        starterTasks = try container.decodeIfPresent([String].self, forKey: .starterTasks) ?? []
    }

    /// The module whose accent tints the kit: `accent` if `catalog` knows
    /// it, otherwise the first tab the kit turns on.
    public func accentModule(catalog: ModuleCatalog = .builtIn) -> ModuleID? {
        if let accent, catalog.contains(accent) { return accent }
        return layout(catalog: catalog).enabled.first
    }

    /// Module ids in kit order, duplicates dropped.
    public var moduleIDs: [ModuleID] {
        var seen = Set<ModuleID>()
        return modules.map(\.id).filter { seen.insert($0).inserted }
    }
}

/// One tab in a kit. Written in JSON as a bare id (`"planner"`), or as an
/// object (`{"id": "system", "enabled": false}`) to ship it switched off.
public struct KitModuleEntry: Codable, Equatable, Sendable {
    public var id: ModuleID
    public var enabled: Bool

    public init(_ id: ModuleID, enabled: Bool = true) {
        self.id = id
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey { case id, enabled }

    public init(from decoder: Decoder) throws {
        if let id = try? decoder.singleValueContainer().decode(ModuleID.self) {
            self.init(id)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(ModuleID.self, forKey: .id),
                  enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true)
    }

    public func encode(to encoder: Encoder) throws {
        if enabled {
            var container = encoder.singleValueContainer()
            try container.encode(id)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(enabled, forKey: .enabled)
        }
    }
}

/// Settings a kit starts the user with. Every field is optional: absent means
/// "keep the app default". Values are stored as written; the `resolved…`
/// accessors drop ones this build doesn't know.
public struct KitDefaults: Codable, Equatable, Sendable {
    /// Study methods offered by the Study timer, in order (`StudyMethodKind` raw values).
    public var studyMethods: [String]?
    /// The method the Study timer starts on.
    public var studyMethod: String?
    /// The focus sound mix, as sound id and 0...1 level.
    public var focusSounds: [KitFocusSound]?
    /// Closed-notch preview kinds (`TickerKind` raw values) to show.
    public var ticker: [String]?
    public var pet: KitPetDefaults?
    /// Theme id; "notch" is the built-in hardware-black theme.
    public var theme: String?
    /// Per-module settings, keyed by module id. Each module reads its own
    /// section, so new modules need no changes here.
    public var moduleSettings: [String: KitValue]

    public init(
        studyMethods: [String]? = nil,
        studyMethod: String? = nil,
        focusSounds: [KitFocusSound]? = nil,
        ticker: [String]? = nil,
        pet: KitPetDefaults? = nil,
        theme: String? = nil,
        moduleSettings: [String: KitValue] = [:]
    ) {
        self.studyMethods = studyMethods
        self.studyMethod = studyMethod
        self.focusSounds = focusSounds
        self.ticker = ticker
        self.pet = pet
        self.theme = theme
        self.moduleSettings = moduleSettings
    }

    private enum CodingKeys: String, CodingKey {
        case studyMethods, studyMethod, focusSounds, ticker, pet, theme, moduleSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        studyMethods = try container.decodeIfPresent([String].self, forKey: .studyMethods)
        studyMethod = try container.decodeIfPresent(String.self, forKey: .studyMethod)
        focusSounds = try container.decodeIfPresent([KitFocusSound].self, forKey: .focusSounds)
        ticker = try container.decodeIfPresent([String].self, forKey: .ticker)
        pet = try container.decodeIfPresent(KitPetDefaults.self, forKey: .pet)
        theme = try container.decodeIfPresent(String.self, forKey: .theme)
        moduleSettings = try container.decodeIfPresent([String: KitValue].self, forKey: .moduleSettings) ?? [:]
    }

    /// Known study methods in kit order, or `nil` to offer every preset.
    public var resolvedStudyMethods: [StudyMethodKind]? {
        studyMethods.map { unique($0.compactMap(StudyMethodKind.init(rawValue:))) }
    }

    /// The starting method if known; otherwise the first offered one.
    public var resolvedStudyMethod: StudyMethodKind? {
        studyMethod.flatMap(StudyMethodKind.init(rawValue:)) ?? resolvedStudyMethods?.first
    }

    /// The sound mix with unknown sounds dropped (and levels clamped by `FocusMix`).
    public var resolvedFocusMix: FocusMix? {
        focusSounds.map { sounds in
            FocusMix(sounds.compactMap { entry in
                FocusSound(rawValue: entry.sound).map { FocusMix.Layer(sound: $0, level: Float(entry.level)) }
            })
        }
    }

    /// Preview kinds to show, or `nil` to keep the app default (all).
    public var resolvedTicker: Set<TickerKind>? {
        ticker.map { Set($0.compactMap(TickerKind.init(rawValue:))) }
    }

    /// Settings for one module, if the kit has any.
    public func settings(for module: ModuleID) -> KitValue? {
        moduleSettings[module.rawValue]
    }
}

public struct KitFocusSound: Codable, Equatable, Sendable {
    /// `FocusSound` raw value, e.g. "rain".
    public var sound: String
    /// Relative level, 0...1.
    public var level: Double

    public init(sound: String, level: Double = 1) {
        self.sound = sound
        self.level = level
    }

    private enum CodingKeys: String, CodingKey { case sound, level }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sound = try container.decode(String.self, forKey: .sound)
        level = try container.decodeIfPresent(Double.self, forKey: .level) ?? 1
    }
}

public struct KitPetDefaults: Codable, Equatable, Sendable {
    /// `PetBreed` raw value, e.g. "corgi".
    public var breed: String?
    public var name: String?

    public init(breed: String? = nil, name: String? = nil) {
        self.breed = breed
        self.name = name
    }

    public var resolvedBreed: PetBreed? { breed.flatMap(PetBreed.init(rawValue:)) }
}

/// A first-run question. Each answer can switch modules on or off and add
/// starter tasks, so one kit fits several kinds of user (say, preclinical
/// vs. clinical medical students).
public struct KitQuestion: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var prompt: String
    /// Whether several answers may be picked.
    public var allowsMultiple: Bool
    public var options: [KitAnswer]

    public init(id: String, prompt: String, allowsMultiple: Bool = false, options: [KitAnswer]) {
        self.id = id
        self.prompt = prompt
        self.allowsMultiple = allowsMultiple
        self.options = options
    }

    private enum CodingKeys: String, CodingKey { case id, prompt, allowsMultiple, options }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        prompt = try container.decode(String.self, forKey: .prompt)
        allowsMultiple = try container.decodeIfPresent(Bool.self, forKey: .allowsMultiple) ?? false
        options = try container.decode([KitAnswer].self, forKey: .options)
    }
}

public struct KitAnswer: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    /// Optional SF Symbol shown beside the label.
    public var symbol: String?
    public var enables: [ModuleID]
    public var disables: [ModuleID]
    public var tasks: [String]

    public init(
        id: String,
        label: String,
        symbol: String? = nil,
        enables: [ModuleID] = [],
        disables: [ModuleID] = [],
        tasks: [String] = []
    ) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.enables = enables
        self.disables = disables
        self.tasks = tasks
    }

    private enum CodingKeys: String, CodingKey { case id, label, symbol, enables, disables, tasks }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        enables = try container.decodeIfPresent([ModuleID].self, forKey: .enables) ?? []
        disables = try container.decodeIfPresent([ModuleID].self, forKey: .disables) ?? []
        tasks = try container.decodeIfPresent([String].self, forKey: .tasks) ?? []
    }
}

private func unique<T: Hashable>(_ values: [T]) -> [T] {
    var seen = Set<T>()
    return values.filter { seen.insert($0).inserted }
}
