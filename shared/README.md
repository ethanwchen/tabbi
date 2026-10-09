# shared

Data that both the Mac app and the planned Windows app read, and golden fixtures that keep their logic in step.
See `docs/windows/plan.md` (section 3) for why, and `docs/windows/phase0.md` for what is done.

- `schemas/` holds JSON Schema files for the data formats both apps read.
  `pets.v1.schema.json` describes the pet art, breeds and animation timelines in `Sources/TabbiKitCore/Pets/PetArt/`.
- `fixtures/` holds golden fixtures written by the Swift tests.
  Each port checks its own output against them, so drift between the apps fails a test.

Fixtures are regenerated only on purpose, after an intended change:

```sh
TABBI_RECORD_FIXTURES=1 swift test --filter PetGoldenFrameTests
```

Review the diff before committing it: every changed line is a pixel, color or timing that changed for users.
