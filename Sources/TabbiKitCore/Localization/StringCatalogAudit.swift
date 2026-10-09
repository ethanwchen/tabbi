import Foundation

/// Finds what a String Catalog (`.xcstrings`) still lacks before it can
/// ship: a language with no translation, a translation not marked done, or
/// one whose format specifiers differ from the English, which would show
/// the wrong value or crash when the string is formatted.
///
/// `LocalizationTests` runs it over Tabbi's catalog, so `swift test` fails
/// until every string is translated into every language in `L10n.languages`.
public struct StringCatalogAudit: Sendable {
    /// One problem with one string.
    public struct Issue: Hashable, Sendable, CustomStringConvertible {
        public enum Kind: Hashable, Sendable {
            /// The language has no translation for the string.
            case missing
            /// The translation exists but its state is not `translated`
            /// (`new` or `needs_review`).
            case notTranslated(state: String)
            /// The translation's format specifiers (`%@`, `%lld`) differ
            /// from the English: `expected` and `found`, one per argument.
            case specifierMismatch(expected: [String], found: [String])
        }

        public var key: String
        public var language: String
        /// The plural form (`one`, `other`) the issue is in, if any.
        public var form: String?
        public var kind: Kind

        public var description: String {
            let place = form.map { "\(language) (\($0))" } ?? language
            switch kind {
            case .missing: return "\"\(key)\": no \(place) translation"
            case .notTranslated(let state): return "\"\(key)\": \(place) translation is \(state)"
            case .specifierMismatch(let expected, let found):
                return "\"\(key)\": \(place) uses \(found) where English uses \(expected)"
            }
        }
    }

    /// The catalog's source language (`en` for Tabbi).
    public let sourceLanguage: String
    private let strings: [String: Entry]

    /// Reads a catalog's JSON as Xcode writes it.
    public init(data: Data) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        sourceLanguage = catalog.sourceLanguage
        strings = catalog.strings
    }

    /// The string keys, which are the English text.
    public var keys: [String] { strings.keys.sorted() }

    /// Everything that keeps the catalog from shipping in `languages`,
    /// sorted by key. Strings marked "Don't translate" are skipped; the
    /// source language is checked only where it has text of its own
    /// (plural forms).
    public func issues(languages: [String]) -> [Issue] {
        var issues: [Issue] = []
        for key in keys {
            guard let entry = strings[key], entry.shouldTranslate != false else { continue }
            let expected = Self.specifiers(in: key)
            for language in languages {
                guard let localization = entry.localizations?[language] else {
                    if language != sourceLanguage {
                        issues.append(Issue(key: key, language: language, kind: .missing))
                    }
                    continue
                }
                for (form, unit) in localization.units {
                    if unit.state != "translated" {
                        issues.append(Issue(key: key, language: language, form: form,
                                            kind: .notTranslated(state: unit.state ?? "empty")))
                    }
                    let found = Self.specifiers(in: unit.value ?? "")
                    if found != expected {
                        issues.append(Issue(key: key, language: language, form: form,
                                            kind: .specifierMismatch(expected: expected, found: found)))
                    }
                }
            }
        }
        return issues
    }

    /// The format specifiers in `text`, one per argument in argument order
    /// (positional ones such as `%2$@` sorted into place), each as its length
    /// modifier and conversion (`@`, `lld`, `.1f` becomes `f`). `%%` is a
    /// literal percent sign, not an argument.
    public static func specifiers(in text: String) -> [String] {
        var positional: [Int: String] = [:]
        var sequential: [String] = []
        for match in text.matches(of: specifierPattern) {
            guard match.output.conversion != "%" else { continue }
            let specifier = String(match.output.length ?? "") + String(match.output.conversion)
            if let position = match.output.position.flatMap({ Int($0) }) {
                positional[position] = specifier
            } else {
                sequential.append(specifier)
            }
        }
        guard !positional.isEmpty else { return sequential }
        return positional.keys.sorted().map { positional[$0]! } + sequential
    }

    nonisolated(unsafe) private static let specifierPattern =
        /%(?:(?<position>\d+)\$)?[-+ 0#']*\d*(?:\.\d+)?(?<length>hh|h|ll|l|q|z|t|j|L)?(?<conversion>[@dDiuUxXoOfFeEgGaAcCsSp%])/
}

// MARK: - The catalog format

private struct Catalog: Decodable, Sendable {
    var sourceLanguage: String
    var strings: [String: Entry]
}

private struct Entry: Decodable, Sendable {
    var shouldTranslate: Bool?
    var localizations: [String: Localization]?
}

private struct Localization: Decodable, Sendable {
    var stringUnit: StringUnit?
    var variations: Variations?

    /// Every piece of text: the plain string (form `nil`) or each plural
    /// or device form, named like `one` or `mac other`.
    var units: [(form: String?, unit: StringUnit)] {
        var units: [(form: String?, unit: StringUnit)] = stringUnit.map { [(nil, $0)] } ?? []
        let forms = (variations?.plural ?? [:]).merging(variations?.device ?? [:]) { first, _ in first }
        for (form, variant) in forms.sorted(by: { $0.key < $1.key }) {
            units += variant.units.map { ($0.form.map { "\(form) \($0)" } ?? form, $0.unit) }
        }
        return units
    }
}

private struct Variations: Decodable, Sendable {
    var plural: [String: Localization]?
    var device: [String: Localization]?
}

private struct StringUnit: Decodable, Sendable {
    var state: String?
    var value: String?
}
