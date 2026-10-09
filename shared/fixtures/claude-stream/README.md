# Claude stream golden fixtures

Written by `Tests/TabbiKitCoreTests/ClaudeStreamGoldenTests.swift` from `ClaudeStreamEvent.parse(line:)` and `ClaudeAskConversation`.
They pin how Tabbi reads `claude -p --output-format stream-json --verbose --include-partial-messages` and how Ask Claude turns those lines into a chat, so the Windows port reads the CLI the same way.

The file has `schema` (`tabbi.claude-stream.golden`) and `version` (1).

- `lines`: one raw CLI line each (`line`, exactly as printed, without the newline) and the `event` it parses to.
  `event.type` is `sessionStarted`, `rateLimit`, `textDelta`, `assistantText`, `result` or `other`, and only the fields that event carries are present:
  `sessionID` (session start and result), `text` (deltas, assistant messages, result), `isError` (result), and for `rateLimit` the `status` and the `fiveHour` and `sevenDay` windows (`utilization`, 0 to 1 and above 1 over the limit, and `resetsAt` in seconds since 1970).
  A line that is not a JSON object with a string `type`, or a shape the app does not use, is `other`; the parser never fails.
- `conversations`: Ask Claude exchanges as a list of `steps`, each an `input` and the chat after it.
  `input.action` is `begin` (ask `prompt`), `line` (feed one CLI `line`), `finish` (the CLI exited), `cancel` (the user pressed stop), `retry` (take back the failed question) or `retryLostSession` (take it back only when the CLI no longer has the session, and forget the session).
  `sent` is what `begin` sends (the trimmed prompt) or the question a retry took back, and is absent when the step refused or is another action.
  `messages` lists every bubble (`role` `user` or `assistant`, `text`, `status` `streaming`, `complete`, `stopped` or `failed`), `phase` is `idle`, `streaming` or `failed`, `failure` is the one-line reason shown while failed, and `sessionID` is what the next question resumes.

A port replays only the inputs and compares every recorded output.
Rate-limit numbers compare as numbers (`1` and `1.0` are the same value).
