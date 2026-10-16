# Activity log golden fixtures

Written by `Tests/TabbiKitCoreTests/ActivityLogGoldenTests.swift` from `ActivityRecord`, `ActivityLogRepository` and `VersionedJSON`.
They pin the activity log that streaks, the weekly recap, points and the pet read, so the Windows port makes the same records, puts them in the same day files, writes the same JSON and reads the same files back.
The day file's shape is `shared/schemas/activity-record.v1.schema.json`.

The file has `schema` (`tabbi.activity-log.golden`) and `version` (1).
Times in inputs and records are seconds since 1970; dates inside day files are ISO 8601 strings, as the Mac writes them.

- `constants`: the folder name (`Activity`), the version key (`schemaVersion`), the version written (1), the versions that have an upgrade step (none), and the shared kinds, units and metadata keys.
- `records`: each `input` is what a module hands to `ActivityRecord.init` (`end` may be absent, times may carry fractions) and `record` is the record as the app holds it: whole seconds, `end` never before `start`, the id as an upper-case UUID.
- `days`: `records` are instants around midnight and daylight saving changes, and each entry of `zones` lists, in `records` order, the local day (`yyyy-MM-dd`, the day file's name without `.json`) each one counts toward in `timeZone`.
- `appends`: each `input` has the `timeZone` of the repository's calendar, `seed` files already in the folder (name and exact text), and `batches`, each one call to `append`.
  The `output` has:
  - `threw`: whether each batch's `append` threw.
  - `files`: every file in the folder afterwards, by name, with its exact text (`contents`) and, when it is a day document, its JSON value (`document`).
  - `savedDays`: the days that have a day file, oldest first.
  - `readBack`: every record that reads back over all saved days, skipping unreadable files.
- `reads`: each is the text of the day file for 2 October 2026 and the `records` it reads as, or null when the repository refuses the file.

Rules the fixture pins that are easy to miss:

- A record counts toward the local day its `end` falls on, not its start, so a focus from 23:40 to 00:10 belongs to the second day.
- Times round to whole seconds when a record is made, half a second up, so an end at 23:59:59.5 lands on the next day.
- `end` defaults to `start`, and an `end` before `start` becomes `start`, both when a record is made and when it is read.
- The repeated hour when clocks fall back belongs to one day, and the day a clock springs forward is still one file.
- A day file holds its records sorted by `end`; appending merges into the existing file and skips ids already there, and a batch of nothing new leaves the file untouched.
- `append` writes days in date order and stops at the first day it cannot read: earlier days are written, that day's broken file is left as it was, and later days are not written.
- Files that are not `yyyy-MM-dd.json` (such as `readme.txt`) are ignored, never deleted.
- A file without `schemaVersion` reads like version 1 and is rewritten with it on the next append; a newer `schemaVersion` with unknown keys reads as it is.
- The Mac writes keys sorted, two-space indented with ` : ` between key and value, `/` escaped as `\/`, non-ASCII as raw UTF-8, whole-number quantities without a decimal point, empty `metadata` as an empty object (Foundation prints it as `{`, a blank line and `}`), absent `quantity`, `unit` and `subject` left out, and no trailing newline.
- Reading accepts dates with a numeric offset, lower-case ids, `null` optional fields and `null` or missing `metadata`; it refuses a whole file when it is not JSON, has no `records` array, or any record lacks a valid `id` or has a date that is not an ISO 8601 string with a zone.

A port replays only the inputs and compares every recorded output.
Compare a day file it writes with `document` as a JSON value; `contents` shows the Mac's exact bytes, which a port need not match byte for byte, since both apps parse the files rather than compare them.
