import Foundation

/// Where Tabbi's translations live and which language they show in.
///
/// Every user-facing string is looked up in `Bundle.tabbi`:
/// `Text("Tabs", bundle: .tabbi)` or `String(localized: "Tabs", bundle: .tabbi)`.
/// The strings are in TabbiKitCore's String Catalog (`Localizable.xcstrings`),
/// which `scripts/compile-strings.sh` compiles into one `.lproj` folder per
/// language under `Localization/Strings`. That folder ships copied as is in
/// this target's resource bundle, so every toolchain builds the same layout.
/// A resource bundle follows the main bundle's language, and under `swift run`
/// or `swift test` the main bundle has none, so this picks the language itself
/// from the user's preferred languages and hands out that language's `.lproj`
/// folder. The app, snapshots and tests then all read the same strings. See
/// docs/localization.md.
public enum L10n {
    /// The language the strings are written in, used when none of the
    /// user's languages is translated.
    public static let sourceLanguage = "en"

    /// The languages Tabbi ships, as `.lproj` names. Resources/Info.plist
    /// lists the same ones in `CFBundleLocalizations`, so AppKit's own
    /// controls follow the user into them too.
    public static let languages = ["en", "ar", "de", "es", "fr", "fil", "ja", "ko", "pt-BR", "ru", "zh-Hans", "zh-Hant"]

    /// The folder in the resource bundle that holds one `<language>.lproj`
    /// per language (`Localization/Strings` in the sources).
    static let stringsFolder = "Strings"

    /// The compiled strings folder of `language`, if it shipped.
    static func strings(for language: String) -> Bundle? {
        KitResources.bundle?
            .url(forResource: stringsFolder, withExtension: nil)
            .flatMap { Bundle(url: $0.appendingPathComponent("\(language).lproj")) }
    }

    /// The shipped language the strings show in: the user's best
    /// translated one, or the source language.
    public static let current: String = {
        let available = languages.filter { strings(for: $0) != nil }
        return language(for: Locale.preferredLanguages, available: available)
    }()

    /// The bundle that holds the strings in the chosen language.
    public static let bundle: Bundle = {
        // Without any compiled strings the keys, which are the English, show.
        strings(for: current) ?? strings(for: sourceLanguage) ?? .main
    }()

    /// Whether the chosen language reads right to left (Arabic), so every
    /// view Tabbi hosts lays out mirrored. Hosting views and `ImageRenderer`
    /// take the direction from here rather than from AppKit, whose own
    /// choice follows the main bundle, which has no languages under
    /// `swift run`.
    public static var isRightToLeft: Bool { isRightToLeft(current) }

    /// Whether `language` (an `.lproj` name) is written right to left.
    public static func isRightToLeft(_ language: String) -> Bool {
        Locale.Language(identifier: language).characterDirection == .rightToLeft
    }

    /// The argument that runs Tabbi in one language: `--locale de`.
    public static let localeFlag = "--locale"

    /// Shows this process in `language` (an `.lproj` name such as `de` or
    /// `pt-BR`) whatever the system is set to: strings, dates and numbers,
    /// for snapshots of every language. It sets the launch arguments'
    /// defaults (`-AppleLanguages`, `-AppleLocale`), so nothing is saved, and
    /// must run before anything reads `bundle` or `Locale.current`, and
    /// before `NSApplication.shared`, which fixes the locale for the process.
    public static func use(language: String) {
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleLanguages"] = [language]
        arguments["AppleLocale"] = language.replacingOccurrences(of: "-", with: "_")
        // AppKit's own controls (Settings' toolbar, menus) mirror too.
        arguments["AppleTextDirection"] = isRightToLeft(language)
        arguments["NSForceRightToLeftWritingDirection"] = isRightToLeft(language)
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
