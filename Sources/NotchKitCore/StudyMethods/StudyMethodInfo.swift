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

    public var label: String {
        switch self {
        case .strong: return "Well supported"
        case .mixed: return "Some evidence"
        case .weak: return "Mostly convention"
        }
    }
}

/// Copy for a study method's info popover: what it is, how to do it, and an
/// honest note on the evidence.
///
/// Wording follows the StudyNotch research notes. It is deliberately modest:
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
    public let evidenceLevel: StudyEvidenceLevel

    /// Shared footnote under every popover.
    public static let footnote = "Interval lengths are conventions. What research supports is regular breaks, testing yourself, and spacing reviews over days."

    public static func info(for kind: StudyMethodKind) -> StudyMethodInfo {
        switch kind {
        case .pomodoro:
            return StudyMethodInfo(
                kind: kind,
                name: "Pomodoro",
                tagline: "25 min focus, 5 min break",
                howTo: "Work on one thing for 25 minutes, then take a 5-minute break away from the screen. After four rounds, take a longer 15-minute break. Short, fixed rounds make it easy to start.",
                evidence: "In one study, scheduled breaks beat ad-hoc breaks for mood and efficiency (Biwer et al., 2023). The 25-minute length itself is a convention.",
                evidenceLevel: .mixed
            )
        case .fiftyTwoSeventeen:
            return StudyMethodInfo(
                kind: kind,
                name: "52 / 17",
                tagline: "52 min focus, 17 min break",
                howTo: "Focus for 52 minutes, then take a full 17-minute break. Use the break to actually rest: stand up, move, get water. Good for longer reading or question blocks.",
                evidence: "This ratio comes from a 2014 productivity-app blog post about its users, not from a study of learning. Treat it as a preset, not a finding.",
                evidenceLevel: .weak
            )
        case .ultradian:
            return StudyMethodInfo(
                kind: kind,
                name: "Ultradian",
                tagline: "90 min deep block, 20 min rest",
                howTo: "Do one deep 90-minute block, then rest for about 20 minutes. Best for hard work like a dense lecture or a long practice block. Do at most 3 or 4 of these a day.",
                evidence: "Strict 90-minute daytime cycles have little evidence. Studies of expert practice do support capping deep work at about 4 hours a day (Ericsson et al., 1993).",
                evidenceLevel: .weak
            )
        case .flowtime:
            return StudyMethodInfo(
                kind: kind,
                name: "Flowtime",
                tagline: "Study until focus slips, break scales",
                howTo: "Start the timer and study until your focus starts to slip, then stop. Your break scales with how long you worked: 5 minutes after up to 25, 8 after up to 50, 10 after that.",
                evidence: "In a 2025 comparison, Flowtime did no better or worse overall than Pomodoro or self-chosen breaks (Smits et al., 2025).",
                evidenceLevel: .mixed
            )
        case .ankiSprint:
            return StudyMethodInfo(
                kind: kind,
                name: "Anki sprint",
                tagline: "Clear a card goal, not a clock",
                howTo: "Pick a number of cards, for example 100, and go through them without stopping. The timer counts cards answered in Anki and ends when you hit the goal. Do your due reviews before adding new cards.",
                evidence: "Spaced retrieval, what Anki does, is one of the best-supported study techniques (Dunlosky et al., 2013). Links between Anki use and exam scores are correlational.",
                evidenceLevel: .strong
            )
        case .questionBlock:
            return StudyMethodInfo(
                kind: kind,
                name: "Question block",
                tagline: "40 questions in 60 min, then review",
                howTo: "Do a timed block of practice questions, up to 40 in 60 minutes, as on a real board exam. Then spend at least as long reviewing every explanation, including the ones you got right.",
                evidence: "Testing yourself, then checking answers, is among the best-supported ways to learn (Roediger & Karpicke, 2006; Dunlosky et al., 2013).",
                evidenceLevel: .strong
            )
        case .custom:
            return StudyMethodInfo(
                kind: kind,
                name: "Custom",
                tagline: "Your own focus and break lengths",
                howTo: "Set your own focus and break lengths, and optionally a longer break every few rounds. Pick a rhythm you will actually stick to.",
                evidence: "No interval is proven best. Taking regular breaks at all is what has support.",
                evidenceLevel: .mixed
            )
        }
    }

    /// Info for every method, in `StudyMethodKind.allCases` order.
    public static let all: [StudyMethodInfo] = StudyMethodKind.allCases.map(info(for:))
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
