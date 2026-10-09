# Plan my day golden fixtures

Written by `Tests/TabbiKitCoreTests/PlanMyDayGoldenTests.swift` (cases in `PlanMyDayGoldenSamples.swift`) from `DayPlanContext`, `DayPlanner`, `TodayPlanSettings`, `SchedulePlanner`, `StudyDayPlanner` and `DayPlanProposal`.
They pin what Plan my day offers for a given day, so the Windows port proposes the same blocks, breaks and reasons, sends Claude the same prompt, and reads its answers the same way.

The file has `schema` (`tabbi.plan-my-day.golden`) and `version` (1).
Times are seconds since 1970; lengths in settings are minutes.
Block starts land on five-minute marks counted from 1970 (the same marks as from 2001, which Swift uses).

- `constants`: the shortest block, the most blocks a proposal offers, the longest title Claude is asked for, the usual and latest end hours, when a local plan's working day starts, review sizing, the note on written events, and the arguments passed to `claude -p` (model, no tools, the JSON Schema of the answer).
- `days`: each has an `input` and the `output` it gives.
  - `input` holds the `timeZone` (an IANA name; every wall-clock time is resolved in it), `now`, the calendar `events` (all-day events never block time), Today's checklist `tasks` (`id` is the item's UUID), what other modules share in tab order (`provided`: open `tasks` with estimates and `progress` goals), the kit's planner `settings` (`planMode` is `local`, `study` or `claude`, plus the kit's `studyMethod`), and Claude result texts: `answers` to the plan prompt and `refineAnswers` to the refine prompt.
  - Every day is planned all three ways, whatever its `planMode`:
    `sharedWork` is the other modules' work as the prompt phrases it, `dayEnd` and `gaps` the free time Claude may use, and `taskKeys` the short ids (`t1`, ...) the prompt and answers use, each `key=UUID` or `key=shared work`.
    `local` is the on-device plan: its `preferences`, the `work` ids in the order they were handed over, `day` (midnight), `blocks` with `workID`, `reason` and `part` of `parts`, `breaks`, `unplaced` work with minutes left and why, and `focusMinutes`.
    `study` is the study-day plan: `preferences`, the `reviews` it sized from the goals, `blocks` and `breaks`.
    `prompt` is the full Claude prompt, and each `claude` entry is one answer with what the parser read (`parsed`, absent when no JSON was found) and what the validator kept (`proposal`).
    `refinePrompt` asks Claude to improve the local plan, and each `refinements` entry has the validated `blocks` (absent when no JSON was found) and the proposal after refining: `pending`, `breaks` and `refinement` (`changed`, `unchanged`, or absent when nothing ran).
    `outcome` is what the panel shows for the day's `planMode`: `noFreeTime` when there are no `gaps` or nothing could be planned, `failed` when Claude's (first) answer had no JSON, or `proposal` with its `blocks` and `breaks`.
  - A block has `start`, `end`, `title`, `task` (the linked checklist UUID, when there is one) and `kind` (`focus`, `reviews` or `study`).
- `proposals`: each starts a proposal from `blocks` (with `id`s) and `breaks`, then runs `steps`.
  A step's `input` is `dismiss` (block `id`), `refine` (with `blocks`) or `add` (the blocks `ids`, every pending one when absent, at `at` with the calendar `events` as it is then, through a writer that throws when `writerFails`).
  It records the events `written`, whether the writer `threw`, and the proposal after it: `pending`, `breaksAfter` (the rest shown after each pending block, or null), `breaks`, `addedCount`, `skippedCount`, `refinement` and `isSettled`.

Rules the fixture pins that are easy to miss:

- The day ends at the kit's `dayEndHour`, or two hours from now when that is later, but never after 22:00; from 22:00 nothing is planned.
  The local planner's working day starts at 9:00, or two hours before the end when that is earlier.
- Claude's answer may be fenced, wrapped in prose, or a bare array; `H:mm` and `24:00` are read, a one-digit minute is not.
  Task ids are the short keys in any case, or a checklist UUID, under `task`, `taskId` or `linkedTaskID`; unknown ones just leave the block unlinked.
  A shared-work key (`t4` beside three checklist items) links nothing.
- Validation clips each block to the free time, keeping its longest piece, trims a block that overlaps the one before it, drops anything under 15 minutes and keeps at most five.
- A refinement keeps the kind of the local block for the same task, or else with the same title, ignoring case; a refined plan may keep more than five blocks if the local plan had more.
- On `add`, a block that has started begins on the next five-minute mark, a meeting that now overlaps it leaves its longest free piece, and one with less than 15 minutes left is skipped and counted.
  A writer that throws changes nothing.
- The local planner leaves out goals that `waitsForStart` (a daily focus goal), but the study-day planner and the Claude prompt do not, so a study day plans a review block named after Study's daily study-time goal.
  The fixture records that behavior as it is today.
- Shared work counts (`180 cards left`) stay below 1,000, so no locale's grouping separator appears in the prompt.

A port replays only the inputs and compares every recorded output.
