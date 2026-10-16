# Tabbi for Windows

Tabbi on Windows lives in a top-center island instead of the MacBook notch, with a tray icon and a global hotkey (Ctrl+Alt+Space).
The brief is [docs/windows/HANDOFF.md](../docs/windows/HANDOFF.md), and phase 1 results are in [docs/windows/phase1.md](../docs/windows/phase1.md).

The stack is Tauri 2: a small Rust host in `src-tauri/` for everything Windows-specific, and a React and TypeScript UI in `src/` that runs in the system WebView2.

## Setup

Follow the checklist in [docs/windows/ENVIRONMENT.md](../docs/windows/ENVIRONMENT.md): Node.js 20 or newer, Rust stable with the MSVC toolchain, and Visual Studio 2022 Build Tools with the C++ workload and the Windows 11 SDK.
No environment variables, keys or `.env` file are needed.

```sh
cd windows
npm ci
npm run icons        # generate the app and tray icons from docs/brand/assets
```

## Run, test, look

```sh
npm run app          # the real app, with the UI hot-reloading
npm run dev          # the UI alone in a browser at http://localhost:1420, on a mock host
npm run typecheck
npm run lint
npm test             # Vitest: the shell state machine, geometry, springs, theme
npm run snapshots    # render the shell, every module panel and the kit gallery to tests/snapshots/output/<scale>/
```

In `src-tauri/`:

```sh
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test           # placement math, hot zone dwell, outside clicks, the service rules
cargo test -- --ignored   # live checks on this desktop: Credential Manager, the media session, PDH counters
```

From the repo root, in Git Bash: `bash scripts/check-style.sh` (no em dashes or emojis anywhere).

After any UI change, run `npm run snapshots` and open the PNGs; judge them against [docs/design/guidelines.md](../docs/design/guidelines.md).
The browser dev server runs on the mock host with demo data and takes the state to draw from the query string: `?phase=open&tab=planner`, `?phase=pill&hover`, `?mode=alwaysVisible`, `?window=settings&section=look`, plus `?still` (no motion), `?backdrop` (a desktop color behind the island), `?lang=de`, `?theme=cozy`, `?size=large` and `?kit=medicine`.
The snapshot harness draws any one state still: `?snapshot=open:planner`, `?snapshot=pill:focus`, `?snapshot=onboarding:pet`, `?snapshot=settings:tabs` (`?snapshot=index` lists them all, including each module's own `snapshotStates`).

`TABBI_NOTCH_MODE=alwaysVisible npm run app` keeps the closed pill drawn in a development build, `TABBI_DEMO=1` runs on demo data and saves nothing, and `TABBI_PARTY_SERVER=http://localhost:8787` points Party at a local Worker (debug builds only).

To measure the idle footprint, start a release build (`npx tauri build --no-bundle`, then `src-tauri/target/release/tabbi-windows.exe`), leave the island closed, and run `powershell -ExecutionPolicy Bypass -File scripts/measure-idle.ps1`.
It waits 10 minutes, then checks the budget: at most 80 MB private working set over all Tabbi processes, and under 0.1 percent CPU.

## How it fits together

- `src-tauri/src/placement.rs`: where the island sits on a display (DPI, work area, a taskbar on any edge), pure and unit-tested.
- `src-tauri/src/watcher.rs`: one thread that watches the pointer for the hot zone and for clicks outside the open panel, plus fullscreen apps and display changes, waking only as often as the island's state needs.
- `src-tauri/src/win.rs`: the Win32 calls (tool window, window region, focus, fullscreen detection).
- `src-tauri/src/lib.rs`: the composition root: window, tray, hotkey, `tabbi://` links, and the commands the UI calls.
- The Windows services, one module each with its rules tested: `storage.rs` (JSON documents in `%APPDATA%\Tabbi` and `%LOCALAPPDATA%\Tabbi`, kept as exact text and written atomically), `credentials.rs` (Credential Manager under `Tabbi/`), `notify.rs` (toasts), `media.rs` (the system media session, with change events while watched), `system.rs` (CPU, memory and GPU once a second while watched), `http.rs` (requests to an allow-list of services, streaming for AI, and ICS calendars), `autostart.rs` (Start with Windows, off by default) and `ai_paths.rs` (where the AI command line tools are).
- `src/app/`: the runtime, a port of the Mac's app wiring: `TabbiModule` and `defineModule`, the `ModuleRegistry`, `ModuleContext`, `ProviderHub`, `ActivityLog`, `SettingsStore`, `SharedServices`, the `TickerStore` and `AppServices`, the composition root; stores are plain classes React follows through `useStore`.
- `src/modules/<id>/`: one folder per module, and `src/modules/moduleList.ts`, one line each. A module is its folder plus its line (see "Adding a module" in AGENTS.md; `tests/support/leetCodeModule.tsx` is a complete example).
- `src/ui/shell/machine.ts`: the island's state machine (when it opens and closes, the Mac's input rules), a pure reducer.
- `src/ui/Island.tsx`: runs the machine, draws the shape with the Mac's springs, and hosts the header (`src/ui/Header.tsx`), the panels, the closed pill's preview and the takeover; `src/ui/shell/settings/` is the Settings window and `src/ui/shell/snapshot/` the snapshot harness.
- `src/host/`: the typed boundary to the Rust host, with a mock for tests and snapshots.

The island window is always the size of the open canvas (560 x 236 logical pixels).
Only its window region changes: the open panel, the pill, or nothing, so clicks outside the visible shape reach the app below and the webview never reflows while the shape animates.

Shared data (themes, kits) is read in place from `Sources/TabbiKitCore`, never copied.
