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
- Breeds are data: `PetArt/breeds.json` (also `pets.v1`) holds the base palette, the species of each body shape, and each breed's name, body shape, tail, palette and pattern, in picker order.
  `PetBreed` and `PetBodyShape` keep only their cases (the ids pet saves store).
  An export of every breed definition from the new data path is identical to one taken from the old Swift switches, and `PetArtTests` keeps the schema's role, zone and species lists equal to the Swift enums.
  The pet golden fixtures (digests and palettes) did not change.

- Animation timelines are data: `PetArt/animations.json` (also `pets.v1`) holds, for each of the 19 animations, whether it loops, the frame a still pet holds, and per frame the duration, pose, stance, vertical shift, effects (grid name and position, fixed or from the head in the clip's first frame), steam wisp, dust and speech bubble.
  `PetComposer.clip` reads the timeline and keeps only the placement code (composing a pose, painting effects behind the pet, finding the paws for dust).
  One rule moved from the timeline into the composer: a toy's `bounce` lifts only a dog's ball, so the data needs no per-species values.
  The pet golden fixtures (every frame's pixels, duration and bubble anchor, and each clip's `loops`) did not change.
  Demo snapshots match the commit before, apart from shots that change between any two runs of the same build: live clocks, and the playing pet in the Closet and the onboarding pet step, whose idle breath is caught at whatever moment the shot is taken.
  Re-rendered, those pet shots matched the earlier commit pixel for pixel.

## Next

1. Themes and study methods to JSON, each pinned by a golden test written before the move.
2. JSON Schema files for kits, editions and `catalog.json`.
3. Logic fixtures for the TypeScript port: focus timer and study session sequences, the stream-json parser, Plan my day, ticker selection.
4. Snapshot comparison against `main`, pixel for pixel.
