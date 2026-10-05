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
