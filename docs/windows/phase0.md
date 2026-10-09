# Windows phase 0: shared data

Status of phase 0 from `docs/windows/plan.md`: the Mac app's shared pieces move to platform-neutral data, with nothing a Mac user can see changing.

## Done

- `shared/` exists, with golden fixtures under `shared/fixtures/`.
- Pet golden fixtures (`shared/fixtures/pets/`), recorded from the Swift string-grid art before any of it moved:
  a SHA-256 digest of every composed frame of every animation for every breed in each outfit, each accessory and four full looks (612 dresses, 76,500 frames),
  readable run-length frames for a cat and a dog,
  and every breed's palette.
  `PetGoldenFrameTests` compares the live composer against them on every `swift test`.
- Pet art is data: every hand-drawn grid (cat, dog, costume, effect, paw, prop, tail and walk art, 127 grids and 12 frame sequences) is in the `pets.v1` JSON files in `Sources/TabbiKitCore/Pets/PetArt/`, a SwiftPM resource like the kits.
  Costume items carry their anchors (`rise`, `eyeRow`, `sitRow`) beside their grids.
  `PetArt` loads them, checking the schema version and every grid; the Swift in `Pets/Art/` only names the grids and generates the procedural pieces (legs, wrapped tails, the groom arm).
  `shared/schemas/pets.v1.schema.json` describes the format for the TypeScript port, and `PetArtTests` keeps its symbol pattern equal to the Swift sprite legend.
  The pet golden fixtures did not change, and the demo snapshots are pixel-identical to the commit before the move (the PNG bytes of 17 shots differ, their pixels do not).

## Next

1. Move the rest of the pet definitions to `pets.v1`: breed palettes and patterns, body shapes and animation timelines, again pinned by the pet golden fixtures.
2. Themes and study methods to JSON, each pinned by a golden test written before the move.
3. JSON Schema files for kits, editions and `catalog.json`.
4. Logic fixtures for the TypeScript port: focus timer and study session sequences, the stream-json parser, Plan my day, ticker selection.
5. Snapshot comparison against `main`, pixel for pixel.
