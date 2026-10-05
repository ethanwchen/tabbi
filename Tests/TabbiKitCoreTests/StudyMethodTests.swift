import XCTest
import TabbiKitCore

final class StudyMethodTests: XCTestCase {
    private let minute: TimeInterval = 60

    // MARK: Presets

    func testPomodoroIsTwentyFiveFiveWithLongBreakEveryFour() {
        let method = StudyMethod.pomodoro
        XCTAssertEqual(method.duration(of: .focus), 25 * minute)
        XCTAssertEqual(method.duration(of: .shortBreak), 5 * minute)
        XCTAssertEqual(method.duration(of: .longBreak), 15 * minute)
        XCTAssertEqual(method.longBreak?.every, 4)
        XCTAssertEqual(method.rhythmLabel, "25/5")
    }

    func testPomodoroLongBreakFollowsEveryFourthFocus() {
        let method = StudyMethod.pomodoro
        let breaks = (1...8).map { method.nextPhase(after: .focus, completedFocusCount: $0) }
        XCTAssertEqual(breaks, [
            .shortBreak, .shortBreak, .shortBreak, .longBreak,
            .shortBreak, .shortBreak, .shortBreak, .longBreak,
        ])
    }

    func testBreaksAlwaysLeadBackToFocus() {
        for method in StudyMethod.presets {
            XCTAssertEqual(method.nextPhase(after: .shortBreak, completedFocusCount: 1), .focus)
            XCTAssertEqual(method.nextPhase(after: .longBreak, completedFocusCount: 4), .focus)
        }
    }

    func testFiftyTwoSeventeenAndUltradianHaveNoLongBreak() {
        XCTAssertEqual(StudyMethod.fiftyTwoSeventeen.duration(of: .focus), 52 * minute)
        XCTAssertEqual(StudyMethod.fiftyTwoSeventeen.duration(of: .shortBreak), 17 * minute)
        XCTAssertEqual(StudyMethod.ultradian.duration(of: .focus), 90 * minute)
        XCTAssertEqual(StudyMethod.ultradian.duration(of: .shortBreak), 20 * minute)
        for method in [StudyMethod.fiftyTwoSeventeen, .ultradian] {
            XCTAssertNil(method.longBreak)
            XCTAssertEqual(method.nextPhase(after: .focus, completedFocusCount: 4), .shortBreak)
            // Without a long break configured, asking for one falls back to the short one.
            XCTAssertEqual(method.duration(of: .longBreak), method.duration(of: .shortBreak))
        }
        XCTAssertEqual(StudyMethod.ultradian.rhythmLabel, "90/20")
    }

    func testFlowtimeFocusIsOpenEndedWithTieredBreaks() {
        let method = StudyMethod.flowtime
        XCTAssertEqual(method.focus, .openEnded)
        XCTAssertNil(method.duration(of: .focus))
        XCTAssertEqual(method.duration(of: .shortBreak, workedBeforeBreak: 10 * minute), 5 * minute)
        XCTAssertEqual(method.duration(of: .shortBreak, workedBeforeBreak: 25 * minute), 5 * minute)
        XCTAssertEqual(method.duration(of: .shortBreak, workedBeforeBreak: 25 * minute + 1), 8 * minute)
        XCTAssertEqual(method.duration(of: .shortBreak, workedBeforeBreak: 50 * minute), 8 * minute)
        XCTAssertEqual(method.duration(of: .shortBreak, workedBeforeBreak: 120 * minute), 10 * minute)
        XCTAssertEqual(method.rhythmLabel, "Open")
    }

    func testFlowtimeFifthSchemeScalesAndRoundsToWholeMinutes() {
        let scheme = FlowtimeBreakScheme.fifth
        XCTAssertEqual(scheme.breakDuration(afterWorking: 50 * minute), 10 * minute)
        XCTAssertEqual(scheme.breakDuration(afterWorking: 37 * minute), 7 * minute)
        XCTAssertEqual(scheme.breakDuration(afterWorking: 90 * minute), 18 * minute)
        // A very short stretch still earns a one-minute break.
        XCTAssertEqual(scheme.breakDuration(afterWorking: 30), minute)
        XCTAssertEqual(scheme.breakDuration(afterWorking: -5), minute)
        XCTAssertEqual(StudyMethod.flowtime(scheme: .fifth).duration(of: .shortBreak, workedBeforeBreak: 60 * minute), 12 * minute)
    }

    func testAnkiSprintCountsCardsNotMinutes() {
        let method = StudyMethod.ankiSprint(cards: 150)
        XCTAssertEqual(method.cardGoal, 150)
        XCTAssertNil(method.duration(of: .focus))
        XCTAssertEqual(method.duration(of: .shortBreak), 5 * minute)
        XCTAssertEqual(method.rhythmLabel, "150 cards")
        XCTAssertEqual(StudyMethod.ankiSprint().cardGoal, StudyMethod.defaultSprintCards)
        XCTAssertEqual(StudyMethod.ankiSprint(cards: 0).cardGoal, 1)
    }

    func testSprintGoalClearsReviewsAndLearningFirst() {
        XCTAssertEqual(StudyMethod.sprintGoal(reviewDue: 180, learnDue: 24), 204)
        XCTAssertEqual(StudyMethod.sprintGoal(reviewDue: 0, learnDue: 0), StudyMethod.defaultSprintCards)
        XCTAssertEqual(StudyMethod.sprintGoal(reviewDue: -3, learnDue: 7), 7)
    }

    func testQuestionBlockReviewsBeforeBreaking() {
        let method = StudyMethod.questionBlock
        XCTAssertEqual(method.duration(of: .focus), 60 * minute)
        XCTAssertEqual(method.questionCount, 40)
        XCTAssertEqual(method.nextPhase(after: .focus, completedFocusCount: 1), .review)
        XCTAssertEqual(method.duration(of: .review), 60 * minute)
        XCTAssertEqual(method.nextPhase(after: .review, completedFocusCount: 1), .shortBreak)
        XCTAssertEqual(method.duration(of: .shortBreak), 10 * minute)
        XCTAssertEqual(method.rhythmLabel, "60+60/10")
    }

    func testMethodsWithoutReviewHaveNoReviewDuration() {
        XCTAssertNil(StudyMethod.pomodoro.duration(of: .review))
    }

    // MARK: Custom and clamping

    func testCustomMethodUsesGivenLengths() {
        let method = StudyMethod.custom(
            focus: 40 * minute,
            breakLength: 8 * minute,
            longBreak: StudyLongBreak(duration: 25 * minute, every: 3)
        )
        XCTAssertEqual(method.kind, .custom)
        XCTAssertEqual(method.duration(of: .focus), 40 * minute)
        XCTAssertEqual(method.duration(of: .shortBreak), 8 * minute)
        XCTAssertEqual(method.nextPhase(after: .focus, completedFocusCount: 3), .longBreak)
        XCTAssertEqual(method.duration(of: .longBreak), 25 * minute)
        XCTAssertEqual(method.rhythmLabel, "40/8")
    }

    func testCustomLengthsAreClampedToSaneBounds() {
        let tiny = StudyMethod.custom(focus: 0, breakLength: -10)
        XCTAssertEqual(tiny.duration(of: .focus), StudyMethod.minimumPhase)
        XCTAssertEqual(tiny.duration(of: .shortBreak), StudyMethod.minimumPhase)
        let huge = StudyMethod.custom(focus: 24 * 60 * minute, breakLength: 10 * 60 * minute)
        XCTAssertEqual(huge.duration(of: .focus), StudyMethod.maximumPhase)
        XCTAssertEqual(huge.duration(of: .shortBreak), StudyMethod.maximumPhase)
        let long = StudyLongBreak(duration: 0, every: 1)
        XCTAssertEqual(long.duration, StudyMethod.minimumPhase)
        XCTAssertEqual(long.every, 2, "A long break every round would replace every short break")
    }

    func testNonFiniteLengthsAreClamped() {
        let method = StudyMethod.custom(
            focus: .nan,
            breakLength: .infinity,
            longBreak: StudyLongBreak(duration: .nan, every: 4)
        )
        XCTAssertEqual(method.duration(of: .focus), StudyMethod.minimumPhase)
        XCTAssertEqual(method.duration(of: .shortBreak), StudyMethod.maximumPhase)
        XCTAssertEqual(method.longBreak?.duration, StudyMethod.minimumPhase)
        XCTAssertEqual(method.rhythmLabel, "1/240")
        XCTAssertEqual(FlowtimeBreakScheme.fifth.breakDuration(afterWorking: .nan), minute)
        XCTAssertEqual(FlowtimeBreakScheme.tiered.breakDuration(afterWorking: .infinity), 5 * minute)
    }

    func testDecodingAppliesTheSameClamps() throws {
        let json = #"""
        {"kind":"custom","focus":{"cards":{"_0":0}},"breakRule":{"fixed":{"_0":0}},
         "longBreak":{"duration":0,"every":0},"review":0,"questionCount":0}
        """#
        let method = try JSONDecoder().decode(StudyMethod.self, from: Data(json.utf8))
        XCTAssertEqual(method.cardGoal, 1)
        XCTAssertEqual(method.duration(of: .shortBreak), StudyMethod.minimumPhase)
        XCTAssertEqual(method.longBreak, StudyLongBreak(duration: 0, every: 0))
        XCTAssertEqual(method.longBreak?.every, 2)
        XCTAssertEqual(method.review, StudyMethod.minimumPhase)
        XCTAssertEqual(method.questionCount, 1)
        XCTAssertEqual(method.nextPhase(after: .review, completedFocusCount: 2), .longBreak)
    }

    func testZeroFocusCountNeverPicksLongBreak() {
        XCTAssertEqual(StudyMethod.pomodoro.nextPhase(after: .focus, completedFocusCount: 0), .shortBreak)
    }

    // MARK: Catalogue and persistence

    func testPresetsCoverEveryKindOnceInPickerOrder() {
        XCTAssertEqual(StudyMethod.presets.map(\.kind), StudyMethodKind.allCases)
        for kind in StudyMethodKind.allCases {
            XCTAssertEqual(StudyMethod.preset(kind).kind, kind)
        }
    }

    func testMethodsRoundTripThroughCodable() throws {
        let methods = StudyMethod.presets + [
            .flowtime(scheme: .fifth),
            .custom(focus: 33 * minute, breakLength: 7 * minute, longBreak: StudyLongBreak(duration: 20 * minute, every: 3)),
        ]
        let data = try JSONEncoder().encode(methods)
        XCTAssertEqual(try JSONDecoder().decode([StudyMethod].self, from: data), methods)
    }

    func testPhaseKindBreakFlag() {
        XCTAssertEqual(StudyPhaseKind.allCases.filter(\.isBreak), [.shortBreak, .longBreak])
    }

    // MARK: Info copy

    func testEveryMethodHasConciseHowToAndEvidence() {
        XCTAssertEqual(StudyMethodInfo.all.map(\.kind), StudyMethodKind.allCases)
        for info in StudyMethodInfo.all {
            XCTAssertFalse(info.name.isEmpty)
            XCTAssertFalse(info.tagline.isEmpty)
            let howToSentences = sentenceCount(info.howTo)
            XCTAssertTrue((2...3).contains(howToSentences), "\(info.kind) how-to has \(howToSentences) sentences")
            XCTAssertTrue((1...2).contains(sentenceCount(info.evidence)), "\(info.kind) evidence is too long")
            XCTAssertLessThanOrEqual(info.howTo.count, 260, "\(info.kind) how-to won't fit a popover")
            XCTAssertFalse(info.howTo.contains("\u{2014}") || info.evidence.contains("\u{2014}"), "No em dashes in copy")
        }
    }

    func testEvidenceNotesNeverOverclaim() {
        let overclaims = ["proven", "guarantee", "scientifically", "best method", "optimal"]
        for info in StudyMethodInfo.all {
            let text = (info.howTo + " " + info.evidence + " " + info.tagline).lowercased()
            for word in overclaims {
                let negated = text.contains("no interval is proven") && word == "proven"
                XCTAssertTrue(negated || !text.contains(word), "\(info.kind) says '\(word)'")
            }
        }
    }

    func testEvidenceLevelsMatchResearch() {
        XCTAssertEqual(StudyMethodInfo.info(for: .ankiSprint).evidenceLevel, .strong)
        XCTAssertEqual(StudyMethodInfo.info(for: .questionBlock).evidenceLevel, .strong)
        XCTAssertEqual(StudyMethodInfo.info(for: .fiftyTwoSeventeen).evidenceLevel, .weak)
        XCTAssertEqual(StudyMethodInfo.info(for: .ultradian).evidenceLevel, .weak)
        XCTAssertEqual(StudyMethod.pomodoro.info.name, "Pomodoro")
        XCTAssertEqual(Set(StudyEvidenceLevel.allCases.map(\.label)).count, 3)
        XCTAssertTrue(StudyMethodInfo.footnote.contains("conventions"))
    }

    private func sentenceCount(_ text: String) -> Int {
        // "et al." and "e.g." are not sentence ends.
        let cleaned = text.replacingOccurrences(of: "et al.", with: "et al").replacingOccurrences(of: "e.g.", with: "eg")
        return cleaned.split(whereSeparator: { ".!?".contains($0) })
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
}
