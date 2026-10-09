# Windows phase 0: shared data

Status of phase 0 from `docs/windows/plan.md`: the Mac app's shared pieces move to platform-neutral data, with nothing a Mac user can see changing.

## Done

- `shared/` exists, with golden fixtures under `shared/fixtures/`.
- Pet golden fixtures (`shared/fixtures/pets/`), recorded from the Swift string-grid art before any of it moved:
  a SHA-256 digest of every composed frame of every animation for every breed in each outfit, each accessory and four full looks (612 dresses, 76,500 frames),
  readable run-length frames for a cat and a dog,
  and every breed's palette.
  `PetGoldenFrameTests` compares the live composer against them on every `swift test`.

## Next

1. Define the `pets.v1` JSON schema and move the art from `Pets/Art` into JSON resources loaded by `TabbiKitCore`, with the pet golden tests unchanged and green.
2. Themes and study methods to JSON, each pinned by a golden test written before the move.
3. JSON Schema files for kits, editions and `catalog.json`.
4. Logic fixtures for the TypeScript port: focus timer and study session sequences, the stream-json parser, Plan my day, ticker selection.
5. Snapshot comparison against `main`, pixel for pixel.
