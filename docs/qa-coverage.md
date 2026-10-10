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
Sleep and wake are still untested, because the store only observes them outside snapshot runs.

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

### 5. Network transports and the Claude CLI (core)

- `TabbiKitCore/Party/PartyTransport.swift` 43%: `URLSessionPartyTransport.send(_:timeout:)` and URL building have no test.
- `TabbiKitCore/AI/AIProvider.swift` 82%: `AIHTTPProvider.urlSession(_:)`, the real streaming transport, has no test; the providers are tested through a fake transport.
- `TabbiKitCore/Claude/ClaudeCLI.swift` 19%: `stream(...)`, `events(from:)` and `lookupInLoginShell()` run only against a real `claude` binary.
- `TabbiKitCore/AI/AIKeyStore.swift` 34%: the Keychain-backed store is untested.

Plan: a `URLProtocol` stub for the two URLSession transports (timeouts, non-2xx, malformed bodies, cancellation mid-stream), and a fake `claude` shell script that prints canned stream-json for `ClaudeCLI`.
Status: `URLSessionPartyTransportTests` now drives `URLSessionPartyTransport` through a `URLProtocol` stub: the request it builds (route under a server path prefix, headers, bearer token, body, timeout), non-2xx replies with `Retry-After`, network failures mapped to `PartyError`, and cancellation of a request that never answers.
The AI streaming transport and `ClaudeCLI` are still untested.

### 6. Claude Ask session (app)

`Tabbi/Modules/ClaudeAsk/ClaudeAskSession.swift` is at 56%.
`retry()`, `newChat()`, `delete(_:)`, `deleteAllChats()`, `removePending(_:)` and the screenshot attachment are untested.
Plan: tests through a fake `AIProvider` covering retry after an error, deleting the open chat while it streams, and history reload.

### 7. Crash handler installation (app)

`Tabbi/Feedback/CrashHandler.swift` is at 67%.
Report building and sanitizing are covered (`CrashReport` 96%, `CrashReporting` 92%), but `install(in:environment:)` and the signal and exception handlers are not, since they would crash the test process.
Plan: keep sanitizing tests in core; test `install` only for its environment checks (demo and snapshot runs never install).

### 8. Other app stores below 40%

`AnkiStore` 17%, `ConnectionsStore` 16%, `FocusController` 21%, `StudyReminderScheduler` 15%, `ScheduleStore` 31%, `SpotifyController` 35%, `PetCoachController` 34%, `SystemMonitor` 28%.
Most of these wrap system services (AnkiConnect over HTTP, AppleScript, notifications, sampling).
Their parsing lives in `TabbiKitCore` and is covered; what is missing is state handling when the service is off, slow or returns garbage.

### 9. Backend

The Worker is well covered.
Remaining uncovered lines:

- `src/index.ts` lines 40-41: the 503 answer when the Hub Durable Object throws.
- `src/webauth.ts` branches at lines 67, 71 and 76-77: malformed web sign-in callbacks.
- `src/apple.ts` around lines 274-297: Apple token revoke failures.
- `src/admin.ts` line 50 and `src/leaderboard.ts` line 20: one branch each.
- `src/hub.ts` around lines 1518-1536: a few error branches in the Durable Object.

A load test already exists (`backend/scripts/loadtest.ts`, tested by `test/loadtest-script.test.ts`).
What is missing is a client end-to-end run: two simulated Tabbi users against `wrangler dev` who befriend, party, study together and block.

## Already strong

Pure logic that the objective calls out is covered at 95% or more: sync documents and rounds, party moderation and invites, app links, pet economy and limited (seasonal) items, streaks and streak freezes, weekly recap aggregation and archive, Now Playing scripts and state, crash report sanitizing, the focus timer, and Claude stream-json parsing.
New tests there should target specific edge cases (date windows across time zones and daylight saving, concurrent edits) rather than raw coverage.
