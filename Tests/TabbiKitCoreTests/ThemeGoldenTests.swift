import Foundation
import TabbiKitCore
import XCTest

/// Pins every shipped theme to the golden fixture `shared/fixtures/themes/themes.json`.
///
/// The fixture was written by the Swift theme catalog before the themes moved
/// to JSON, so it proves the move changes no color, and the Windows port checks
/// its own theme loading and accent treatments against the same file.
/// Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an intended change.
///
/// Colors compare within `Color.tolerance`: the old code computed the cozy
/// text colors (0.9580000000000001), the data spells them as written (0.958).
/// A pixel is a step of 1/255, so the tolerance hides no visible change.
final class ThemeGoldenTests: XCTestCase {
    func testThemesMatchGoldenFixture() throws {
        let url = ThemeGoldenFixture.folder.appendingPathComponent("themes.json")
        let current = ThemeGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: ThemeGoldenFixture.folder, withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(ThemeGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertTrue(stored.matches(current), "The theme catalog no longer matches \(url.lastPathComponent)")
        XCTAssertEqual(stored.themes.map(\.id), current.themes.map(\.id))
        for (old, new) in zip(stored.themes, current.themes) {
            XCTAssertTrue(old.matches(new), "Theme \(old.id) changed")
        }
    }

    func testMatchingToleratesRoundingButNotAVisibleChange() {
        let color = ThemeGoldenFixture.Color(ThemeColor(red: 0.958, green: 0.5, blue: 0.2))
        var rounded = color
        rounded.red = 0.9580000000000001
        XCTAssertTrue(color.matches(rounded))
        var changed = color
        changed.red += 1.0 / 255
        XCTAssertFalse(color.matches(changed))
    }
}

/// Every theme fully resolved (each color as its four components), the glass
/// sheen, and what each accent treatment makes of the shipped module accents.
struct ThemeGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.themes.golden"

    static var folder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/themes")
    }

    struct Color: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var opacity: Double

        static let tolerance = 1e-9

        init(_ color: ThemeColor) {
            red = color.red
            green = color.green
            blue = color.blue
            opacity = color.opacity
        }

        func matches(_ other: Color) -> Bool {
            zip([red, green, blue, opacity], [other.red, other.green, other.blue, other.opacity])
                .allSatisfy { abs($0 - $1) <= Self.tolerance }
        }
    }

    struct Theme: Codable, Equatable {
        var id: String
        var name: String
        var summary: String
        var family: String
        var accents: String
        var typeface: String
        var motion: String
        var controls: String
        var surfaces: String
        /// Role name (`background`, `glow`, `surface`, ...) to color; `glow`
        /// is absent for a flat body.
        var palette: [String: Color]

        func matches(_ other: Theme) -> Bool {
            var (a, b) = (self, other)
            (a.palette, b.palette) = ([:], [:])
            return a == b && ThemeGoldenFixture.matches(palette, other.palette)
        }
    }

    struct AccentSample: Codable, Equatable {
        var base: Color
        /// Treatment name to the color it gives.
        var treated: [String: Color]

        func matches(_ other: AccentSample) -> Bool {
            base.matches(other.base) && ThemeGoldenFixture.matches(treated, other.treated)
        }
    }

    static func matches(_ a: [String: Color], _ b: [String: Color]) -> Bool {
        a.keys.sorted() == b.keys.sorted() && a.allSatisfy { key, color in b[key].map(color.matches) ?? false }
    }

    func matches(_ other: ThemeGoldenFixture) -> Bool {
        schema == other.schema && version == other.version && defaultTheme == other.defaultTheme
            && legacyKitThemes == other.legacyKitThemes
            && themes.count == other.themes.count && zip(themes, other.themes).allSatisfy { $0.matches($1) }
            && Self.matches(glassSheen, other.glassSheen)
            && accentSamples.count == other.accentSamples.count
            && zip(accentSamples, other.accentSamples).allSatisfy { $0.matches($1) }
    }

    var schema = schemaName
    var version = 1
    var defaultTheme: String
    /// Kit `theme` values from before themes existed, to the theme they mean.
    var legacyKitThemes: [String: String]
    var themes: [Theme]
    var glassSheen: [String: Color]
    var accentSamples: [AccentSample]

    /// The shipped module accents (and the Claude accent), inputs for the
    /// accent treatments.
    static let sampleAccents: [ModuleAccent] = [
        ModuleAccent(red: 0.85, green: 0.47, blue: 0.34),
        ModuleAccent(red: 1.00, green: 0.50, blue: 0.42),
        ModuleAccent(red: 1.00, green: 0.62, blue: 0.26),
        ModuleAccent(red: 1.00, green: 0.42, blue: 0.62),
        ModuleAccent(red: 0.66, green: 0.55, blue: 1.00),
        ModuleAccent(red: 0.36, green: 0.62, blue: 1.00),
        ModuleAccent(red: 0.12, green: 0.84, blue: 0.38),
        ModuleAccent(red: 0.35, green: 0.78, blue: 1.00),
        ModuleAccent(red: 0.30, green: 0.84, blue: 0.76),
        ModuleAccent(red: 0.98, green: 0.80, blue: 0.30),
        // Edge cases: a gray (no hue), a dark pure blue (vivid lifts it to
        // reach contrast) and black.
        ModuleAccent(red: 0.50, green: 0.50, blue: 0.50),
        ModuleAccent(red: 0.10, green: 0.10, blue: 0.60),
        ModuleAccent(red: 0, green: 0, blue: 0),
    ]

    static let treatments: [AccentTreatment] = [.original, .monochrome, .vivid, .pastel]

    static func current() -> ThemeGoldenFixture {
        let sheen = GlassSheen.standard
        return ThemeGoldenFixture(
            defaultTheme: ThemeCatalog.defaultID.rawValue,
            legacyKitThemes: ["notch": ThemeCatalog.id(forKitValue: "notch")?.rawValue ?? ""],
            themes: ThemeCatalog.all.map(theme),
            glassSheen: [
                "fillTop": Color(sheen.fillTop), "fillBottom": Color(sheen.fillBottom), "glint": Color(sheen.glint),
                "rimTop": Color(sheen.rimTop), "rimBottom": Color(sheen.rimBottom),
            ],
            accentSamples: sampleAccents.map { base in
                AccentSample(
                    base: Color(ThemeColor(base)),
                    treated: Dictionary(uniqueKeysWithValues: treatments.map { ($0.rawValue, Color($0.apply(to: base))) })
                )
            }
        )
    }

    private static func theme(_ theme: AppTheme) -> Theme {
        let p = theme.palette
        var palette: [String: Color] = [
            "background": Color(p.background), "surface": Color(p.surface), "surfaceHover": Color(p.surfaceHover),
            "stroke": Color(p.stroke), "primaryText": Color(p.primaryText), "secondaryText": Color(p.secondaryText),
            "tertiaryText": Color(p.tertiaryText), "success": Color(p.success), "warning": Color(p.warning),
            "danger": Color(p.danger),
        ]
        palette["glow"] = p.glow.map(Color.init)
        return Theme(
            id: theme.id.rawValue, name: theme.name, summary: theme.summary, family: theme.family.rawValue,
            accents: theme.accents.rawValue, typeface: theme.typeface.rawValue, motion: theme.motion.rawValue,
            controls: theme.controls.rawValue, surfaces: theme.surfaces.rawValue, palette: palette
        )
    }
}
