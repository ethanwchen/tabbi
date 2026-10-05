# Study core

Pure Swift logic behind Tabbi's study tabs, living in `Sources/TabbiKitCore`.
No AppKit or SwiftUI, so every type here is unit tested.
Each folder is self-contained: `Anki/`, `StudyMethods/`, `Coach/`.

## Anki (`Sources/TabbiKitCore/Anki`)

A typed async client for the [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on, API version 6.

### Transport

- `AnkiConnectTransport` is a one-method protocol (`post(_:timeout:)`) so tests replay JSON fixtures.
- `URLSessionAnkiConnectTransport` posts to `http://127.0.0.1:8765`.
  It sends no `Origin` header, and AnkiConnect trusts requests without one, so no CORS setup is needed.
- `URLError`s are classified into `AnkiConnectTransportError` (`connectionRefused`, `timedOut`, `failed`), except `.cancelled`, which is rethrown as `CancellationError` so a cancelled refresh never shows an error state.
- The client checks for cancellation before sending and again after any failure, so a cancelled caller always gets `CancellationError`, never an `AnkiConnectError`, even if the transport failed for another reason meanwhile.

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
| `deckStats(for:)` | `getDeckStats` | `[AnkiDeckStats]` in the order asked for, matched by deck id so subdecks keep their full name |
| `numCardsReviewedToday()` | `getNumCardsReviewedToday` | `Int` (button presses since rollover) |
| `numCardsReviewedByDay()` | `getNumCardsReviewedByDay` | `[AnkiDayCount]`, newest first |
| `findCards(query:)` | `findCards` | `[Int64]` card ids |
| `cardReviews(deck:startID:)` | `cardReviews` | `[AnkiReview]` (exact deck only, no children) |
| `cardReviews(decks:startID:)` | `multi` of `cardReviews` | `[AnkiReview]` for every deck in one round trip; any deck's error fails the call |
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
- `AnkiDeckName`: `components`, `normalized` and `leaf` for `::` paths; AnkiConnect always gets the full path.
- `AnkiFavoriteDeck`: the pinned deck behind the one-click "Study <deck>" button, stored by id (follows renames) and full name (fallback), as a `VersionedJSON` document.
- `AnkiDeckStats`: new, learn, and review counts plus `dueTotal`, matching Anki's deck list.
- `AnkiDay`: a `yyyy-MM-dd` calendar day with `adding(days:)`, built from a `Date` with Anki's rollover hour.
- `AnkiReview`: one review-log row (`ease`, `kind`, `durationMilliseconds`, `isFailure`, `reviewedAt`).

### Summary

`AnkiSummary` is the glanceable model for the Anki card.
The pure initializer does the math, so it is tested without a transport.
`AnkiConnectClient.summary(now:rolloverHour:calendar:historyDays:retentionWindowDays:)` fetches and aggregates in one call.

```swift
let summary = try await client.summary()   // decks, getDeckStats, today, by-day, one multi of cardReviews
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
- `cardReviews` does not include child decks, so `summary` asks for every deck, batched into one `multi` request (five requests per refresh, however many decks).
- `AnkiSummary.demo(now:)` is the `TABBI_DEMO=1` sample: about 425 due, 112 reviewed today, a 12-day streak, about 91% retention.
  It is built through the real aggregation.
- `AnkiSummary` is `Codable`, so the UI can cache the last good value for its error state.

### Connection state

`AnkiConnectionState.resolve(error:isInstalled:launchedAt:now:)` turns a refresh outcome into the screen the Anki tab shows.

| State | From |
|---|---|
| `ready` | The refresh succeeded |
| `notInstalled` / `notRunning` | `ankiNotRunning`, split by whether an Anki app is on disk |
| `starting` | `addOnMissing` within `startupGrace` (15 s) of Anki launching, while add-ons load |
| `addOnMissing` | `addOnMissing` after the grace period |
| `needsPermission(_)` | `permissionDenied` or `apiKeyRequired` |
| `addOnOutdated` | `addOnOutdated` or `unsupportedAction` |
| `problem(_)` | Anything transient (timeout, profile picker, transport) |

- `isSetupStep` marks the states that need the user to act first.
- `keepsLastSummary` is true for `ready`, `checking` and `problem`, so a transient error shows the last numbers instead of an empty panel.
- `refreshInterval` is the poll interval while the panel is visible: 2 s while starting, 5 s for setup steps (60 s when Anki is not installed), 30 s for problems, 3 min when ready.
- `pollsWhileHidden` is true only for `starting`, so Today and the ticker get numbers as soon as AnkiConnect comes up after a background launch; the startup grace bounds it to a few polls.
- `AnkiSummary.topDecks` lists top-level decks with cards due, most due first; `completionFraction` drives the progress ring; `isCurrent(now:)` stops yesterday's numbers from being shared after the rollover.
  `AnkiSummary.nextRollover(after:)` is when that happens, so the store wakes once a day at the rollover to stop sharing the old summary and fetch the new day's.
- `AnkiConnectionState(previewName:)` parses `TABBI_ANKI_STATE` (for example `addOnMissing`, `notRunning`, `apiKey`, `problem`), which pins the Anki tab to one screen so every state can be snapshotted: `TABBI_ANKI_STATE=addOnMissing swift run Tabbi --snapshot snapshots-anki`.

### Opening a deck

`AnkiDeckOpener(client:launcher:clock:launchTimeout:pollInterval:)` runs one click on a deck: bring Anki forward, starting it if closed, wait for AnkiConnect, then `guiDeckReview` the deck's full name.

- `AnkiAppLauncher` (find, launch, activate Anki) and `AnkiOpenClock` are injected, so tests step through the whole flow without Anki.
- `open(deck:onPhase:)` reports `AnkiOpenPhase` (`opening`, or `launching` while a just-started Anki loads) and returns an `AnkiOpenOutcome`: `opened`, `openedApp`, `addOnMissing`, `deckNotFound`, `failed`, `notInstalled` or `launchFailed`.
- An Anki started within `AnkiConnectionState.startupGrace` gets the full `launchTimeout` (30 s), polled every 0.5 s; one that has been up a while answers at once or not at all, so a refused connection means the add-on is missing.
- Every outcome except `notInstalled` and `launchFailed` leaves Anki in front.
- `AnkiOpenOutcome(previewName:deck:)` parses `TABBI_ANKI_OPEN`, which pins the Anki tab to one click result for snapshots.
- `AnkiSummary.studyDeck(favorite:)` picks the deck a one-click Study opens (the favorite, else the deck with the most due), and `studyAction(favorite:)` is the `ProvidedAction` on the shared reviews goal, so Today's row and the closed notch's preview open it too.
- `AnkiSummary.deckOutline` lists every deck with cards due, subdecks indented under their nearest listed ancestor, so any exact subdeck can be picked.

### Formatting

`AnkiFormat` holds the Anki tab's wording and scales: `heatLevels(for:)` shades the two-week heatmap (0 to 4, scaled to the busiest day, any reviews at least 1), `streak(_:)`, `dayHelp(_:today:)` for heatmap tooltips, `progressHelp(_:)` for the ring, and `age(_:now:)` for how stale the numbers are.

## Study methods (`Sources/TabbiKitCore/StudyMethods`)

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
| `.timer(_:)` | User (`StudyTimerLength`, 10 min by default) | None | One countdown that stops when it ends; one-click 5, 10 and 25 min, or a stepper |

- `StudyMethod.presets` lists every kind once, in picker order; `preset(_:)` looks one up.
- `nextPhase(after:completedFocusCount:)` gives the next `StudyPhaseKind`: focus, then `review` when the method has one, then `shortBreak` or `longBreak`, then focus.
  A method without breaks (`hasBreaks` false, the Timer) goes from focus to a fresh idle focus.
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
| `retune(to:at:)` | Swap in new lengths for the same kind of method (e.g. an edited Custom rhythm) without starting over; a phase already past its new length ends no sooner than a minute later |
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
  The first reading after sprint focus starts or resumes only sets the baseline, so call `recordReviewedToday(_:at:)` right after `start(at:)`.
  Cards answered before the sprint, while paused, or on a break are therefore ignored even if the app stopped polling, and the drop at Anki's day rollover just rebases.
- `StudyMethod` and `StudyLongBreak` are immutable and decode through their initializers, so a decoded method gets the same clamps (phases 1 min...4 h, long break every 2+ rounds, card goal 1+) and can never complete a phase instantly.
  A decoded `StudySession` also repairs its own state: a phase shorter than a minute, non-finite or negative banked time, and negative tallies.

`StudyPhaseRecord` holds `method`, `phase`, `startedAt`, `endedAt`, `activeDuration` (pauses excluded), `outcome` (`completed`, `stopped`, `skipped`, `abandoned`), and `cards` for sprint focus.
Records are only logged for phases that actually started.

## Pet coach (`Sources/TabbiKitCore/Coach`)

`PetCoach` decides when the study pet nudges and what it says.
It sees only idle seconds and the category of the frontmost app's bundle id, never window titles, URLs, or keystrokes, so it needs no permission prompt.
Nothing it sees leaves the device.

### App lists

`CoachAppList` sorts bundle ids into `CoachAppCategory` (`focus`, `distracting`, `neutral`) with `category(of:)`.
Matching ignores case, and an app on both lists counts as `focus`, so the coach errs toward staying quiet.
Anki (`net.ankiweb.anki`, `net.ankiweb.dtop`) is a focus app by default.
The distracting list starts empty: the user picks it, and `suggestedDistracting` only offers common apps (Messages, Discord, Slack, WhatsApp, Telegram, Steam, TV) as opt-in chips.
Websites such as YouTube can't be detected without window titles, so settings copy should say so.
Edit with `markDistracting(_:)`, `markFocus(_:)`, and `forget(_:)`.

### Evaluating

The app builds a `PetCoachInput` every few seconds while a session runs and calls `evaluate(_:)` (or `evaluate(_:using:)` with a seeded generator in tests):

| Field | Source |
|---|---|
| `now` | Wall clock |
| `idleSeconds` | `CGEventSource.secondsSinceLastEventType` |
| `frontmost` | `CoachAppList.category(of:)` on the frontmost app's bundle id |
| `study` | `PetCoachStudyState`: `focusing`, `onBreak`, `paused`, `notStudying` |
| `deepFocus` | The UI's deep-focus flag |

It returns a `PetCoachDecision`: `.none`, `.lookOver` (a silent glance, no bubble), or `.nudge(PetCoachNudge)`.
A nudge has a `kind` and a `message`; `pausesTimer` is true for `autoPause`, and the app should pause the `StudySession` with it.

| `PetCoachNudgeKind` | When (standard rules) | Buttons |
|---|---|---|
| `distraction` | 2 min in a distracting app (after a glance at 30 s) | Back to it |
| `offerPause` | 5 min in a distracting app | Pause / Back to it |
| `idleCheck` | 2 min without input (10 min in deep focus) | Still studying / Pause |
| `autoPause` | 5 min without input (20 min in deep focus) | Resume |

Rules:

- The coach only acts while `study == .focusing`; breaks, pauses, and no session end any episode.
- Each step fires once per episode and steps up one at a time, even when the app first notices an episode late.
  The last step is always an offer to rest, so escalation only gets kinder.
- Leaving the distracting app ends that episode; any input ends the idle episode.
- Idle never means distracted: it only triggers a question, because reading and thinking look idle.
- Rate limits (`PetCoachRules`): the first bubble of an episode needs 10 minutes since the last one, the next step within an episode needs 2 minutes, and at most 3 bubbles per rolling hour, after which the pet goes quiet rather than nag.
  The silent glance is not rate limited.
- `autoPause` skips the cooldowns, because pausing keeps the stats honest, but it still counts toward the hourly cap.
- `snooze(for:at:)` / `snooze(until:)` / `endSnooze()` and the per-session `nudgesEnabled` switch silence everything, including the glance and auto-pause.
- `PetCoach` is `Codable`, so cooldowns, the hourly window, and snooze survive relaunch.

### Messages

`PetCoachMessages.standard` holds 4 to 6 lines per kind, each with a stable `id`.
Lines are short enough for a notch bubble (`maxLength`, 64 characters), warm, and never shaming: no counting slip-ups, no guilt, no "you should".
The standard lines name no subject, so every kit can use them.
A kit adds its own flavor as `coachLines` in the Closet module's settings (see [Kits](../kits.md#defaults)), and `PetCoachMessages.lines(kitSettings:)` returns the standard lines plus the kit's.
The Med School kit brings the med-school lines ("The Krebs cycle is saving your seat.").
Blank lines, lines over `maxLength` and unknown kinds are skipped.
`evaluate(_:lines:)` picks from the lines it is given; the app passes the active kit's lines on every sample, so switching kits changes the flavor at once.
`pick(_:from:avoiding:using:)` skips recently used ids while others remain and never repeats the most recent line; the coach remembers its last 8 lines in `recentMessageIDs`.

### Replies and the stroll

`PetCoachNudgeKind.replies` lists a bubble's buttons as `PetCoachReply` values, the kind's default first and `snooze` always last.
`PetCoach.handle(_:at:)` applies the coach's part of a reply: `snooze` silences it for `PetCoachReply.snoozeDuration` (15 minutes).
`pausesTimer` and `resumesTimer` tell the app when to change the study timer.

`PetCoachStroll` times the overlay: the pet walks `distance` points out from the notch at `speed`, talks for `talkDuration`, then walks back.
Ask it for `phase(at:)`, `offset(at:)`, `heading(at:)`, and `showsBubble(at:)`, so every frame (and every snapshot) follows from a date.
`dismiss(at:)` (any reply) turns the pet around at once, mid-walk included; only the first dismissal counts.

`PetCoachGlance` times the silent `.lookOver`: the pet lowers its head out of the notch (`peekIn`), hangs there looking for `hold` (2.5 s by default), then pulls back up (`peekOut`).
`init(startedAt:clips:)` takes the clip lengths from the pet's own peek clips, `pose(at:)` gives the clip and the time into it (nil while tucked away), and `stroll` is a zero-distance stroll of the same length, so the overlay closes a glance the same way it closes a walk.

In the app, `PetCoachOverlayView` (`Modules/PetCoach`) draws a stroll or a glance.
A glance hangs from the notch's own bottom edge, just inside its rounded corner, has no bubble, takes no clicks, and never replaces a bubble that is still up.
`--snapshot` renders `coach-walking.png`, one `coach-<kind>.png` per bubble kind, and `coach-glance-lowering.png` and `coach-glance.png`.

### Running the coach

`PetCoachStudyState(_:)` reads the shared focus timer (`ProviderSnapshot.focus`): only a running focus phase is `.focusing`, so the pet stays quiet on breaks, while paused, and with no timer.
`PetCoachInput(now:idleSeconds:frontmost:timer:)` builds a reading from that timer and marks focus phases of 45 min or longer as deep focus.
The app samples every `PetCoach.sampleInterval` (5 s) during a focus phase and not at all otherwise.
`PetCoachSave` persists the coach (cooldowns, snooze), the app lists and the user's `nudgesOn` switch as `Pet/coach.json`, next to the pet's save.
Saves without `nudgesOn` read as on.
`CoachAppList.toggleDistracting(_:)` backs the settings chips, and `addedDistracting` lists the apps the user added beyond the suggestions.

In the app, `PetCoachController` (`Modules/PetCoach`) runs while the Closet module is on.
It plays each nudge in `PetCoachOverlayWindow`, a transparent, non-activating panel hung below the menu bar at the notch's right edge.
The window ignores the mouse except while the pointer is over the bubble.
Run the app with `TABBI_COACH_PREVIEW=1` to play one nudge at launch, `TABBI_COACH_PREVIEW=celebrate` to play a level-up celebration, or `TABBI_COACH_PREVIEW=glance` to play the silent glance.
Settings › Pet Coach (shown with the Closet module) turns nudges on or off and edits the distracting apps: suggestion chips plus any app picked from the Applications folder.
Turning nudges off stops sampling and ends any open episode, so turning them back on starts fresh.
Turning the coach off (the Closet module) does the same, and the save keeps cooldowns and snooze but never an open episode, so the next focus phase after a relaunch gets its full grace period.

### The pet in the notch

`PetPresence` is the pet as the closed notch shows it: its profile plus `lastActive`, the last time a session ran.
`observe(_:at:)` stamps `lastActive` while the shared timer runs or is paused, and at the moment a session ends.
`mood(focus:at:)` reads `.studying` in a running focus phase, `.onBreak` in a running break, `.awake` while paused or within `sleepAfter` (20 min) of the last session, and `.asleep` after that.
The Closet module shares it as `ModuleProvision.pet`, and `ProviderSnapshot.pet` keeps the first in tab order.
The ticker turns it into a `.pet` item (`TickerKind.pet`, last in rotation), and `TickerSources.nextChange` includes the moment the pet dozes off, so the notch updates without polling.
`NotchPetWing` (TabbiKit) draws the animated pet in the leading wing and its name in the trailing wing, with a quiet "zzz" while it sleeps; mood changes play the real fall-asleep and wake-up clips.
`--snapshot` renders `closed-pet.png` and `closed-pet-asleep.png` when the Closet module is on (use `--kit medicine`).

## Closet (`Sources/TabbiKitCore/Closet`)

`PetCloset` holds the Closet tab's editing rules over one `PetSave`, so every edit leaves a save that is valid to persist.

- `wardrobe` lists every paid item, cheapest first; "no outfit" is not a tile, because tapping the worn outfit takes it off.
- `state(of:)` is `wearing`, `owned`, `affordable`, or `locked(missing:)`.
- `tap(_:)` toggles owned items, buys and wears affordable ones, and changes nothing for locked ones.
- `wearing(_:on:)` dresses a profile without checking ownership, for hover "try it on" previews.
- `setSpecies(_:)` picks the species' first breed; a default name (`PetProfile.hasDefaultName`, see [pets.md](pets.md#the-default-pet)) follows the species, a chosen name is kept.
- `cycleBreed(by:)` wraps within the species, and `setBreed(_:)` re-derives the fur tint from the new breed's shading.
- `furSwatches` are the offered fur colors; `furTint` reads the picked one back from the `furBase` override.
- `PetCloset.demo` is the `TABBI_DEMO=1` closet, with every tile state on show.

### Points and celebrations

`PetCloset.credit(from:to:at:)` pays study points from two observations of the shared focus timer and returns a `PetStudyAward` to celebrate.
A focus phase that runs out earns its length plus the completion bonus (`PetPointsRules`).
Completions are counted from `FocusTimer.completedFocusCount` against `PetSave.creditedFocusCount`, so sessions that ended while the app was closed are paid once, and the first timer a pet ever sees only sets the baseline.
A focus phase skipped or reset part-way earns the minutes studied without the bonus; under 5 minutes earns nothing.
`PetStudyAward.unlocked` lists wardrobe items the award just made affordable (a level-up), and `headline`, `unlockLine` and `pointsText` are the bubble's copy, free of any subject so every kit can use it.

`ClosetStore` credits on every shared focus change, plays the celebrate clip on the Closet preview, and publishes the award.
`PetCoachController.celebrate(_:)` then sends the pet out of the notch with a happy hop and a heart, the points pill, the unlock line on a level-up, and a single "Yay!" button.
Celebrations play whenever the coach runs (with the Closet module), even with nudges off, and stay up for `PetCoach.celebrationDuration` (6 s).
`--snapshot` renders `coach-celebrate.png` and `coach-level-up.png`.

In the app, `ClosetStore` (owned by `AppServices`) saves to `~/Library/Application Support/<edition>/Pet/pet.json` after each edit.
It never writes in demo mode, and never overwrites a save it could not read.
