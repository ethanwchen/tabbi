# Theme golden fixtures

Written by `Tests/TabbiKitCoreTests/ThemeGoldenTests.swift` from the Swift theme catalog.
`themes.json` was first recorded while the themes were still Swift, so it proves the move to `Sources/TabbiKitCore/Themes/themes.json` changed no color.

The file has `schema` (`tabbi.themes.golden`) and `version` (1).
Every color is written out as `red`, `green`, `blue` and `opacity`, each 0...1, with no shorthand.

- `defaultTheme` and `legacyKitThemes`: the theme used when nothing picks one, and old kit `theme` values to the theme they mean.
- `themes`: every theme in picker order, fully resolved: its names, its enum values (`family`, `accents`, `typeface`, `motion`, `controls`, `surfaces`) and every palette color by role.
  `family` is the resolved picker group (`sweet` for a theme whose `group` is `sweet`, though its `family` in `themes.json` is `cozy`).
  `glow` is absent for a flat body, and `accent` and `onAccent` for a theme without a key color of its own.
  `resolved` is what the theme draws for Study's amber accent (red 1, green 0.62, blue 0.26): `accent` (the theme's key color, or the treated module accent), `identityAccent` (always the treated module accent) and `onAccent` (the palette's, or the background).
- `glassSheen`: the light drawn on glass cards.
- `accentSamples`: inputs and outputs of the accent treatments.
  `base` is a module accent (every shipped module's accent, plus a gray, a dark blue and black as edge cases), and `treated` is what each treatment (`original`, `monochrome`, `vivid`, `pastel`) makes of it.

Compare colors within 1e-9 per component.
The old Swift computed some of them (`0.9580000000000001`) where the data writes them as typed (`0.958`), and a pixel is a step of 1/255, so the tolerance hides no visible change.
