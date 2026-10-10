# Test coverage

This page records where Tabbi's automated tests are thin and what to test next.
Numbers are line coverage, measured on 2026-10-09 at commit `936baeff`.

## How to measure

Swift (all three test targets, merged):

```sh
swift test --enable-code-coverage
BIN=$(swift build --show-bin-path)
xcrun llvm-cov report "$BIN/TabbiTests.xctest/Contents/MacOS/TabbiTests" \
  -object "$BIN/TabbiKitCoreTests.xctest/Contents/MacOS/TabbiKitCoreTests" \
  -object "$BIN/TabbiWidgetUITests.xctest/Contents/MacOS/TabbiWidgetUITests" \
  -instr-profile="$BIN/codecov/default.profdata" -ignore-filename-regex='(Tests|\.build)/'
```

`swift test` also writes `$BIN/codecov/Tabbi.json`, but that export covers only `TabbiKitCore`.
Pass every test binary with `-object` as above to see the app targets too.

Backend (the Workers pool only supports the istanbul provider, which is not a saved dependency):

```sh
cd backend
npm ci
npm install --no-save @vitest/coverage-istanbul@$(node -p "require('vitest/package.json').version")
npx vitest run --coverage.enabled --coverage.provider=istanbul --coverage.include='src/**'
```

## Summary

| Area | Lines | Covered |
| --- | ---: | ---: |
| `TabbiKitCore` (pure logic) | 21708 | 96.0% |
| `TabbiWidget` | 306 | 99.7% |
| `TabbiKit` (shared AppKit and SwiftUI) | 4565 | 29.5% |
| `Tabbi` (app, modules, stores, views) | 39104 | 18.0% |
| `backend/src` (Worker and Hub) | 1241 | 98.2% (branches 95.6%) |

At this commit `swift test` ran 2219 XCTest cases plus the Swift Testing suites, all green (2 skipped), and the backend ran 366 tests, all green.

Most uncovered app lines are SwiftUI view bodies, the snapshot renderer and the notch window controller.
Those are checked by the snapshot run rather than by unit tests, so this page ranks the non-view code, where a bug changes data or behavior.

## Weakest areas, by risk

### 1. Party store actions (app)

`Tabbi/Modules/Party/PartyStore.swift` is at 74%, and the uncovered part is the user-facing actions.
No test drives `addFriend(code:)`, `removeFriend(code:)`, `createParty()`, `joinParty(code:)`, `join(friend:)`, `leaveParty()`, `startSession(minutes:)`, `endSession()`, `leaveSession()`, `rejoinSession()`, `block(_:)`, `retry()`, `cancelReport()`, `retryInviteConnection()`, `willSleep()` or `didWake()` through the store.
The wire format is well tested in `TabbiKitCore`, so the gap is how the store updates its state, errors and refresh plan around each call.
Plan: an in-memory `PartyTransport` fake that answers like the Hub, then one test per action, including the error path and sleep and wake.
Status: `PartyStoreActionTests` now drives friends, parties, shared sessions, block, retry and the single-action guard through a stateful fake server.
`PartyStoreSleepWakeTests` covers sleep and wake through a notification center the store now takes in its init.
Going to sleep sends one `offline` heartbeat before the observer returns (none when already invisible), waking sends a fresh heartbeat and asks for grants again, a wake after the server was unreachable reconnects at once instead of waiting out the backoff, and a stopped store ignores both.

### 2. Sync store lifecycle (app)

`Tabbi/Sync/SyncStore.swift` is at 75%.
`flushOnQuit()`, `saveDidChange(_:)`, `syncSoon(after:)` (the debounce) and the background loop started in `start()` have no test.
Merge and conflict rules in `TabbiKitCore/Sync` are covered (98%), so the risk is losing the last change on quit or syncing too often.
Plan: drive the store with a fake server and a fake clock, save, quit before the debounce fires, and check the server got the change once.
Status: `SyncStoreTests` now covers the debounce (edits in a row push once), wake (waits `wakeDelay`, fetches grants again) and quit inside the debounce (the edit is pushed once, the pending round is cancelled), through an injected sleep.
They found that adopting a merged save scheduled a redundant second round, which is fixed.

### 3. Focus timer persistence and notifications (app)

`Tabbi/Modules/Focus/FocusStore.swift` is at 74%.
`toggleRunning()`, `focus(on:)`, `link(_:)`, `rescheduleNotification()` and the `FocusNotifications` wrapper are untested, and so is the `recoverAtLaunch()` path that records a session cut short by quit.
Plan: tests for stop and partial reward across sleep and quit, using the store's clock and a stub notification center.
Status: `FocusSessionInterruptionTests` covers stop and partial reward across sleep, quit and a crash.
`FocusStoreControlTests` now covers play and pause, "Focus on this" (idle, paused, on a break), linking and unlinking, launch recovery after an older build (phases that ran out are logged once), a crash during the break, a heartbeat from the future, and the demo saving nothing.
Notifications are still untested, because `FocusNotifications` only exists inside an `.app` bundle.

### 4. Study store controls (app)

`Tabbi/Modules/Study/StudyStore.swift` is at 80%.
`skip()`, `setDeepFocus(_:)`, `setCustom(_:)`, `receiveCards(_:)` (the Anki card feed) and the heartbeat to Party are untested.
Plan: tests that skip a phase mid-session, switch deep focus on and off, and feed cards, checking the activity log and the shared focus clock.
Status: `StudyStoreControlTests` now covers skipping a running block (logged as skipped with its minutes, the break runs, the skip is saved), skipping while paused and on the plain Timer, deep focus saved and read back, the shared focus clock following start, deep focus, pause and stop, new Custom lengths retuning a running block (and never ending it sooner than a minute), the Anki card feed (baseline at start, pauses ignored, the goal ending the sprint, Anki going away), and the demo saving nothing.
They found that a snapshot run saved the deep focus switch into the user's preferences, which is fixed.
The heartbeat (the last-alive time a crash recovers from) is covered by `StudySessionRecoveryTests`, and following the party's shared session by `StudyPartySessionTests`, so this area has no known gap left.

### 5. Network transports and the Claude CLI (core)

- `TabbiKitCore/Party/PartyTransport.swift` 43%: `URLSessionPartyTransport.send(_:timeout:)` and URL building have no test.
- `TabbiKitCore/AI/AIProvider.swift` 82%: `AIHTTPProvider.urlSession(_:)`, the real streaming transport, has no test; the providers are tested through a fake transport.
- `TabbiKitCore/Claude/ClaudeCLI.swift` 19%: `stream(...)`, `events(from:)` and `lookupInLoginShell()` run only against a real `claude` binary.
- `TabbiKitCore/AI/AIKeyStore.swift` 34%: the Keychain-backed store is untested.

Plan: a `URLProtocol` stub for the two URLSession transports (timeouts, non-2xx, malformed bodies, cancellation mid-stream), and a fake `claude` shell script that prints canned stream-json for `ClaudeCLI`.
Status: `URLSessionPartyTransportTests` now drives `URLSessionPartyTransport` through a `URLProtocol` stub: the request it builds (route under a server path prefix, headers, bearer token, body, timeout), non-2xx replies with `Retry-After`, network failures mapped to `PartyError`, and cancellation of a request that never answers.
`AIHTTPURLSessionTransportTests` drives `AIHTTPProvider.urlSession(_:)` the same way: lines split across body chunks, the OpenAI and Anthropic auth headers, non-2xx replies (529, 404 with a message, 500 with an empty body), an error inside a 200 stream, a refused connection, a connection dropped mid-stream (it fails rather than finishing), and cancelling the consumer, which cancels the URLSession task.
`ClaudeCLIStreamTests` runs `ClaudeCLI.stream` (both the prompt and the stdin input-line forms) and `ClaudeLimitsProbe.run` against a fake `claude` shell script: events parsed in order with noise skipped, the prompt passed last after `--` verbatim, the temporary working directory, a failing CLI delivering its output before throwing with its stderr, a missing executable, a 1 MB input line delivered whole, cancellation stopping the process, and the probe stopping the CLI as soon as limits arrive.
`ClaudeCLI.lookupInLoginShell()` (it depends on the user's login shell) and `AIKeyStore` (Keychain) are still untested.

### 6. Claude Ask session (app)

`Tabbi/Modules/ClaudeAsk/ClaudeAskSession.swift` is at 56%.
`retry()`, `newChat()`, `delete(_:)`, `deleteAllChats()`, `removePending(_:)` and the screenshot attachment are untested.
Plan: tests through a fake `AIProvider` covering retry after an error, deleting the open chat while it streams, and history reload.
Status: `ClaudeAskSessionHistoryTests` drives the session against a scripted hosted API that can hold an answer open.
It covers retry after a server error (the failed exchange is replaced and saved once, and a fresh session reads it back), retry with nothing to retry, deleting the open chat while it streams (the late answer never writes into the new chat and the chat is not saved again), deleting another chat, Delete All leaving unrelated files alone, New chat cancelling an answer, opening another chat saving the partial answer as stopped, and screenshots (kept for Retry and sent again, deleted once answered, on remove and on New chat).
Taking a real screenshot (`ClaudeAskScreenCapture.captureDisplay`) still needs Screen Recording and stays untested.

### 7. Crash handler installation (app)

`Tabbi/Feedback/CrashHandler.swift` is at 67%.
Report building and sanitizing are covered (`CrashReport` 96%, `CrashReporting` 92%), but `install(in:environment:)` and the signal and exception handlers are not, since they would crash the test process.
Plan: keep sanitizing tests in core; test `install` only for its environment checks (demo and snapshot runs never install).
Status: `install` runs only in crashing child processes (so its lines never count toward coverage), which `CrashHandlerTests` starts with `xcrun xctest`.
Besides a bad memory access and a Swift trap, a child now raises an uncaught Objective-C exception on a named background thread: the log names the exception and the thread, keeps none of its reason, and the abort that follows does not overwrite it.
Another child overflows its stack, and the handler still writes a signal log from the stack it was given at install.
Each child installs twice, and the second install (with another environment) changes nothing.
Removing `SA_ONSTACK`, the install guard or the abort guard each makes these tests fail.
The exception test takes about 30 seconds, because XCTest's own terminate handler holds an uncaught exception that long before the system's handler sees it.
The check that demo and snapshot runs never install lives in `AppDelegate` and is still untested.

### 8. Other app stores below 40%

`AnkiStore` 17%, `ConnectionsStore` 16%, `FocusController` 21%, `StudyReminderScheduler` 15%, `ScheduleStore` 31%, `SpotifyController` 35%, `PetCoachController` 34%, `SystemMonitor` 28%.
Most of these wrap system services (AnkiConnect over HTTP, AppleScript, notifications, sampling).
Their parsing lives in `TabbiKitCore` and is covered; what is missing is state handling when the service is off, slow or returns garbage.
Status: `AnkiStoreRefreshTests` drives `AnkiStore` against a scripted AnkiConnect transport (the store now takes an optional `client`).
It covers the first fetch at start (counts shared as Today's goal, answered cards logged once and then only the new ones), Anki quitting (setup screen, counts cleared, nothing shared), a busy or garbled Anki (the last counts kept with a warning, then recovery), an older slower refresh landing after a newer one, a refresh and a Sync that finish after `stop()` (dropped, no warning, no extra fetch), and Sync failing then succeeding (a second click while syncing does nothing).
The store's own `Task.isCancelled` check after a refresh is backed up by the client, which already throws for a cancelled request, so removing only that check changes nothing visible.
`ConnectionsStoreTests` covers `ConnectionsStore` where it never probes the Mac: demo mode (sample rows, no checks, no actions, a pretend Do Not Disturb test), the Party row fed by the Party tab (each state shown, repeats ignored, the setup sheet starting and retrying through the tab, a second tab replacing the first), counting the views that watch a row (returning to Tabbi checks only rows still shown), and the Do Not Disturb switch, which probes nothing while its row is hidden.
The probed rows (Spotify, Music, Anki, Calendar, Claude, notifications, Focus shortcuts) need real apps and permissions and are still checked by hand.
`ScheduleStorePlanTests` drives `ScheduleStore` (which now takes an optional `clock`) at a fixed 9:00 with a mocked Ollama as the picked AI.
It covers Plan filling the rest of the day, Skip clearing the offer and a skipped block's selection, Refine replacing the blocks with the AI's validated plan, an unusable answer keeping the local plan, Select and Skip waiting while the AI refines, a refine cancelled by Discard or by planning again (its late answer neither lands nor shows as a failure), week plans never refined, and Add in demo mode (one block, then the rest, and Add waiting while the demo refines).
The live store in these tests is never shown and never adds, so it neither reads nor writes the real calendar on a test host with calendar access; reading EventKit and writing planned blocks are still checked by hand.
`FocusController`, `StudyReminderScheduler`, `SpotifyController`, `PetCoachController` and `SystemMonitor` are still below 40%.

### 9. Backend

The Worker is well covered.
Remaining uncovered lines:

- `src/index.ts` lines 40-41: the 503 answer when the Hub Durable Object throws.
- `src/webauth.ts` branches at lines 67, 71 and 76-77: malformed web sign-in callbacks.
- `src/apple.ts` around lines 274-297: Apple token revoke failures.
- `src/admin.ts` line 50 and `src/leaderboard.ts` line 20: one branch each.
- `src/hub.ts` around lines 1518-1536: a few error branches in the Durable Object.

Status: the index.ts 503, the malformed web sign-in callbacks and the Apple failures are now covered (backend lines 98.8%, branches 96.3%; `index.ts` and `webauth.ts` at 100%).
`test/log.test.ts` calls the Worker with a Hub that throws: the reply is a JSON 503 with CORS, the log names the error and the route but no code, token or IP, and the health check, catalog and preflights never reach the Hub.
`test/webauth.test.ts` posts callbacks with a missing, empty, oversized or repeated code or identity token (refused before Apple is asked, without using up the token), an Apple error that is not echoed back, a token endpoint that cannot be reached, and a stale Bearer at the token exchange.
`test/apple.test.ts` covers a token endpoint that cannot be reached (sign-in goes on with no refresh token), a keys endpoint that cannot be reached (503, no account made), and a revoke that Apple refuses or cannot be reached (the account is still deleted everywhere and `appleRevoked` is false).
The fake Apple in `test/fake-apple.ts` takes a revoke status and a set of endpoints that fail like a network error.
Still uncovered: a Hub exception that is not an `HttpError` inside the web callback, a key Apple publishes that will not import, and the code allocation retries in `insertUser` and party creation.

A load test already exists (`backend/scripts/loadtest.ts`, tested by `test/loadtest-script.test.ts`).
Status: `backend/scripts/e2e.ts` (`npm run e2e -- --url http://localhost:8787`) is the client end-to-end run.
Two simulated users, Ana and Ben, make the app's requests in its order: they register, Ana adds Ben by a pasted code, Ben sees her studying, Ana hosts a party that Ben joins through her, Ana starts and ends a shared session (Ben cannot start one), both show up studying in the party and on the leaderboard, Ben blocks Ana (the friendship and the party end, and Ana's add, join and report look like an unknown code), and an unblock brings no friendship back until one adds the other.
Both accounts are deleted at the end, even after a failed step, so repeated runs leave nothing behind.
`test/e2e-script.test.ts` runs the scenario against the Worker in `npm test`, twice in a row, and checks that a server bug (a block that leaves the friend list intact), a bad status and a network failure each stop at the right step with a readable reason and still clean up.
On 2026-10-09 it passed 8 runs in a row against a real `wrangler dev`.

## Already strong

Pure logic that the objective calls out is covered at 95% or more: sync documents and rounds, party moderation and invites, app links, pet economy and limited (seasonal) items, streaks and streak freezes, weekly recap aggregation and archive, Now Playing scripts and state, crash report sanitizing, the focus timer, and Claude stream-json parsing.
New tests there should target specific edge cases (date windows across time zones and daylight saving, concurrent edits) rather than raw coverage.
