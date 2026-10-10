# Performance, energy and memory

Tabbi runs all day in the notch, so it has to stay light.
Targets: near 0% CPU and no periodic wakeups while idle with the notch closed, modest CPU while open, and flat memory over hours.
This page records how to measure that and the numbers before and after each fix.
Older, deeper write-ups live in `docs/perf/` (for example `claude-usage-scan.md`).

## Measuring

Build the release app, then measure it:

```sh
scripts/bundle.sh tabbi release
scripts/measure-performance.sh                          # 2 min, demo data, idle and closed
scripts/measure-performance.sh --pointer-moves 60       # the same while the mouse moves
scripts/measure-performance.sh --live --duration 600    # real data
scripts/measure-performance.sh --pid <pid> --no-leaks   # an app that is already running
```

The script launches the binary directly with `TABBI_DEMO=1` (unless `--live`), so it knows the PID and stops only that process.
It writes `samples.csv`, `network.csv`, `footprint.txt`, `leaks.txt` and `summary.txt` to `perf-results/<timestamp>` (or `--out`).
Nothing needs sudo:

- CPU: `top` per sample, and the CPU seconds `ps` reports over the whole window, which is the number to compare.
- Wakeups: `top`'s IDLEW column reads 0 on macOS 26, so the script reports context switches per second (`top -c d`) instead. A process that truly sleeps has none.
- Energy: `top`'s POWER column, Apple's energy impact score. For Tabbi it tracks CPU closely.
- Memory: `footprint` (the number Activity Monitor shows) per sample, and `leaks` at the end.
- Network: one `nettop` in delta mode for the whole window, bytes in and out and the connections opened. A fresh `nettop` per sample costs the target CPU, so it is not used that way.

`--pointer-moves N` posts N mouse-moved events per second at the pointer's current spot (`scripts/perf-pointer-moves.swift`), so the pointer stays put but every global mouse monitor runs.
The terminal needs Accessibility access for that.
The notch tracks the pointer with a global monitor, so this is how a user moving the mouse all day looks to Tabbi.

Measure on a quiet machine: real mouse movement during an "idle" run shows up as CPU (see below), so compare runs with `--pointer-moves`, or keep your hands off the mouse.

## Idle, notch closed

Demo data, release build, Apple Silicon (M1), macOS 26.6.

With the pointer still, Tabbi used 0.00 s of CPU over 30 s: no timers, no polling, no context switches.
All of its idle cost came from pointer tracking.
`sample` showed each mouse move running `NotchController.pointerMoved()`, which set `panel.ignoresMouseEvents` on every move, and re-measured the preview's text (`NotchPreviewLayout.wingWidth`, which also rebuilt a font for the Join button) through `NotchViewModel.size`.
Setting `ignoresMouseEvents`, even to the value it already has, commits a window server transaction: about 7.5 us in the app plus a Core Animation commit and window server work.

The fix sets `ignoresMouseEvents` only when it changes, measures the preview's wing once per preview change, and measures the Join button once.

| 60 pointer moves per second, 60 s | CPU | Context switches |
| --- | --- | --- |
| Before | 4.44% | 775 per second |
| After | 2.50% | 200 per second |
| An empty app with only a global mouse monitor (floor) | 2.6% | |

After the fix Tabbi's own work per move no longer shows in `sample`; what is left is AppKit receiving each event from the window server, which any global mouse monitor pays.
Getting below that floor would mean not watching every mouse move (for example tracking areas on a small window over the notch), which is a larger change to `NotchController`.

`NotchPointerTrackingCostTests` guards this: the closed size follows every preview change, and reading the size with a preview costs no more than without one (it was 15 times slower before the fix).

Memory stayed flat at 21-23 MB over these runs.
`leaks` reports about 290 leaks, 14 KB in total, all of them root cycles inside system frameworks (an `NSXPCConnection` for `LNDaemonApplicationInterface`, App Intents), none in Tabbi's code.

## To measure next

- Each tab open, a focus session with sounds, celebrations and animated cosmetics, Party connected, and the widget installed.
- Live data over hours.
  A first look at an older installed build with real data showed 5.4% CPU, about 670 context switches per second and 61 MB while the mouse was in use.
  Part of that is the pointer tracking fixed above; a live run with the pointer still will show what the live modules add.
