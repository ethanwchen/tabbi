# Focus timer golden fixtures

Written by `Tests/TabbiKitCoreTests/FocusTimerGoldenTests.swift` from `FocusTimer`, `FocusTimerFormat`, `FocusTimer.provided(by:)` and `FocusPhaseCompletion.activityRecord(config:source:)`.
They pin the Pomodoro that Today, Focus and the pet coach share, so the Windows port runs the same timer.

The file has `schema` (`tabbi.focus-timer.golden`) and `version` (1).
Times are seconds since 1970 and lengths are seconds.

- `clocks`: the countdown readout (`text`) for sample `seconds`. Seconds round up, so a phase shows its full length when it starts and `0:00` only once it is over; negative time shows `0:00`.
- `sequences`: each starts from a fresh 25/5 timer (focus phase, idle, nothing finished) and lists `steps`, each an `input` and the timer after it.
  `input.action` is `start` (start, or resume from pause), `pause`, `reset` (idle focus phase, keeping the finished count), `skip` (end the phase early: the next one runs if the timer was running), `advance` (apply every phase end up to `at`) or `configure` (set `focusDuration` and `restDuration`; each is at least one second).
  Every input has `at`, the moment it happens; `reset` and `configure` ignore it, but the readouts are taken then.
  - `completions` lists the phases that ran out during the step, oldest first, each with when it ended, the notification `title` and `body`, and the `activity` record the app logs (`focus.completed` or `break.taken`, lasting the configured length and ending when the phase did).
    A finished focus phase starts the break on its own; a finished break leaves the timer idle in a focus phase.
  - `state` is the timer: `phase` (`focus` or `rest`), `run` (`idle`, `running` with `endsAt`, or `paused` with `pausedRemaining`), the lengths and `completedFocusCount`.
  - `view` is what the focus card shows at `at`: time left, ring `progress` (0 to 1), the `clock` string, the phase name and the status line.
  - `provided` is the timer as the shared focus clock the ticker, pet and Party read (`ProvidedFocus`), with its `remaining`, `elapsed` and `shownTime` at `at`.

The app calls `advance` with the current time before every user action and on each tick, so a phase that already ended is never paused with no time left.
The `pause-after-end-without-advance` sequence shows what happens when that is skipped; a port should follow the app and advance first.

A port replays only the inputs and compares every recorded output.
Compare numbers within 1e-9: `progress` is a computed fraction.
