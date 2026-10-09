# Pet golden fixtures

Written by `Tests/TabbiKitCoreTests/PetGoldenFrameTests.swift` from the Swift pet composer.
They were first recorded while the pet art was still Swift string grids, so they prove the move to JSON changed no pixel.

Every file has `schema` (`tabbi.pets.golden`) and `version` (1).
A dress is a breed, an outfit and a list of accessories, by their raw names (`orangeTabby`, `scrubs`, `stethoscope`).

## Frames and symbols

A frame is a 32 by 32 canvas (`frameSize`) of palette roles.
A pixel is written as the role's grid symbol (`PetPaletteRole.symbol`, for example `O` outline, `B` fur base) or `.` when transparent.
Mouth pixels stay `R` here; the renderer picks their color from the fur around them.

Run-length rows (`rle`): rows joined by `/`, each row a list of runs written as an optional decimal count and a symbol.
`12.3B.` is twelve transparent pixels, three `B` pixels and one transparent pixel.

## Files

- `palettes.json`: every breed's palette after the visible rim is applied, role name to `#RRGGBB`, plus the rim color.
- `frames.json`: readable frames for a compact subset.
  `clips` has every animation of an orange tabby and a golden retriever, with each frame's duration in seconds and optional speech-bubble anchor `[x, y]`.
  `sitting` has the sitting frame of every breed, and of both pets in each outfit and each accessory.
- `composed-digests.json`: one SHA-256 per dress over every frame of every animation, for every breed bare, in each outfit, in each accessory and in four full looks.
  The digest covers, for each animation in declaration order: the animation name and a 0 byte, the frame count as UInt32, then per frame the duration as Float64 bits, a bubble anchor flag byte, the anchor x and y as Int32 (0 when absent) and the 1,024 row-major symbol bytes.
  A frame where an animated costume item moves (its `itemFrames`, one per tick of the item clock, `itemFrameDuration` in `costume.json`) then adds the item frame count as UInt32 and each item frame's 1,024 symbol bytes; frames that hold still add nothing.
  All integers are little-endian.
  `frameCount` is the total number of frames, a quick first check before comparing digests.
