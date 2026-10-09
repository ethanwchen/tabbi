# Study session golden fixtures

Written by `Tests/TabbiKitCoreTests/StudySessionGoldenTests.swift` from `StudySession`, `StudyTimerFormat`, `StudyPetCue`, `FocusActivity(_:deepFocus:)`, `StudySession.sharedFocus(by:isDeep:at:)` and `StudyPhaseRecord.activityRecord(source:)`.
They pin the Study tab's timer for every study method, so the Windows port runs the same sessions.

The file has `schema` (`tabbi.study-session.golden`) and `version` (1), plus `minimumLoggedDuration`: phases shorter than this many seconds are logged but get no activity record.
Times are seconds since 1970 and lengths are seconds.

- `labels`: the dial's `clocks` (seconds round up, and an hour field appears only when needed), `studied` minutes (`45 min`, `1h 5m`) and day-tally `points` (`+1 pt`, `+79 pts`).
- `sequences`: each starts from a fresh session on `method` (focus phase, idle, nothing finished) and lists `steps`, each an `input` and the session after it.
  A method has `kind`, `focus` (`duration` with `seconds`, `openEnded`, or `cards` with `cards`), `breakRule` (`fixed` with `seconds`, `proportional` with a Flowtime `scheme`, or `none`), and optional `longBreak` (`duration`, `every`), `review` and `questionCount`.
  Building a method clamps it: lengths to 1 min...4 h, `every` to at least 2, card goals and question counts to at least 1.
  Inputs carry the method as written; `state.method` is the clamped one, with its `rhythmLabel`.
  `input.action` is one of:
  - `start` (start an idle phase or resume a paused one), `pause`, `skip` (end the phase early; the next one runs if the clock was running and the method has breaks), `stopFocus` (end a started Flowtime focus phase; `accepted` says whether it did), `reset` (back to an idle first focus phase), `switchMethod` (start over on `method`), `retune` (take on `method`'s lengths if it is the same kind; `accepted` says whether it did);
  - `reviewed` (Anki's reviewed-today `count`; the first count after a sprint starts or resumes only sets the baseline, and only increases seen while a sprint's focus runs count as cards), `advance` (apply every phase end up to `at`), and `takeLog` (hand over and clear the logged phases, in `taken`).

  Every input has `at`, the moment it happens.
  - `ended` lists the phases that `advance` or `reviewed` ended during the step, oldest first.
    Each record has its method, phase, start, end, the `activeDuration` the clock ran, the `outcome` (`completed`, `stopped`, `skipped` or `abandoned`), `cards` for a sprint's focus, and the `activity` record the app logs (`focus.completed` for focus and review, `break.taken` for breaks, in minutes), absent for a phase under a minute.
  - `state` is the session: method, `phase` (`focus`, `review`, `shortBreak`, `longBreak`), `run` (`idle`, `running`, `paused`), `phaseDuration` (absent for open-ended or card-goal focus), counts, `lastFocusWorked`, and at `at` its `elapsed`, `remaining`, `runningSince`, `endsAt`, `progress` and `suggestsSprintBreak`, plus the `log` not yet taken.
  - `view` is what the Study tab shows: the dial's `value`, `caption` and `countsDown`, the `round` label, the `primaryAction` button title, whether the pet dozes, the `petEvents` this step caused (`wake`, `sleep`, `celebrate`), and what the session asks of focus mode with deep focus on (`focusing`, `interrupted`, `idle`).
  - `provided` is the session as the shared focus clock (`ProvidedFocus`, in the same form as `focus-timer.json`), absent while the session is idle.
    Phases with no length count up from `runningSince`.

Rules that are easy to miss:

- A finished focus or review phase starts the next phase on its own; a finished break, or a Timer's countdown, leaves an idle focus phase.
- A skipped focus phase never counts as done and never leads to a long break.
- `retune` gives a started phase its new length, but no less than a minute more than it has already run.
- Skipping an idle phase moves on without logging anything.
- The app calls `advance` with the current time before every action and on each tick, and feeds the latest card count right after every action.
  The `skips` sequence pauses a break that already ran out without advancing first, which leaves it paused at `0:00`; a port should follow the app and advance first.

A port replays only the inputs and compares every recorded output.
Compare numbers within 1e-9: `progress` is a computed fraction.
