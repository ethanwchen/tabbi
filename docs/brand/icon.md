# Tabbi app icon

Tabbi's mascot is the maintainer's British Shorthair, a shaded silver cat with a famously unimpressed face, who lives in the tabs on your MacBook notch.
The icon has to say that in one glance: this particular cat, a nod to tabs, and a hint that this is a tool for getting things done.

The icon is drawn entirely in code by `scripts/make-icon.swift` (CoreGraphics, vector shapes, no source art).

## Research

### macOS 26 icon guidance

- macOS 26 (Tahoe) adopts the iOS squircle for every app icon.
  The canvas shape acts as a mask, so irregular silhouettes and frame-breaking accessories are no longer allowed.
  A legacy icon that does not fill the squircle is shrunk into a grey rounded tile ("squircle jail"), which looks broken in the Dock.
  Consequence for Tabbi: the art must fill the whole squircle edge to edge, and nothing (ears, paws, shadows) may poke out of it.
- Icons still use a 1024 px canvas.
  For `.icns` files the body is the 824 px squircle centred on the canvas (100 px margin for the drop shadow), the same grid since Big Sur.
  macOS 26 rounds the corners a little more than Big Sur did, so key details must stay clear of the corners.
- New icons are layered (background plus one or more foreground groups) and rendered with the Liquid Glass material: edge highlights, frostiness and translucency make them look lit from within.
  Apple's Icon Composer (shipped with Xcode 26) builds a `.icon` file from those layers.
- macOS 26 renders each icon in several appearances: Default (light), Dark, Clear (light and dark) and Tinted (light and dark).
  Default and Dark are designed by hand; Clear and Tinted are derived by the system from the layers' luminance, so the foreground must read as a clean shape in monochrome.
- Design guidance that carries over from the HIG: one simple, centred subject; few details; no text; avoid thin lines that vanish at small sizes; check the icon at 16 px, where it shows in Finder lists and Spotlight.

### What this means for a SwiftPM app

Tabbi is built with SwiftPM, not an Xcode project, and `scripts/assemble.sh` copies `Resources/AppIcon.icns` into the bundle (Info.plist `CFBundleIconFile` is `AppIcon`).
An `.icns` cannot carry the Dark, Clear or Tinted appearances; those need an Icon Composer `.icon` compiled into `Assets.car` by `actool` (available here at `xcrun actool`, Xcode 26.6).
Plan: ship a full-bleed squircle `.icns` (works on macOS 14 through 26 without the grey tile), and export light, dark and tinted renders as PNGs so the appearances exist as assets and can move into a `.icon` later.

### Indie Mac icons worth learning from

- Things 3: one bold, flat symbol (a checkbox) on a single colour field; perfectly readable at 16 px.
- Bear: a single friendly animal head, centred, large, with almost no inner detail; charm comes from the silhouette.
- Raycast and Arc: a strong single colour and one geometric idea; instantly spotted in a crowded Dock.
- CleanShot, Craft, Mela: soft gradients and a gentle top light, never busy.
- Lesson: one subject, one accent colour, a silhouette that survives as a blob, and charm from one small detail rather than many.

## History

The first Tabbi icon (2026) was a ginger tabby face on deep ink: folder-tab ears, a tabby "M" on the forehead and one eye winking as a checkmark.
Its layout logic carries over unchanged: a face rising from the bottom edge and filling the squircle, ears that read as folder tabs, a checkmark wink, an optical small-size drawing at 32 px and below, a glass rim and top light, and the Default, Light, Dark, Tinted and glyph set.
Its review sheets are in the git history of `docs/brand/rounds/`.

## British Shorthair redesign

Reference: a photo of the maintainer's cat lying on a pink silk pillow.
What makes her recognizable, in order:

1. A big round face with full, chubby jowls that are wider than the skull.
2. A taupe blaze: the crown is darker than the face and the colour runs down between the eyes to the bridge of the nose.
3. Heavy, half-lidded grey-green eyes whose lids slope down toward the nose: unimpressed, not angry.
4. Pale silver-beige face, white muzzle pads, chin and chest, and a small pink-tan nose.
5. Small ears set wide apart, low on the corners of the head.

The colours were sampled from the photo and brightened to studio light: fur `#EAE1D4`, jowl shade `#CDBFAE`, taupe crown `#A89A89`, ticking `#7F7264`, white `#FCFAF6`, iris `#A3AD8C`, nose `#D6978A`.

Each round is archived as a review sheet in `docs/brand/rounds/`: light desktop on top, dark below; 1024 px at half size, then 128, 32 and 16 px, then 4x pixel blow-ups of 32 and 16 px, and from round 2 on the reference photo on the right.
Dock sheets put the icon between Apple's icons at 128 and 32 px.

### Round 1: the breed, and two grounds

Sheets: `rounds/r1-navy.png`, `rounds/r1-blush.png`.

Changes from the tabby:

- The head is a skull ellipse joined (with path booleans) to two jowl ellipses, so the lower face bulges out the way a British Shorthair's does.
- The ears are smaller, lower and set wider (236 px base, 160 px tall, leaning out 0.42 rad), still tab shapes with rounded corners and a pink label inside.
- The "M" and cheek stripes are gone; the coat is silver-beige with a taupe crown, three faint ticked lines and white muzzle pads.
- The open eye is grey-green under a heavy level lid; the other eye is still the checkmark wink.
  Together they read as a deadpan wink: the cat is unimpressed, but the task is done.
- The mouth is a short flat line instead of the tabby's smiling "w".
- Two grounds were tried: deep navy (`#24335F` to `#0D1430`) and a warm blush like the pillow (`#F7D5C8` to `#E7A898`).

Verdict:

- Navy is clearly stronger.
  The pale cat glows on it at every size and on both desktops, and the dark ground still echoes the black notch.
  On blush the silver-beige face and taupe ears have almost no contrast with the ground; at 32 px the ears disappear and the icon is a pale smudge.
  Decision: navy is the Default ground.
  Blush becomes the Light appearance, which is shown on dark pages where the ground itself provides the contrast, and it echoes the pillow in the photo.
- The cat sits too low: the top 40% of the icon is empty navy.
- The lid line runs past the eye and reads as an angry eyebrow rather than a heavy lid.
- The ticked lines read as scratches, and the face is one flat beige.

### Round 2: lift, lids and the Dock

Sheets: `rounds/r2.png`, `rounds/r2-dock.png`.

Changes from round 1:

- The whole cat is lifted 56 units, so the face sits at the optical centre and the ears fill the upper corners.
- The jowls moved in a little (centres 200 units from the middle instead of 215) so the cheeks no longer touch the squircle sides.
- The eye is larger (138 by 104), and the lid line stays inside the eye and slopes 12 units down toward the nose.
- The ticked lines fade out as they run down, so they read as fur rather than marks.

Verdict:

- The eye now reads as half-lidded and deadpan, which is the cat's whole personality.
- In the Dock row it is the only character icon and sits comfortably between Clock and Messages on both desktops; the pale face on navy is as easy to spot as Messages' green.
- Beside the photo the face is still too even: the real cat's most recognizable marking, the taupe blaze down the forehead, is missing.

### Round 3: the taupe blaze

Sheets: `rounds/r3.png`, `rounds/r3-dock.png`.

Changes from round 2:

- A taupe blaze: wide across the crown, narrowing between the eyes and fading out on the bridge of the nose, like the reference.
  It is drawn at every size, so even the 16 px face has a darker crown above the eyes.

Verdict:

- Beside the photo it is now clearly this cat: the V of taupe between the eyes, the pale jowls, the white muzzle and the heavy lid.
- At 32 px the half-lidded eye, the check and the pink nose are distinct.
- At 16 px the face is a pale round blob with two ear bumps and two dark marks; it reads as a cat, but the ears are weak.
- The glyph is still the tabby's silhouette (large ears, round head) and needs the new jowls and small ears.
- `Resources/AppIcon.icns` and the 1024 px brand assets were regenerated from this round.

Next round: the glyph with the new silhouette and a half-lidded eye cut-out, stronger ears at 16 px, and the light, dark and tinted appearances reviewed together.

## Assets

`scripts/make-icon.swift` writes these to `docs/brand/assets/` on every default run.
Other parts of the project (README, website, installer, onboarding) should use them by path rather than copying or redrawing them.

| File | Use |
| --- | --- |
| `tabbi-icon-1024.png` | The shipped icon at 1024 px; the README and anywhere the app icon is shown |
| `tabbi-icon-light-1024.png` | Light appearance (blush ground), for dark pages and light marketing surfaces |
| `tabbi-icon-dark-1024.png` | macOS 26 Dark appearance |
| `tabbi-icon-tinted-1024.png` | macOS 26 Tinted appearance (luminance only) |
| `tabbi-glyph.pdf` | Monochrome vector mark, for template images in menus and small UI |
| `tabbi-glyph-256.png` | The same mark as a black PNG on transparent |

## Regenerating the icon

```sh
swift scripts/make-icon.swift            # Resources/AppIcon.icns and docs/brand/assets
swift scripts/make-icon.swift --sheet /tmp/sheet.png        # 1024, 128, 32, 16 px review sheet
swift scripts/make-icon.swift --sheet /tmp/sheet.png --reference photo.png --crop 370,300,360  # beside the reference photo
swift scripts/make-icon.swift --sheet /tmp/sheet.png --ground blush  # try a candidate ground
swift scripts/make-icon.swift --dock /tmp/dock.png          # beside Apple's icons in a Dock row
swift scripts/make-icon.swift --variants /tmp/variants.png  # every appearance and the glyph
```

The default run renders every size of the `.iconset` natively (16 to 1024 px, with the small-size drawing at 32 px and below), builds `Resources/AppIcon.icns` with `iconutil`, and exports the assets above.
The output is deterministic, so an unchanged script rebuilds a byte-identical `.icns` and leaves every asset untouched.
The glyph PDF is only rewritten when its drawing changes, since Quartz stamps each PDF with a new date and file ID.

How the icon reaches the app: `scripts/assemble.sh` (used by `scripts/bundle.sh` and `scripts/run.sh`) copies `Resources/AppIcon.icns` into `Tabbi.app/Contents/Resources/AppIcon.icns`, and `Resources/Info.plist` names it with `CFBundleIconFile` = `AppIcon`.
After regenerating, rebuild the bundle with `scripts/bundle.sh`; Finder and the Dock may keep a cached icon until the app is moved or `killall Dock` is run.
