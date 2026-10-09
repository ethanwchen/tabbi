import Foundation
import TabbiKitCore
import XCTest

/// Pins every study method to the golden fixture
/// `shared/fixtures/study-methods/study-methods.json`.
///
/// The fixture was written by the Swift study methods before they moved to
/// JSON, so it proves the move changes no length, label or rule, and the
/// Windows port checks its own timer rules against the same file.
/// Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an intended change.
final class StudyMethodGoldenTests: XCTestCase {
    func testStudyMethodsMatchGoldenFixture() throws {
        let url = StudyMethodGoldenFixture.folder.appendingPathComponent("study-methods.json")
        let current = StudyMethodGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: StudyMethodGoldenFixture.folder, withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(StudyMethodGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.methods.map(\.kind), current.methods.map(\.kind))
        for (old, new) in zip(stored.methods, current.methods) {
            XCTAssertEqual(old, new, "Method \(old.kind) changed")
        }
        XCTAssertEqual(stored, current, "The study methods no longer match \(url.lastPathComponent)")
    }
}

/// Every study method resolved to what the timer and the picker use: its
/// parameters, phase lengths, the phase order over several rounds, labels and
/// info copy, plus the limits and rules around them (Flowtime breaks, sprint
/// goals, Timer and Custom steppers).
struct StudyMethodGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.study-methods.golden"

    static var folder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/study-methods")
    }

    struct Method: Codable, Equatable {
        var kind: String
        /// `duration`, `openEnded` or `cards`.
        var focusTarget: String
        /// Length of a timed focus phase; absent for open or card focus.
        var focusSeconds: Double?
        var cardGoal: Int?
        /// `fixed`, `proportional:<scheme>` or `none`.
        var breakRule: String
        var longBreakSeconds: Double?
        var longBreakEvery: Int?
        var reviewSeconds: Double?
        var questionCount: Int?
        var hasBreaks: Bool
        var rhythmLabel: String
        var nameIsRhythm: Bool
        /// Phase name to its length with nothing worked before the break;
        /// absent when the phase has no length.
        var phaseSeconds: [String: Double]
        /// The phases a session walks through from its first focus, for
        /// eight focus rounds.
        var phaseSequence: [String]
        var name: String
        var tagline: String
        var howTo: String
        var howToSentencePrefixes: [String]
        var evidence: String
        var evidenceLevel: String?
    }

    struct FlowtimeBreak: Codable, Equatable {
        var workedSeconds: Double
        /// Scheme name to the break it gives, in seconds.
        var breakSeconds: [String: Double]
    }

    struct SprintGoal: Codable, Equatable {
        var reviewDue: Int
        var learnDue: Int
        var goal: Int
    }

    struct TimerStep: Codable, Equatable {
        var minutes: Int
        var up: Int
        var down: Int
    }

    struct Stepper: Codable, Equatable {
        var min: Int
        var max: Int
        var step: Int
    }

    var schema = schemaName
    var version = 1
    var footnote: String
    var evidenceLabels: [String: String]
    var minimumPhaseSeconds: Double
    var maximumPhaseSeconds: Double
    var defaultSprintCards: Int
    var sprintBreakCards: Int
    var sprintBreakSeconds: Double
    var methods: [Method]
    var flowtimeBreaks: [FlowtimeBreak]
    var sprintGoals: [SprintGoal]
    var timerMinMinutes: Int
    var timerMaxMinutes: Int
    /// What one stepper click up or down makes of a Timer length.
    var timerSteps: [TimerStep]
    var timerPresetMinutes: [Int]
    var timerStandardMinutes: Int
    /// Custom field name to its stepper (minutes, or rounds for `longBreakEvery`).
    var customFields: [String: Stepper]
    var customStandard: [String: Int]
    var customStandardHasLongBreak: Bool

    static func current() -> StudyMethodGoldenFixture {
        let worked: [TimeInterval] = [0, 59, 60, 300, 450, 1500, 1501, 3000, 3001, 3150, 5400, 14400]
        let flowtimeBreaks = worked.map { worked in
            var breaks: [String: Double] = [:]
            for scheme in FlowtimeBreakScheme.allCases {
                breaks[scheme.rawValue] = scheme.breakDuration(afterWorking: worked)
            }
            return FlowtimeBreak(workedSeconds: worked, breakSeconds: breaks)
        }
        let dues: [(Int, Int)] = [(0, 0), (12, 3), (0, 7), (-5, 0), (250, 40)]
        let sprintGoals = dues.map { review, learn in
            SprintGoal(reviewDue: review, learnDue: learn, goal: StudyMethod.sprintGoal(reviewDue: review, learnDue: learn))
        }
        let timerSteps = [1, 2, 9, 10, 11, 23, 25, 179, 180].map { minutes in
            let length = StudyTimerLength(minutes: minutes)
            return TimerStep(minutes: minutes, up: length.stepped(up: true).minutes, down: length.stepped(up: false).minutes)
        }
        let custom = StudyCustomRhythm.standard
        var customFields: [String: Stepper] = [:]
        var customStandard: [String: Int] = [:]
        for field in StudyCustomRhythm.Field.allCases {
            customFields[field.rawValue] = Stepper(min: field.range.lowerBound, max: field.range.upperBound, step: field.step)
            customStandard[field.rawValue] = custom[field]
        }
        var evidenceLabels: [String: String] = [:]
        for level in StudyEvidenceLevel.allCases {
            evidenceLabels[level.rawValue] = level.label
        }
        return StudyMethodGoldenFixture(
            footnote: StudyMethodInfo.footnote,
            evidenceLabels: evidenceLabels,
            minimumPhaseSeconds: StudyMethod.minimumPhase,
            maximumPhaseSeconds: StudyMethod.maximumPhase,
            defaultSprintCards: StudyMethod.defaultSprintCards,
            sprintBreakCards: StudyMethod.sprintBreakCards,
            sprintBreakSeconds: StudyMethod.sprintBreakInterval,
            methods: StudyMethod.presets.map(method),
            flowtimeBreaks: flowtimeBreaks,
            sprintGoals: sprintGoals,
            timerMinMinutes: StudyTimerLength.range.lowerBound,
            timerMaxMinutes: StudyTimerLength.range.upperBound,
            timerSteps: timerSteps,
            timerPresetMinutes: StudyTimerLength.presets,
            timerStandardMinutes: StudyTimerLength.standard.minutes,
            customFields: customFields,
            customStandard: customStandard,
            customStandardHasLongBreak: custom.hasLongBreak
        )
    }

    private static func method(_ method: StudyMethod) -> Method {
        let info = method.info
        var focusTarget = "duration"
        var focusSeconds: Double?
        switch method.focus {
        case .duration(let length): focusSeconds = length
        case .openEnded: focusTarget = "openEnded"
        case .cards: focusTarget = "cards"
        }
        let breakRule = switch method.breakRule {
        case .fixed: "fixed"
        case .proportional(let scheme): "proportional:\(scheme.rawValue)"
        case .none: "none"
        }
        var phaseSeconds: [String: Double] = [:]
        for phase in StudyPhaseKind.allCases {
            phaseSeconds[phase.rawValue] = method.duration(of: phase)
        }
        var sequence = [StudyPhaseKind.focus]
        var completed = 1
        while completed <= 8 {
            let next = method.nextPhase(after: sequence.last!, completedFocusCount: completed)
            if next == .focus { completed += 1 }
            sequence.append(next)
        }
        return Method(
            kind: method.kind.rawValue, focusTarget: focusTarget, focusSeconds: focusSeconds, cardGoal: method.cardGoal,
            breakRule: breakRule, longBreakSeconds: method.longBreak?.duration, longBreakEvery: method.longBreak?.every,
            reviewSeconds: method.review, questionCount: method.questionCount, hasBreaks: method.hasBreaks,
            rhythmLabel: method.rhythmLabel, nameIsRhythm: method.nameIsRhythm, phaseSeconds: phaseSeconds,
            phaseSequence: sequence.map(\.rawValue), name: info.name, tagline: info.tagline, howTo: info.howTo,
            howToSentencePrefixes: info.howToSentencePrefixes, evidence: info.evidence,
            evidenceLevel: info.evidenceLevel?.rawValue
        )
    }
}
