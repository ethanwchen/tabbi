import Foundation

/// Where Tabbi's translations live and which language they show in.
///
/// Every user-facing string is looked up in `Bundle.tabbi`:
/// `Text("Tabs", bundle: .tabbi)` or `String(localized: "Tabs", bundle: .tabbi)`.
/// The strings are in TabbiKitCore's String Catalog (`Localizable.xcstrings`),
/// which SwiftPM compiles into this target's resource bundle. A resource
/// bundle follows the main bundle's language, and under `swift run` or
/// `swift test` the main bundle has none, so this picks the language itself
/// from the user's preferred languages and hands out that language's
/// `.lproj` folder. The app, snapshots and tests then all read the same
/// strings. See docs/localization.md.
public enum L10n {
    /// The language the strings are written in, used when none of the
    /// user's languages is translated.
    public static let sourceLanguage = "en"

    /// The languages Tabbi ships, as `.lproj` names. Resources/Info.plist
    /// lists the same ones in `CFBundleLocalizations`, so AppKit's own
    /// controls follow the user into them too.
    public static let languages = ["en", "de", "es", "fr", "ja", "ko", "pt-BR", "zh-Hans"]

    /// The bundle that holds the strings in the chosen language.
    public static let bundle: Bundle = {
        guard let resources = KitResources.bundle else { return .main }
        // The source language has a folder only once it has plurals, so it
        // is always available; without a folder the keys are the English.
        let available = Set(resources.localizations + [sourceLanguage]).sorted()
        let chosen = language(for: Locale.preferredLanguages, available: available)
        return resources.path(forResource: chosen, ofType: "lproj").flatMap(Bundle.init(path:)) ?? resources
    }()

    /// The argument that runs Tabbi in one language: `--locale de`.
    public static let localeFlag = "--locale"

    /// Shows this process in `language` (an `.lproj` name such as `de` or
    /// `pt-BR`) whatever the system is set to: strings, dates and numbers,
    /// for snapshots of every language. It sets the launch arguments'
    /// defaults (`-AppleLanguages`, `-AppleLocale`), so nothing is saved, and
    /// must run before anything reads `bundle` or `Locale.current`.
    public static func use(language: String) {
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleLanguages"] = [language]
        arguments["AppleLocale"] = language.replacingOccurrences(of: "-", with: "_")
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    /// The translated language that best fits `preferences` (the user's
    /// languages, most preferred first), or the source language.
    public static func language(for preferences: [String], available: [String]) -> String {
        Bundle.preferredLocalizations(from: available, forPreferences: preferences).first ?? sourceLanguage
    }
}

extension Bundle {
    /// Tabbi's translations in the user's language; see `L10n`.
    public static var tabbi: Bundle { L10n.bundle }
}
