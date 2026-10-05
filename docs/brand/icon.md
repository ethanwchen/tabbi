# Tabbi app icon

Tabbi is a tabby cat that lives in the tabs on your MacBook notch.
The icon has to say that in one glance: a friendly tabby, a nod to tabs, and a hint that this is a tool for getting things done.

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

## Concept exploration (round 0)

Each concept was rendered at 1024, 128, 32 and 16 px on a light and a dark desktop, plus 4x pixel blow-ups of the 32 and 16 px renders.

| Concept | Sheet |
| --- | --- |
| A. "Tab-by": tabby face rising from the bottom, folder-tab ears, "M" stripes, one eye winking as a checkmark, on deep ink | `rounds/r0-concept-a.png` |
| B. "Peek": tabby peeking over a strip of folder tabs, paws on the edge, tab-shaped stripes, on cream | `rounds/r0-concept-b.png` |
| C. "Pomodoro": tabby curled into a timer ring, stripes as ticks, tail as the clock hand, on cream | `rounds/r0-concept-c.png` |

Verdicts:

- A reads as a cat instantly at every size, and the checkmark wink is the single charming detail that also says "done".
  The deep ink background makes the orange glow on both light and dark desktops and echoes the black notch.
  Weak points: the ears are tall enough to read as rabbit ears, and they read as generic ears more than as folder tabs; the cheek stripes poke past the head and look like whiskers.
- B is cute, but the tab strip reads as a desk or a box, and at 32 px the tabs, paws and face merge into noise.
  Two subjects (cat plus tab bar) split the attention.
- C is the cleverest idea, but at 128 px and below it reads as a clock or a sun first and a cat second; the head is too small to carry the character, and at 16 px it is an orange ring that any timer app could own.

Decision: develop A.
Refinement goals: make the ears unmistakably folder tabs (shorter, wider, flat-topped), keep stripes inside the head, strengthen the check at small sizes, and tune the 16 px render.

## Refinement rounds (concept A)

Each round is archived as a review sheet in `docs/brand/rounds/` (light desktop on top, dark below; 1024 at half size, then 128, 32 and 16 px, then 4x pixel blow-ups of 32 and 16 px).

### Round 1: ears become tabs

Sheet: `rounds/r1.png`.

Changes from round 0:

- Ears are now short, wide, flat-topped tabs (290 px base, 170 px top, 200 px tall, leaning out 0.30 rad) instead of tall narrow ones.
  The outer edges end up nearly vertical, so each ear reads as a folder tab standing on the head while still reading as a cat ear.
  The cream inner ear sits in the tab like a label.
- Cheek stripes are clipped to the head and run in from its edge, so they read as tabby markings rather than whiskers.
- The head is a little wider (720 px) so the ears sit on its shoulders, and the "M" is a touch bolder.

Verdict:

- The rabbit-ear problem is gone; the silhouette is now a round cat face with two blocky tab ears, and it is clearly a cat at 128 and 32 px.
- At 16 px the face is an orange blob with two ear bumps: the cat survives, but the checkmark wink and the "M" turn to mush.
- The orange glow behind the head reads slightly muddy purple on the ink background.
- `Resources/AppIcon.icns` was regenerated from this round, so the bundled app shows the tabby instead of the old notch icon.

Next round: thicker check that survives at 32 px, a cleaner background light, and check how the ears sit against the squircle corners.

### Round 2: clean shadows, light and check

Sheet: `rounds/r2.png`.

Changes from round 1:

- Fixed a rendering bug that hurt every small size.
  CoreGraphics applies shadow offsets and blurs in device pixels and ignores the current transform, so the 28 px icon shadow and the 20 to 30 px head and ear shadows stayed that size at 128, 32 and 16 px.
  On the round 1 sheet this showed as a grey box around the small icons on the light desktop and a darkened, smeared face at 16 px.
  Shadows are now scaled by the render's pixel scale, so they look the same at every size.
- The warm screen-blend glow behind the head is replaced by a cool top light in the ink's own hue, like a glass layer lit from above.
  The background is now a clean indigo instead of a muddy purple, and the orange head stands out more against it.
- The checkmark wink is thicker (36 px stroke instead of 26) and a little larger, so it still reads as a dark tick at 32 px.

Verdict:

- The small icons now sit cleanly on both desktops with no halo, and the 128 px render looks like a finished Dock icon.
- At 32 px the wink reads as a mark and the face is clearly a cat; the "M" is only a smudge.
- At 16 px it is still an orange cat blob with two ears on indigo, which is the right silhouette, but the eyes and stripes turn into noise.
- The ears clear the squircle corners comfortably; the head's sides leave slim ink slivers at the bottom corners, which frame the face and are acceptable.
- `Resources/AppIcon.icns` was regenerated from this round.

Next round: an optical small-size drawing for 16 and 32 px (larger eyes and check, no cheek stripes, a bolder "M" or none), selected by render size.

### Round 3: an optical small size

Sheet: `rounds/r3.png`.

Changes from round 2:

- Renders of 32 px or less (16 pt at 1x and 2x, 32 pt at 1x) now use a separate small-size drawing of the face, selected by render size in `drawConceptA`, like a caption cut of a typeface.
  At 16 px one pixel is 64 canvas units, so anything thinner than about 50 units became grey noise.
- The small face drops the cheek stripes, the mouth and the eye's catch light.
- It grows what carries the character: a larger open eye, a 62 unit checkmark, a 52 unit "M", one wide cream muzzle and a bigger nose.
- The glass rim stroke is left out at small sizes, where it only lightened the outer pixel ring.

Verdict:

- 32 px now reads as a finished small icon: a dark eye, a clear tick, the "M" and the cream muzzle are each distinct.
- 16 px shows the eye, the wink and the muzzle as separate shapes instead of a smudged face, while keeping the round head and tab ears silhouette.
- 64 px and up are unchanged, so the 1024 and 128 px art keeps its detail.
- `Resources/AppIcon.icns` was regenerated from this round.

Next round: the light, dark and tinted variant PNGs, and a check of the 1024 px art against Apple's own icons in the Dock.

### Round 4: next to Apple's icons

Sheets: `rounds/r4.png` and `rounds/r4-dock.png`.

The script has a new `--dock <file.png>` mode.
It puts Tabbi in a Dock row between Calendar, Reminders, Notes, Clock, Messages and Music (plus Things, Linear and Anki when installed) at 128 and 32 px, on a light and a dark desktop.
The other icons come from `NSWorkspace`, so on macOS 26 they show with the system's own Liquid Glass rendering.

What the round 3 Dock row showed:

- Shape, size and drop shadow match Apple's icons; nothing looks boxed in or oversized.
- Tabbi is the only character icon in the row, and the orange face on indigo stands out without shouting, the way Linear's dark tile does.
- Apple's icons have a bright glass edge, strongest at the top, and soft rounded volume. Tabbi's faint even rim and flat head read as an older, flatter style beside them.

Changes from round 3:

- The glass rim is a 10 unit stroke with a vertical gradient: brightest at the top (55% white), faint in the middle and slightly brighter at the bottom, like the lit edge on macOS 26 icons.
- The crown of the head has a soft warm sheen from the same top light, so the face looks rounded instead of cut from flat paper.
- The rim is still left out at 32 px and smaller, where it only lightened the outer pixel ring. The sheen stays at every size; at 16 px it only warms the top of the head.

Verdict:

- At 1024 px the icon now has the same glassy edge and lighting direction as Apple's icons while keeping its flat, friendly shapes.
- In the Dock row it sits comfortably next to Calendar, Reminders and Music on both desktops and is still the most recognizable icon there at 32 px.
- `Resources/AppIcon.icns` was regenerated from this round.

Next round: the light, dark and tinted variant PNGs, the 1024 px README PNG and the monochrome glyph, then a final review of all of them together.
