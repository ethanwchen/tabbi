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
