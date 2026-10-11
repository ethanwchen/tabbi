# Final pre-launch gates

Evidence for the ship gate and the resource gate before the App Store and direct-download launch.
Each section names the commit it was measured on, so a later run can tell what it covers.
The QA history behind these numbers is in `docs/qa-log.md`.

## Ship gate

Checked on `gnhf/qa-final` after 4fb344ab (main at bfd327ad, the last feature merge, plus the QA fixes); the test runs include the `PartyStore` defaults fix.
`origin/main` had no newer commits when this section was written.
A final pass after the Canvas fix (95dd01c9) and a merge of main at a19e46df (a site-only change) repeated the build, one full `swift test --parallel` run, the style check and the site build and tests: all pass, with the same counts as below.

### Tests and checks

| Check | Result |
| --- | --- |
| `swift build` | no warnings |
| `swift test --parallel` (as CI runs it), three full runs in a row | all three pass: 3009 XCTest tests (TabbiKitCoreTests and TabbiTests) and 52 Swift Testing tests each, exit code 0, no `with N failure` line, 8-9 minutes per run. A first set of three found one flaky test (`PartySnapshotTraceTests` sharing `UserDefaults.standard` between parallel processes), now fixed (see `docs/qa-log.md`), and these runs were on the fix. The two skips are `PartyLiveServerTests`, which need `PARTY_TEST_SERVER` set |
| `scripts/check-style.sh` | passes |
| `backend`: `npm test` and `npm run typecheck` | 395 tests in 23 files pass, typecheck clean |
| `python3 site/build.py` and `node --test 'site/test/*.test.mjs'` | builds all 12 pages, 14 tests pass |

Each test log was searched as a whole for `with [1-9][0-9]* failure`, not only its last summary line, so a failure in any bundle (TabbiKitCoreTests, TabbiTests, the Swift Testing tests) would show.
The `CoreData: XPC: sendMessage: failed` lines the logs print come from the test host's environment, not from a test.

### GitHub CI

Main's CI (Xcode 26.6) passed on bfd327ad, the newest commit on main (run 38142848036, 27 minutes), and on the two merges before it.
CI runs on pushes to main and on pull requests, so the QA fixes on `gnhf/qa-final` get their own CI run when that branch is opened as a pull request or merged; that run has to be green before the App Store upload.

### App Store edition end to end

Built as `scripts/release-appstore.sh --adhoc` builds it (sandboxed, nothing uploaded), then re-signed under throwaway bundle ids so each check had its own container and none of the maintainer's data.
The sandbox log (`/usr/bin/log stream` filtered on Sandbox) was watched during every check.

| Gate item | Result | Details in `docs/qa-log.md` |
| --- | --- | --- |
| First-run onboarding | passes: name, kit, question, tabs, pet, Anki, calendar access granted in the sandbox, timer method, extras | first-run entry; Party wording, kit summary and tile alignment fixed |
| Every tab it ships | passes: with all eight tabs turned on, Timer, Today (with yesterday and tomorrow), Now Playing (the Automation prompt only after setup, then Spotify's track), Ask AI (its "Add your Claude API key" state), System (graphs filling within seconds), and from More tabs Focus, Anki ("Anki is closed" with Open Anki) and Schedule ("See your day at a glance" before calendar access), plus the Closet with its bond row and collar | first-run entry and the final walkthrough; Now Playing prompt fix |
| Timer through a full focus and break, Stop for partial rewards | passes: focus rolled into the break, the break ended idle, Stop paid 6 points for 6 minutes and none under the 5-minute minimum | timer entry; coach bubble and Today timer card fixed |
| The Closet and the heatmap | passes, the heatmap took the session's minutes | timer and recap entries |
| Weekly recap shown once | passes, not shown again after a reopen or a relaunch | recap entry |
| AI consent | passes: Cancel keeps None, Allow picks the provider, the key saves to the sandboxed Keychain, an invalid key shows a clean error with Retry | AI consent entry |
| Sign in with Apple's sheet | the age question, the Sign in with Apple sheet and Apple's web sign-in page appear, and closing the page leaves no error | Sign in with Apple entry |
| Settings | passes in every pane: panel sizes, More options, Tabs, Look themes, Connections, About links | Settings entry |
| Quit and relaunch with data kept | passes: name, pet, tabs, timer history and recap state kept | first-run and recap entries |

Sandbox denials: none from Tabbi's code in any check.
The log showed only the throwaway build's renamed App Group (the real build's group matches), one NVMe query from a system framework, and `syspolicy.exec` lookups while a macOS consent prompt or the web sign-in was open.
No crash, hang, blank panel or broken panel came up in any check.

Limitation: an ad-hoc build has no Sign in with Apple entitlement, so it takes the web flow; the native `ASAuthorizationController` sheet needs the App Store provisioning profile, which is not installed on this Mac.
Check the native sheet once on the signed build from `scripts/release-appstore.sh` (TestFlight) before submitting.

### Late arrivals

Pet growth (#115) and Arabic (#114) were merged before these checks.
The bond row and collars, the adventure walk-off with a paw print and the return with a gift, the night doze, the closed-notch pet inside the 32 pt bar in every state, and Arabic's mirrored layout on the main tabs all check out in English and Arabic snapshots, at all three panel sizes where it matters.
The one fix this needed was the Timer tab's study method text, which stayed English in every other language and reversed "52 / 17" in Arabic.

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

Fixed: the transient rise of about 250 MB of graphics memory ("owned unmapped (graphics)" in `vmmap`, 32 regions of 8 MB) was not the pet coach's window.
It came from SwiftUI's `Canvas`, which renders through Metal (RenderBox); the first `Canvas` on screen made the renderer set up that memory for as long as one showed.
Three views used one: the sparkles around the closed-notch pet when it cheers (about two seconds, which is why it looked tied to the coach, whose demo previews fire a cheer around the same time), the celebration burst in the open panel, and the paw loader, which held it for a whole Ask AI "Thinking" wait or Anki start.
All three now draw the same paths as SwiftUI shapes; every English and Arabic snapshot is pixel-identical to the `Canvas` version.

| Release build, demo data | Before | After |
| --- | --- | --- |
| Launch with the pet's cheer (peak footprint, `vmmap --summary`) | 274-281 MB in about half of the runs | 29.4-29.9 MB in 18 of 18 runs, with the cheer confirmed in the log in 8 of them |
| Anki's "Starting Anki" paw loader held open (`TABBI_ANKI_STATE=starting TABBI_PERF_OPEN=anki`) | 269-272 MB for as long as it shows | 24 MB flat, 1.2-1.6% CPU |

The earlier bisect that seemed to tie it to `orderFrontRegardless()` was noise: the cheer comes or doesn't from run to run, so a handful of runs per variant could not tell them apart.

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
