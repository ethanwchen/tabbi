# Theme golden fixtures

Written by `Tests/TabbiKitCoreTests/ThemeGoldenTests.swift` from the Swift theme catalog.
`themes.json` was first recorded while the themes were still Swift, so it proves the move to `Sources/TabbiKitCore/Themes/themes.json` changed no color.

The file has `schema` (`tabbi.themes.golden`) and `version` (1).
Every color is written out as `red`, `green`, `blue` and `opacity`, each 0...1, with no shorthand.

- `defaultTheme` and `legacyKitThemes`: the theme used when nothing picks one, and old kit `theme` values to the theme they mean.
- `themes`: every theme in picker order, fully resolved: its names, its enum values (`family`, `accents`, `typeface`, `motion`, `controls`, `surfaces`) and every palette color by role.
  `glow` is absent for a flat body.
- `glassSheen`: the light drawn on glass cards.
- `accentSamples`: inputs and outputs of the accent treatments.
  `base` is a module accent (every shipped module's accent, plus a gray, a dark blue and black as edge cases), and `treated` is what each treatment (`original`, `monochrome`, `vivid`, `pastel`) makes of it.

Compare colors within 1e-9 per component.
The old Swift computed some of them (`0.9580000000000001`) where the data writes them as typed (`0.958`), and a pixel is a step of 1/255, so the tolerance hides no visible change.
