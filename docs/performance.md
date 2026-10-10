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
scripts/measure-performance.sh --cycle 3                # open each tab in turn, closing in between
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

`--cycle <seconds>` launches with `TABBI_PERF_CYCLE` set: every that many seconds the notch opens on the next enabled tab (including the ones under the chevron and the Closet) or closes again, so a long run shows whether memory grows with each open and close.

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

### Hang watchdog (live runs)

Demo runs leave out one thing a live run starts: `HangWatchdog`, which notices a stuck main thread and leaves a hang log.
It pinged the main thread every 2 s for as long as Tabbi ran, so an idle, closed notch still woke a background thread and the main thread about once a second, all day.
A main thread asleep in its run loop cannot be hung, so the watchdog now follows the main run loop: the timer parks on the first tick that finds the main thread waiting for events, and starts again a full interval after it wakes.
Hangs are still caught as before (about 6-8 s after the main thread stops answering).

Measured with the watchdog started in a demo release build, notch closed and the pointer still, 18 samples of 5 s each:

| Idle, notch closed, 90 s | Context switches, mean | Lowest 5 s sample | Samples at 0 |
| --- | --- | --- | --- |
| Watchdog before | 3.4 per second | 1.6 per second | 0 of 18 |
| Watchdog after | 1.3 per second | 0 | 7 of 18 |
| No watchdog (floor) | 2.7 per second | 0 | 7 of 18 |

The means move with other activity on the Mac (other processes posting events Tabbi receives), so the lowest sample is the clearer signal: before, Tabbi never went 5 s without waking; after, it is as quiet as without the watchdog.
CPU was 0.00% in all three runs.
`HangWatchdogTests` guards it: with the main thread idle for 20 intervals the watchdog ticks at most 4 times (20 without the fix), a busy main thread keeps it ticking, and the hang tests still pass.

## Open, on each tab

Demo data, release build, the notch held open with `--open`, 45 s per tab.

| Tab | CPU before | CPU after | Memory before | Memory after |
| --- | --- | --- | --- | --- |
| Focus (running Pomodoro) | 5.02% | 0.19% | 40 MB, growing to 73 MB | 25 MB, flat |
| Timer (Study, running party session) | 4.88% | 0.37% | 38 MB, growing to 74 MB | 26 MB, flat |
| Today | 0.16% | 0.09% | 34 MB | 33 MB |
| Now Playing | 0.19% | 0.21% | 27 MB | 26 MB |
| AI Usage | 0.04% | 0.04% | 26 MB | 25 MB |
| Closet (one animated pet) | 1.0% | 0.02% | 34 MB | 34 MB |
| Party (six animated pets) | 3.8% | 1.11% | 37 MB | 37 MB |

No tab made a network request in demo mode.

The timer dials were the problem.
Focus and Study wrapped their dial in an animation keyed on the timer's progress, which changes every second.
So every tick ran a spring over the whole dial, and the countdown's `.numericText` transition re-rendered its digits with a blur into a drawing layer for most of each second: about 230 context switches per second and memory growing about 0.6 MB per second (some 2 GB an hour) for as long as a running timer was on screen.
`sample` showed the main thread in `CA::Transaction::commit` and `CABackingStoreUpdate` all the time, and `heap` showed the growth as tens of thousands of 2 to 2.5 KB blocks.
The fix drops the per-second animation: `ProgressRing` already sets a tick without a spring and animates real jumps itself, phase changes keep their spring, and a card sprint's count still rolls (the Study dial animates on `cardsDone`).

The animated pets were the other cost.
Each pet drew through a `TimelineView` that woke exactly at its frame changes (`PetFrameSchedule`), so an idle pet changes about 1.5 times a second.
But every change was a full SwiftUI update of the notch: `sample` showed `NSHostingView.layout`, an AttributeGraph update, a display list diff and a Core Animation commit, about 4 ms of CPU per change.
Six pets on the Party tab made about 9 changes a second and kept the notch at 3.8% CPU with about 200 context switches per second.
(Turning off the hosting view's `sizingOptions` was tried first: it removes the window min and max size bookkeeping from each update, but that was a small part of it and CPU did not move.)

On screen a pet now plays in a layer of its own (`PetAnimationView` in `PetView.swift`): a timer that follows the same `PetFrameSchedule` swaps the layer's picture, so a frame change touches neither SwiftUI nor the window's layout.
The timers have 10 ms of tolerance, so the system can wake several pets at once, and a pet stops when its view leaves the window or the window is fully hidden (for example behind a full-screen app).
Pictures drawn into an image (`ImageRenderer` snapshots, the exported recap card) set `rendersToImage` and keep the SwiftUI drawing, since `ImageRenderer` can't draw AppKit views.

| Notch open, 45 s | CPU before | CPU after | Context switches before | after |
| --- | --- | --- | --- | --- |
| Party (six pets) | 3.84% | 1.11% | 196 per second | 56 per second |
| Closet (one pet, 3x) | 0.98% | 0.02% | | 7 per second |

What is left on Party is its own once-a-second countdown and the six pets' timer wakeups.
`PetAnimationViewTests` guards the fix: the pet animates with no SwiftUI update, stops when it leaves the window, and draws its speech bubble where the SwiftUI drawing does.

### Memory over many opens

Demo data, release build, `--cycle 3 --duration 600 --interval 10`: the notch opened on each of the eight enabled tabs in turn and closed again, about 110 opens and 110 closes in 11 minutes.

| 11 minutes, open and close every 3 s | Value |
| --- | --- |
| Footprint | 37 MB at the start, 39-42 MB throughout, 40 MB at the end |
| CPU | 3.66% of one core (24.85 s) |
| Context switches | 124 per second |
| Leaks | 288 leaks, 14 KB, the same system framework cycles as an idle run |
| Network | none |

Memory does not grow with use: opening a tab for the tenth time costs no more memory than the first.
The CPU is the open and close springs themselves, about 0.1 s of CPU per open or close, which a real day (a few dozen opens an hour) barely notices.

## Focus sounds

`FocusSoundEngine` runs AVAudioEngine only while a sound is audible: it starts on play, and after a stop or a switch to Off it fades out for 2 s and shuts the engine down once the mixer reports exact silence.
A focus session with sound off, or the gaps between sessions, keep no audio thread or device awake.

While a sound plays, its synthesis runs on the audio thread.
Its cost was measured by rendering 10 s of each sound through `FocusMixer` in a release build (the share of one core it takes to keep up in real time):

| Sound | Before | After |
| --- | --- | --- |
| Brown, pink or white noise | 0.06-0.08% | unchanged |
| Fireplace | 0.15% | unchanged |
| Rain | 0.19-0.22% | unchanged |
| Cafe murmur | 1.66-1.73% | 0.97% |

The cafe was about eight times rain's cost: sixteen synthesized talkers, each with a glottal pulse, three formant resonators, a consonant burst and a muffle filter, every sample.
`sample` put most of the time in the voiced path (the pulse and its resonators), spread over many small operations.
Two things that did not help: a lookup table in place of the pulse's `sin` and `cos` (no change in time), and skipping a talker while it is silent (talkers are silent 43% of the time, but a silent sample was already cheap, so it saved only 7%).
What did help: the talkers now run at 24 kHz, half the output rate, and the cafe interpolates between their samples.
Everything they say sits below about 6 kHz and passes a 4 kHz low-pass, so nothing audible is lost.
Over 60 s of cafe the level is unchanged (RMS 0.1818 before, 0.1817 after) and every octave band from 125 Hz to 16 kHz is within 0.4 dB of before.
`FocusAmbienceTests` and `FocusLoudnessTests` still pass, and they guard what the cafe sounds like (voice band, no low growl, steady level, loudness within 1 LU).
A timing test was not added: in the debug build that `swift test` uses, the cafe's cost relative to rain moves only from 2.3 to 1.6 times, too close to set a threshold that never flakes.

## To measure next

- A focus session with sounds playing in the running app (demo mode plays none, so this needs a live run), celebrations, Party connected to a real server, and the widget installed.
- Live data over hours.
  A first look at an older installed build with real data showed 5.4% CPU, about 670 context switches per second and 61 MB while the mouse was in use.
  Part of that is the pointer tracking fixed above; a live run with the pointer still will show what the live modules add.
