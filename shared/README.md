# shared

Data that both the Mac app and the planned Windows app read, and golden fixtures that keep their logic in step.
See `docs/windows/plan.md` (section 3) for why, and `docs/windows/phase0.md` for what is done.

- `schemas/` holds JSON Schema files for the data formats both apps read.
  `pets.v1.schema.json` describes the pet art, breeds and animation timelines in `Sources/TabbiKitCore/Pets/PetArt/`.
  `themes.v1.schema.json` describes the themes in `Sources/TabbiKitCore/Themes/themes.json`.
  `study-methods.v1.schema.json` describes the study methods in `Sources/TabbiKitCore/StudyMethods/study-methods.json`.
  `events.v1.schema.json` describes the year of seasonal events in `Sources/TabbiKitCore/Events/events.json`.
  `kit.v1.schema.json` describes kit files (`formatVersion` 1), bundled in `Sources/TabbiKitCore/Kits/Bundled` or imported; see `docs/kits.md`.
  `edition.v1.schema.json` describes the edition files in `Sources/TabbiKitCore/Editions/BundledEditions`.
  `catalog.v1.schema.json` describes the Party catalog, `backend/shared/catalog.json`.
  `party.v1.schema.json` is the Party wire contract: every request body and reply the apps and the server exchange (endpoints and errors in `docs/study/backend-api.md`, versioning in `docs/party-compatibility.md`); `backend/test/compat.test.ts` checks the server's replies against it.
  `sync-document.v1.schema.json` describes the Party sync document both apps write to the same server document (`SyncDocument`); `SyncDocumentGoldenTests` keeps its fields equal to what the Swift encoder writes.
  `activity-record.v1.schema.json` describes an `ActivityRecord` and the per-day file `ActivityLogRepository` writes in the edition's `Activity` folder.
  `SharedSchemaTests` keeps the kit and edition schemas' fields, limits and patterns equal to the Swift decoders, and the catalog schema equal to the catalog's fields.
- `fixtures/` holds golden fixtures written by the Swift tests.
  Each port checks its own output against them, so drift between the apps fails a test.
  `pets/`, `themes/` and `study-methods/` pin the data files above (`pets/rendered.json` also pins the rendered colors, dark-coat rim included); `claude-stream/` pins how the `claude` CLI's stream-json lines are parsed and folded into an Ask Claude chat;
  `focus-timer/` pins the shared Pomodoro: its steps, readouts, shared focus clock and logged activity;
  `study-session/` pins the Study tab's timer for every method: its steps, the dial, buttons and pet, the shared focus clock and the logged phases;
  `ticker/` pins which items the closed notch can show, when it next has to look again, and which one the rotation picks;
  `plan-my-day/` pins Plan my day: free time, the on-device and study planners, the Claude prompt and how its answers are read, and the proposal the user adds to the calendar;
  `party/` pins the Party protocol: the server id of every outfit and accessory, the profile bodies sample pets send, and how sample replies (from this, an older and a newer server) read, down to the pet drawn for each profile;
  `sync-document/` pins the sync document: its wire text, how lenient reads clean it, how a local and a remote document merge, and whole sync rounds against a scripted server;
  `closet/` pins the closet economy: every item's price, tier and unlock rule, the points rules, ledgers, purchases, milestones, streak freezes and limited shelves;
  `activity-log/` pins activity records and their day files: how a record is normalized, which day file it lands in, the exact file text and how older or broken files read;
  `streaks-recap/` pins streaks (with freezes and milestones), the study heatmap and weekly recaps over sample activity logs;
  `anki/` pins AnkiConnect: the requests a refresh sends, how recorded replies (failures included) become the summary, and the connection states;
  `kits/` pins kits: every bundled kit and malformed ones, the errors and warnings validation gives, and the layout and settings applying them gives;
  `onboarding/` pins first-run setup: step order and skipping for different kits, answers and tab choices;
  `formatting/` pins durations and date ranges in all 12 languages;
  `break-buddy/` pins the break buddy: its moves, which move the planner picks for a break and the water tally's counts.

Fixtures are regenerated only on purpose, after an intended change:

```sh
TABBI_RECORD_FIXTURES=1 swift test --filter 'PetGoldenFrameTests|ThemeGoldenTests|StudyMethodGoldenTests|ClaudeStreamGoldenTests|FocusTimerGoldenTests|StudySessionGoldenTests|TickerGoldenTests|PlanMyDayGoldenTests|PartyProtocolGoldenTests|SyncDocumentGoldenTests|ClosetGoldenTests|ActivityLogGoldenTests|StreaksRecapGoldenTests|AnkiGoldenTests|KitGoldenTests|OnboardingGoldenTests|FormattingGoldenTests|BreakBuddyGoldenTests'
```

A push to a branch named `shared/...` runs `.github/workflows/record-fixtures.yml`, which records the newer fixtures on a Mac runner, uploads `shared/fixtures/` as the `fixtures` artifact and then checks the tests against that recording.
Fetch it with `gh run download <run id> -n fixtures`.

Review the diff before committing it: every changed line is a pixel, color or timing that changed for users.

To check a data file against its schema, use any JSON Schema (draft 2020-12) validator, for example:

```sh
python3 -c 'import json, sys, jsonschema; jsonschema.validate(json.load(open(sys.argv[2])), json.load(open(sys.argv[1])))' \
  shared/schemas/kit.v1.schema.json Sources/TabbiKitCore/Kits/Bundled/medicine.json
```
