# Tabbi themes

A theme styles the open panel: its surfaces, text, accents, type and motion.
The closed notch always stays pure black, so it keeps reading as part of the hardware.
Users pick a theme in **Settings > Look**, which shows a live mini preview of each one, and a kit can start in one through its `theme` field (see [docs/kits.md](../kits.md)).
How to add a theme is in [CONTRIBUTING.md](../../CONTRIBUTING.md#add-a-theme).

## Where it lives

- `Sources/TabbiKitCore/Themes/themes.json`: every theme as data (`themes.v1`, described by `shared/schemas/themes.v1.schema.json`), which `ThemeCatalog` loads, so the Mac app and the Windows port share one source.
- `Sources/TabbiKitCore/Themes/`: the themes as pure values (`AppTheme`, `ThemePalette`, `ThemeCatalog`) and the rules that pick an accent, a typeface, a motion style and a control material, tested in `ThemeTests`.
  `shared/fixtures/themes/themes.json` pins every resolved color and what each accent treatment makes of the module accents.
- `Sources/TabbiKit/Design/Theme.swift`: the SwiftUI tokens (`Theme.Palette`, `Theme.Typography`, `Theme.Motion`) read the active theme, so modules never name a theme.
  `controlBackground` draws small floating controls with the theme's material.
- `swift run Tabbi --snapshot snapshots-themes --theme all` renders every panel once per theme, one folder per theme.

## The themes

| Theme | Family | Look |
| --- | --- | --- |
| Midnight | Classic | Hardware black with white text: the original look and the Essentials default. |
| Graphite | Classic | Cool gray surfaces and plain SF Pro. |
| Liquid Glass | Classic | Frosted glass cards over a cool blue glow, with Liquid Glass controls on macOS 26. |
| Neon | Classic | Vivid accents and a violet glow. |
| Monochrome | Classic | Grayscale accents; errors keep a soft red so they are never lost. |
| Cozy | Cozy | Warm cream text, a peach glow, sage and honey status colors: the Med School default. |
| Sakura | Cozy | Cherry blossom pink on warm black. |
| Forest | Cozy | Mossy sage greens. |

Each theme is a few independent choices:

- `palette`: surfaces, text levels, status colors and an optional `glow` that rises softly from the bottom of the open panel, so the top still meets the hardware notch in black.
- `accents`: how module accents are treated (`original`, `monochrome`, `vivid`, saturated and lifted until it reads on black at 4.5:1, or `pastel`, mixed toward cream for the cozy family), so one theme restyles every module without the module knowing.
- `typeface`: SF Pro Rounded (the default) or SF Pro.
- `motion`: `standard`, or `gentle` for the cozy themes, which plays every motion token 30% longer with 0.08 less bounce (see [motion.md](motion.md)).
- `controls`: `solid` surfaces, or `glass` for Liquid Glass.
- `surfaces`: `flat` cards, or `glass` for frosted cards (`GlassSheen`).

## Rules every theme keeps

- **An opaque black body.** Apple's Dynamic Island uses an opaque black background, not glass, so the panel body stays black and meets the hardware notch with no visible seam.
  A glow is a tint over the black, at most 0.3 opacity.
- **Readable text.** On a card lit by the full glow, primary text reaches 7:1, secondary text 4.5:1 (the minimum for text up to 17 pt) and tertiary metadata 2.5:1.
  `ThemeTests` checks every theme.
- **Color means the same thing.** One accent per module, and status colors (success, warning, danger) are never reused for decoration.
- **No thin weights.** Type uses regular to bold weights; SF Pro Rounded is Apple's sanctioned soft voice, which suits the cozy family without leaving the system font.

## Liquid Glass

Apple describes Liquid Glass as a functional layer for controls and navigation that floats above content, and asks apps not to use it in the content layer and to use it sparingly.
Glass over plain black has almost nothing to refract, so an earlier version kept cards opaque and put glass only on small controls.
In practice that made the theme nearly indistinguishable from Midnight.
So the Liquid Glass theme now gives the glass something to catch: a cool blue glow rises from the bottom of the black body, and cards become frosted glass panes.

A glass card (`surfaces: .glass`) is two layers:

- A live layer: `glassEffect(.regular)` on macOS 26, `.ultraThinMaterial` on macOS 14 and 15, nothing with Reduce Transparency on or in snapshots.
- A painted `GlassSheen` in every case: a fill lit from the top, a soft glint near the top-leading corner and a rim that catches the light.

Because the sheen is plain paint, snapshots and Reduce Transparency still show the glass look, and `GlassSurfaceRenderingTests` renders a card in both themes to prove it.
`ThemeTests` checks that text keeps 7:1 (primary) and 4.5:1 (secondary) on the brightest part of the sheen over the full glow.

`ControlMaterial.resolve` picks what a glass control is drawn with on the user's Mac:

| Situation | Drawn with |
| --- | --- |
| macOS 26 or later | Interactive `glassEffect(.regular)`, the variant meant for text, tinted when it marks a selection |
| macOS 14 or 15 | `.ultraThinMaterial` under the palette's surface, with a lit rim on the top edge |
| Reduce Transparency is on | The palette's opaque surface |
| Snapshot rendering (`ImageRenderer` draws neither glass nor materials) | The opaque surface with the lit rim |

## Sources

- Apple HIG, Color: https://developer.apple.com/design/human-interface-guidelines/color
- Apple HIG, Live Activities (black opaque background, bold brand colors): https://developer.apple.com/design/human-interface-guidelines/live-activities
- Apple HIG, Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- Apple HIG, Accessibility (contrast minimums, Reduce Transparency, Reduce Motion): https://developer.apple.com/design/human-interface-guidelines/accessibility
- Applying Liquid Glass to custom views: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- Adopting Liquid Glass: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Nielsen Norman Group, Liquid Glass: https://www.nngroup.com/articles/liquid-glass/
