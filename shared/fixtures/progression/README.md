# Progression golden fixtures

Written by `Tests/TabbiKitCoreTests/ProgressionGoldenTests.swift` from `ProgressTrack`, `ProgressTier`, `ProgressBadge`, `ProgressTally`, `GentleStreak`, `MonthlyQuests`, `PetProgression`, `ProgressionSave` and the mastery outfits of `PetLimitedEdition`.
They pin the Closet's Goals section (docs/design/progression.md): every badge's tiers, how activity records become each track's count, the gentle streak, monthly quests and the hash that picks them, short progress labels, the mastery outfits each badge tier unlocks, and how the progression save reads and writes, so the Windows port counts, picks quests and unlocks exactly like the Mac.

The file has `schema` (`tabbi.progression.golden`) and `version` (1).
Times are seconds since 1970, record ids are UUIDs, days are local `yyyy-MM-dd` strings and months `yyyy-MM`.
Every time zone is an IANA name, every calendar Gregorian in that zone with the given `firstWeekday` (1 is Sunday, 2 is Monday).

- `constants`: the tier names in order, the `namedMethods` the Study methods badge counts, `steadyWeekDays` (study days that make a Monday-to-Sunday week steady), `minutesForStudyDay`, and the monthly quests' `questCount`, `questCore` (one of them is always picked), `questExtras` (offered once the user did them before the month) and `questTargets` (each in its track's unit), plus the save's `saveSchemaVersion`.
- `tracks`: each badge with its four `thresholds`, Bronze first, in its unit: minutes for `focusHours`, otherwise days, sessions, cards, tasks, moves, Party sessions, methods, weeks, glasses or months.
- `mastery`: each mastery outfit's `item`, its `edition`, the `badge` tier that unlocks it (`track.tier`, tiers counted from 1) and that tier's `goal`.
- `hashes`: 32-bit FNV-1a of UTF-8 `text`.
  A month's quests rank the core tracks and the available extras by the hash of `<month>|<track>` (ties by track id), take the first core track, then the two lowest of the rest.
- `labels`: a track's short progress `label` for `value` toward `goal`: hours rounded down with " h" for focus, otherwise the counts, each written as is below 10,000 and in whole thousands with "k" above; the value is clamped to 0...goal.
- `streaks`: the longest run of study days for `studyDays` up to `today`, where a missed day while a run goes on uses that calendar week's free freeze, then the oldest extra freeze bought before that day (`freezePurchases`), and otherwise ends the run; today counts once studied.
- `scenarios`: a progression started from an optional `save` (progression save JSON), fed `records` (each counted once by `id`, toward the local day it ended) and refreshed at `today` with `freezePurchases`.
  The `output` has every track's count (`values`, the larger of the log and the save's best), the highest tier reached per track (`tiers`, absent below Bronze), the badges the refresh reached for the first time (`reachedBadges`, sorted by track order then tier), every month whose quests are all done (`completedMonths`, saved ones included), this month's `quests` with their `value`, `isDone` and `label`, the mastery outfits a closet that owned none gets (`unlocked`), and every badge's `progress` label.
- `saves`: a stored progression save `json` and, when it reads, its `output`: `best`, `reached` (seconds since 1970), `completedMonths`, `seen` and `encoded`, the save written back (pretty printed, sorted keys, ISO 8601 dates).

Rules the fixture pins that are easy to miss:

- `focus.completed` records count only in minutes with a positive finite quantity; one counts as a finished session when its `outcome` is missing, `completed` or `stopped`.
- A Party session counts only from the `party` source, with the `completed` outcome and at least one friend in the `friends` metadata.
- Only the named study methods count; a custom timer, the plain countdown and Party's own method ids do not.
- A task checked off twice (the same `subject`) counts once; one without a subject counts each time.
- Water counts the record's quantity (1 when absent); a negative or missing card count adds nothing.
- Month totals for quests count only the records whose day falls in that month.
- An extra track joins a month's quest pool only when the user did it on a day before the month began.
- A save drops ids it does not know, keeps only positive best counts, only seen tiers that were reached, and only valid months; a file that is not an object does not read.

A port replays only the inputs and compares every recorded output.
