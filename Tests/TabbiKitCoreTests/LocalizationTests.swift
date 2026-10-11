import Foundation
import XCTest
@testable import TabbiKitCore

/// Tabbi's String Catalog ships complete: every string in every language,
/// with the same format specifiers as the English, and the compiled
/// translations load from the resource bundle.
final class LocalizationTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func catalog() throws -> StringCatalogAudit {
        let url = repositoryRoot.appendingPathComponent("Sources/TabbiKitCore/Localization/Localizable.xcstrings")
        return try StringCatalogAudit(data: Data(contentsOf: url))
    }

    func testEveryStringIsTranslatedIntoEveryLanguage() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog.sourceLanguage, L10n.sourceLanguage)
        XCTAssertFalse(catalog.keys.isEmpty)
        let issues = catalog.issues(languages: L10n.languages)
        XCTAssertTrue(issues.isEmpty, "Fix in Localizable.xcstrings (docs/localization.md):\n"
            + issues.map(\.description).joined(separator: "\n"))
    }

    func testInfoPlistDeclaresTheShippedLanguages() throws {
        let url = repositoryRoot.appendingPathComponent("Resources/Info.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: url))
        XCTAssertEqual(plist["CFBundleLocalizations"] as? [String], L10n.languages)
        XCTAssertEqual(plist["CFBundleDevelopmentRegion"] as? String, L10n.sourceLanguage)
    }

    func testEveryLanguageLoadsFromTheResourceBundle() throws {
        for language in L10n.languages {
            XCTAssertNotNil(L10n.strings(for: language), "\(language).lproj is missing from the resource bundle")
        }
        let german = try XCTUnwrap(L10n.strings(for: "de"))
        XCTAssertEqual(String(localized: "General", bundle: german), "Allgemein")
        // Plurals come from the .stringsdict beside the .strings.
        let cores = german.localizedString(forKey: "%lld cores", value: nil, table: nil)
        XCTAssertEqual(String.localizedStringWithFormat(cores, 1), "1 Kern")
        XCTAssertEqual(String.localizedStringWithFormat(cores, 4), "4 Kerne")
        let english = try XCTUnwrap(L10n.strings(for: "en"))
        let friends = english.localizedString(forKey: "with %lld friends", value: nil, table: nil)
        XCTAssertEqual(String.localizedStringWithFormat(friends, 1), "with 1 friend")
    }

    /// Russian picks one of three forms by the last digits (1 and 21 are
    /// "one", 2 to 4 "few", 5 to 20 "many"), so every Russian plural needs
    /// all of them. The rules follow the formatting locale, which in the app
    /// is the user's, so this passes Russian explicitly.
    func testRussianPluralsFollowTheLastDigits() throws {
        let russian = try XCTUnwrap(L10n.strings(for: "ru"))
        let locale = Locale(identifier: "ru")
        let days = russian.localizedString(forKey: "%lld days", value: nil, table: nil)
        XCTAssertEqual([1, 2, 5, 11, 21, 22, 25].map { String(format: days, locale: locale, $0) },
                       ["1 день", "2 дня", "5 дней", "11 дней", "21 день", "22 дня", "25 дней"])
        let cores = russian.localizedString(forKey: "%lld cores", value: nil, table: nil)
        XCTAssertEqual([1, 2, 5, 21].map { String(format: cores, locale: locale, $0) },
                       ["1 ядро", "2 ядра", "5 ядер", "21 ядро"])
        let friends = russian.localizedString(forKey: "%lld friends are here with you.", value: nil, table: nil)
        XCTAssertEqual([1, 2, 5, 21].map { String(format: friends, locale: locale, $0) },
                       ["С тобой 1 друг.", "С тобой 2 друга.", "С тобой 5 друзей.", "С тобой 21 друг."])
    }

    /// The widget's streak count has a key of its own ("%lld days" is the
    /// Closet chart's dative phrase), with an English plural, so English
    /// reads "12 days" and German the nominative "12 Tage".
    func testWidgetStreakDaysReadAsAPlainCount() throws {
        let key = "%lld streak days"
        let cases: [(language: String, expected: [String])] = [
            ("en", ["1 day", "2 days", "5 days", "21 days"]),
            ("de", ["1 Tag", "2 Tage", "5 Tage", "21 Tage"]),
            ("ru", ["1 день", "2 дня", "5 дней", "21 день"]),
        ]
        for (language, expected) in cases {
            let format = try XCTUnwrap(L10n.strings(for: language)).localizedString(forKey: key, value: nil, table: nil)
            XCTAssertEqual([1, 2, 5, 21].map { String(format: format, locale: Locale(identifier: language), $0) },
                           expected, language)
        }
    }

    /// Seasonal event names and taglines live in events.json, in English,
    /// and are looked up in the catalog by that text, so a new event or a
    /// reworded line needs its translations added with it.
    func testEverySeasonalEventIsTranslated() throws {
        let missing = "\u{0}missing"
        for language in L10n.languages where language != L10n.sourceLanguage {
            let bundle = try XCTUnwrap(L10n.strings(for: language))
            for event in SeasonalEventCatalog.bundled.events {
                for text in [event.name, event.tagline] {
                    XCTAssertNotEqual(bundle.localizedString(forKey: text, value: missing, table: nil), missing,
                                      "\(language) lacks \"\(text)\"")
                }
            }
        }
        let german = try XCTUnwrap(L10n.strings(for: "de"))
        let pumpkin = german.localizedString(forKey: "Focus for %lld hours during %@.", value: nil, table: nil)
        XCTAssertEqual(String.localizedStringWithFormat(pumpkin, 5, "Halloween"),
                       "Konzentrier dich 5 Stunden während Halloween.")
        let japanese = try XCTUnwrap(L10n.strings(for: "ja"))
        let hat = japanese.localizedString(forKey: "Focus for %lld minutes during %@.", value: nil, table: nil)
        XCTAssertEqual(String.localizedStringWithFormat(hat, 90, "ハロウィン"), "ハロウィンの期間中に90分集中しよう。")
    }

    /// The calendar sentences name each bundled kit's word for events
    /// ("lectures, labs, and shifts"), looked up in the catalog like the
    /// seasonal events, so every language needs each phrase.
    func testEveryBundledKitsEventWordIsTranslated() throws {
        let phrases = Set(KitLibrary.bundled.kits.map { TodayPlanSettings(kit: $0.defaults).upNextEvents } + ["events"])
        let missing = "\u{0}missing"
        for language in L10n.languages where language != L10n.sourceLanguage {
            let bundle = try XCTUnwrap(L10n.strings(for: language))
            for phrase in phrases {
                XCTAssertNotEqual(bundle.localizedString(forKey: phrase, value: missing, table: nil), missing,
                                  "\(language) lacks \"\(phrase)\"")
            }
        }
        XCTAssertEqual(UpNextEmptyState.localizedEvents("gigs and rehearsals"), "gigs and rehearsals")
    }

    /// The .lproj folders that ship are compiled from the catalog by
    /// scripts/compile-strings.sh, and committed. This re-derives what each
    /// language's files must hold (every string and every plural form) and
    /// fails when someone edited the catalog without running the script.
    func testCompiledStringsMatchTheCatalog() throws {
        let catalogURL = repositoryRoot.appendingPathComponent("Sources/TabbiKitCore/Localization/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(CompiledCatalog.self, from: Data(contentsOf: catalogURL))
        let folder = repositoryRoot.appendingPathComponent("Sources/TabbiKitCore/Localization/Strings")
        let shipped = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(".lproj".count)) }
        XCTAssertEqual(Set(shipped), Set(L10n.languages), "Run scripts/compile-strings.sh")

        var problems: [String] = []
        for language in L10n.languages {
            let lproj = folder.appendingPathComponent("\(language).lproj")
            let strings = try plist(lproj.appendingPathComponent("Localizable.strings")) as? [String: String] ?? [:]
            let plurals = try plist(lproj.appendingPathComponent("Localizable.stringsdict")) as? [String: Any] ?? [:]
            for key in Set(strings.keys).union(plurals.keys).subtracting(catalog.strings.keys).sorted() {
                problems.append("\(language): \"\(key)\" is no longer in the catalog")
            }
            for (key, entry) in catalog.strings.sorted(by: { $0.key < $1.key }) {
                let localization = entry.localizations?[language]
                if let forms = localization?.variations?.plural {
                    let expected = forms.compactMapValues(\.stringUnit?.value)
                    if Self.pluralForms(plurals[key]) != expected {
                        problems.append("\(language): plural \"\(key)\" differs")
                    }
                } else if plurals[key] != nil {
                    // A plural wins over the plain string of the same key.
                    problems.append("\(language): \"\(key)\" is no longer a plural")
                } else if let value = localization?.stringUnit?.value {
                    if strings[key] != value { problems.append("\(language): \"\(key)\" differs") }
                } else if let compiled = strings[key], compiled != key {
                    // A string without text of its own in this language
                    // (English, or one marked "Don't translate") shows its
                    // key, the English.
                    problems.append("\(language): \"\(key)\" differs")
                } else if language == catalog.sourceLanguage, strings[key] == nil {
                    problems.append("\(language): \"\(key)\" is missing")
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "The compiled strings are out of date; run scripts/compile-strings.sh:\n"
            + problems.prefix(20).joined(separator: "\n"))
    }

    private func plist(_ url: URL) throws -> Any? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
    }

    /// The plural forms (`one`, `other`, ...) of a compiled .stringsdict entry.
    private static func pluralForms(_ entry: Any?) -> [String: String]? {
        guard let entry = entry as? [String: Any] else { return nil }
        for case let rule as [String: Any] in entry.values
        where rule["NSStringFormatSpecTypeKey"] as? String == "NSStringPluralRuleType" {
            return rule.filter { !$0.key.hasPrefix("NSString") }.compactMapValues { $0 as? String }
        }
        return nil
    }

    func testPicksTheUsersBestTranslatedLanguage() {
        let available = L10n.languages
        XCTAssertEqual(L10n.language(for: ["de-DE", "en-US"], available: available), "de")
        XCTAssertEqual(L10n.language(for: ["pt-BR"], available: available), "pt-BR")
        XCTAssertEqual(L10n.language(for: ["zh-Hans-CN"], available: available), "zh-Hans")
        XCTAssertEqual(L10n.language(for: ["zh-Hant-TW"], available: available), "zh-Hant")
        XCTAssertEqual(L10n.language(for: ["ru-RU"], available: available), "ru")
        XCTAssertEqual(L10n.language(for: ["fil-PH"], available: available), "fil")
        XCTAssertEqual(L10n.language(for: ["ja-JP"], available: available), "ja")
        XCTAssertEqual(L10n.language(for: ["it-IT", "fr-FR"], available: available), "fr")
        XCTAssertEqual(L10n.language(for: ["it-IT"], available: available), "en")
        XCTAssertEqual(L10n.language(for: [], available: available), "en")
    }

    // MARK: - The audit

    private func audit(_ json: String) throws -> StringCatalogAudit {
        try StringCatalogAudit(data: Data(json.utf8))
    }

    private func unit(_ value: String, state: String = "translated") -> String {
        #"{ "stringUnit" : { "state" : "\#(state)", "value" : "\#(value)" } }"#
    }

    func testReportsMissingAndUnfinishedTranslations() throws {
        let catalog = try audit(#"""
        { "sourceLanguage" : "en", "version" : "1.0", "strings" : {
          "Done" : { "localizations" : { "de" : \#(unit("Fertig")), "fr" : \#(unit("Fini", state: "needs_review")) } },
          "Tabbi" : { "shouldTranslate" : false }
        } }
        """#)
        XCTAssertEqual(catalog.issues(languages: ["en", "de", "fr", "ja"]).map(\.description), [
            #""Done": fr translation is needs_review"#,
            #""Done": no ja translation"#,
        ])
    }

    func testReportsSpecifierMismatchesInEveryPluralForm() throws {
        let catalog = try audit(#"""
        { "sourceLanguage" : "en", "version" : "1.0", "strings" : {
          "%lld cards" : { "localizations" : {
            "en" : { "variations" : { "plural" : { "one" : \#(unit("%lld card")), "other" : \#(unit("%lld cards")) } } },
            "de" : { "variations" : { "plural" : { "one" : \#(unit("eine Karte")), "other" : \#(unit("%lld Karten")) } } }
          } },
          "%@ of %@" : { "localizations" : { "de" : \#(unit("%2$@ von %1$@")), "fr" : \#(unit("%@ sur %d")) } }
        } }
        """#)
        XCTAssertEqual(catalog.issues(languages: ["en", "de", "fr"]), [
            .init(key: "%@ of %@", language: "fr", kind: .specifierMismatch(expected: ["@", "@"], found: ["@", "d"])),
            .init(key: "%lld cards", language: "de", form: "one",
                  kind: .specifierMismatch(expected: ["lld"], found: [])),
            .init(key: "%lld cards", language: "fr", kind: .missing),
        ])
    }

    func testReadsSpecifiersInArgumentOrder() {
        XCTAssertEqual(StringCatalogAudit.specifiers(in: "%2$@ at %1$lld%%"), ["lld", "@"])
        XCTAssertEqual(StringCatalogAudit.specifiers(in: "%.1f h, %@"), ["f", "@"])
        XCTAssertEqual(StringCatalogAudit.specifiers(in: "100%% done"), [])
    }
}

// MARK: - The catalog, as far as the compiled files need it

private struct CompiledCatalog: Decodable {
    struct Entry: Decodable {
        var localizations: [String: Localization]?
    }

    struct Localization: Decodable {
        var stringUnit: Unit?
        var variations: Variations?
    }

    struct Variations: Decodable {
        var plural: [String: Localization]?
    }

    struct Unit: Decodable {
        var value: String?
    }

    var sourceLanguage: String
    var strings: [String: Entry]
}
