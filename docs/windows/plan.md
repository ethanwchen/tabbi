# Tabbi for Windows: plan

Status: proposal for a decision, October 2026.
Nothing here is built yet.

## Recommendation in brief

- Form factor: a top-center island that stays hidden until the pointer reaches the top edge or the hotkey is pressed, plus a tray icon that opens the same island.
- Stack: Tauri 2 (Rust host, TypeScript UI) in a top-level `windows/` folder of this repo.
- Sharing: data first.
  Kits, `catalog.json`, themes, study method definitions and the pet art become JSON that both apps load, and the TypeScript logic is checked against golden fixtures produced by the Swift tests.
- Accounts: Sign in with Apple through the system browser and the Worker, with Microsoft sign-in added later; Party keeps working with no account, as on the Mac.
- Distribution: a per-user NSIS installer signed with Azure Artifact Signing (formerly Trusted Signing), the Tauri updater and winget first, then the Microsoft Store as MSIX.
- Start trigger: Mac 1.0 tagged with a frozen module set, kit format, Party API v1 and account sync.

## 1. Form factor

Windows has no notch, so the top-center of the screen is not dead space: it holds the title bars and browser tabs of maximized windows.
A permanently drawn pill there would cover real UI, which the Mac notch never does.

Options considered:

| Option | Pros | Cons |
| --- | --- | --- |
| Top-center island | Keeps Tabbi's identity, reuses the whole panel design, matches DynamicWin and Dynamic Edge | Covers tabs and title bars if always drawn |
| Taskbar-adjacent flyout | Feels like Windows 11 Quick Settings | No supported way to embed in the Windows 11 taskbar (deskbands are gone), loses the live-activity wings |
| Tray popover only | Most conventional, zero overlap | Hidden in the overflow by default, no glanceable state |

Existing apps confirm the island works on Windows: DynamicWin offers media, calendar and a file tray in a top island ([github.com/FlorianButz/DynamicWin](https://github.com/FlorianButz/DynamicWin)), and Dynamic Edge docks a WinUI 3 island at the top or a side edge ([drop.space](https://drop.space/products/dynamic-edge--fee3093b-c74f-52bb-953f-2a9b15fa5d35)).
ModernFlyouts, which replaced system flyouts, is archived, a warning against depending on undocumented shell hooks ([github.com/soumyamahunt/ModernFlyouts](https://github.com/soumyamahunt/ModernFlyouts)).

Decision: a combination.
- The island is the panel: the same 500x150 canvas, tab bar and themes as the Mac.
- `NotchMode.showOnHover` is the Windows default, so nothing is drawn until the pointer rests at the top-center edge; `alwaysVisible` draws a slim pill for people who want the live activity.
- A tray icon opens the island on left click and offers Settings and Quit on right click, the Windows home for what the Mac puts on the notch's right-click menu.
- The global hotkey works as on the Mac.
- Native touches: Segoe UI Variable, 8 px corners, Fluent-style ease curves for opening, and Mica or acrylic only on Windows 11 with a solid fallback (the default Midnight theme is black anyway).

## 2. Stack

Scores are 1 (poor) to 5 (best).

| Criterion | Tauri 2 | WinUI 3 (C#) | Avalonia | Flutter | Electron | Swift + WinUI |
| --- | --- | --- | --- | --- | --- | --- |
| Size and memory | 5 | 4 | 3 | 4 | 1 | 4 |
| Native feel | 3 | 5 | 3 | 3 | 3 | 5 |
| Transparent, always-on-top overlay | 4 | 3 | 4 | 3 | 4 | 3 |
| Code sharing with the Mac app | 3 | 1 | 1 | 1 | 3 | 5 |
| Team skills (Swift, TypeScript) | 4 | 2 | 2 | 1 | 5 | 3 |
| Signing and distribution | 4 | 5 | 3 | 3 | 4 | 3 |
| Long-term maintenance | 4 | 4 | 3 | 3 | 4 | 2 |
| Total | 27 | 24 | 19 | 18 | 24 | 25 |

Notes:
- Tauri 2 uses the WebView2 runtime that ships with Windows 11, so installers are a few MB and idle memory is a fraction of Electron's 150 MB or more, which is wrong for an always-running companion ([openreplay.com](https://blog.openreplay.com/comparing-electron-tauri-desktop-applications/)).
  Transparent, undecorated, always-on-top windows are configuration, and Mica or acrylic come from `window-vibrancy` ([github.com/tauri-apps/window-vibrancy](https://github.com/tauri-apps/window-vibrancy)).
  The UI language matches `backend/` (TypeScript), so the Party client can share types with the Worker.
- Tabbi's look is custom on every surface (black canvas, cards, pixel pet), so a web UI gives up little native feel; the controls that must feel native (tray menu, file pickers) stay native.
- WinUI 3 is the most native, but an always-on-top transparent window needs Win32 interop, and the built-in always-on-top presenter is a fixed 16:9 compact overlay ([learn.microsoft.com](https://learn.microsoft.com/en-us/windows/apps/develop/ui/materials)).
  It also adds C#, which neither the maintainer nor the agents lean on.
- Swift on Windows would reuse most of the 28,500 lines of `TabbiKitCore`, which needs only small swaps (CoreGraphics in the pet renderer, Security for the Party token, CryptoKit to swift-crypto).
  The UI layer is the problem: swift-winrt powered Arc for Windows, which was discontinued, SwiftCrossUI is still experimental, and the Swift on Windows workgroup only formed in January 2026 ([infoworld.com](https://www.infoworld.com/article/3709855/using-swift-with-winui-on-windows.html), [forums.swift.org](https://forums.swift.org/t/swiftui-for-linux-windows-and-web-still-experimental/85463)).
  A one-person project should not be the one that finds the toolchain's sharp edges.
- Compiling `TabbiKitCore` to WebAssembly inside Tauri was considered and rejected for 1.0 (Foundation weight, harder debugging); revisit once the shared data is in place.

Decision: Tauri 2, with the rule that logic shared with the Mac is either data or fixture-tested.
Revisit Swift + WinUI at Windows 2.0 if the workgroup ships stable bindings.

## 3. Code sharing

Shared as data, one source of truth in this repo:

| Asset | Today | Plan |
| --- | --- | --- |
| Kits | JSON in `Sources/TabbiKitCore/Kits/Bundled` | Load the same files; port `KitValidation` against fixtures |
| Catalog | `backend/shared/catalog.json` | Bundle the same file |
| Party API | `docs/study/backend-api.md`, Worker in TypeScript | TypeScript client sharing request and reply types with `backend/src` |
| Themes | Swift in `Themes/ThemeCatalog.swift` | Export to `themes.json`, Swift loads it |
| Study methods | Swift enum in `StudyMethods/StudyMethod.swift` | Export phase lengths, labels and rules to `study-methods.json` |
| Pet art | Swift string grids in `Pets/Art` | JSON, steps below |

Rewritten in TypeScript, behind golden fixtures: the focus timer and `StudySession`, the provider snapshot and ticker rules, Plan my day, the coach, kit application and the stream-json parser for `claude`.
Each ported unit gets a fixture file that a Swift test writes (inputs and expected outputs) and a Vitest suite reads, and CI fails on drift.

Making the pet art data:
1. Define a versioned `pets.v1` schema: grids as arrays of strings with the existing legend (`SpriteCell`, `PetPatternZone` letters), palettes per breed, breed patterns, costume and prop layers with anchors, and animation timelines.
2. Move the strings from `CatArt`, `DogArt`, `CostumeArt`, `PropArt`, `EffectArt`, `TailArt`, `PawArt` and `WalkArt` into `Sources/TabbiKitCore/Pets/Art/*.json` unchanged, loaded as SwiftPM resources like the kits.
3. Before the move, record every composed canvas (`PetComposer` output for each breed, costume and frame) as palette-index arrays; after the move, assert the Swift output is byte-identical.
4. Commit a compact subset of those canvases as golden fixtures in `shared/fixtures/pets/`.
5. Port `PetComposer` and `PetAnimator` to TypeScript and render to a canvas with nearest-neighbor scaling; Vitest compares against the fixtures, and a new breed becomes one JSON edit for both apps.

## 4. Feature mapping

| Tab | Windows approach | 1.0 |
| --- | --- | --- |
| Focus and Study timer | Ported logic; focus sounds as Web Audio noise generators matching `FocusMix` | Yes |
| Do Not Disturb | No stable public toggle; deep link to `ms-settings:quiethours`, evaluate the Windows 11 focus session API later | Deferred |
| Today tasks, Plan my day | Ported logic, local storage | Yes |
| Calendar (Today, Schedule) | No EventKit equivalent for desktop apps; ICS subscription URLs first (any provider, read-only), Microsoft Graph `calendarView` next ([learn.microsoft.com](https://learn.microsoft.com/en-us/graph/api/user-list-calendarview)) | ICS yes, Graph 1.1 |
| Now Playing | `GlobalSystemMediaTransportControlsSessionManager` covers Spotify, Apple Music for Windows and browsers, with artwork, shuffle and repeat ([learn.microsoft.com](https://learn.microsoft.com/en-us/uwp/api/windows.media.control)) | Yes |
| Ask Claude, Claude Usage | Native `claude.exe` (winget or `install.ps1`) with the same `-p` stream-json; locate on PATH and `%USERPROFILE%\.local\bin`; usage logs under `%USERPROFILE%\.claude` ([code.claude.com](https://code.claude.com/docs/en/setup)) | Yes |
| Anki | AnkiConnect on `localhost:8765`, unchanged | Yes |
| System | CPU and GPU through PDH counters, memory through `GlobalMemoryStatusEx` | Yes |
| Pet and Closet | Shared pet data and unlock rules | Yes |
| Party | Same API and server, TypeScript client | Yes |
| Screenshot attach for Ask Claude | Windows.Graphics.Capture | 1.1 |

Dropped: notch geometry and per-display notch detection (replaced by the top-edge hot zone), and Apple-only integrations (AppleScript control of Music).

## 5. Accounts and identity

Sign in with Apple works on any platform through the web flow with a Services ID ([developer.apple.com](https://developer.apple.com/documentation/signinwithapplejs)).
Apple accepts only HTTPS return URLs, so the flow is: the app opens the system browser, Apple posts to a Worker route, the Worker verifies the identity token, and hands a one-time code back through a `tabbi://` protocol handler that the app exchanges for a session.
Many Windows users have no Apple account, so the account model should hold several linked identities (Apple `sub`, later Microsoft `oid`) per user.
Add Microsoft sign-in in phase 5; its Entra app registration also covers Graph calendar consent.
Party identity stays the anonymous token and friend code from `POST /v1/register`; signing in links that code to the account, so the same friend code follows a person across Mac and Windows, and a second device adopts it instead of registering anew.
Sync payloads reuse the versioned JSON formats, so both apps read each other's tasks, pet save and settings.

## 6. Distribution

- Signing: Azure Artifact Signing costs $9.99 a month for 5,000 signatures and is open to individuals in the US and Canada ([azure.microsoft.com](https://azure.microsoft.com/en-us/pricing/details/trusted-signing/)); Tauri signs through it with a `signCommand` ([v2.tauri.app](https://v2.tauri.app/distribute/sign/windows/)), with an OV certificate as the fallback.
- Installer: Tauri's per-user NSIS installer, no admin prompt, published on GitHub releases next to the Mac DMG.
- Updates: the Tauri updater with Ed25519-signed archives, which cannot be turned off ([v2.tauri.app](https://v2.tauri.app/plugin/updater/)), the same model as Sparkle.
- winget: a manifest in `microsoft/winget-pkgs` updated by the release workflow ([learn.microsoft.com](https://learn.microsoft.com/en-us/windows/package-manager/package/)).
- Microsoft Store: registration is free for individuals, and the Store signs and hosts MSIX packages for free ([blogs.windows.com](https://blogs.windows.com/windowsdeveloper/2025/09/10/free-developer-registration-for-individual-developers-on-microsoft-store/)).
  Tauri does not emit MSIX, but Microsoft's winapp CLI packages a Tauri app as one ([learn.microsoft.com](https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/guides/tauri)).
  The Store build turns off the self-updater.

## 7. Phases

Trigger: Mac 1.0 tagged, with the module list, kit format, Party API v1 and account sync frozen for two weeks.
Efforts assume one maintainer with agents.

| Phase | Scope | Effort | Exit check |
| --- | --- | --- | --- |
| 0. Shared data | Pets, themes and study methods to JSON in the Mac app; golden fixtures; `shared/` folder | 1 to 2 weeks | Mac snapshots and canvases unchanged |
| 1. Shell spike | Tauri island, hover zone, click-through outside the panel, tray, hotkey, DPI and multi-monitor, fullscreen apps | 2 weeks | Go or no-go on Tauri on real Windows 10 and 11 hardware |
| 2. Core tabs | Kits, Focus and Study with sounds, Today, pet and Closet, Now Playing, themes, onboarding | 3 to 4 weeks | Fixture suites green, screenshot review |
| 3. Connected tabs | Ask Claude, Claude Usage, Anki, System, Party, ICS calendar, Schedule | 3 weeks | Live tests against `claude.exe`, AnkiConnect and a local Worker |
| 4. Ship beta | Signing, NSIS, updater, winget, Sign in with Apple and sync | 2 weeks | Signed beta installs clean on a fresh VM |
| 5. 1.0 | MSIX and Store, Microsoft sign-in, Graph calendar, polish | 2 weeks | Store certification passes |

Total: about 13 to 15 weeks.
A `windows-latest` GitHub Actions job builds, tests and packages on every change under `windows/` or `shared/`.

## Risks

- Logic drift between Swift and TypeScript: mitigated by JSON sources and fixture tests in both CIs.
- WebView2 transparency and hit testing: a transparent window swallows clicks unless click-through is toggled outside the panel; the phase 1 spike must prove this.
- Covering apps at the top edge: the hover default and a position setting (top-center or above the tray) keep it out of the way.
- Signing eligibility and SmartScreen reputation for a new publisher; the Store path sidesteps both.
- Two apps to maintain: every new Mac module needs a Windows decision, so module specs should name it up front.
- No Windows hardware in the current agent setup: phase 1 needs a Windows machine or a cloud VM with GPU-backed composition.
