# Study method golden fixtures

Written by `Tests/TabbiKitCoreTests/StudyMethodGoldenTests.swift` from the Swift study methods.
`study-methods.json` was first recorded while the methods were still Swift, so it proves the move to `Sources/TabbiKitCore/StudyMethods/study-methods.json` changed no length, label or rule.

The file has `schema` (`tabbi.study-methods.golden`) and `version` (1).
Lengths are seconds, as the timer counts them, where the data file writes minutes.

- `methods`: every method in picker order, resolved to what the timer and the picker use.
  `focusTarget` is `duration` (with `focusSeconds`), `openEnded` or `cards` (with `cardGoal`), and `breakRule` is `fixed`, `proportional:<scheme>` or `none`.
  `phaseSeconds` maps each phase (`focus`, `review`, `shortBreak`, `longBreak`) to its length with nothing worked before the break, and leaves out a phase that has none.
  `phaseSequence` is the phase order from the first focus through eight focus rounds, which pins `nextPhase` and the long break spacing.
  `rhythmLabel`, `nameIsRhythm` and `howToSentencePrefixes` are what the views show, beside the info copy.
- `footnote` and `evidenceLabels`: the text under every info popover and each evidence badge.
- `minimumPhaseSeconds` and `maximumPhaseSeconds`: the clamp on every timed phase.
- `defaultSprintCards`, `sprintBreakCards`, `sprintBreakSeconds` and `sprintGoals`: an Anki sprint's card goal (inputs `reviewDue` and `learnDue`, output `goal`) and when it suggests a break.
- `flowtimeBreaks`: the break each Flowtime scheme gives after `workedSeconds`, around every tier edge.
- `timerMinMinutes`, `timerMaxMinutes`, `timerPresetMinutes`, `timerStandardMinutes` and `timerSteps`: the Timer's range, one-click lengths, starting length, and what one stepper click up or down makes of a length.
- `customFields`, `customStandard` and `customStandardHasLongBreak`: each Custom stepper's range and step, and the rhythm a fresh Custom method starts with.
