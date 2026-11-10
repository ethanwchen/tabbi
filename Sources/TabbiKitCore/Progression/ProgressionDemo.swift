import Foundation

extension PetProgression {
    /// The `TABBI_DEMO=1` Goals shelf, a few months in: the same focus as
    /// the milestones' demo (`PetMilestoneProgress.demoRecords`), with the
    /// newest stretches run with three study methods and the last three
    /// finished with friends in Party, plus flashcards, tasks, break moves
    /// and water on the study days. Most badges are at Bronze or Silver,
    /// three mastery outfits are earned (Little Sprout, Apprentice Robe and
    /// Explorer's Hat), and this month's quests are part of the way.
    public static func demo(today: Date, calendar: Calendar = .current) -> PetProgression {
        let focus = PetMilestoneProgress.demoRecords(today: today, calendar: calendar)
        let methods = ["pomodoro", StudyMethodKind.fiftyTwoSeventeen.rawValue, StudyMethodKind.flowtime.rawValue]
        var records: [ActivityRecord] = []
        for (index, record) in focus.enumerated() {
            let fromEnd = focus.count - 1 - index
            var metadata = record.metadata
            metadata[ActivityMetadata.method] = methods[index % methods.count]
            var source = record.source
            if fromEnd < 3 {
                source = .party
                metadata[ActivityMetadata.outcome] = StudyPhaseOutcome.completed.rawValue
                metadata[PartySessionCompletion.friendsKey] = "2"
            }
            records.append(ActivityRecord(id: record.id, source: source, kind: record.kind, start: record.start,
                                          end: record.end, quantity: record.quantity, unit: record.unit,
                                          metadata: metadata))
            let end = record.end
            // A second finished block on two days in three, so the demo's
            // session count passes the Apprentice Robe's 75.
            if index % 3 != 0 {
                records.append(ActivityRecord(source: record.source, kind: .focusCompleted,
                                              start: end.addingTimeInterval(1800), end: end.addingTimeInterval(3300),
                                              quantity: 25, unit: .minutes, metadata: metadata))
            }
            records.append(ActivityRecord(source: .anki, kind: .cardsReviewed, start: end, quantity: 45, unit: .cards))
            if index % 3 == 0 {
                records.append(ActivityRecord(source: .planner, kind: .taskCompleted, start: end, quantity: 1,
                                              subject: "demo-task-\(index)"))
            }
            if index % 2 == 0 {
                records.append(WaterTally.water(at: end))
                records.append(WaterTally.water(at: end.addingTimeInterval(60)))
            }
            if index % 4 == 0 { records.append(WaterTally.move(.stretch, at: end)) }
        }
        var progression = PetProgression(tally: ProgressTally(records: records, calendar: calendar))
        progression.refresh(at: today, calendar: calendar)
        progression.markSeen()
        return progression
    }
}
