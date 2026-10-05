import Foundation

/// A kit: a declarative, human-editable bundle of modules and defaults for one
/// audience (Essentials, Med School, ...).
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
    /// The author's own version of the kit, such as "1.3", shown when a
    /// re-import replaces an earlier copy. Free text; Tabbi never compares it.
    public var version: String?
    /// Modules the kit can't work without. Importing refuses the kit when
    /// this build lacks one, instead of quietly skipping the tab the kit is
    /// about. Optional modules are just listed in `modules`.
    public var requires: KitRequirements
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
    /// Where a kit that ships with Tabbi sits in the kit picker; lower comes
    /// first, and kits without one follow in id order. Bundled kits are
    /// found by listing their folder, so this is what keeps the picker
    /// order stable. Imported kits always follow the bundled ones in import
    /// order, so the field means nothing there.
    public var pickerOrder: Int?
    /// Fields of the decoded file that the kit format doesn't read (typos,
    /// or fields from a newer format), as paths like `defaults.tickers`.
    /// Filled by `decode(from:)` and reported by `issues(catalog:)`; never encoded.
    public internal(set) var unknownFields: [String] = []

    public init(
        formatVersion: Int = currentFormatVersion,
        version: String? = nil,
        requires: KitRequirements = KitRequirements(),
        id: String,
        name: String,
        summary: String,
        symbol: String,
        accent: ModuleID? = nil,
        modules: [KitModuleEntry],
        defaults: KitDefaults = KitDefaults(),
        onboarding: [KitQuestion] = [],
        starterTasks: [String] = [],
        pickerOrder: Int? = nil
    ) {
        self.formatVersion = formatVersion
        self.version = version
        self.requires = requires
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.accent = accent
        self.modules = modules
        self.defaults = defaults
        self.onboarding = onboarding
        self.starterTasks = starterTasks
        self.pickerOrder = pickerOrder
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case formatVersion, version, requires, id, name, summary, symbol, accent, modules, defaults, onboarding
        case starterTasks, pickerOrder
    }

    public init(from decoder: Decoder) throws {
        decoder.reportUnknownKitFields(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        requires = try container.decodeIfPresent(KitRequirements.self, forKey: .requires) ?? KitRequirements()
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        accent = try container.decodeIfPresent(ModuleID.self, forKey: .accent)
        modules = try container.decode([KitModuleEntry].self, forKey: .modules)
        defaults = try container.decodeIfPresent(KitDefaults.self, forKey: .defaults) ?? KitDefaults()
        onboarding = try container.decodeIfPresent([KitQuestion].self, forKey: .onboarding) ?? []
        starterTasks = try container.decodeIfPresent([String].self, forKey: .starterTasks) ?? []
        pickerOrder = try container.decodeIfPresent(Int.self, forKey: .pickerOrder)
    }

    /// The module whose accent tints the kit: `accent` if `catalog` knows
    /// it, otherwise the first tab the kit turns on.
    public func accentModule(catalog: ModuleCatalog) -> ModuleID? {
        if let accent, catalog.contains(accent) { return accent }
        return layout(catalog: catalog).enabled.first
    }

    /// Module ids in kit order, duplicates dropped.
    public var moduleIDs: [ModuleID] {
        var seen = Set<ModuleID>()
        return modules.map(\.id).filter { seen.insert($0).inserted }
    }
}

/// What a kit needs from the app it runs in.
public struct KitRequirements: Codable, Equatable, Sendable {
    /// Modules that must exist in this build for the kit to be imported.
    public var modules: [ModuleID]

    public init(modules: [ModuleID] = []) {
        self.modules = modules
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case modules }

    public init(from decoder: Decoder) throws {
        decoder.reportUnknownKitFields(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modules = try container.decodeIfPresent([ModuleID].self, forKey: .modules) ?? []
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

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, enabled }

    public init(from decoder: Decoder) throws {
        if let id = try? decoder.singleValueContainer().decode(ModuleID.self) {
            self.init(id)
            return
        }
        decoder.reportUnknownKitFields(CodingKeys.self)
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
/// "keep the app default". Only settings that span modules live here; each
/// module's own defaults are in its `moduleSettings` section.
public struct KitDefaults: Codable, Equatable, Sendable {
    /// Closed-notch previews to show: built-in `TickerKind` raw values and
    /// the ids of modules whose highlights should show.
    public var ticker: [String]?
    /// Theme id; "notch" is the built-in hardware-black theme.
    public var theme: String?
    /// Per-module settings, keyed by module id. Each module reads its own
    /// section and declares its keys as `ModuleDescriptor.kitSettings`, so
    /// new modules need no changes here.
    public var moduleSettings: [String: KitValue]
    /// Old top-level fields this kit still uses, already read into their
    /// module's section. Filled when decoding, reported by
    /// `issues(catalog:)`; never encoded.
    public internal(set) var legacyFields: [KitLegacyField] = []

    public init(ticker: [String]? = nil, theme: String? = nil, moduleSettings: [String: KitValue] = [:]) {
        self.ticker = ticker
        self.theme = theme
        self.moduleSettings = moduleSettings
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ticker, theme, moduleSettings
        // Legacy aliases, see `KitLegacyField.all`.
        case studyMethods, studyMethod, focusSounds, pet
    }

    public init(from decoder: Decoder) throws {
        decoder.reportUnknownKitFields(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try container.decodeIfPresent([String].self, forKey: .ticker)
        theme = try container.decodeIfPresent(String.self, forKey: .theme)
        moduleSettings = try container.decodeIfPresent([String: KitValue].self, forKey: .moduleSettings) ?? [:]
        for field in KitLegacyField.all {
            guard let key = CodingKeys(rawValue: field.name),
                  let value = try container.decodeIfPresent(KitValue.self, forKey: key) else { continue }
            legacyFields.append(field)
            moveLegacy(value, to: field)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ticker, forKey: .ticker)
        try container.encodeIfPresent(theme, forKey: .theme)
        if !moduleSettings.isEmpty { try container.encode(moduleSettings, forKey: .moduleSettings) }
    }

    /// Puts an old field's value where its module reads it, unless the kit
    /// also sets the new key, which wins.
    private mutating func moveLegacy(_ value: KitValue, to field: KitLegacyField) {
        let section = moduleSettings[field.module.rawValue] ?? .object([:])
        guard case .object(var object) = section, object[field.key] == nil else { return }
        object[field.key] = value
        moduleSettings[field.module.rawValue] = .object(object)
    }

    /// Preview kinds to show, or `nil` to keep the app default (all). Names
    /// `catalog` has no preview for are dropped.
    public func resolvedTicker(catalog: ModuleCatalog) -> Set<TickerKind>? {
        let known = Set(TickerKind.all(in: catalog))
        return ticker.map { Set($0.map(TickerKind.init(rawValue:)).filter(known.contains)) }
    }

    /// Settings for one module, if the kit has any.
    public func settings(for module: ModuleID) -> KitValue? {
        moduleSettings[module.rawValue]
    }
}

/// A field that kit format 1 first had at the top of `defaults` and that
/// now belongs to one module's `moduleSettings` section. Kits that still
/// use the old name keep working for one release, with a warning, so
/// core never again has to know a module's settings.
public struct KitLegacyField: Equatable, Sendable {
    /// The old name under `defaults`, such as "studyMethods".
    public let name: String
    public let module: ModuleID
    /// The key in the module's section, such as "methods".
    public let key: String

    public static let all = [
        KitLegacyField(name: "studyMethods", module: .study, key: "methods"),
        KitLegacyField(name: "studyMethod", module: .study, key: "method"),
        KitLegacyField(name: "focusSounds", module: .focus, key: "sounds"),
        KitLegacyField(name: "pet", module: .closet, key: "pet"),
    ]

    public var oldPath: String { "defaults.\(name)" }
    public var newPath: String { "defaults.moduleSettings.\(module.rawValue).\(key)" }
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

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, prompt, allowsMultiple, options }

    public init(from decoder: Decoder) throws {
        decoder.reportUnknownKitFields(CodingKeys.self)
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

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, label, symbol, enables, disables, tasks }

    public init(from decoder: Decoder) throws {
        decoder.reportUnknownKitFields(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        enables = try container.decodeIfPresent([ModuleID].self, forKey: .enables) ?? []
        disables = try container.decodeIfPresent([ModuleID].self, forKey: .disables) ?? []
        tasks = try container.decodeIfPresent([String].self, forKey: .tasks) ?? []
    }
}
