# Contributing to Tabbi

Thanks for helping make the notch more useful.
Bug reports, design feedback, and pull requests are all welcome.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) before you take part.
Report security issues privately as described in [SECURITY.md](SECURITY.md), not in a public issue.

## Dev setup

You need macOS 14 Sonoma or later and Xcode 26 or later (its SDK has the Liquid Glass API the themes use).
A MacBook with a notch is nice to have but not required: other displays get a virtual notch at the top center of the screen.

```sh
git clone https://github.com/ethanwchen/notchdeck.git
cd notchdeck
swift build                     # compile; must stay warning-free
swift test                      # unit tests for TabbiKitCore and the app wiring
scripts/run.sh                  # bundle build/Tabbi.app (debug) and launch it
```

`scripts/run.sh` quits any running Tabbi before it relaunches the fresh build.
To quit the app yourself, right-click the notch and choose **Quit Tabbi**.

There is no Xcode project.
Open the folder in Xcode (`xed .`) if you want the IDE; it reads `Package.swift` directly.

## Demo mode

Set `TABBI_DEMO=1` to replace every data source with realistic sample data:

```sh
TABBI_DEMO=1 scripts/run.sh
```

Demo mode never talks to Spotify, Music, Calendar, the network, or the `claude` CLI.
If you add a data source, give it demo data too, so screenshots and reviews never depend on someone's personal setup.

## Snapshot workflow

Tabbi can render every notch state to PNG without opening a window.
Use it to check your UI change, and attach the result to your pull request.

```sh
TABBI_DEMO=1 swift run Tabbi --snapshot snapshots   # sample data
swift run Tabbi --snapshot snapshots-live               # your real data, or the empty states
```

This writes, for the active kit (pick one with `--kit <id>`):

- `closed.png`, plus one `closed-<item>.png` per closed-notch preview item that has data (`meeting`, `music`, `focus`, `tasks`, `progress`, `usage`, `pet` and `pet-asleep`, `party`).
- One `open-<module>.png` per module, including modules the kit leaves off (shown as if switched on), plus `open-closet-look` (the Closet's second section) and `open-pet-shortcut` (the paw at the far right of the header).
- `onboarding-*.png`, one per first-run setup step of the kit, and `settings-*.png`, one per Settings pane.
- `coach-*.png` and `motion-*.png`, frame strips of the pet coach and the shared motion.

Add `--theme all` to render every notch shot once per theme, one subfolder per theme.
Look at both runs:

- The demo run shows the panel with realistic content.
- The live run on a machine without Spotify, a calendar, or `claude` shows the empty and unavailable states.
  These must look designed, never blank or like a raw error.

Judge the images against the [design rules in AGENTS.md](AGENTS.md#design-rules): alignment, spacing on the 4 pt grid, one primary element per panel, no truncation or clipping at the canvas edges.
Do not commit snapshot folders.

## Architecture

[AGENTS.md](AGENTS.md) is the source of truth for the architecture, design rules, and project rules.
It is written for both human contributors and coding agents.
In short:

| Path | What lives there |
| --- | --- |
| `Sources/TabbiKitCore` | Pure Swift with no AppKit or SwiftUI: parsers, models, stores, formatting. Everything here has unit tests in `Tests/TabbiKitCoreTests`. |
| `Sources/TabbiKit` | Shared AppKit and SwiftUI: the design system in `Design/Theme.swift` (palette, type, spacing, radius, motion, plus `Card` and `IconButton`), shared components, the notch panel, shape and geometry, the notch's open/close and tab state with its tab bar, the root notch view with its closed-notch preview, the notch controller (panel placement, pointer, keyboard, swipe and hotkey input), pet views, the focus audio engine, and the settings infrastructure (the toolbar Settings window and the shortcut recorder field). The app fills the notch through `ModuleViews.notchContent` and `ModuleViews.notchInputs`. |
| `Sources/Tabbi/Modules/<Module>/` | One folder per module: an `ObservableObject` store, its SwiftUI views, and a `NotchModule` with its descriptor. `ModuleList.swift` lists every module, one per line. |
| `Sources/TabbiKitCore/Claude` | `ClaudeCLI` and the stream-json parser used by both Claude modules. |

Put logic you can test without a UI in `TabbiKitCore`, and test it through its public API.
When you work on one module, keep your changes inside that module's folders and their tests.
Touch the shared files only when you have to, and keep those edits small.

## Extending Tabbi

Most additions are a few lines in one place, plus a test.
[AGENTS.md](AGENTS.md#adding-a-module) walks through adding a whole module.

### Add a theme

Themes live in `Sources/TabbiKitCore/Themes/ThemeCatalog.swift`.
[docs/design/themes.md](docs/design/themes.md) explains what a theme controls and the rules every theme keeps.

1. Add a `ThemeID` constant in `AppTheme.swift`.
2. Declare the theme in `ThemeCatalog` with a name, a one-line summary, a `family` (`.classic` or `.cozy`, which picks its group in Settings > Look) and a `ThemePalette`.
   Cozy themes can reuse `cozyPalette(glow:tint:)`.
3. Choose its `accents` (`original`, `monochrome`, `vivid` or `pastel`), `typeface`, `motion` and `controls` (`glass` draws Liquid Glass on macOS 26, a translucent material on macOS 14 and 15, and a solid surface when Reduce Transparency is on).
4. Add it to `ThemeCatalog.all` in picker order, update the order in `ThemeTests`, and add the id to the `theme` row in [docs/kits.md](docs/kits.md).

Keep the panel `background` opaque black and any `glow` at 0.3 opacity or less, so the open panel still meets the hardware notch.
`ThemeTests` checks both, and checks that primary, secondary and tertiary text stay readable on a card lit by the glow.
Render every panel in the new theme and look at each one:

```sh
TABBI_DEMO=1 swift run Tabbi --snapshot snapshots-themes --theme all
```

A kit can start in the theme by naming its id in the kit's `theme` field (see [docs/kits.md](docs/kits.md)).

### Add a pet breed

Breeds are pixel art in `Sources/TabbiKitCore/Pets`: add a `PetBreed` case, pick or draw a body shape, and give it a palette and pattern.
[docs/study/pets.md](docs/study/pets.md#adding-a-breed) explains the sprite format and the steps, and `swift run PetGallery /tmp/petgallery` draws contact sheets to review it on black.
Give it the server's breed name in `PartyPetAppearance.wireBreed` (the compiler asks for it), so friends see the right pet.
The breed then shows up in the Closet, the onboarding pet step, Party and kit validation with no other changes.

### Add a focus sound

Focus sounds are generated in code, so there are no audio files to ship.

1. Add a case to `FocusSound` (`Sources/TabbiKitCore/Focus/FocusSound.swift`) with a `displayName` and an SF Symbol.
2. Write its synth beside the others in `FocusAmbience.swift`: allocation-free per sample (it runs on the audio thread) and calibrated to `NoiseGenerator.targetRMS`, so layers mix at predictable levels.
3. Wire it into `FocusSoundGenerator`, and add the id to the `focus` sounds in [docs/kits.md](docs/kits.md).

`FocusAmbienceTests` checks every sound's level, DC offset, peaks and determinism; add a test for what makes the new sound recognizable, as the rain, fireplace and cafe tests do.
The Focus pane, the Study sound chip and kit validation read `FocusSound.allCases`, so the sound appears there, and kits can list its id in `focus.sounds`.

### Add a study method

Study methods are presets of one engine in `Sources/TabbiKitCore/StudyMethods`.

1. Add a case to `StudyMethodKind`.
2. Add a preset to `StudyMethod` (focus target, break rule, optional long break and review phase) and list it in `StudyMethod.presets` in picker order.
3. Write its copy in `StudyMethodInfo.info(for:)`: a name, a rhythm tagline, how to do it, and what the evidence says with an honest `evidenceLevel`.
   Cite the source in the evidence text, and keep claims to what studies support.
4. Add the id to the `study` methods in [docs/kits.md](docs/kits.md).

`StudyMethodTests` checks that every kind has a preset.
The Study tab, the onboarding study method step and kit validation pick the method up from there, and a kit offers it by listing its id in `study.methods`.
Render `TABBI_STUDY_SNAPSHOT=method:<kind> swift run Tabbi --snapshot snapshots-study --kit medicine` to see it in the Study tab and in onboarding.

## Pull request guidelines

- **Open an issue first** for new modules, new permissions, or larger design changes, so we can agree on the direction before you build it.
- **Keep each pull request focused** on one fix or feature.
- **Keep the build clean:** `swift build` with zero warnings and `swift test` green.
  CI builds with warnings treated as errors and runs the tests.
  While the repository is private, a maintainer starts CI by hand from the Actions tab.
- **Add tests** for new logic in `TabbiKitCore`.
- **Show the UI:** for any visual change, attach the relevant snapshot PNGs (demo and live), before and after.
- **Follow the design rules:** `Theme` tokens only, one accent color per module, spring animations, a hover state and a `.help(...)` tooltip on every control.
- **Respect privacy:** no telemetry and no network calls beyond what a module inherently needs.
  Claude features go only through the user's local `claude` CLI, and never read credentials or the keychain.
- **No new dependencies** without a strong reason in the pull request description.
- **Use [Conventional Commits](https://www.conventionalcommits.org/)** for commit and pull request titles, for example `feat(today): add a focus timer` or `fix(now-playing): keep the scrubber in sync after seeking`.
- Do not edit `CHANGELOG.md` in your pull request; maintainers update it when they cut a release.

## Regenerating assets

The app icon and README screenshots are generated from code, so they stay reproducible.

```sh
swift scripts/make-icon.swift            # redraws Resources/AppIcon.icns and docs/brand/assets (see docs/brand/icon.md)
sips -Z 256 docs/brand/assets/tabbi-icon-1024.png --out docs/images/icon.png   # README icon
swift docs/make-screenshots.swift        # re-renders docs/images (PNGs and the hero GIF) from Essentials and Med School demo snapshots
```

The same script writes `docs/images/social-preview.png`, the 1280x640 image GitHub shows when the repository is shared.
After regenerating it, upload it under the repository's Settings > General > Social preview.

## Releases

Maintainers cut releases with `scripts/release.sh`.
It builds a universal (Apple silicon and Intel), stripped app, signs it with the maintainer's Developer ID under the Hardened Runtime (`packaging/Tabbi.entitlements`), notarizes and staples it, and writes `Tabbi-<version>.dmg`, `Tabbi-<version>.zip` and `SHA256SUMS` to `build/release/`.
The version comes from `CFBundleShortVersionString` in `Resources/Info.plist`.
Signing needs three one-time steps (a Developer ID Application certificate, `xcrun notarytool store-credentials notchdeck`, and an update signing key from Sparkle's `generate_keys`, whose public half goes in `packaging/updates.env`); the script checks all three before building and explains what is missing.
`packaging/signing.env` picks the identity and notary profile when the defaults do not fit.
The release app checks the appcast in `packaging/updates.env` through Sparkle (Settings > About > Check for Updates, and the notch's context menu); development builds carry no feed and never update themselves.
It also writes `release-notes.md`, made from the `feat`, `fix` and `perf` commits since the previous `v*` tag by `scripts/release-notes.sh`, and `appcast.xml`, which offers the zip as the update with those notes and is signed with the update key from the login keychain (or `SPARKLE_PRIVATE_KEY` in CI).
Publish the DMG, the zip, `appcast.xml` and `SHA256SUMS` as assets of a GitHub Release tagged `v<version>`, so the feed's `releases/latest/download/appcast.xml` points at it.
Commit subjects become the release notes, so write `feat` and `fix` subjects for the people who use Tabbi.
The build number is the commit count, so release from a full clone.
Without a Developer ID, `scripts/release.sh --adhoc` builds the same files ad-hoc signed and not notarized, which is what CI runs.
