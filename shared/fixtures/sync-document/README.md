# Sync document golden fixture

Written by `Tests/TabbiKitCoreTests/SyncDocumentGoldenTests.swift` from `SyncDocument`, `SyncedPet`, `SyncTally`, `SyncRound`, `SyncState` and `SyncOutcome.folding(_:base:)`.
It pins the one document Sign in with Apple keeps per account on the Party server, which every app reads and writes, so a Windows port writes the same JSON, reads stored documents the same way, merges the same and syncs the same.
`shared/schemas/sync-document.v1.schema.json` describes the document, and the routes are in `docs/study/backend-api.md` (`GET` and `PUT /v1/sync`).

The file has `schema` (`tabbi.sync-document.golden`) and `version` (1).
Times are seconds since 1970; days are `YYYY-MM-DD` strings.
Every document in the fixture is a JSON object exactly as it goes over the wire, `schemaVersion` included.

- `constants`: the document's `schemaVersion` (1), `keptStudyDays` (400, the newest study days a document keeps) and `maxAttempts` (3, the pushes a round tries before it gives up on conflicts).
- `wire`: sample documents as `SyncDocument.encoded()` writes them: `text` is the exact string and `document` the same JSON as an object.
  Reading `text` and writing it again gives `text` back.
- `decodes`: stored documents (`input`, any text, including ones an app would not write) and what reading them gives, written back out (`document`), or null when the text cannot be read at all.
- `merges`: an `input` with a `local` document, a `remote` one (null when the server holds none, which merges like an empty document) and a `today`, and the `output`:
  the `merged` document, the account's `earned` and `spent` points (sums over devices), the `ledger` this build reads from it (`earned`, `spent`, `purchased` and `granted` item ids) and the `currentStreak` on `today`.
  Merging the other way round, or merging the result again, gives the same document.
- `rounds`: one `SyncRound` each, against a scripted server.
  - `input` holds the device's `SyncState` (`device` id, `account`, the `adopted` document and its `revision`), its progress (`local`: the pet `save`, `lookChangedAt` and its own `studyDays`), the `server` before the round (`revision`, `document`), `racers` and `now`.
    A `save` is the pet profile as `PetProfile` encodes it and the ledger (`earned`, `spent`, `purchased` and `granted` item ids, `streakFreezes` times).
    `racers[n]`, when not null, is a document another device merges into the server's (bumping its revision) just before this device's n-th push lands, so that push meets a `409`.
    `duringRound`, when present, is progress made while the round ran, folded on top of its outcome.
  - `output.exchanges` lists every request in order: a `pull` with the `revision` and document `received`, or a `push` with its `ifMatch` revision, the document `sent`, the `status` (200 or 409) and the new `revision`.
  - `output.outcome` is the merged `document` (also the one the state adopts), whether it was `pushed`, the `save` to adopt, the state's `revision` and `lastSyncedAt`; `output.folded` is the same for `duringRound`.
    When the round gives up, `outcome` is absent and `error` is `revision_conflict`.
  - `output.server` is the server's revision and document after the round.

Rules the fixture pins that are easy to miss:

- The document is a join: per-device tallies take the larger `earned` and the larger `spent` separately, unlocks and study days are unions, `longestStreak` is the maximum, and the pet is last writer wins.
- `pet.updatedAt` is ISO 8601 in UTC with whole seconds; fractions are cut off (towards earlier) when the time is recorded, so two looks set in the same second tie.
  Reading accepts only what Foundation's `.iso8601` date strategy accepts; see the `pet-date-*` decodes for an offset, fractions, no zone and a number.
- Equal times are settled by the profile's compact JSON with sorted keys (`{"accessories":[],"breed":"calico","furTint":null,...}`, as `JSONEncoder` with `.sortedKeys` writes it): the greater string wins.
  So no accessories (`[]`) beat worn ones, and a null `furTint` beats a color.
- A device's tally is what its ledger holds beyond the other devices' tallies in the document it last adopted, so points earned on two devices while offline add up.
- A look counts as chosen on this device only when its profile differs from the adopted document's pet; an unchanged look never wins, whatever `lookChangedAt` says, and an unknown `lookChangedAt` counts as 1970.
- A round pushes only when the merged document differs from the server's as read (field by field after reading, not as text), so a server document an older build wrote is not rewritten just for its form.
- On a `409` the round pulls, merges into what it already merged and pushes again, at most `maxAttempts` pushes in all.
- Reading is lenient and field by field: a missing, null or unreadable field reads as empty (no pet, no tallies, no unlocks, no days, a streak of 0) and the rest is kept; unknown keys are dropped.
  One bad entry drops its whole field (a tally without `spent` drops every tally, a number in `unlocks` drops every unlock).
  A negative tally is kept as it is; a merge clamps a tally to 0 or more only when both sides have that device.
- A pet whose profile has no known `breed` or whose `updatedAt` cannot be read is dropped; any other profile field falls back to a default (see the `pet-*` decodes, including a profile from before `furTint`, whose `furBase` becomes the tint).
- Study days that are not real calendar days in exactly `YYYY-MM-DD` form are dropped; the newest 400 are kept, and `longestStreak` is never below the longest run in the days, so it remembers runs trimmed away.
  `currentStreak` counts the run of days ending today or yesterday, among the kept days only.
- Unknown unlock ids are kept in the document; the ledger skips them, reads limited edition items as granted and leaves free items out.
  Applying a document to a save keeps the save's granted items and streak freezes, and takes off worn items the ledger does not own.
- The Mac writes keys sorted with no spaces and escapes `/` as `\/` (the `name-with-slash-and-accents` wire sample); a port may write either form, since readers parse the JSON, but its documents must parse to the same objects.

A port replays only the inputs (`wire[].text`, `decodes[].input`, `merges[].input`, `rounds[].input`) and compares every recorded output.
Compare documents as parsed JSON objects.
