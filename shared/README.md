# shared

Data that both the Mac app and the planned Windows app read, and golden fixtures that keep their logic in step.
See `docs/windows/plan.md` (section 3) for why, and `docs/windows/phase0.md` for what is done.

- `schemas/` holds JSON Schema files for the data formats both apps read.
  `pets.v1.schema.json` describes the pet art, breeds and animation timelines in `Sources/TabbiKitCore/Pets/PetArt/`.
  `themes.v1.schema.json` describes the themes in `Sources/TabbiKitCore/Themes/themes.json`.
  `study-methods.v1.schema.json` describes the study methods in `Sources/TabbiKitCore/StudyMethods/study-methods.json`.
  `kit.v1.schema.json` describes kit files (`formatVersion` 1), bundled in `Sources/TabbiKitCore/Kits/Bundled` or imported; see `docs/kits.md`.
  `edition.v1.schema.json` describes the edition files in `Sources/TabbiKitCore/Editions/BundledEditions`.
  `catalog.v1.schema.json` describes the Party catalog, `backend/shared/catalog.json`.
  `SharedSchemaTests` keeps the kit and edition schemas' fields, limits and patterns equal to the Swift decoders, and the catalog schema equal to the catalog's fields.
- `fixtures/` holds golden fixtures written by the Swift tests.
  Each port checks its own output against them, so drift between the apps fails a test.
  `pets/`, `themes/` and `study-methods/` pin the data files above; `claude-stream/` pins how the `claude` CLI's stream-json lines are parsed and folded into an Ask Claude chat;
  `focus-timer/` pins the shared Pomodoro: its steps, readouts, shared focus clock and logged activity;
  `ticker/` pins which items the closed notch can show, when it next has to look again, and which one the rotation picks.

Fixtures are regenerated only on purpose, after an intended change:

```sh
TABBI_RECORD_FIXTURES=1 swift test --filter 'PetGoldenFrameTests|ThemeGoldenTests|StudyMethodGoldenTests|ClaudeStreamGoldenTests|FocusTimerGoldenTests|TickerGoldenTests'
```

Review the diff before committing it: every changed line is a pixel, color or timing that changed for users.

To check a data file against its schema, use any JSON Schema (draft 2020-12) validator, for example:

```sh
python3 -c 'import json, sys, jsonschema; jsonschema.validate(json.load(open(sys.argv[2])), json.load(open(sys.argv[1])))' \
  shared/schemas/kit.v1.schema.json Sources/TabbiKitCore/Kits/Bundled/medicine.json
```
