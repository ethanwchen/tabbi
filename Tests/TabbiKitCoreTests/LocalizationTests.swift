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
        let resources = try XCTUnwrap(KitResources.bundle)
        let german = try XCTUnwrap(resources.path(forResource: "de", ofType: "lproj").flatMap(Bundle.init(path:)))
        XCTAssertEqual(String(localized: "General", bundle: german), "Allgemein")
        for language in L10n.languages where language != L10n.sourceLanguage {
            XCTAssertNotNil(resources.path(forResource: language, ofType: "lproj"), "\(language).lproj is missing")
        }
    }

    func testPicksTheUsersBestTranslatedLanguage() {
        let available = L10n.languages
        XCTAssertEqual(L10n.language(for: ["de-DE", "en-US"], available: available), "de")
        XCTAssertEqual(L10n.language(for: ["pt-BR"], available: available), "pt-BR")
        XCTAssertEqual(L10n.language(for: ["zh-Hans-CN"], available: available), "zh-Hans")
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
