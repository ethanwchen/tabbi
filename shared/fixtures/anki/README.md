# Anki golden fixtures

Written by `Tests/TabbiKitCoreTests/AnkiGoldenTests.swift` from `AnkiConnectClient.summary`, `AnkiSummary`, `AnkiFormat`, `AnkiSummary.reviewActivity(after:source:now:)`, `AnkiConnectError` and `AnkiConnectionState`.
They pin how Tabbi talks to the AnkiConnect add-on on `127.0.0.1:8765` and what the Anki tab makes of the replies, so the Windows port sends the same requests and shows the same numbers and messages.
The background is in `docs/windows/HANDOFF.md`, "Anki: the `getDeckStats` lesson".

The file has `schema` (`tabbi.anki.golden`) and `version` (1).
Times are seconds since 1970, except inside AnkiConnect bodies, where review ids and `startID` are milliseconds.

- `cases`: one refresh each, a call of `summary` on a fresh client, named for what it shows.
  - `environment`: the inputs around the refresh.
    `now` is the moment it runs, Anki days are counted in `timeZone` with the day starting at `rolloverHour`, `apiKey` is sent as `key` when set, and `ankiRunning`, `isInstalled` and `launchedAt` are what the app knows about the Anki process, which only matter when the connection is refused.
  - `activityLog`: `cards.reviewed` and other records already logged, each with its `source` module, `kind`, `quantity` and the Anki day it counts toward (`ankiDay`).
  - `exchanges`: every request the client sent, in order, with the `reply` it got.
    `request` is the JSON body as an object (compare it by value, not as text); `timeout` is the seconds the client allowed.
    `reply` is either an HTTP `status` with the raw `body` text, or a transport `failure`: `connectionRefused`, `timedOut`, or `failed` with `failureMessage`.
  - `reportedErrors`: the failed actions the client hands to its error log, in order, as the action name and the `AnkiConnectError` case.
  - `summary`, when the refresh succeeded: the due counts, today's reviews, the streak, `history` (14 days, oldest first, ending on the Anki day `day`), `retention` (absent below 20 answers) with its sample size, `studyTimeToday` in seconds, `completionFraction`, the counts of every deck Anki counted, in the requested order (`decks`, leaving out the others), the decks with cards due (`topDecks`), the indented `deckOutline`, the `missing` pieces and the `gaps` that explain them.
  - `format`: the streak line, the ring's tooltip (`progressHelp`), and one heat level and tooltip (`dayHelp`, written in `en_US`) per history day.
  - `progress`: the shared progress goal Today and the ticker show, with the action a click runs.
  - `activity`: the `cards.reviewed` record the refresh logs, or absent when nothing new was reviewed.
  - `error`, when the refresh failed: the error's case (`kind`), the raw `message` and its `quotedMessage` for the errors Tabbi can't explain, whether it `failsWholeRefresh`, and the `title` and `suggestion` the panel shows.
  - `connection`: the `AnkiConnectionState` the refresh resolves to (`state`, the label support sees), whether it is a setup step, whether the last summary stays on screen, how many seconds until the next refresh, and the Settings > Connections row (`light`, `headline`, `detail`, and the button as `action` and `actionTitle`).

Rules the fixture pins that are easy to miss:

- A refresh asks, in this order: `deckNamesAndIds`, `getDeckStats`, `getNumCardsReviewedToday`, `getNumCardsReviewedByDay`, and one `multi` of `cardReviews` for every deck, children included, from 30 days before `now`.
  Decks are sorted by name in plain code point order, so `Biology Extra` comes before `Biology::Cells` and lowercase names come last.
  With no decks there is no `getDeckStats` and no `multi`.
- AnkiConnect 2026.10 fails a whole `getDeckStats` with "Deck counts unavailable." when a deck in it can't be counted, as the empty Default deck (id 1) never can.
  The client then asks again without Default, then deck by deck in one `multi`, keeping every deck that answers and failing only when none does.
  With only the Default deck there is nothing to ask again, so it goes straight to `multi`, and that refresh fails.
  An older add-on skips such a deck instead.
- Replies are matched by deck id, never by name: older add-ons name a deck by its leaf (`Cardio`), and the summary keeps the full name.
- Every inner action of a `multi` carries `version` 6 and, when set, the API key.
  The `multi` batch gets a 20 second timeout, every other request 3 seconds.
- An error that means Anki can't be read right now (closed, busy, no collection, refused, a missing or wrong key) fails the whole refresh, and a closed collection is never asked again deck by deck.
  Any other failure of the three optional actions leaves a gap and marks its piece `missing`, and the due counts still show.
  A gap's message is the error's short message, or the case written as Swift prints it, such as `unsupportedAction("getNumCardsReviewedToday")`.
- A reply AnkiConnect wrote because it could not parse the body ("Expecting value...") makes the client send the same request once more.
- Today's count is the larger of `getNumCardsReviewedToday` and the day's entry in `getNumCardsReviewedByDay`, and duplicate days in the latter are added up.
  A streak ending yesterday is still alive while today has no reviews.
- The Anki day is the date in `timeZone` four hours (`rolloverHour`) before the moment, so 02:30 counts toward the day before, and the night the clocks go back still lands on the right day.
- Retention counts answers to review cards (type 1) with a button pressed, from the 30 days up to `now`, one per review id; study time adds up every answer of today's Anki day.
- Unexplained errors are shortened to one line of at most 90 characters, ending in an ellipsis when cut.
- The activity record logs only the reviews of today's Anki day that the log does not hold yet, counting only this module's `cards.reviewed` records for that same Anki day.

A port answers its client's requests with the recorded replies, in order, and compares the requests and every recorded output.
Compare numbers within 1e-9: `retention` and `completionFraction` are computed fractions.
