# Final pre-launch gates

Evidence for the ship gate and the resource gate before the App Store and direct-download launch.
Each section names the commit it was measured on, so a later run can tell what it covers.
The QA history behind these numbers is in `docs/qa-log.md`.

## Resource gate

Measured on `gnhf/qa-final` at 927f3385 (main at bfd327ad plus the QA fixes), Apple M3 Max, macOS 26.6, 3456 x 2234 built-in display.
Builds: `scripts/bundle.sh tabbi release` (direct download, build/Tabbi.app, copied to a temporary folder) and `scripts/release-appstore.sh --adhoc` (App Store edition, sandboxed, build 125).
Tools: `scripts/measure-performance.sh` (see `docs/performance.md`), `footprint`, `vmmap --summary` and `leaks`.
Runs use demo data (`TABBI_DEMO=1`) unless they say otherwise, so they touch none of the maintainer's data.

### Memory

| Moment | Build | Physical footprint |
| --- | --- | --- |
| At launch, notch closed | direct, demo | 26 MB |
| At launch, notch closed | App Store, demo | 30 MB |
| At launch, sandboxed throwaway profile with real data | App Store | 22-24 MB |
| After opening every tab in turn for 11 minutes (`--cycle 10`, 66 opens and closes) | direct, demo | 36 MB rising to 62-66 MB by minute 4, then flat |
| After opening every tab in turn for 7 minutes (`--cycle 10`) | App Store, demo | 30 MB rising to 49-51 MB by minute 1, then flat |
| A full focus session with the rain sound playing, the end chime and the pet's "Done! You stuck with it, +8" moment, then the break | App Store, throwaway profile | 24 MB during focus, 31-32 MB after the moment, flat for 3 minutes |
| 30 minutes idle, notch closed | direct, demo | 26 MB at the start, 25 MB at the end, peak 27 MB |

Steady state stays between 25 and 66 MB, far under the 120 MB target, and every long run levels off instead of growing.
The rise during the tab cycles is SwiftUI and image caches filling once per tab; a second pass over the same tabs adds nothing.

Leaks: 286-436 leaks of 14-24 KB in total in every run (after the tab cycles, after the focus session, after 30 minutes idle).
All of them are root cycles of `NSXPCConnection`, `NSArray` and `NSSet` objects inside system frameworks (the `LNDaemonApplicationInterface` App Intents connection documented in `docs/performance.md`); none names a Tabbi type.

Open item: when the pet coach's overlay window appears beside the notch (a nudge, a glance or the end-of-session moment), a release build sometimes holds about 250 MB of extra graphics memory ("owned unmapped (graphics)" in `vmmap`) for about two seconds, then gives it back (276 MB peak, back to 31-33 MB).
It shows in release builds only, not every time, and it comes from putting the window on screen: the same window with empty content still shows it, and skipping `orderFrontRegardless()` makes it go away.
A standalone app with the same panel setup does not reproduce it, so the cause is still open; it never stays, so steady state and the numbers above are unaffected.

### CPU and wakeups

| Moment | Build | CPU | Context switches |
| --- | --- | --- | --- |
| 30 minutes idle, notch closed | direct, demo | 0.04% of one core on average (0.67 s of CPU in 31 minutes), 0.5% highest 30 s sample | 4.4 per second |
| Opening every tab in turn, every 10 seconds | direct, demo | 1.29% on average, 2.7% highest sample | 47.8 per second |
| Opening every tab in turn, every 10 seconds | App Store, demo | 1.56% on average, 2.8% highest sample | 51.5 per second |
| Notch held open on each tab (`--open`, iteration 1 of this pass) | direct, demo | 1.2% or less on every tab | |

Idle is far under the 0.5% target, and no open tab comes near pegging a core.
The idle run's context switches include a few minutes of synthetic pointer moves (one per second) that another check posted at the same time; `docs/performance.md` has the pointer-free idle numbers (0 to 1.3 per second).

### Energy

`top`'s energy impact score, which Activity Monitor shows, averaged 0.01 over 30 idle minutes with the notch closed and 1.2-1.4 while a tab opened every 10 seconds.
That is "Low" in Activity Monitor, and nothing in Tabbi raises a "significant energy" flag: no timer runs while idle, and the only wakeups left are the documented hang watchdog (live runs only, parked while the main thread sleeps).

### Network

Every run above (demo data) opened no connection and sent and received 0 bytes.

### Disk

The App Store throwaway profile, after a full first run, a week of seeded activity, a focus session, a recap and a relaunch, holds four small folders in `Application Support/Tabbi` (`Activity` with one JSON file per day, `Pet`, `Planner` with one file per day, `Recaps`), 40 KB in all.
Activity and Planner grow by one small file per day used; nothing else accumulates: logs go to the unified log, and `Crash Reports` holds at most one pending crash or hang log, which is deleted once the next launch reads it, and snapshot and demo runs write nothing.
