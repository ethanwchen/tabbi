# Tabbi app icon

Tabbi's mascot is the maintainer's British Shorthair, a shaded silver cat with round blue eyes, who lives in the tabs on your MacBook notch.
The icon has to say that in one glance: this particular cat, a nod to tabs, and a hint that this is a tool for getting things done.

The icon art is `docs/brand/source/tabbi-cover.png`, a flat cover illustration of the cat generated with the ip-as-logo recipe (see Cover art below).
`scripts/make-icon.swift` masks it into the macOS squircle with the drop shadow and glass rim, and still draws the monochrome glyph in code.
Without the cover file it falls back to the code-drawn cat described in History.

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

The colours were first sampled from the photo and brightened to studio light, then in round 5 aligned with the pet sprite's British Shorthair palette (`PetBreed.britishShorthair`), so the icon and the cat in the notch are the same cat.
The shipped colours: fur `#E6DFD5`, jowl shade `#CAC1B5`, taupe crown `#ADA398`, ticking `#756D66`, white `#F8F5EF`, inner ear `#E6B3AC`, iris `#3F86D6` to `#5FA3EA` (round 6 on), nose `#D29A8A`.

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

### Round 4: small sizes and the glyph

Sheets: `rounds/r4.png`, `rounds/r4-dock.png`, `rounds/r4-variants.png`.

Changes from round 3:

- At 32 px and below the ears are cut taller (220 units instead of 160) and more upright (0.30 rad instead of 0.42), in solid ticking taupe with a small pink label.
  Before, the taupe ears ran into the taupe crown and the head read as a box; now each ear rises above the crown as its own bump.
- The small-size eye is taller (156 units) with the lid a little higher, so at 16 px it is a solid dark pixel pair instead of a grey smear, and the checkmark is 70 units wide instead of 62.
- The glyph is redrawn with the new silhouette: a round skull joined to two chubby jowls, small upright tab ears, a half-oval eye cut-out whose flat top is the lid sloping toward the nose, the checkmark wink and the nose.

Verdict:

- At 16 px the icon is now a pale round face with two dark ear bumps, two dark eye marks and a pink nose on navy: a cat, and the same cat as at 1024 px.
- At 32 px the ears are clearly tabs with a pink label, and the deadpan eye and the check read as a wink.
- In the Dock it is the only character icon and holds its own between Clock and Messages on both desktops.
- The glyph keeps the deadpan wink in one colour: the heavy lid survives even at 16 px as a flat-topped hole.
- The Light (blush), Dark and Tinted appearances were reviewed side by side: all three keep the cat recognizable, and the Tinted render separates the ears, crown and eyes by luminance alone.
- `Resources/AppIcon.icns` and the glyph assets were regenerated from this round.

### Round 5: one cat with the pet

Sheets: `rounds/r5.png`, `rounds/r5-dock.png`, `rounds/r5-variants.png`.

The pet sprite's British Shorthair was redrawn from the same photo in parallel.
Its palette came out a little cooler and greyer than the icon's, so the two cats looked like relatives rather than the same animal.

Changes from round 4, colour only (the shapes are unchanged):

- Shared roles take the sprite's colours: taupe crown `#ADA398` (the sprite's fur shade), ticking `#756D66` (its accent), white `#F8F5EF` (its belly), inner ear `#E6B3AC` (its blush), iris `#9AA889` and nose `#D29A8A`.
- The icon is lit and the sprite is flat, so the sprite's base fur `#D6CEC3` sits between the icon's lit fur `#E6DFD5` and its jowl shade `#CAC1B5`, which keeps the round modelling of the face.

Verdict:

- Next to the photo the coat now reads more silver and less cream, which is closer to the real cat.
- On navy the face still glows: the contrast barely moves, and the 16 and 32 px renders are unchanged in shape and clarity.
- The Light, Dark and Tinted appearances keep the cat recognizable; Tinted is unchanged because it carries its own greys.
- `Resources/AppIcon.icns`, the 1024 px assets, every derived image and the DMG background were regenerated from this round.

### Rounds 6 to 8: open, cute blue eyes

Maintainer request: "Make sure the eyes on the British Shorthair are open and cute. Blue eye."
The pet sprite got round blue eyes at the same time, so the icon follows it.

Round 6 (`rounds/r6.png`):

- The half-lidded grey-green eye is replaced by a round, wide-open eye: a blue iris (the sprite's `#3F86D6` at the top, lit to `#5FA3EA` at the bottom), a dark pupil, a thin dark rim, a big white catch light up and to the left and a small one low on the right.
- The flat, downturned mouth becomes a short line under the nose that opens into a gentle "w", a content little smile.
- At 32 px and below the eye is a blue disc around a dark pupil instead of a dark half-oval.
- Verdict: friendly at once, and the 16 px render still shows a blue eye with a dark centre.
  But the eye is small next to the heavy checkmark, and the iris ring is thin and lopsided.

Round 7 (`rounds/r7.png`, `rounds/r7-dock.png`):

- The eye grows from 118 by 128 to 136 by 146 units, and the catch light is bigger and closer to the centre.
- Verdict: the eye and the check now balance as a wink.
  In the Dock the open eye is the first thing you see, on both desktops.
  Up close the pupil is a narrow oval that reads a little startled, and the rim is heavier than it needs to be.

Round 8 (`rounds/r8.png`, `rounds/r8-dock.png`, `rounds/r8-variants.png`):

- A rounder, larger pupil (a kitten's proportions) and a lighter 8-unit rim.
- A soft pink blush under each eye, in the inner-ear colour, drawn at 1024 and 128 px only.
- The glyph's eye is a round hole with its catch light left standing, so the one-colour mark is wide open too.
- Verdict: cute and clear at every size.
  The Light, Dark and Tinted appearances keep the round eye; Tinted turns it a mid grey with the same dark pupil and white catch lights.
  `Resources/AppIcon.icns`, the 1024 px assets and the glyph were regenerated from this round.

## Cover art

The cover follows the same recipe as the Tapir app icon: the [ip-as-logo](https://github.com/s1dashu/ip-as-logo-skill) skill's prompt skeleton, rendered once by OpenAI GPT Image 2 at 1024 px.
The subject is the maintainer's British Shorthair as a chubby kitten face: pale silver-cream fur, taupe tabby stripes on the forehead and ear tips, the banded tail peeking in, round blue eyes and a small pink nose, emerging from the lower left of a muted golden yellow ground.
It was candidate A3 of five (navy, rose, yellow, and two whole-body loaf poses).
The exact prompt is saved beside it as `tabbi-cover.prompt.txt`.
The image is used as generated, with no retouching.

Tinted renders the cover in luminance only; Default, Light and Dark use it unchanged, since an `.icns` cannot carry appearances anyway.

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

## Derived images

Every other image that shows the icon is made from the assets above, so after a redesign regenerate them all and check that the old cat appears nowhere.

| Image | How it is made |
| --- | --- |
| `docs/images/icon.png` (README) | `sips -Z 256 docs/brand/assets/tabbi-icon-1024.png --out docs/images/icon.png` |
| `docs/images/social-preview.png` | `swift docs/make-screenshots.swift`, which places `docs/images/icon.png` beside the name (it also rewrites the other README screenshots, whose clocks differ on every run) |
| `docs/images/install/gatekeeper-steps.png` | `swift docs/images/install/render-gatekeeper-steps.swift`, which reads `Resources/AppIcon.icns` |
| The DMG window background | `packaging/dmg/render-background.swift` at build time. Its palette mirrors the cover icon: the golden ground, the cat's two blue eyes and pink nose peeking out of the notch, and a taupe arrow in the tabby stripes' colour. The ground is light enough that Finder's black labels need no backing pills |
| `docs/images/install/dmg-window.png` | A screenshot of the real installer: `scripts/make-dmg.sh`, mount the DMG, then `screencapture -l <window id>` of its Finder window. For an icon-only change it can be repainted in place: the background art sits at (112, 140) in the 2x capture, so add the new minus the old `background@2x.png` there, draw the 1024 px asset at 258 px over the new background for the Finder icon, and the iconset's `icon_16x16@2x.png` for the title bar |
| `docs/images/install/move-prompt.png`, `settings-about.png` | Screenshots of the running app. For an icon-only change the icon can be repainted in place: both show it on a flat surface, at 128 and 200 px with its 824/1024 body at the same spot, so the new 1024 px asset drawn into that rect matches a fresh capture |

The pixel pet in the notch screenshots, the hero GIF and the social preview's Study panel is the pet sprite, not the icon.
It is the demo pet (Mochi, a British Shorthair, from `PetCloset` in `TabbiKitCore/Closet`), so it changes with the pets, not with the icon.
After a change to the British Shorthair sprite, run `swift docs/make-screenshots.swift` again so the social preview and README shots show it, and check the hex values quoted above against `PetBreed.britishShorthair`.
