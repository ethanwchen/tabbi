# StudyNotch pets

A study-buddy cat or dog lives in the notch.
This document explains how pet sprites are drawn, composed, and rendered, and how to add a breed.

Status: the sprite format, palettes, pattern zones, renderer, and all eight cat breeds (sitting pose) exist.
Dogs, costumes, and animations are in progress.

![All cat breeds sitting, on black at 4x](images/cats-sitting.png)

## Look at the art

```sh
swift run PetGallery /tmp/petgallery   # writes contact sheets as PNGs at 4x
```

Sheets are drawn on pure black, exactly like the notch.
Do not commit the output folder; curated sheets live in `docs/studynotch/images/`.

## Sprite format

Art is plain text inside Swift string literals (`Sources/NotchDeckCore/Pets/Art/`).
Each character is one pixel.
A grid never stores a color, only what the pixel *means*; palettes turn meanings into colors.
That is what lets one drawing serve every breed, user recolor, and costume color.

```swift
static let ear = SpriteGrid(art: """
    .ee.
    ePPe
    eBBe
    """)
```

All rows of a grid must be the same width.
Parse errors report the 1-based row and column of the problem.

### Palette roles (uppercase)

| Symbol | Role | Used for |
| --- | --- | --- |
| `O` | outline | inner lines, mouth; outer outlines are automatic |
| `B` | furBase | main fur |
| `S` | furShade | shading, leg separation |
| `A` | furAccent | stripes, points |
| `K` | furSpot | second marking color (calico black) |
| `W` | belly | light fur |
| `E` | eye | pupils |
| `L` | eyeLight | eye highlight |
| `N` | nose | nose |
| `P` | blush | cheeks, inner ears |
| `C` | costumeBase | clothing |
| `D` | costumeShade | clothing shading |
| `T` | costumeTrim | collars, cuffs, piping |
| `M` | metal | stethoscope, head mirror |
| `Z` | effect | sleep "z", sparkles, speech bubble |
| `H` | heart | celebration heart |

### Special cells

| Symbol | Meaning |
| --- | --- |
| `.` or space | transparent, lower layers show through |
| `x` | erase whatever lower layers painted here (a cap hiding ear tips) |

### Pattern zones (lowercase)

Shared body art marks regions whose color depends on the breed.
Each breed's `PetPattern` maps a zone to a palette role.
Unmapped zones fall back to their default.

| Symbol | Zone | Default |
| --- | --- | --- |
| `m` | muzzle | belly |
| `c` | chest | belly |
| `p` | paws | furBase |
| `t` | tailTip | furBase |
| `e` | ears | furBase |
| `f` | mask (center of the face) | furBase |
| `s` | stripes | furBase |
| `a` | patchA | furBase |
| `b` | patchB | furBase |

For example, the tuxedo maps paws, muzzle, chest, and mask to `belly`, and the Siamese maps ears, mask, muzzle, paws, and tail tip to `furAccent`.

## Composition

Every frame is a 32x32 canvas with the paws on the bottom row, so frames swap without jitter.
Layers are stamped in order, later layers painting over earlier ones:

1. body (shared per body shape)
2. pattern (the breed's zone map, applied while stamping)
3. face (eyes, nose, blush; swapped for blinks and expressions)
4. costume
5. accessory

After stamping, `PetCanvas.outlined()` adds a one-pixel outline around the whole silhouette using direct neighbors only, so corners stay round and every costume is outlined consistently.

## Colors and visibility on black

`PetPalette` holds one color per role.
Breeds define a default palette; a pet profile applies user overrides on top with `applying(_:)`.
Always render through `withVisibleRim()`: when the fur is dark and the outline is too, the outline becomes a warm light rim (`PetPalette.warmRim`) so black and tuxedo cats never vanish on the black notch.
This also protects user recolors.

## Rendering

`PetRenderer` turns a canvas plus palette into a `CGImage`, writing every sprite pixel as an exact `scale`x`scale` block for crisp nearest-neighbor scaling.
`PetRenderer.shared` caches results, since an idle animation repeats a handful of frames.

## Adding a breed

1. Add a case to `PetBreed` with its `displayName`.
2. Pick a `bodyShape`. Reuse an existing one if the silhouette fits; add a new shape (and its art) only when ears, snout, or body need to differ to be recognizable at 24-32 pt.
3. Give it a `palette` with at least `furBase`, `furShade`, `furAccent`, and `belly`.
   Keep the outline dark for light fur; dark fur gets the warm rim automatically.
4. Map pattern zones in `pattern` to place its markings.
5. Run `swift test` and `swift run PetGallery /tmp/petgallery`, then review the sheet on black at 1x and 4x.
