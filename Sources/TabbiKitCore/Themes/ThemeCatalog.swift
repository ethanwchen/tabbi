import Foundation

/// Every theme Tabbi ships, in picker order, loaded from `themes.json`.
///
/// The themes are data so the Mac app and the Windows port draw the same
/// colors from one source; `shared/schemas/themes.v1.schema.json` describes
/// the format. What a theme does with them (accent treatments, gentle
/// motion, glass) stays in code, pinned for both apps by
/// `shared/fixtures/themes/themes.json`.
public enum ThemeCatalog {
    static let file = ThemeFile.load()

    /// Used when nothing (settings or kit) picks a theme.
    public static let defaultID: ThemeID = file.defaultTheme

    public static let all: [AppTheme] = file.themes

    /// The theme with `id`, or nil when this build doesn't have it.
    public static func theme(_ id: ThemeID) -> AppTheme? {
        all.first { $0.id == id }
    }

    /// The theme with `id`, falling back to the default so an unknown saved
    /// id (from a newer build) still draws something sensible.
    public static func resolve(_ id: ThemeID) -> AppTheme {
        theme(id) ?? named(defaultID)
    }

    /// The theme a kit's `theme` field names, or nil for an id this build
    /// doesn't have. "notch", the name kits used before themes existed, is
    /// Midnight.
    public static func id(forKitValue value: String) -> ThemeID? {
        let id = legacyKitIDs[value] ?? ThemeID(rawValue: value)
        return theme(id)?.id
    }

    static let legacyKitIDs: [String: ThemeID] = file.legacyKitThemes

    /// White text and surfaces on black: the original Tabbi look.
    public static let midnight = named(.midnight)
    public static let graphite = named(.graphite)
    /// An opaque black body (so the panel still meets the hardware notch)
    /// lit by a cool blue glow, with frosted glass cards and Liquid Glass
    /// controls on top of it.
    public static let liquidGlass = named(.liquidGlass)
    public static let neon = named(.neon)
    public static let monochrome = named(.monochrome)
    /// The study default: cream text, peach glow, sage and honey status
    /// colors, pastel accents and gentle motion.
    public static let cozy = named(.cozy)
    public static let sakura = named(.sakura)
    public static let forest = named(.forest)

    /// A theme `themes.json` must have; `ThemeFile` checks the file has
    /// every id `ThemeID` names.
    private static func named(_ id: ThemeID) -> AppTheme {
        guard let theme = theme(id) else { preconditionFailure("themes.json has no theme \"\(id)\"") }
        return theme
    }
}

/// `themes.json`: the themes in picker order, the default, the kit values
/// that predate themes, and the glass sheen of glass surfaces.
struct ThemeFile: Decodable, Sendable {
    enum LoadError: Error, Equatable, CustomStringConvertible {
        case unsupportedSchema(String)
        case duplicateTheme(ThemeID)
        case unknownTheme(path: String, id: ThemeID)
        case componentOutOfRange(path: String, value: Double)

        var description: String {
            switch self {
            case .unsupportedSchema(let schema): "Unsupported schema \"\(schema)\"; expected \"\(ThemeFile.schemaName)\""
            case .duplicateTheme(let id): "Theme \"\(id)\" is defined twice"
            case let .unknownTheme(path, id): "\(path): no theme \"\(id)\""
            case let .componentOutOfRange(path, value): "\(path): \(value) is outside 0...1"
            }
        }
    }

    static let schemaName = "themes.v1"

    /// The ids Swift names (`ThemeID.midnight` and so on), which the file
    /// must define.
    static let requiredIDs: [ThemeID] = [.midnight, .graphite, .liquidGlass, .neon, .monochrome, .cozy, .sakura, .forest]

    let schema: String
    let defaultTheme: ThemeID
    let legacyKitThemes: [String: ThemeID]
    let glassSheen: GlassSheen
    let themes: [AppTheme]

    /// Reads the bundled file. It ships inside the app, so a missing or
    /// broken file is a build mistake: this stops with the reason instead of
    /// drawing with made-up colors.
    static func load() -> ThemeFile {
        guard let url = KitResources.bundle?.url(forResource: "themes", withExtension: "json") else {
            preconditionFailure("Missing themes.json")
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            preconditionFailure("Invalid themes.json: \(error)")
        }
    }

    /// Parses and checks a file: its schema version, unique ids, every id it
    /// or Swift refers to, and color components in 0...1.
    static func decode(_ data: Data) throws -> ThemeFile {
        let file = try JSONDecoder().decode(ThemeFile.self, from: data)
        guard file.schema == schemaName else { throw LoadError.unsupportedSchema(file.schema) }
        var ids = Set<ThemeID>()
        for theme in file.themes where !ids.insert(theme.id).inserted {
            throw LoadError.duplicateTheme(theme.id)
        }
        func check(_ id: ThemeID, _ path: String) throws {
            guard ids.contains(id) else { throw LoadError.unknownTheme(path: path, id: id) }
        }
        try check(file.defaultTheme, "defaultTheme")
        for (value, id) in file.legacyKitThemes.sorted(by: { $0.key < $1.key }) {
            try check(id, "legacyKitThemes.\(value)")
        }
        for id in requiredIDs {
            try check(id, "themes")
        }
        func check(_ color: ThemeColor, _ path: String) throws {
            for (name, value) in [("red", color.red), ("green", color.green), ("blue", color.blue), ("opacity", color.opacity)]
            where !(0...1).contains(value) {
                throw LoadError.componentOutOfRange(path: "\(path).\(name)", value: value)
            }
        }
        let sheen = file.glassSheen
        for (name, color) in [("fillTop", sheen.fillTop), ("fillBottom", sheen.fillBottom), ("glint", sheen.glint),
                              ("rimTop", sheen.rimTop), ("rimBottom", sheen.rimBottom)] {
            try check(color, "glassSheen.\(name)")
        }
        for (index, theme) in file.themes.enumerated() {
            for (role, color) in theme.palette.roles {
                try check(color, "themes[\(index)].palette.\(role)")
            }
        }
        return file
    }
}

extension ThemePalette {
    /// Every color by its `themes.json` key, in declaration order; `glow`
    /// only when set.
    var roles: [(String, ThemeColor)] {
        [("background", background)] + (glow.map { [("glow", $0)] } ?? []) + [
            ("surface", surface), ("surfaceHover", surfaceHover), ("stroke", stroke),
            ("primaryText", primaryText), ("secondaryText", secondaryText), ("tertiaryText", tertiaryText),
            ("success", success), ("warning", warning), ("danger", danger),
        ]
    }
}
