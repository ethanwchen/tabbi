# Ticker golden fixtures

Written by `Tests/TabbiKitCoreTests/TickerGoldenTests.swift` from `TickerSources`, `TickerItem`, `TickerFormat` and `TickerRotation`.
They pin what the closed notch shows beside the hardware cutout, so the Windows port picks the same line at the same moment.

The file has `schema` (`tabbi.ticker.golden`) and `version` (1).
Times are seconds since 1970 and lengths are seconds.

- `constants`: a meeting pins once it starts within `pinLeadTime` (or is under way), a meeting further out than `meetingHorizon` stays hidden, the pet dozes off after `petSleepAfter` without a session, and the party shows at most `maxPartyPets` pets.
- `kinds`: the built-in kinds in rotation order, `leading` ones before the module highlights and `trailing` ones after, each with the module it needs (none for `focus` and `progress`, which any module can provide).
  A module highlight's kind is the module id.
- `selections`: each has `sources`, what the enabled modules provide, and `reads` of them at `at`.
  - `sources` holds calendar `events` (`meetingLink` only matters for `canJoin`), `isMusicPlaying`, the shared `focus` clock (`clock.kind` is `idle`, `countdown` with `endsAt`, `countUp` with `since`, or `paused` with `shown`; no `phaseLength` means it counts up), `tasksRemaining`, `progress` goals and module `highlights` in tab order, the `pet` with when a session last ran (`lastActive`), and the `party` members, the user's pet first.
    A pet `name` is cleaned the way the app does it (spaces collapsed, at most 16 characters), and an empty one becomes the breed's name.
  - Each read has `enabled`, the kinds turned on (every kind when absent), the `items` in rotation order and `nextChange`, the next moment the items can change from the clock alone (absent when nothing is pending).
    An item has its `kind`, the `module` a click opens, the `action` a click runs (a progress goal's), `isPinned`, and one object named after its case with the case's fields and display strings: `meeting`, `focus`, `tasks`, `progress`, `highlight`, `pet` or `party` (`nowPlaying` has none).
- `rotations`: each starts a `TickerRotation` with `interval` (held at least one second) and lists `steps`.
  A step offers `items` at `at` (only a `meeting` or a module highlight can be `pinned`), sets the interval first when `interval` is given, and records the kind it `shown` plus the state it left: `currentKind` and `shownSince`.

Rules the fixture pins that are easy to miss:

- A meeting starting within five minutes beats one already under way, an all-day event never shows, and a blank title reads `Untitled event`.
- Countdowns round up to whole minutes, so `nextChange` falls each time the lead crosses a minute.
- One highlight per module: the highest `priority` that has not expired, the first one on a tie.
  Modules then rotate by priority, ties in tab order.
- A progress goal shows once it has work left, and a goal that `waitsForStart` only once some of it is done; a target of 0 has nothing left.
- The pet studies with a running focus phase, takes a break with a running break, stays awake while a session is paused, and otherwise dozes `petSleepAfter` after `lastActive`.
  `moodSince` is when the running phase began; `label` is the name beside the pet, shown only when the user chose it.
- A rotation step whose kind on screen vanished hands over to the next kind that followed it last time and is still there, or to the first item.
  A new interval applies to the item already on screen, and an interval set after creation is not clamped (0 moves on at every step).

A port replays only the inputs and compares every recorded output.
