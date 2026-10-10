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
scripts/measure-performance.sh --open focus             # the notch held open on a tab
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

`--open <module id>` launches with `TABBI_PERF_OPEN` set, which opens the notch on that tab and pins it, so it stays open with no hand on the mouse.
A module id that is not in the layout opens the first tab instead; the demo layout has `focus`, `study`, `planner`, `spotify` and more under the chevron.

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

## Open, on each tab

Demo data, release build, the notch held open with `--open`, 45 s per tab.

| Tab | CPU before | CPU after | Memory before | Memory after |
| --- | --- | --- | --- | --- |
| Focus (running Pomodoro) | 5.02% | 0.19% | 40 MB, growing to 73 MB | 25 MB, flat |
| Timer (Study, running party session) | 4.88% | 0.37% | 38 MB, growing to 74 MB | 26 MB, flat |
| Today | 0.16% | 0.09% | 34 MB | 33 MB |
| Now Playing | 0.19% | 0.21% | 27 MB | 26 MB |
| AI Usage | 0.04% | 0.04% | 26 MB | 25 MB |
| Closet (one animated pet) | 1.0% | 0.98% | 34 MB | 34 MB |
| Party (six animated pets) | 3.8% | 3.84% | 37 MB | 36 MB |

No tab made a network request in demo mode.

The timer dials were the problem.
Focus and Study wrapped their dial in an animation keyed on the timer's progress, which changes every second.
So every tick ran a spring over the whole dial, and the countdown's `.numericText` transition re-rendered its digits with a blur into a drawing layer for most of each second: about 230 context switches per second and memory growing about 0.6 MB per second (some 2 GB an hour) for as long as a running timer was on screen.
`sample` showed the main thread in `CA::Transaction::commit` and `CABackingStoreUpdate` all the time, and `heap` showed the growth as tens of thousands of 2 to 2.5 KB blocks.
The fix drops the per-second animation: `ProgressRing` already sets a tick without a spring and animates real jumps itself, phase changes keep their spring, and a card sprint's count still rolls (the Study dial animates on `cardsDone`).

Party still costs about 3.8%.
`sample` shows no Tabbi code there, only SwiftUI layout passes: each of the six pets redraws on its own frame schedule (`PetFrameSchedule`), and each frame change lays out the window.
That is the next thing to look at, for example by letting pets that share a view change frames on the same ticks.

## To measure next

- Party's animated pets (above), a focus session with sounds playing (demo mode plays none), celebrations, Party connected to a real server, and the widget installed.
- Live data over hours.
  A first look at an older installed build with real data showed 5.4% CPU, about 670 context switches per second and 61 MB while the mouse was in use.
  Part of that is the pointer tracking fixed above; a live run with the pointer still will show what the live modules add.
