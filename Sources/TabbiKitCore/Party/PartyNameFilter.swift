import Foundation

/// The friends server refuses display names and pet names with slurs or
/// explicit terms (`name_not_allowed`, `pet_name_not_allowed`), since
/// friends and party members see them. This is the same check, run in the
/// app so a rejected name gets an inline message as it is typed. Its rules
/// copy `backend/shared/name-filter.json`, and the tests hold both to the
/// same rules and the same cases.
public enum PartyNameFilter {
    /// The blocklist and how text is read before matching (see the JSON's `about`).
    public struct Rules: Equatable, Sendable {
        public var substitutions: [String: String]
        public var ambiguous: [String: String]
        public var anywhere: [String]
        public var allow: [String]
        public var words: [String]
    }

    public static let rules = Rules(
        substitutions: [
            "0": "o", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "9": "g",
            "@": "a", "$": "s", "+": "t", "\u{20AC}": "e",
            "\u{0430}": "a", "\u{0435}": "e", "\u{043E}": "o", "\u{0440}": "p", "\u{0441}": "c",
            "\u{0445}": "x", "\u{0443}": "y", "\u{0456}": "i", "\u{0458}": "j", "\u{0455}": "s",
            "\u{043A}": "k", "\u{043C}": "m", "\u{0442}": "t",
            "\u{03B1}": "a", "\u{03BF}": "o", "\u{03B9}": "i", "\u{03BA}": "k", "\u{03BD}": "v",
            "\u{03C1}": "p", "\u{03C4}": "t", "\u{03C5}": "u",
        ],
        ambiguous: ["1": "il", "!": "il", "|": "il"],
        anywhere: [
            "arsehole", "asshole", "bastard", "bitch", "blowjob", "bullshit", "cocksucker", "dickhead", "dildo",
            "faggot", "fuck", "handjob", "hentai", "hitler", "jizz", "killyourself", "milf", "nigga", "nigger",
            "orgasm", "paedophile", "pedophile", "shithead", "wetback", "whore",
        ],
        allow: ["niggard", "snigger"],
        words: [
            "anal", "anus", "arse", "ass", "boob", "chink", "cock", "coon", "cum", "cunt", "fag", "gook", "kike",
            "kkk", "kys", "nazi", "paedo", "paki", "pedo", "penis", "porn", "porno", "prick", "puta", "pussy",
            "rape", "rapist", "retard", "retarded", "sex", "shit", "shitty", "slut", "spic", "tit", "titty",
            "titties", "tranny", "twat", "vagina", "wank", "wanker", "xxx",
        ]
    )

    /// True when `name` contains none of the blocked terms, read through
    /// accents, case, look-alike letters, leetspeak, separators and repeated
    /// letters. Ordinary names that merely contain a short term (Cassandra,
    /// Scunthorpe, Dick Van Dyke) pass, because short terms only match whole words.
    public static func isAllowed(_ name: String) -> Bool {
        let plain = String(String.UnicodeScalarView(
            name.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !isMark($0) }
        ))
        let camelSplit = splittingCamelCase(plain)
        for choice in 0..<2 {
            let plainWords = words(of: plain, choice: choice)
            var joined = plainWords.joined()
            for allowed in rules.allow { joined = joined.replacingOccurrences(of: allowed, with: "") }
            let joinedRuns = runs(joined)
            if anywhere.contains(where: { contains(joinedRuns, $0) }) { return false }
            let candidates = plainWords + words(of: camelSplit, choice: choice) + [plainWords.joined()]
            if candidates.contains(where: { word in blockedWords.contains { isWord(word, $0) } }) { return false }
        }
        return true
    }

    // MARK: - Matching

    /// A string as runs of one letter: `fuuck` is f1 u2 c1 k1. Repeated letters then compare by count.
    private struct Run: Equatable {
        var ch: Character
        var n: Int
    }

    private static let anywhere = rules.anywhere.map(runs)
    private static let blockedWords = rules.words.map(runs)

    private static func runs(_ s: String) -> [Run] {
        var out: [Run] = []
        for ch in s {
            if let last = out.last, last.ch == ch { out[out.count - 1].n += 1 } else { out.append(Run(ch: ch, n: 1)) }
        }
        return out
    }

    /// True when `term` matches `text` at run `at`; each letter of the term may repeat in the text.
    private static func matches(_ text: [Run], _ term: [Run], at: Int) -> Bool {
        guard at + term.count <= text.count else { return false }
        return term.indices.allSatisfy { j in text[at + j].ch == term[j].ch && text[at + j].n >= term[j].n }
    }

    private static func contains(_ text: [Run], _ term: [Run]) -> Bool {
        text.indices.contains { matches(text, term, at: $0) }
    }

    private static func equals(_ text: [Run], _ term: [Run]) -> Bool {
        text.count == term.count && matches(text, term, at: 0)
    }

    /// A whole word is the term, or the term plus a plural `s` or `es`.
    private static func isWord(_ word: String, _ term: [Run]) -> Bool {
        if equals(runs(word), term) { return true }
        if word.hasSuffix("es"), equals(runs(String(word.dropLast(2))), term) { return true }
        return word.hasSuffix("s") && equals(runs(String(word.dropLast())), term)
    }

    // MARK: - Reading text

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// Puts a space where a lower case letter meets an upper case one, so `BigWord` reads as two words.
    private static func splittingCamelCase(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in s.unicodeScalars {
            if let previous, previous.properties.generalCategory == .lowercaseLetter,
               scalar.properties.generalCategory == .uppercaseLetter {
                out.append(" ")
            }
            out.append(scalar)
            previous = scalar
        }
        return String(out)
    }

    /// The words of `text` with every ambiguous character read as its `choice`-th letter.
    private static func words(of text: String, choice: Int) -> [String] {
        var mapped = ""
        for scalar in text.lowercased().unicodeScalars {
            let key = String(scalar)
            let letter = rules.substitutions[key]
                ?? rules.ambiguous[key].map { String(Array($0)[choice]) }
                ?? key
            let scalars = letter.unicodeScalars
            mapped += scalars.count == 1 && ("a"..."z").contains(scalars.first!) ? letter : " "
        }
        // A run of single letters is one spelled-out word: "f u c k" or "f.u.c.k".
        var out: [String] = []
        var spelled = ""
        for word in mapped.split(separator: " ").map(String.init) {
            if word.count == 1 {
                spelled += word
                continue
            }
            if !spelled.isEmpty { out.append(spelled) }
            spelled = ""
            out.append(word)
        }
        if !spelled.isEmpty { out.append(spelled) }
        return out
    }
}
