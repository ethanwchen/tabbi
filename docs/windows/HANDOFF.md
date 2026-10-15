# Tabbi for Windows: handoff

This is the brief for the Claude Code session that builds Tabbi for Windows on a Windows PC.
Read it top to bottom once, then keep it open while you work.
It builds on [plan.md](plan.md) (the October 2026 proposal) and [phase0.md](phase0.md) (the shared data that is already done).
Where this page and plan.md disagree, this page is newer and wins.
The environment variables and the machine setup checklist are also on their own page, [ENVIRONMENT.md](ENVIRONMENT.md).

## 1. What Tabbi is

Tabbi is a cozy study and focus companion that lives in the MacBook notch.
The closed notch shows a small ticker beside the camera housing (the focus clock, the next meeting, the song playing, cards due, the pet).
Clicking or hovering opens a fixed black panel of tabs, and each tab is a module: Timer (`study`), Today (`planner`), Now Playing (`spotify`), Ask AI (`claudeAsk`), Closet (`closet`), Anki (`anki`), Party (`party`), Focus (`focus`), System (`system`), AI Usage (`claudeUsage`) and the opt-in Schedule (`schedule`).
A kit (a JSON manifest) picks which modules are on, in what order, with which defaults; Essentials is the default kit and Med School the second bundled one.
A pixel-art cat or dog earns points from focus time, wears outfits bought in the Closet, keeps streaks, and studies beside friends' pets in a Party.
The Mac app is Swift (SwiftUI and AppKit) in `Sources/`, the backend is a Cloudflare Worker in `backend/`, and data both apps read lives in `shared/`.
The repo is `ethanwchen/tabbi`, MIT licensed, with art under `ASSETS-LICENSE.md`.

### Product rules the Windows build must keep

These are not style preferences; each one is a promise already made to users or a rule the owner enforces on every change.

- No telemetry and no analytics, ever, in any form: no usage pings, no crash uploads without consent, no third-party SDKs that phone home.
- Privacy by default: no network call except what a feature inherently needs, and every host a module connects to is listed in its descriptor's `network` field (the kit import sheet shows that list before a kit turns a module on).
- Crash reports go out only after the person agrees, after a crash or through an "always send" switch in Settings > About, and never contain typed text, names, tasks, tokens or home folder paths.
- No account is needed for anything local; Party works without an account, and Sign in with Apple only adds sync.
- Party and Sign in with Apple are for people 13 and older: ask birth month and year on the device before Party or sign-in sends anything, and never send a birth date or age to the server.
- AI goes only to the provider the user picked, with the user's own key or local model, and nothing is sent before a provider is picked.
- Pricing copy is exactly "Tabbi is free. Optional extras may come later, and the core will stay free."
  Never write "free forever", "always free" or a promise of that shape anywhere (UI, installer, Store listing, site, release notes).
- No capes in demo art: screenshots, Store images, hero art and demo or snapshot modes never dress the pet in a cape (the Superhero Cape or the King's Cape), even though both items exist in the Closet.
- No truncated text: no ellipsis cut-offs, no clipped labels and no control cut off by its frame, in any language; a line that can be too long scrolls slowly (the Mac's `MarqueeText`) or the layout drops a row (`RowsThatFit`), and a list cut by its frame fades at the edge.
- Cozy brand: friendly, plain, short words, never shaming; a hardware-black panel with content on cards; one accent color per module; calm spring motion; pixel art drawn crisp.
- Writing style everywhere in the repo, the UI and commit messages: no emojis and no em dashes (use a hyphen, comma, colon or parentheses); `scripts/check-style.sh` enforces it.
- The product is called Tabbi; NotchDeck and StudyNotch are old names and must not appear in new UI.
- Empty, loading and error states are designed; never a blank panel and never a raw error dump.
- Every control has a hover state and a tooltip.

## 2. The Windows equivalent of the notch

Windows has no notch, and the top-center of the screen is live space (maximized title bars, browser tabs), so the island must not cover it by default.

Recommendation: a top-center island plus a tray icon.

- **The island is the panel.**
  A borderless, transparent, always-on-top window centered at the top of the active display, holding the same fixed canvas as the Mac (`Theme.Layout.expandedSize`, 560 x 236 logical pixels, scaled by the display's DPI), the same tab bar, the same themes and the same panels.
  It drops down from the top edge with the Mac's spring curves and has rounded bottom corners, so it reads as a pill hanging from the screen edge, the way the notch hangs from the bezel.
- **The closed state is a slim pill, shown only when it has something live.**
  Default mode "Auto": while a focus clock runs, music plays, a meeting starts within 5 minutes or a party session is on, a slim pill (about 32 px tall) at the top edge shows the ticker; otherwise nothing is drawn and a thin invisible hot zone at the top-center edge opens the panel when the pointer rests there (about 300 ms dwell, so flicking to a browser tab does not open it).
  Settings > Look offers "Always show the pill" and "Only on hover or hotkey" as well (the Mac's `NotchMode` values).
- **A tray icon is the always-available entry point.**
  Left click toggles the island, right click opens a native menu (Open Tabbi, Settings, Pause focus, Check for Updates, Quit).
  Windows hides new tray icons in the overflow by default, so onboarding's last step shows how to pin it, without nagging again.
- **Global hotkey.**
  Default Ctrl+Alt+Space (the Mac's Control+Option+Space), changeable in Settings with the same recorder; if `RegisterHotKey` fails because another app owns it, Settings says so plainly and offers to pick another.
- **Click-through and focus.**
  The island never steals focus while closed and never appears in Alt+Tab or on the taskbar (tool window, `skip_taskbar`).
  Outside the visible pill or panel, clicks pass through to the app below; the window toggles ignore-cursor-events from the pointer position, or is resized to the shape, whichever the phase 1 spike proves flicker-free.
  The panel closes on Escape, on a click outside, and when the pointer leaves it after opening by hover (the Mac's rules).
- **Fullscreen and presentations.**
  Hide the island while a fullscreen app, game or presentation owns the island's monitor (`SHQueryUserNotificationState` reports busy, D3D fullscreen or presentation mode), and show it again after.
- **Multiple monitors and DPI.**
  Per-monitor DPI aware v2; the island follows the monitor with the pointer when opened by hover or hotkey, and a setting can pin it to the primary display.
  Recompute placement on display changes, DPI changes, taskbar moves (top-docked taskbars exist) and resume from sleep.
- **Native touches without losing the brand.**
  The panel stays hardware-black with cards, as on the Mac; Mica or acrylic are not used for the panel body.
  Tray menu, file pickers, toasts and the installer are native Windows UI.
  Notifications are Windows toasts (focus block finished, break over, study reminder), which respect Windows "Do not disturb".
- **Start with Windows** is an opt-in switch in onboarding and Settings > General (a per-user Run key or the Store's startup task), off until the user turns it on.

## 3. Recommended stack: Tauri 2 (Rust host, TypeScript and React UI)

Pick Tauri 2: a small Rust host for everything Windows-specific and a TypeScript UI in the system WebView2, in a top-level `windows/` folder of this repo.
This confirms the choice in plan.md section 2 after weighing it again against the four criteria the owner named.

| Criterion | Tauri 2 + TypeScript | .NET 9 + WinUI 3 | Electron |
| --- | --- | --- | --- |
| Native feel | Good: the panel is custom-drawn on every platform anyway (black canvas, cards, pixel pet), and tray, menus, toasts and dialogs stay native | Best for stock Fluent controls, which Tabbi barely uses | Same as Tauri |
| Footprint | Installer a few MB; idle about 40 to 80 MB across the host and WebView2 processes, close to the Mac's 55 MB | Idle about 40 to 70 MB, plus the Windows App SDK runtime | 150 MB or more idle, wrong for an always-running companion |
| Maintainability by Claude Code | TypeScript and Rust are languages agents write and test well; the UI can be rendered and screenshotted in headless Chromium (the WebView2 engine) with no Windows desktop, mirroring the Mac's `--snapshot` loop | C# and XAML are fine, but the transparent always-on-top overlay needs Win32 interop, and UI screenshots need a real desktop session | Like Tauri, minus the footprint |
| Reuse of `shared/` JSON | Direct: the fixtures replay in Vitest, and the Party and sync clients share request and reply types with `backend/src` (also TypeScript) | Possible, but types are written twice and nothing is shared with the Worker | Same as Tauri |

Reasons, in order of weight:

- **Fixture-driven parity is the core of this port**, and the fixtures were designed to be replayed by a TypeScript port (`shared/README.md`).
  A pure TypeScript core (`windows/src/core/`, no DOM, no Tauri) replays every golden fixture in Vitest, and the same code runs in the app.
- **One language with the backend.**
  The Worker is TypeScript, so the Windows Party and sync client can import its request and reply types instead of retyping them, and contract drift fails `tsc`.
- **Headless visual checks.**
  The Mac workflow depends on rendering every panel to PNG and looking at it; the web UI can do the same with Playwright against the Vite dev server and mocked host commands, on any machine and in CI.
- **Footprint.**
  WebView2 ships with Windows 10 and 11, so the app does not carry a browser; Electron would triple the idle memory.
- **The Windows-only parts are small and well served in Rust** through the `windows` crate: media sessions, Credential Manager, hotkeys, fullscreen detection, protocol activation.

Accepted costs and how to contain them:

- WebView2 transparency and hit testing need the phase 1 spike to prove click-through and no flicker on Windows 10 and 11, at 100, 125, 150 and 200 percent scaling.
- Idle memory must be measured, not assumed: the budget is at most 80 MB private working set summed over all Tabbi processes after 10 minutes idle with the panel closed, and near-zero CPU (no timers or animations while nothing is visible).
  If the spike misses it badly, fall back to .NET 9 + WinUI 3 with a C# core that replays the same fixtures; do not fall back to Electron.

Stack details:

- Tauri 2 with the official plugins for global shortcut, single instance, deep link (`tabbi://`), notification, autostart, updater and window state; nothing else without a reason stated in the PR (the repo rule on dependencies).
- UI: React 19, TypeScript in strict mode, Vite; CSS variables generated from `themes.json`; no UI kit, the Mac's components (`Card`, `IconButton`, `MarqueeText`, `RowsThatFit`, `EdgeFade`, `StatusMessage`) are ported as small React components.
- Rust host (`windows/src-tauri/`): window placement and hit testing, tray, hotkey, Credential Manager, media sessions, system stats, fullscreen detection, file storage paths, protocol activation; exposes typed commands to the UI.
- Tests: Vitest for the core and the fixtures, `cargo test` for the host, Playwright screenshot runs for every panel state.
- Lint: `tsc --noEmit`, ESLint, `cargo clippy -- -D warnings`, `cargo fmt --check`, and `scripts/check-style.sh` (it runs in Git Bash, which ships perl).

Folder layout:

```text
windows/
  package.json, tsconfig.json, vite.config.ts, vitest.config.ts, playwright.config.ts
  src/
    core/          pure TypeScript ports of TabbiKitCore (no DOM, no Tauri), one folder per area
    host/          typed wrappers over the Rust commands, plus a mock for tests and snapshots
    ui/            shared components, theme tokens, the island shell, tab bar, settings
    modules/<id>/  one folder per module, same ids as the Mac (study, planner, spotify, ...)
    i18n/          the catalog loader and plural rules
  src-tauri/       Rust host, tauri.conf.json, icons, capabilities
  tests/
    fixtures/      Vitest suites that replay ../shared/fixtures
    snapshots/     Playwright runs that render every panel state to PNG
  README.md        how to build, test and run on Windows
```

Keep the Mac's architecture: modules publish a provision and log to the activity log, shared views read the merged snapshot, and no module reaches into another's store.
A module is its own folder plus one line in the module list, exactly as `CLAUDE.md` describes for Swift.

## 4. Feature parity map

"MVP" is phase 2 below; later phases are named.
Every module keeps its Mac id, so kits, Party and sync stay compatible.

| Area | Mac today | Windows equivalent | Phase |
| --- | --- | --- | --- |
| Island, ticker, tab bar | `TabbiKit/Notch`, `TickerSources`, `TickerRotation` | Section 2 island; ticker ported and checked against `shared/fixtures/ticker` | 1 and 2 |
| Kits and onboarding questions | `Kits/Bundled/*.json`, `KitValidation` | Load the same files; port validation leniently (warn, never crash) | 2 |
| Timer (`study`) and Focus (`focus`) | `StudySession`, `FocusTimer`, `study-methods.json` | Port and replay `study-session`, `focus-timer` and `study-methods` fixtures | 2 |
| Focus sounds | Brown, pink and white noise, rain and fireplace synthesized in `TabbiKitCore/Focus`; the cafe is `Focus/FocusRecordings/cafe.m4a`, a seamless 120 s loop; `FocusSoundEngine` mixes at equal loudness | Web Audio: synthesized sounds as AudioWorklet ports of the Swift DSP, the cafe decoded once and looped sample-accurately with `AudioBufferSourceNode.loop`, per-sound loudness trims from the Mac; check the decoded cafe is exactly 5,760,000 samples at 48 kHz with no seam | 2 |
| Chimes | macOS system sounds (`NSSound`), not redistributable | Toast audio (`ms-winsoundevent:Notification.Default`) for notifications; any in-app chime must be original or CC0 and listed in `docs/sounds.md` | 2 |
| Do Not Disturb with focus | macOS Focus via Shortcuts | No supported public API to toggle Windows "Do not disturb"; offer a button that opens `ms-settings:notifications` and say why; revisit Windows focus session APIs later | later |
| Today (`planner`) tasks | Local checklist, `PlannerRepository` versioned JSON | Same, local, versioned JSON in the app data folder | 2 |
| Today calendar, Up next, Schedule | EventKit (any account in macOS Calendar) | No EventKit equivalent: first an ICS subscription URL (read-only, any provider, no OAuth); then Microsoft Graph `calendarView` with OAuth PKCE as a public client (Outlook, Microsoft 365) and the Google Calendar API with OAuth for installed apps (`calendar.readonly`, which needs Google's OAuth verification before public release); `Windows.ApplicationModel.Appointments` is not used because new Outlook does not feed it and it needs package identity | ICS in 2, OAuth in 4 |
| Plan my day, Day review | Ported planners, Claude prompts | Port, replay `shared/fixtures/plan-my-day`; writing the plan into a calendar waits for Graph or Google write scopes, until then the plan stays in Today | 2 (on device), 4 (AI and calendar write) |
| Now Playing (`spotify`) | Spotify and Music through AppleScript, artwork from album URLs | `GlobalSystemMediaTransportControlsSessionManager` in Rust: title, artist, artwork thumbnail, play, pause, next, previous, shuffle and repeat for Spotify, browsers and any app that publishes a media session; subscribe to change events instead of polling | 3 |
| Anki (`anki`) | AnkiConnect on `127.0.0.1:8765` | Same protocol, same port, unchanged; see the fallback lesson below | 3 |
| Ask AI (`claudeAsk`), Plan my day AI, Day review, Schedule refine | `AIService`: Claude, OpenAI and Gemini APIs with the user's key, Ollama, and the `claude`, `codex` and `gemini` CLIs | API keys and Ollama first; keys in Windows Credential Manager, one generic credential per provider under a `Tabbi/` target prefix, never in a file or settings; Ollama at `http://localhost:11434`; the CLI providers later (`claude.exe` on PATH or `%USERPROFILE%\.local\bin`), replaying `shared/fixtures/claude-stream` | 4 (API, Ollama), 5 (CLIs) |
| AI Usage (`claudeUsage`) | Reads the claude CLI and Codex logs | `%USERPROFILE%\.claude` and `%USERPROFILE%\.codex`; ship only with the CLI providers | 5 |
| System (`system`) | CPU, memory, GPU | PDH counters and `GlobalMemoryStatusEx` in Rust, sampled only while the tab is visible | 3 |
| Pet and Closet (`closet`) | `PetComposer`, `PetAnimator`, `PetArt/*.json`, `PetUnlocks` | Port the composer and animator over the same JSON, replay `shared/fixtures/pets`; render to a canvas at an integer device-pixel scale with smoothing off (`imageSmoothingEnabled = false`, `image-rendering: pixelated`), and snap the scale to whole device pixels so 125 and 150 percent displays never get uneven pixels | 2 |
| Points, unlocks, streaks, heatmap, weekly recap | `PetPointsRules`, `PetUnlocks`, `StudyStreak`, `StudyHeatmap`, `RecapStats`, `WeeklyRecap` | Port from the activity log; these lack fixtures today (section 5), so add them on the Mac first | 2 (points, unlocks, streaks), 3 (heatmap, recap) |
| Recap share image | `RecapShareFormat`, rendered PNG | Render the same card to a canvas and copy or save it as PNG; no upload | 3 |
| Seasonal events | `events.json` (`events.v1`) | Load the same file; names and taglines translate through the catalog | 3 |
| Party (`party`) and friends | `PartyClient`, `backend/` | TypeScript client over the same API, sharing types with `backend/src`; same polling rules | 4 |
| Sign in with Apple and sync | Native sheet (App Store build) or the web flow through the Worker (direct build), `SyncDocument` merge | The web flow only, exactly as the Mac direct download does (section 6); same `SyncDocument` and merge rules | 4 |
| Widget | WidgetKit desktop and Notification Center widget fed by `WidgetState` | Windows 11 Widgets board provider (Windows App SDK, needs package identity, so the MSIX or Store build) showing pet, streak and live timer from the same `WidgetState` shape; until then the closed pill is the glanceable surface | later |
| Onboarding | In-notch flow, `OnboardingFlow` | Same flow inside the island: kit, kit questions, tabs, setup steps, plus "Start with Windows" and "pin the tray icon" | 2 |
| Settings | Five sections: General, Tabs, Look, Connections, About | The same five sections in a normal, themed settings window (dark, native title bar), rare settings under More options | 2 |
| Localization | `Localizable.xcstrings`, 12 languages | Read the same catalog (section 5 and below) | 2 |
| Updates | Sparkle with an EdDSA-signed `appcast.xml` | Tauri updater with Ed25519-signed bundles and a `latest.json` feed on GitHub Releases; WinGet manifest per release; the Store build updates through the Store | 5 |
| Code signing | Developer ID and notarization | Azure Artifact Signing (formerly Trusted Signing) through Tauri's `signCommand`; an OV certificate as the fallback | 5 |
| Packaging and distribution | DMG on tabbinotch.com and GitHub Releases, Homebrew, App Store | Per-user NSIS installer (no admin prompt) on GitHub Releases linked from tabbinotch.com, then WinGet, then MSIX in the Microsoft Store | 5 and later |
| Feedback | Suggest page link, opt-in crash reports | Same Suggest link with the app version and Windows version filled in; crash reports only after the backend change in section 6 | 5 |
| Data migration | `LegacyDataMigration` (NotchDeck to Tabbi) | Not needed: Windows starts fresh | none |

### Anki: the `getDeckStats` lesson

AnkiConnect 2026.10, the rewrite AnkiWeb serves for Anki 26.08 and later, fails a whole `getDeckStats` call with "Deck counts unavailable." when any deck in it is missing from Anki's deck list.
The empty Default deck (id 1) is always missing, because Anki hides it while it is empty, but `deckNamesAndIds` still returns it; older AnkiConnect versions silently skipped such a deck.
The Mac client (`AnkiConnectClient.deckStats` in `Sources/TabbiKitCore/Anki/`) therefore does this, and the Windows client must do the same:

1. Ask `getDeckStats` for all decks in one call.
2. If that fails with an Anki error (not a connection failure), ask again without the Default deck (id 1).
3. If that also fails, ask deck by deck in one `multi` call, keep every deck that answers, and fail only when every deck fails.
4. Match replies by deck id, not name, because older add-ons name decks by their leaf ("Cardio") and newer ones by their full path ("Step1::Cardio").

Explain what Anki said in plain words (`AnkiConnectionState` maps the messages), and port the Mac's Anki tests (`AnkiConnectClientTests`, `AnkiRobustnessTests`, `AnkiConnectWireTests`) as wire-level tests with recorded replies.
AnkiConnect's CORS setting (`webCorsOriginList`) does not matter if the Rust host makes the calls; if the webview calls it directly, the onboarding guide must explain adding Tabbi's origin, so prefer the host.

### Localization

The 12 languages are English, Arabic, German, Spanish, French, Filipino, Japanese, Korean, Brazilian Portuguese, Russian, Simplified Chinese and Traditional Chinese.
`Sources/TabbiKitCore/Localization/Localizable.xcstrings` is plain JSON: the key is the English text, each entry has a comment and per-language `stringUnit` values or plural `variations`.
The Windows build reads that file directly at build time (a Vite plugin or a small script that emits one JSON per language), so the Mac and Windows apps share every translation with no copy to drift.
Convert the format specifiers (`%@`, `%lld`, `%f` and positional `%1$@`) to the UI's interpolation, and map plural variations through `Intl.PluralRules` (Arabic uses all six forms).
Format dates, times, numbers and durations with `Intl`, and port `DurationFormat` and `DateRangeFormat` so "45 min" and "Oct 5 - 11" match the Mac.
Arabic is right to left: set `dir="rtl"` and mirror layouts as the Mac does.
Windows-only strings (tray, Credential Manager, Start with Windows) cannot go in the Mac catalog from Windows, because `scripts/compile-strings.sh` needs Xcode's `xcstringstool` and `LocalizationTests` fails until it runs.
Put them in `windows/src/i18n/Windows.xcstrings`, the same format, with all 12 translations, written by `scripts/l10n-add.py` pointed at that file or by hand, and test that both catalogs are complete.
Follow the tone rules in `docs/localization.md` (informal du, tu and voce, Taiwan conventions for Traditional Chinese, no emojis or em dashes in any language).

### Fonts and icons

SF Rounded and SF Symbols are licensed for Apple platforms only, so they cannot ship on Windows.
Use Segoe UI Variable for UI text, or bundle an OFL rounded family for the cozy look after checking its license in `docs/legal/ip-review.md` terms, with the system CJK and Arabic fonts as fallbacks (Yu Gothic UI, Microsoft YaHei UI, Microsoft JhengHei UI, Malgun Gothic, Segoe UI).
Kits and descriptors name SF Symbols (`timer`, `checklist`, `pawprint.fill`); map each name to an SVG icon or a Segoe Fluent Icons glyph in one table, and fall back to a neutral icon for an unknown name.
Use `.monospacedDigit()`'s equivalent (`font-variant-numeric: tabular-nums`) on every changing number.

## 5. Using `shared/`

`shared/schemas/` holds JSON Schema (draft 2020-12) files: `pets.v1`, `themes.v1`, `study-methods.v1`, `events.v1`, `kit.v1`, `edition.v1` and `catalog.v1`.
The data they describe lives where the Mac app reads it, and the Windows build reads the same paths, never a copy:

| Data | Path |
| --- | --- |
| Pet art, breeds, animations | `Sources/TabbiKitCore/Pets/PetArt/*.json` |
| Themes | `Sources/TabbiKitCore/Themes/themes.json` |
| Study methods | `Sources/TabbiKitCore/StudyMethods/study-methods.json` |
| Seasonal events | `Sources/TabbiKitCore/Events/events.json` |
| Kits | `Sources/TabbiKitCore/Kits/Bundled/*.json` |
| Party catalog | `backend/shared/catalog.json` |
| Strings | `Sources/TabbiKitCore/Localization/Localizable.xcstrings` |
| Cafe loop | `Sources/TabbiKitCore/Focus/FocusRecordings/cafe.m4a` |
| App icon source | `docs/brand/assets/tabbi-icon-1024.png`, `tabbi-glyph-256.png`, `tabbi-glyph.pdf` |

The Windows build copies them into its bundle at build time and validates each against its schema in a test (Ajv), so a malformed file fails CI rather than a user's launch.

`shared/fixtures/` holds golden fixtures written by the Swift tests; each folder has a README describing its shape.
The Windows port must pass all of them, replaying the fixture's own inputs and comparing every recorded output:

| Fixture | What the port must reproduce |
| --- | --- |
| `pets/` | SHA-256 of every composed frame of every animation for every breed and outfit (612 dresses, 76,500 frames), run-length frames for a cat and a dog, every palette |
| `themes/` | Every resolved theme color and accent treatment, within 1e-9 |
| `study-methods/` | Every method's parameters, phase order over eight rounds, labels, copy, Flowtime breaks, sprint goals, Timer steps |
| `focus-timer/` | Countdown readouts at rounding edges, 15 Pomodoro sequences with the focus card, shared clock, notifications and activity records |
| `study-session/` | 18 `StudySession` sequences with dial, buttons, pet events, shared clock and logged phases |
| `ticker/` | 19 source sets with visible items, strings and next change, and 13 rotation sequences |
| `plan-my-day/` | 19 days planned three ways, prompts, parsed answers and 4 proposal sequences |
| `claude-stream/` | 34 `claude -p` stream-json lines and 13 Ask Claude exchanges (needed with the CLI providers) |

Write one Vitest suite per fixture under `windows/tests/fixtures/`, each shown to fail on a one-value change, like the Swift suites.
Never edit a fixture from the Windows side; fixtures are regenerated only on a Mac, on purpose, with `TABBI_RECORD_FIXTURES=1 swift test --filter ...` (`shared/README.md`).
When a fixture test fails on Windows, the Windows port is wrong until proven otherwise; if the Mac behavior itself is wrong, fix it on the Mac in a separate PR that re-records the fixture.

### What `shared/` is missing for Windows

Each item is a small Mac-side PR (a Swift test that records a fixture, or data moved out of Swift), best done before the phase that needs it.

1. **Sync document**: a `sync-document.v1` schema and a merge fixture (pairs of local and remote documents with the merged result, including points per device, unlock unions, study-day unions, longest-streak maximum and last-writer-wins look), recorded from `SyncDocument` and `SyncRound`; needed before phase 4, because both apps write the same server document.
2. **Closet prices and unlock rules**: item prices and tiers live in Swift (`Pets/PetUnlocks.swift`, `PetPointsRules`, `PetEconomy`, `PetLimited`); move them to data (or record a fixture of every item's price, tier and unlock rule, and points per focus block); needed for phase 2.
3. **Streaks, heatmap and weekly recap**: fixtures from `StudyStreak` (including freezes and milestones), `StudyHeatmap`, `RecapStats` and `WeeklyRecap` over recorded activity logs; needed for phases 2 and 3.
4. **Activity records**: a schema for `ActivityRecord` and its per-day file, so streaks, recap and the pet read the same shape on both platforms.
5. **Focus sounds**: the mixes, presets, playlists and per-sound loudness trims (`FocusMix`, `FocusMixPreset`, `FocusSound.loudnessTrimDecibels`, `NoiseGenerator.targetRMS`) as data, and a fixture of each synthesized sound's RMS and integrated loudness, so the Web Audio port can be measured against the Mac; the DSP itself is code and gets ported.
6. **Anki**: recorded AnkiConnect replies (deck list, stats, the "Deck counts unavailable." failure, `multi` partial failures, old leaf-name replies) with the expected summary, from `AnkiSummary` and `AnkiConnectClient`.
7. **Kit application and validation**: a fixture of kits (bundled and malformed) with the warnings `KitValidation` reports and the layout applying them gives.
8. **Onboarding flow**: a fixture of `OnboardingFlow` step order and skipping for different kits, answers and tab choices.
9. **Formatting**: a fixture of `DurationFormat` and `DateRangeFormat` outputs in all 12 languages, so durations and date spans match.
10. **Symbol map**: a JSON table from every SF Symbol name used in kits, descriptors and catalog to a neutral icon id, so both apps agree on icons for imported kits.
11. **Icons**: a multi-size `.ico` (16 to 256 px) generated from `tabbi-icon-1024.png`, and light and dark monochrome tray icons from the glyph; generate them in the Windows build from the PNG and PDF rather than committing hand-made copies.
12. **Chimes**: original or CC0 notification sounds, if the Windows build wants in-app chimes beyond toast audio, listed in `docs/sounds.md` with their license.
13. **Coach and greeting copy**: the pet coach's lines and seasonal greetings are Swift today (`Coach/`, `Motivation/`, `SeasonalEventGreeting`); move them to data or a fixture when the Windows pet coach is built.

## 6. Backend

The Windows client talks to the same production Worker, `https://tabbi-friends.drosophil-anki-friends-backend.workers.dev`, documented in [docs/study/backend-api.md](../study/backend-api.md), with what it stores in [backend/PRIVACY.md](../../backend/PRIVACY.md).

### Endpoints the Windows client uses

| Route | When |
| --- | --- |
| `GET /v1/catalog` | optional, to check for a newer catalog than the bundled one |
| `POST /v1/register` | once, when Party is first turned on (after the age check) |
| `GET /v1/me`, `PATCH /v1/me` | on launch and after the pet changes |
| `DELETE /v1/me` | Delete Account |
| `POST /v1/presence` | launch, every status or phase change, then every `heartbeatSeconds`, and `offline` on quit, sleep and logoff |
| `GET /v1/friends`, `POST /v1/friends`, `DELETE /v1/friends/{code}` | friends panel open (every 60 s while open), add, remove |
| `GET /v1/blocks`, `POST /v1/blocks`, `DELETE /v1/blocks/{code}`, `POST /v1/reports` | safety actions |
| `GET /v1/leaderboard` | once each time its view opens |
| `GET /v1/party`, `POST /v1/party`, `POST /v1/party/join`, `POST /v1/party/leave`, `POST`/`DELETE /v1/party/session` | Party, polling every 30 s only while in a party and visible |
| `POST /v1/auth/apple/web/token` | finishing web sign-in |
| `POST /v1/auth/signout` | Sign Out |
| `GET /v1/sync`, `PUT /v1/sync` | launch, resume, after a `409`; `PUT` debounced about 30 s after progress changes and once on quit |
| `GET /v1/grants` | once per launch, resume and identity |
| `POST /v1/crashes` | only with consent, after the backend change below |

The Windows client never calls `/v1/admin/...` and never holds `ADMIN_TOKEN`.

### Auth model, limits and versioning

- `POST /v1/register` returns a 64-hex secret token and an 8-character friend code; send `Authorization: Bearer <token>` on every other call.
  Store the token in Credential Manager (generic credential, target `Tabbi/party`), never in a file or log; the server keeps only its SHA-256, so a lost token is unrecoverable.
- Sign in with Apple is optional and only links the friend code to an Apple account for sync; each device gets its own token for the same code.
- Bodies are JSON, at most 4096 bytes (65,536 for `PUT /v1/sync`); unknown fields are rejected with `unknown_field`, so send exactly the documented fields.
  Branch on the stable `error` code, never on `message`.
- Limits: 60 requests per minute per token; 60 failed authentications, 10 registrations and 10 Apple sign-ins per minute per client IP (an IPv6 /64 counts as one); 20 sync writes per minute per user.
  On `429` wait `Retry-After`; on `503` or network errors back off exponentially (5 s, 10 s, 20 s, capped at 5 minutes).
- The whole service runs on the Cloudflare free plan, where requests are the binding limit, so follow the polling table exactly and stop every timer whose data is not on screen.
- Versioning: every route is under `/v1/`, `GET /` answers `{"ok":true,"service":"tabbi-friends","version":1}`, the catalog carries a `version`, and the sync document carries `schemaVersion`.
  The server stores the sync document as sent, so a newer client format never needs a deploy, but the Windows client must merge and write the same format as the Mac.

### Sign in with Apple on Windows

Use the web flow that the Mac direct download already uses (`AppleWebSignIn.swift`), with no backend change:

1. Make a random `state` (32 bytes, base64url) and keep it in memory.
2. Open the system browser at `https://appleid.apple.com/auth/authorize` with `response_type=code id_token`, `response_mode=form_post`, `scope=name`, `client_id=dev.tabbi.Tabbi.signin`, that `state`, `nonce` = base64url(SHA-256(`state`)), and `redirect_uri` = the Worker's `/v1/auth/apple/web/callback`.
3. Apple posts to the Worker, which verifies the token and redirects the browser to `tabbi://auth/apple?code=<64 hex>` (or `?error=<reason>`).
4. Windows hands that link to Tabbi through the `tabbi://` protocol registered per user by the installer; the single-instance plugin forwards it to the running app.
5. The app posts `{"code", "state"}` to `POST /v1/auth/apple/web/token`, with its Party token as Bearer if it has one, and gets the same reply as `POST /v1/auth/apple`.

Because the Services ID is grouped with the App ID, the Windows sign-in reaches the same account as the Mac, so the pet, streaks and friend code follow the user across platforms.
Microsoft sign-in is a later addition (plan.md section 5) and would be a backend change; it is not needed for Windows 1.0.

### Is a backend change needed?

Not for phases 1 to 4: the API, CORS (open, with `Authorization`, `Content-Type` and `If-Match` allowed and `ETag` and `Retry-After` exposed), the web sign-in flow and the `tabbi://` redirect all work for a Windows client as they are.
Do not add a platform field to the profile or presence: the server does not need it, and knowing less is the privacy promise.
Three small, additive, backward compatible changes are worth doing when their phase arrives, each as its own PR with tests in `backend/test`:

1. **Crash reports (before Windows sends any):** `backend/src/crashes.ts` refuses frames with a home path by matching `/Users/` or `/home/` only, so `C:\Users\name\...` would slip through; extend `HOME_PATH` to Windows paths (`\Users\` with either slash, any drive letter) and update `backend/PRIVACY.md`.
   The report's `macos` field is required; accept an optional `os` field as its alternative (one of the two required), stored in the same column, and keep `macos` working for every existing Mac client.
   The same applies to `POST /v1/suggestions`, whose optional `macos` field the website fills.
2. **Download count:** `GET /v1/public/downloads` counts only `.dmg` assets; count the Windows installer asset too once it ships, so the public figure stays honest.
3. **Docs:** say "device" instead of "Mac" in `backend-api.md` and `PRIVACY.md` where the meaning is any device, in the same PR as Windows sync.

Deploys follow `backend/README.md` (tests and typecheck, staging first) and are the owner's or an authorized Mac session's job; schema steps are added at the end of `MIGRATIONS` and a deployed step is never edited.

## 7. Environment variables and secrets

Short answer to "Do we need any environment variables?": no, none are needed to build, test and run the Windows app against the production backend.
[ENVIRONMENT.md](ENVIRONMENT.md) has the same answer as a checklist.

### Not needed

- No API keys, tokens or `.env` file to build or run.
- No backend secrets: the Windows client is a public client, and the production Worker URL and the Services ID `dev.tabbi.Tabbi.signin` are public values that belong in code.
- No Apple developer account access: web sign-in uses the Worker's existing Services ID.
- No Cloudflare account, unless the session is asked to deploy the backend (it should not be).

### Optional, for development only

Mirror the Mac's names so both apps behave the same:

| Variable | Effect |
| --- | --- |
| `TABBI_DEMO=1` | Demo mode: realistic sample data, no network, calendar, Anki or AI calls, nothing saved; the pet never wears a cape |
| `TABBI_PARTY_SERVER=http://localhost:8787` | Point Party and sync at a local `wrangler dev` Worker; accept only plain-http localhost here, so a dev run can never register users on a deployed server (the Mac's rule) |
| `TABBI_PARTY_TOKEN`, `TABBI_PARTY_CODE` | Render as an existing user of that local Worker |
| `TABBI_RECORD_FIXTURES=1` | Mac only, for re-recording fixtures; never set on Windows |
| `TABBI_CLAUDE_PATH`, `TABBI_CODEX_PATH`, `TABBI_GEMINI_PATH` | Phase 5 only: explicit paths to the AI command line tools |

The production backend URL is not an environment variable on the Mac; a user can point Party at their own server in Settings (`PartySettings`), and Windows should offer the same field.
AI keys are not environment variables either: when testing AI, paste your own key into Settings > Connections, which stores it in Credential Manager, or run Ollama locally.
Never read a key from an environment variable in shipped code.

### Secrets that must never be committed

| Secret | Lives in | Who needs it |
| --- | --- | --- |
| Apple Sign in with Apple key (`APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, the `.p8`) | Worker secrets (`wrangler secret put`) and the owner's password manager | the Worker only |
| `ADMIN_TOKEN` | Worker secret | the owner, for moderation and stats |
| `GITHUB_TOKEN` (download count) | Worker secret | the Worker only |
| Cloudflare API token or `wrangler login` session | the owner's machine | backend deploys |
| Mac Developer ID certificate, notarization password, Sparkle EdDSA private key | the owner's keychain and GitHub repository secrets | Mac releases |
| Windows code-signing identity (Azure Artifact Signing credentials, or an OV certificate) | Azure and GitHub repository secrets, later | Windows releases, phase 5 |
| Tauri updater private key (Ed25519) and its password | the owner's password manager and GitHub repository secrets, later | Windows releases, phase 5 |
| A Microsoft Entra or Google OAuth client secret, if one is ever issued | never in the app; desktop OAuth uses PKCE as a public client, and a Google installed-app client id is not a secret | phase 4 |
| Users' Party tokens and AI keys | Credential Manager on the user's machine | the app |

`.gitignore` must cover `.env*`, `*.pfx`, `*.p12`, `*.p8`, `*.key` and the Tauri key files under `windows/`.

### What the owner sets up on the Windows PC

- Windows 11 (or 10 22H2) with Developer Mode on.
- Git for Windows (includes Git Bash and perl for `scripts/check-style.sh`); set `git config --global core.autocrlf input` so checked-in files keep LF.
- GitHub CLI, then `gh auth login` (HTTPS, with repo scope).
- Node.js 20 or newer (LTS) with npm, for the Windows UI and for `backend/` tests.
- Rust stable through rustup with the `x86_64-pc-windows-msvc` toolchain (add `aarch64-pc-windows-msvc` for ARM builds later).
- Visual Studio 2022 Build Tools with "Desktop development with C++", the MSVC toolset and the Windows 11 SDK (the Tauri prerequisites).
- WebView2 Runtime (preinstalled on Windows 11; the Evergreen installer on Windows 10).
- Claude Code itself.
- Later, for phase 5: an Azure subscription with Artifact Signing set up by the owner, and a Microsoft Partner Center account for the Store.
- Optional: Anki with AnkiConnect for phase 3, Ollama for phase 4, Python 3 for `scripts/l10n-add.py`.

## 8. Phased plan

Each phase ends with a PR that is green on every check below; nothing merges with a failing or flaky test.
Every phase keeps `scripts/check-style.sh` passing, and every UI change is followed by a snapshot run that someone actually looks at, against `docs/design/guidelines.md`.
Add a `windows-latest` GitHub Actions job in phase 1 that runs the Windows checks on changes under `windows/` or `shared/`.

### Phase 1: shell spike (go or no-go on Tauri)

Scope: the `windows/` project, the island window with the closed pill, hover zone, open and close springs, click-through, tray icon and menu, global hotkey, single instance, per-monitor DPI, multi-monitor placement, fullscreen hiding, `tabbi://` protocol registration in dev, and a stub panel with the tab bar.

Acceptance:

- Opens and closes by hover, click, hotkey and tray on Windows 11 and Windows 10, at 100, 125, 150 and 200 percent scaling, on two monitors with different scaling.
- Clicks outside the pill and panel reach the app below; no flicker, no focus stealing, not in Alt+Tab or the taskbar.
- Hidden during a fullscreen video, game and PowerPoint slideshow, back afterwards.
- Idle budget met: at most 80 MB private working set over all Tabbi processes and under 0.1 percent CPU after 10 minutes closed.
- A written go or no-go note in `docs/windows/` with measurements and screenshots.

Tests: `cargo test` for placement math (work area, DPI, taskbar positions), Vitest for the shell state machine, a Playwright snapshot of the closed and open stub.

### Phase 2: MVP (local only)

Scope: kits and onboarding; Timer and Focus with all study methods and focus sounds (synthesized and cafe); toasts; Today tasks and Plan my day on device, with ICS calendar read; pet, Closet, points, unlocks and streaks; themes; Settings (five sections); localization in all 12 languages; the activity log; versioned JSON storage in `%APPDATA%\Tabbi` (caches in `%LOCALAPPDATA%\Tabbi`); demo mode.

Acceptance:

- Vitest replays `pets`, `themes`, `study-methods`, `focus-timer`, `study-session`, `ticker` and `plan-my-day` fixtures with zero differences.
- Every data file validates against its schema.
- Both catalogs are complete in all 12 languages, and snapshots in German, Japanese and Arabic show no truncation and correct right-to-left layout.
- Snapshot run renders every module state, empty, loading and error state, onboarding step and Settings section, for the default theme and every theme, and each PNG is reviewed.
- The cafe loop plays with no audible seam, and every focus sound plays within 1 LU of the target loudness through the mixer.
- No network traffic at all in an MVP run (checked with a proxy or `netstat`), apart from an ICS URL the user entered.
- Storage migrations tested: every persisted file has `schemaVersion` and an upgrade test.

### Phase 3: connected local tabs

Scope: Now Playing through media sessions; Anki through AnkiConnect with the full `getDeckStats` fallback; System; heatmap, weekly recap and share image; seasonal events.

Acceptance:

- Live checks against Spotify, a browser playing media and Anki with AnkiConnect 2026.10 and an older AnkiConnect, including an empty Default deck and a collection with nested decks.
- Recorded-reply tests for every Anki failure mode, and media session tests with a fake manager.
- Nothing polls while its tab is hidden, verified by logging timer starts and stops.

### Phase 4: Party, sync, AI

Scope: Party and friends with the age check, safety actions and Delete Account; Sign in with Apple web flow and sync; AI with API keys in Credential Manager and Ollama for Ask AI, Plan my day, Day review and Schedule refine; Microsoft Graph and Google calendar OAuth.

Acceptance:

- The Party client compiles against types imported from `backend/src`, and an end-to-end Vitest run against `wrangler dev` (`TABBI_PARTY_SERVER=http://localhost:8787`) registers two users, befriends them, shares a party session, blocks, syncs with a `409` retry and deletes both.
- A Mac and a Windows device signed in to the same Apple account show the same friend code, pet and streak, and neither loses points after both go offline and sync back (merge fixture from section 5 passes).
- Polling intervals match the backend's table, verified with request logs.
- No key ever appears in a file, a log or settings; deleting it in Settings removes it from Credential Manager.

### Phase 5: release

Scope: signed per-user NSIS installer, Tauri updater feed on GitHub Releases, WinGet manifest, CLI AI providers and AI Usage, opt-in crash reports (after the backend change), Suggest link, website download button.

Acceptance:

- A signed beta installs, updates to a newer signed build and uninstalls cleanly on a fresh Windows 10 and Windows 11 VM with no admin prompt, and SmartScreen shows the publisher.
- An update with a tampered signature is refused.
- `winget install` works from the submitted manifest.
- Release notes and the site use the pricing sentence verbatim and show no cape.

### Later

MSIX packaging and the Microsoft Store (the Store build turns the self-updater off), the Windows 11 widget provider, Microsoft sign-in, ARM64 builds.

## 9. First prompt for the Windows Claude Code session

Paste this as the first message in Claude Code on the Windows PC, from an empty folder such as `C:\dev`:

```text
You are building Tabbi for Windows. Tabbi is a cozy study and focus companion; the macOS app (Swift) lives in the repo ethanwchen/tabbi, with the backend in backend/ and cross-platform data and golden fixtures in shared/.

Setup:
1. Run `gh auth status`; if it fails, stop and ask me to run `gh auth login`.
2. `gh repo clone ethanwchen/tabbi` (skip if it exists), then `cd tabbi`, `git fetch origin` and `git switch -c windows/phase1-shell origin/main`.
3. Read, in this order: CLAUDE.md (repo rules, they apply to you), docs/windows/HANDOFF.md (your brief), docs/windows/ENVIRONMENT.md, docs/windows/plan.md, shared/README.md and the README in each shared/fixtures folder, docs/design/guidelines.md, docs/study/backend-api.md.
4. Check the toolchain: git, node 20+, npm, rustc and cargo (MSVC target), the Windows SDK and WebView2. Report anything missing instead of working around it.

Rules:
- Put all Windows code in a top-level windows/ folder. Change Mac code, shared/ or backend/ only in a separate PR, and never edit or re-record a fixture from Windows.
- Stack: Tauri 2, Rust host in windows/src-tauri, TypeScript (strict) and React UI in windows/src, pure ports of TabbiKitCore in windows/src/core with no DOM or Tauri imports.
- Keep module ids, kit format, storage formats (versioned JSON with schemaVersion) and backend contracts identical to the Mac.
- Product rules from HANDOFF.md section 1 are hard requirements: no telemetry, privacy, no capes in demo art, no truncated text, cozy brand, pricing copy exactly "Tabbi is free. Optional extras may come later, and the core will stay free." and never "free forever".
- No emojis and no em dashes anywhere, including commit messages. No new dependency without a reason in the PR.
- No environment variables are needed. Do not ask me for keys; use TABBI_DEMO=1 for demo data and a local wrangler dev server for Party.

Verification before every commit (from the repo root, in Git Bash where noted):
- bash scripts/check-style.sh
- cd windows && npm ci && npm run typecheck && npm run lint && npm test
- cd windows/src-tauri && cargo fmt --check && cargo clippy -- -D warnings && cargo test
- cd windows && npm run snapshots, then open the PNGs and review them against docs/design/guidelines.md
- If you touched backend/: cd backend && npm ci && npm test && npm run typecheck
Create the npm scripts named above in phase 1 if they do not exist yet. Fix any lint error, failing test or flaky test you see, even if you did not cause it.

Workflow:
- One branch and one PR per phase or coherent step, named windows/<phase>-<topic>, based on the latest origin/main.
- Commit in small logical steps. Push with `git push -u origin <branch>`. Never force push, never rewrite pushed history, never push to main.
- Open the PR with `gh pr create`, describing what changed, how it was verified (commands and screenshots), and what is left. Do not merge; I review and merge.
- When a phase's acceptance criteria in HANDOFF.md section 8 are met, say so with evidence.

Start with phase 1 (the shell spike) from HANDOFF.md section 8. Before writing code, post a short plan of the files you will create and how you will measure the idle memory and click-through criteria.
```

## 10. Open decisions for the owner

- Default closed behavior: "Auto" (pill only when something is live) as recommended, or always visible.
- Whether to bundle an OFL rounded font or use Segoe UI Variable.
- When to buy Azure Artifact Signing (needed before the first public Windows download) and register in Partner Center.
- Whether the Google Calendar integration is worth Google's OAuth verification, or ICS plus Microsoft Graph is enough for 1.0.
