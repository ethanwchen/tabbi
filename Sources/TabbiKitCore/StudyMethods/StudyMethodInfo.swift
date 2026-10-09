import Foundation

/// How strong the evidence behind a method's specific rhythm is.
///
/// Shown as a small badge so users can see at a glance which presets are
/// conventions and which rest on well-supported learning techniques.
public enum StudyEvidenceLevel: String, Codable, CaseIterable, Hashable, Sendable {
    /// The underlying technique (retrieval or spaced practice) is well supported.
    case strong
    /// Some experimental support, but no proof that this rhythm is best.
    case mixed
    /// Mostly convention or correlational data.
    case weak

    /// The badge text, from `study-methods.json`.
    public var label: String { StudyMethodDefinitions.file.evidenceLevels[self] ?? rawValue }
}

/// Copy for a study method's info popover: what it is, how to do it, and an
/// honest note on the evidence.
///
/// The copy lives in `study-methods.json`. Wording follows the Tabbi study research notes. It is deliberately modest:
/// what research supports is regular breaks, self-testing, and spacing, not
/// any particular interval length, so no note claims a rhythm is proven.
public struct StudyMethodInfo: Hashable, Sendable {
    public let kind: StudyMethodKind
    public let name: String
    /// One-line description for the method picker.
    public let tagline: String
    /// Plain-language instructions, 2 to 3 sentences.
    public let howTo: String
    /// One or two sentences on what the evidence does and does not show.
    public let evidence: String
    /// The badge rating, or nil for a plain tool that is not a study method
    /// (the Timer), which shows no rating or evidence note at all.
    public let evidenceLevel: StudyEvidenceLevel?

    /// Shared footnote under every popover.
    public static let footnote = StudyMethodDefinitions.file.footnote

    /// The copy `study-methods.json` gives `kind`; the file defines every kind.
    public static func info(for kind: StudyMethodKind) -> StudyMethodInfo {
        byKind[kind] ?? StudyMethodDefinitions.file.methods[0].info
    }

    private static let byKind = Dictionary(uniqueKeysWithValues: StudyMethodDefinitions.file.methods.map { ($0.kind, $0.info) })

    /// Info for every method, in `StudyMethodKind.allCases` order.
    public static let all: [StudyMethodInfo] = StudyMethodKind.allCases.map(info(for:))

    /// `howTo` cut after its first sentence, its first two, and so on up to
    /// the whole text, so a small card can show as many whole sentences as
    /// fit instead of cutting one off mid-way.
    public var howToSentencePrefixes: [String] {
        let sentences = howTo.components(separatedBy: ". ")
        return sentences.indices.map { end in
            let prefix = sentences[...end].joined(separator: ". ")
            return end == sentences.count - 1 ? prefix : prefix + "."
        }
    }
}

public extension StudyMethod {
    /// Popover copy for this method's kind.
    var info: StudyMethodInfo { StudyMethodInfo.info(for: kind) }

    /// Whether the method's name already spells out its rhythm ("52 / 17"),
    /// so views show the name alone instead of "52 / 17 52/17".
    var nameIsRhythm: Bool {
        info.name.replacingOccurrences(of: " ", with: "") == rhythmLabel
    }
}
