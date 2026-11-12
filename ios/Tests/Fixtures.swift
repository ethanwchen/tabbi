import Foundation
import TabbiKitCore

/// The golden fixtures in `shared/fixtures`, copied into the test bundle by
/// project.yml. The Mac's tests write them, and the Windows port checks
/// itself against them, so the iPhone does too.
enum Fixtures {
    private final class Token {}

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle(for: Token.self).url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try Data(contentsOf: url)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from name: String) throws -> Value {
        try JSONDecoder().decode(type, from: data(name))
    }

    static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
}

/// `study-session.json`, read only as far as these tests compare it.
struct StudySessionFile: Decodable {
    let schema: String
    let version: Int
    let sequences: [Sequence]

    struct Sequence: Decodable {
        let name: String
        let method: Method
        let steps: [Step]
    }

    /// A method as the fixture writes it (shared/fixtures/study-session/README.md).
    struct Method: Decodable {
        struct Focus: Decodable {
            let kind: String
            let seconds: Double?
            let cards: Int?
        }

        struct Break: Decodable {
            let kind: String
            let seconds: Double?
            let scheme: String?
        }

        struct LongBreak: Decodable {
            let duration: Double
            let every: Int
        }

        let kind: String
        let focus: Focus
        let breakRule: Break
        let longBreak: LongBreak?
        let review: Double?
        let questionCount: Int?

        var method: StudyMethod {
            let target: StudyFocusTarget = switch focus.kind {
            case "duration": .duration(focus.seconds ?? 0)
            case "cards": .cards(focus.cards ?? 0)
            default: .openEnded
            }
            let rule: StudyBreakRule = switch breakRule.kind {
            case "fixed": .fixed(breakRule.seconds ?? 0)
            case "proportional": .proportional(FlowtimeBreakScheme(rawValue: breakRule.scheme ?? "") ?? .tiered)
            default: .none
            }
            return StudyMethod(kind: StudyMethodKind(rawValue: kind) ?? .custom, focus: target, breakRule: rule,
                               longBreak: longBreak.map { StudyLongBreak(duration: $0.duration, every: $0.every) },
                               review: review, questionCount: questionCount)
        }
    }

    struct Step: Decodable {
        let input: Input
        let ended: [Record]?
        let taken: [Record]?
        let accepted: Bool?
        let state: State
        let view: View?
        let provided: Provided?
    }

    struct Input: Decodable {
        let action: String
        let at: Double
        let count: Int?
        let method: Method?
    }

    struct Record: Decodable {
        struct Activity: Decodable {
            let kind: String
            let quantity: Double
        }

        let method: String
        let phase: String
        let startedAt: Double
        let endedAt: Double
        let activeDuration: Double
        let outcome: String
        let cards: Int?
        let activity: Activity?
    }

    struct State: Decodable {
        let phase: String
        let run: String
        let phaseDuration: Double?
        let completedFocusCount: Int
        let cardsDone: Int
        let lastFocusWorked: Double
        let elapsed: Double
        let remaining: Double?
        let endsAt: Double?
        let runningSince: Double?
        let progress: Double?
    }

    struct View: Decodable {
        let value: String
        let primaryAction: String
        let round: String?
        let caption: String
    }

    struct Provided: Decodable {
        struct Clock: Decodable {
            let kind: String
            let endsAt: Double?
            let since: Double?
            let shown: Double?
        }

        let clock: Clock
        let phase: String
        let completedFocusCount: Int
        let phaseLength: Double?
        let focusLength: Double?
    }
}
