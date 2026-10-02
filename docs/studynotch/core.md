# StudyNotch core

Pure Swift logic behind StudyNotch, living in `Sources/NotchDeckCore`.
No AppKit or SwiftUI, so every type here is unit tested and can later move into a shared `NotchKitCore` library unchanged.
Each folder is self-contained: `Anki/`, `StudyMethods/`, `Coach/`.

## Anki (`Sources/NotchDeckCore/Anki`)

A typed async client for the [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on, API version 6.

### Transport

- `AnkiConnectTransport` is a one-method protocol (`post(_:timeout:)`) so tests replay JSON fixtures.
- `URLSessionAnkiConnectTransport` posts to `http://127.0.0.1:8765`.
  It sends no `Origin` header, and AnkiConnect trusts requests without one, so no CORS setup is needed.
- `URLError`s are classified into `AnkiConnectTransportError` (`connectionRefused`, `timedOut`, `failed`).

### Client

`AnkiConnectClient(transport:apiKey:requestTimeout:syncTimeout:isAnkiRunning:)`

- Every request sends `"version": 6`, plus `"key"` when `apiKey` is set.
- `requestTimeout` (default 3 s) is for polling reads; `syncTimeout` (default 90 s) is for `sync`, which blocks Anki's main thread.
- `isAnkiRunning` is the app's process check.
  It is only used to explain a refused connection; the HTTP reply is the source of truth for reachability.
- `AnkiConnectClient.isAnkiApp(bundleIdentifier:localizedName:)` matches `net.ankiweb.anki` (25.07+ launcher), `net.ankiweb.dtop` (older builds), or the name "Anki".

| Method | AnkiConnect action | Returns |
|---|---|---|
| `version()` | `version` | `Int` |
| `requestPermission()` | `requestPermission` | `AnkiPermission` (decodes both `requireApikey` and `requireApiKey`) |
| `connect()` | `requestPermission` | Same, but throws `.permissionDenied` or `.addOnOutdated` |
| `decks()` | `deckNamesAndIds` | `[AnkiDeck]` sorted by name |
| `deckStats(for:)` | `getDeckStats` | `[AnkiDeckStats]` in the order asked for |
| `numCardsReviewedToday()` | `getNumCardsReviewedToday` | `Int` (button presses since rollover) |
| `numCardsReviewedByDay()` | `getNumCardsReviewedByDay` | `[AnkiDayCount]`, newest first |
| `findCards(query:)` | `findCards` | `[Int64]` card ids |
| `cardReviews(deck:startID:)` | `cardReviews` | `[AnkiReview]` (exact deck only, no children) |
| `guiDeckReview(name:)` | `guiDeckReview` | `Bool`; the app must still activate Anki |
| `guiDeckOverview(name:)` | `guiDeckOverview` | `Bool` |
| `sync()` | `sync` | nothing |

### Errors

All failures are `AnkiConnectError`, each with a short `title` and a one-sentence `suggestion` for empty and error states.

| Case | When |
|---|---|
| `ankiNotRunning` | Connection refused and no Anki process |
| `addOnMissing` | Connection refused while Anki runs (or Anki is still starting; retry ~15 s first) |
| `timeout` | No answer in time: App Nap or a modal dialog in Anki |
| `permissionDenied` | Permission denied, or HTTP 403 |
| `apiKeyRequired` | `valid api key must be provided` |
| `addOnOutdated(version:)` | Add-on API older than 6 |
| `unsupportedAction(_:)` | `unsupported action` |
| `collectionUnavailable` | Anki is on the profile picker |
| `syncNotConfigured` | `sync: auth not configured` |
| `anki(_:)`, `invalidResponse(_:)`, `transport(_:)` | Anything else |

### Models

- `AnkiDeck`: `id`, `name`, `leafName`, `depth` (names nest with `::`).
- `AnkiDeckStats`: new, learn, and review counts plus `dueTotal`, matching Anki's deck list.
- `AnkiDay`: a `yyyy-MM-dd` calendar day with `adding(days:)`, built from a `Date` with Anki's rollover hour.
- `AnkiReview`: one review-log row (`ease`, `kind`, `durationMilliseconds`, `isFailure`, `reviewedAt`).

### Summary

`AnkiSummary` is the glanceable model for the Anki card.
The pure initializer does the math, so it is tested without a transport.
`AnkiConnectClient.summary(now:rolloverHour:calendar:historyDays:retentionWindowDays:)` fetches and aggregates in one call.

```swift
let summary = try await client.summary()   // decks, getDeckStats, today, by-day, cardReviews per deck
summary.dueTotal       // new + learn + review due today
summary.streak         // consecutive review days
summary.retention      // 0.91, or nil below 20 graded reviews
```

| Field | Meaning |
|---|---|
| `newDue`, `learnDue`, `reviewDue`, `dueTotal` | Due today, summed over top-level decks only, because Anki already rolls children into parents |
| `reviewedToday`, `hasReviewedToday` | The larger of `getNumCardsReviewedToday` and today's by-day row, so the two queries never disagree visibly |
| `streak` | Consecutive days with reviews ending today; if today has none yet, it counts from yesterday so the streak still reads as alive |
| `history` | `defaultHistoryDays` (14) `AnkiDayCount`s, oldest first, ending today, zero-filled |
| `retention`, `retentionSampleSize` | True retention over `defaultRetentionWindowDays` (30): `1 - Again / graded` over review-kind rows only (learn, relearn, filtered, and manual rows are ignored). `nil` below `minimumRetentionSample` (20) so the UI never shows a noisy percentage |
| `studyTimeToday` | Sum of answer durations for reviews on today's Anki day (rollover-aware) |
| `decks` | Every `AnkiDeckStats`, in the order given, for a per-deck list |

- Review rows are de-duplicated by id, so overlapping `cardReviews` fetches are safe.
- `summary` makes one `cardReviews` call per deck because that action does not include child decks.
- `AnkiSummary.demo(now:)` is the `NOTCHDECK_DEMO=1` sample: about 320 due, 112 reviewed today, a 12-day streak, about 91% retention.
  It is built through the real aggregation.
- `AnkiSummary` is `Codable`, so the UI can cache the last good value for its error state.

## Study methods (`Sources/NotchDeckCore/StudyMethods`)

### Methods

`StudyMethod` holds the parameters of one timer rhythm.
Every preset is the same struct, so the session engine runs presets and custom methods through identical code.
It is `Codable`, so a running session persists the exact method it started with.

| Preset | Focus | Break | Extra |
|---|---|---|---|
| `.pomodoro` | 25 min | 5 min | 15 min long break after every 4th focus |
| `.fiftyTwoSeventeen` | 52 min | 17 min | |
| `.ultradian` | 90 min | 20 min | |
| `.flowtime` / `.flowtime(scheme:)` | Open-ended | Proportional | `.tiered`: 5 min after up to 25, 8 after up to 50, else 10; `.fifth`: work / 5 |
| `.ankiSprint(cards:)` | Card goal (default 100) | 5 min | Suggest a break every `sprintBreakCards` (200) or `sprintBreakInterval` (30 min) |
| `.questionBlock` | 60 min, 40 questions | 10 min | 60 min `review` phase after each block |
| `.custom(focus:breakLength:longBreak:)` | User | User | Lengths clamped to 1 min...4 h |

- `StudyMethod.presets` lists every kind once, in picker order; `preset(_:)` looks one up.
- `nextPhase(after:completedFocusCount:)` gives the next `StudyPhaseKind`: focus, then `review` when the method has one, then `shortBreak` or `longBreak`, then focus.
- `duration(of:workedBeforeBreak:)` is the wall-clock length of a phase, or `nil` for open-ended and card-goal focus.
  Proportional breaks use `workedBeforeBreak`.
- `sprintGoal(reviewDue:learnDue:)` defaults a sprint to today's reviews plus learning cards, the work that should come before new cards.
- `rhythmLabel` is a short label: "25/5", "60+60/10", "Open", "100 cards".

### Info popover copy

`StudyMethodInfo.info(for:)` (or `method.info`) returns `name`, `tagline`, a 2 to 3 sentence `howTo`, a 1 to 2 sentence `evidence` note, and an `evidenceLevel` badge (`strong`, `mixed`, `weak`).
`StudyMethodInfo.footnote` goes under every popover.
The copy follows the research notes and never claims an interval is proven: what research supports is regular breaks, self-testing, and spacing, so only the Anki sprint and question block (retrieval practice) are rated `strong`.

### Session engine

`StudySession` is the `Codable` state machine every method runs through.
Time comes from wall-clock dates (when the clock last resumed plus the time banked before it), never a ticking counter.
So the session stays correct while the notch is closed or the Mac sleeps, and a snapshot restored after relaunch continues exactly where it was.
Every call takes `now`, so tests drive it with fixed dates.

| Member | Purpose |
|---|---|
| `method`, `phase`, `runState` (`idle` / `running` / `paused`) | Where the session is |
| `phaseDuration` | Length of the current phase, fixed when it begins; `nil` for open-ended or card-goal focus |
| `elapsed(at:)`, `remaining(at:)`, `endsAt`, `progress(at:)` | Clock readouts; `progress` uses cards for a sprint and is `nil` for Flowtime focus |
| `start(at:)`, `pause(at:)` | Start an idle phase, resume a paused one, freeze a running one |
| `skip(at:)` | End the phase early; the next phase keeps running only if the clock was running |
| `stopFocus(at:)` | End open-ended Flowtime focus and start its proportional break; `false` for any other phase |
| `reset(at:)`, `switchMethod(to:at:)` | Start over idle, logging the current phase as `abandoned` |
| `advance(to:)` | Apply every phase end that has passed and return them |
| `recordReviewedToday(_:at:)` | Feed AnkiConnect's reviewed-today count; reaching the sprint goal ends focus |
| `suggestsSprintBreak(at:)` | A sprint ran 200 cards or 30 minutes |
| `completedFocusCount`, `cardsDone` | Tallies for the header |
| `log`, `takeLog()` | Phases that ran, as `StudyPhaseRecord`s, until the app collects them |

Rules:

- When focus or review ends, the next phase starts on its own.
  When a break ends, the next focus waits idle, so the timer never runs on while the user is away.
- After a long sleep, `advance(to:)` can return several records (focus, then the auto-started break), each stamped with its real end time.
- Only completed or stopped focus phases count (`StudyPhaseOutcome.countsAsDone`).
  A skipped focus never earns a long break.
- Sprint cards are the increases in reviewed-today while sprint focus runs.
  The first reading only sets the baseline, cards answered while paused or on a break are ignored, and the drop at Anki's day rollover just rebases.
- A decoded method with a zero-length phase is floored to `StudyMethod.minimumPhase`, so it can never complete instantly.

`StudyPhaseRecord` holds `method`, `phase`, `startedAt`, `endedAt`, `activeDuration` (pauses excluded), `outcome` (`completed`, `stopped`, `skipped`, `abandoned`), and `cards` for sprint focus.
Records are only logged for phases that actually started.
