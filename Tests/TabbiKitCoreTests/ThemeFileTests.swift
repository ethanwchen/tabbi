import Foundation
import XCTest
@testable import TabbiKitCore

/// `themes.json` loading: the format, the checks that stop a broken file,
/// and that the JSON Schema a TypeScript client validates with agrees with
/// the Swift types.
final class ThemeFileTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private let sheen = #"""
        {"fillTop": {"white": 1, "opacity": 0.1}, "fillBottom": {"white": 1}, "glint": {"white": 1},
         "rimTop": {"white": 1}, "rimBottom": {"white": 1}}
        """#

    private func theme(_ id: String, glow: String? = nil, family: String = "classic", group: String? = nil,
                       accent: String? = nil) -> String {
        #"""
        {"id": "\#(id)", "name": "\#(id)", "summary": "A look.", "family": "\#(family)", "accents": "original",
         \#(group.map { #""group": "\#($0)", "# } ?? "")
         "typeface": "rounded", "motion": "standard", "controls": "solid", "surfaces": "flat",
         "palette": {"background": {"white": 0}, \#(glow.map { #""glow": \#($0), "# } ?? "")
           "surface": {"white": 1, "opacity": 0.07}, "surfaceHover": {"white": 1, "opacity": 0.12},
           "stroke": {"white": 1, "opacity": 0.08}, "primaryText": {"white": 1},
           "secondaryText": {"white": 1, "opacity": 0.62}, "tertiaryText": {"white": 1, "opacity": 0.48},
           "success": {"red": 0.3, "green": 0.85, "blue": 0.48}, "warning": {"red": 1, "green": 0.74, "blue": 0.28},
           "danger": {"red": 1, "green": 0.38, "blue": 0.36}\#(accent.map { ", \($0)" } ?? "")}}
        """#
    }

    /// A valid file with every theme Swift names, plus `extra` themes.
    private func file(schema: String = "themes.v1", defaultTheme: String = "midnight",
                      legacy: String = #"{"notch": "midnight"}"#, sheen: String? = nil,
                      themes: [String]? = nil) -> Data {
        let all = themes ?? ThemeFile.requiredIDs.map { theme($0.rawValue) }
        return Data(#"""
            {"schema": "\#(schema)", "defaultTheme": "\#(defaultTheme)", "legacyKitThemes": \#(legacy),
             "glassSheen": \#(sheen ?? self.sheen), "themes": [\#(all.joined(separator: ","))]}
            """#.utf8)
    }

    private func error(_ data: Data) -> ThemeFile.LoadError? {
        do {
            _ = try ThemeFile.decode(data)
            return nil
        } catch {
            return error as? ThemeFile.LoadError
        }
    }

    func testDecodesColorsGlowAndThemeOrder() throws {
        let glow = #"{"red": 0.36, "green": 0.38, "blue": 0.42, "opacity": 0.24}"#
        var themes = ThemeFile.requiredIDs.map { theme($0.rawValue) }
        themes.insert(theme("aurora", glow: glow, family: "cozy"), at: 1)
        let file = try ThemeFile.decode(file(themes: themes))
        XCTAssertEqual(file.themes.map(\.id), [.midnight, "aurora"] + ThemeFile.requiredIDs.dropFirst())
        let aurora = file.themes[1]
        XCTAssertEqual(aurora.family, .cozy)
        XCTAssertEqual(aurora.palette.glow, ThemeColor(red: 0.36, green: 0.38, blue: 0.42, opacity: 0.24))
        XCTAssertNil(file.themes[0].palette.glow)
        XCTAssertEqual(aurora.palette.surface, ThemeColor(white: 1, opacity: 0.07))
        XCTAssertEqual(aurora.palette.primaryText, ThemeColor(white: 1, opacity: 1))
        XCTAssertEqual(file.glassSheen.fillTop, ThemeColor(white: 1, opacity: 0.1))
        XCTAssertEqual(file.legacyKitThemes, ["notch": .midnight])
    }

    /// `group` refines `family` in builds that know it, and a group from a
    /// newer build falls back to `family`, so the file stays readable by
    /// every build; `family` itself stays a value older builds know.
    func testGroupRefinesTheFamilyAndFallsBackToIt() throws {
        var themes = ThemeFile.requiredIDs.map { theme($0.rawValue) }
        themes.append(theme("candy", family: "cozy", group: "sweet"))
        themes.append(theme("comet", family: "cozy", group: "space"))
        let decoded = try ThemeFile.decode(file(themes: themes))
        XCTAssertEqual(decoded.themes.first { $0.id == "candy" }?.family, .sweet)
        XCTAssertEqual(decoded.themes.first { $0.id == "comet" }?.family, .cozy)
        XCTAssertThrowsError(try ThemeFile.decode(file(themes: ThemeFile.requiredIDs.map { theme($0.rawValue) }
                                                            + [theme("candy", family: "sweet")])))
    }

    /// A theme accent and its on-accent color are optional palette roles;
    /// without them the theme behaves as before.
    func testDecodesTheOptionalThemeAccent() throws {
        let accent = #""accent": {"red": 1, "green": 0.7, "blue": 0.82}, "onAccent": {"red": 0.29, "green": 0.06, "blue": 0.16}"#
        var themes = ThemeFile.requiredIDs.map { theme($0.rawValue) }
        themes.append(theme("candy", family: "cozy", group: "sweet", accent: accent))
        let decoded = try ThemeFile.decode(file(themes: themes))
        let candy = try XCTUnwrap(decoded.themes.last)
        XCTAssertEqual(candy.palette.accent, ThemeColor(red: 1, green: 0.7, blue: 0.82))
        XCTAssertEqual(candy.onAccent, ThemeColor(red: 0.29, green: 0.06, blue: 0.16))
        XCTAssertEqual(candy.accent(ModuleAccent(red: 0.2, green: 0.6, blue: 0.5)), candy.palette.accent)
        XCTAssertEqual(candy.palette.roles.suffix(2).map(\.0), ["accent", "onAccent"])
        let plain = try XCTUnwrap(decoded.themes.first)
        XCTAssertNil(plain.palette.accent)
        XCTAssertEqual(plain.onAccent, plain.palette.background)
        XCTAssertFalse(plain.palette.roles.contains { $0.0 == "accent" || $0.0 == "onAccent" })
        XCTAssertEqual(error(file(themes: [theme("midnight", accent: #""accent": {"white": 1.5}"#)]
                                       + ThemeFile.requiredIDs.dropFirst().map { theme($0.rawValue) })),
                       .componentOutOfRange(path: "themes[0].palette.accent.red", value: 1.5))
    }

    /// The bundled file keeps every theme readable by builds from before
    /// theme accents and groups: `family` is always one they know.
    func testBundledFileStaysReadableByOlderBuilds() throws {
        let url = try XCTUnwrap(KitResources.bundle?.url(forResource: "themes", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let themes = try XCTUnwrap(json["themes"] as? [[String: Any]])
        for theme in themes {
            let family = try XCTUnwrap(theme["family"] as? String)
            XCTAssertTrue(ThemeFamily.baseFamilies.map(\.rawValue).contains(family), "\(theme["id"] ?? "?")")
            XCTAssertTrue(AccentTreatment.allCases.map(\.rawValue).contains(theme["accents"] as? String ?? ""))
        }
    }

    func testRejectsBrokenFiles() {
        XCTAssertEqual(error(file(schema: "themes.v2")), .unsupportedSchema("themes.v2"))
        XCTAssertEqual(error(file(defaultTheme: "aurora")), .unknownTheme(path: "defaultTheme", id: "aurora"))
        XCTAssertEqual(error(file(legacy: #"{"notch": "aurora"}"#)),
                       .unknownTheme(path: "legacyKitThemes.notch", id: "aurora"))
        XCTAssertEqual(error(file(themes: [theme("midnight")])), .unknownTheme(path: "themes", id: .graphite))
        XCTAssertEqual(error(file(themes: ThemeFile.requiredIDs.map { theme($0.rawValue) } + [theme("neon")])),
                       .duplicateTheme(.neon))
        XCTAssertEqual(error(file(themes: [theme("midnight", glow: #"{"white": 1, "opacity": 1.2}"#)]
                                       + ThemeFile.requiredIDs.dropFirst().map { theme($0.rawValue) })),
                       .componentOutOfRange(path: "themes[0].palette.glow.opacity", value: 1.2))
        XCTAssertEqual(error(file(sheen: sheen.replacingOccurrences(of: #""glint": {"white": 1}"#,
                                                                    with: #""glint": {"white": -0.5}"#))),
                       .componentOutOfRange(path: "glassSheen.glint.red", value: -0.5))
        // Unknown names and missing colors are decoding errors.
        XCTAssertThrowsError(try ThemeFile.decode(file(themes: [theme("midnight", family: "retro")])))
        XCTAssertThrowsError(try ThemeFile.decode(Data(#"{"schema": "themes.v1"}"#.utf8)))
    }

    func testBundledFileDefinesTheCatalog() {
        XCTAssertEqual(Array(ThemeCatalog.all.map(\.id).prefix(ThemeFile.requiredIDs.count)), ThemeFile.requiredIDs)
        XCTAssertEqual(ThemeCatalog.defaultID, .midnight)
        XCTAssertEqual(ThemeCatalog.liquidGlass.id, .liquidGlass)
        XCTAssertEqual(GlassSheen.standard, ThemeCatalog.file.glassSheen)
    }

    /// The schema lists the same values as the Swift enums and the same
    /// palette roles, so a TypeScript client accepts exactly the files the
    /// Mac app does.
    func testSchemaMatchesSwift() throws {
        let url = repoRoot.appendingPathComponent("shared/schemas/themes.v1.schema.json")
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let theme = try XCTUnwrap((defs["theme"] as? [String: Any])?["properties"] as? [String: Any])
        func values(_ key: String) -> [String]? { (theme[key] as? [String: Any])?["enum"] as? [String] }
        XCTAssertEqual(values("family"), ThemeFamily.baseFamilies.map(\.rawValue))
        XCTAssertEqual(values("group"), ThemeFamily.allCases.filter { !ThemeFamily.baseFamilies.contains($0) }.map(\.rawValue))
        XCTAssertEqual(values("accents"), AccentTreatment.allCases.map(\.rawValue))
        XCTAssertEqual(values("typeface"), ThemeTypeface.allCases.map(\.rawValue))
        XCTAssertEqual(values("motion"), ThemeMotion.allCases.map(\.rawValue))
        XCTAssertEqual(values("controls"), ThemeControlStyle.allCases.map(\.rawValue))
        XCTAssertEqual(values("surfaces"), ThemeSurfaceStyle.allCases.map(\.rawValue))
        let palette = try XCTUnwrap(theme["palette"] as? [String: Any])
        let roles = try XCTUnwrap((palette["properties"] as? [String: Any]).map { Set($0.keys) })
        let full = try XCTUnwrap(ThemeCatalog.all.first { $0.palette.glow != nil && $0.palette.accent != nil })
        XCTAssertEqual(roles, Set(full.palette.roles.map(\.0)))
        XCTAssertEqual(Set(palette["required"] as? [String] ?? []), roles.subtracting(["glow", "accent", "onAccent"]))
    }
}
