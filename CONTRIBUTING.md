# Contributing to NotchDeck

Thanks for helping make the notch more useful.
Bug reports, design feedback, and pull requests are all welcome.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) before you take part.
Report security issues privately as described in [SECURITY.md](SECURITY.md), not in a public issue.

## Dev setup

You need macOS 14 Sonoma or later and Xcode 16 or later (or a Swift 6 toolchain).
A MacBook with a notch is nice to have but not required: other displays get a virtual notch at the top center of the screen.

```sh
git clone https://github.com/ethanwchen/notchdeck.git
cd notchdeck
swift build                     # compile; must stay warning-free
swift test                      # unit tests for NotchDeckCore
scripts/run.sh                  # bundle build/NotchDeck.app (debug) and launch it
```

`scripts/run.sh` quits any running NotchDeck before it relaunches the fresh build.
To quit the app yourself, right-click the notch and choose **Quit NotchDeck**.

There is no Xcode project.
Open the folder in Xcode (`xed .`) if you want the IDE; it reads `Package.swift` directly.

## Demo mode

Set `NOTCHDECK_DEMO=1` to replace every data source with realistic sample data:

```sh
NOTCHDECK_DEMO=1 scripts/run.sh
```

Demo mode never talks to Spotify, Music, Calendar, the network, or the `claude` CLI.
If you add a data source, give it demo data too, so screenshots and reviews never depend on someone's personal setup.

## Snapshot workflow

NotchDeck can render every notch state to PNG without opening a window.
Use it to check your UI change, and attach the result to your pull request.

```sh
NOTCHDECK_DEMO=1 swift run NotchDeck --snapshot snapshots   # sample data
swift run NotchDeck --snapshot snapshots-live               # your real data, or the empty states
```

This writes `closed.png` and one `open-<module>.png` per module.
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
| `Sources/NotchDeckCore` | Pure Swift with no AppKit or SwiftUI: parsers, models, stores, formatting. Everything here has unit tests in `Tests/NotchDeckCoreTests`. |
| `Sources/NotchDeck/Notch` | The notch window, shape, open and close state, and input handling. Shared by all modules. |
| `Sources/NotchDeck/Design/Theme.swift` | Design tokens (palette, type, spacing, radius, motion) and shared controls such as `Card` and `IconButton`. |
| `Sources/NotchDeck/Modules/<Module>/` | One folder per module: an `ObservableObject` store owned by `AppServices`, and its SwiftUI views. |
| `Sources/NotchDeckCore/Claude` | `ClaudeCLI` and the stream-json parser used by both Claude modules. |

Put logic you can test without a UI in `NotchDeckCore`, and test it through its public API.
When you work on one module, keep your changes inside that module's folders and their tests.
Touch the shared files only when you have to, and keep those edits small.

## Pull request guidelines

- **Open an issue first** for new modules, new permissions, or larger design changes, so we can agree on the direction before you build it.
- **Keep each pull request focused** on one fix or feature.
- **Keep the build clean:** `swift build` with zero warnings and `swift test` green.
  CI runs both with warnings treated as errors.
- **Add tests** for new logic in `NotchDeckCore`.
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
swift scripts/make-icon.swift            # redraws Resources/AppIcon.icns
swift docs/make-screenshots.swift        # re-renders docs/images/*.png from demo snapshots
```

## Releases

Maintainers cut releases with `scripts/release.sh`.
It builds a universal (Apple silicon and Intel), ad-hoc signed `NotchDeck-<version>.zip` with a `.sha256` checksum in `build/release/`, and prints the steps to publish a GitHub release.
The version comes from `CFBundleShortVersionString` in `Resources/Info.plist`.
Builds are not notarized, so the README explains how to open the app the first time.
