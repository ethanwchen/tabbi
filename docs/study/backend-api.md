# Tabbi friends API (client contract)

This is the contract between the Tabbi app and the `tabbi-friends` Cloudflare Worker in [`backend/`](../../backend).
Deployment, architecture and the free-tier math are in [`backend/README.md`](../../backend/README.md); what is stored is in [`backend/PRIVACY.md`](../../backend/PRIVACY.md).

## Basics

- Production base URL: `https://tabbi-friends.drosophil-anki-friends-backend.workers.dev`.
  It is the default server in Tabbi's Party settings (`PartyServer.productionURL`); users can point the app at their own deployment there.
  A server from before the rename answers as `studynotch-friends`, which the client also accepts (`PartyClient.serviceNames`).
  Local dev: `http://localhost:8787` (`npm run dev` in `backend/`).
- The Swift client is `PartyClient` in `Sources/TabbiKitCore/Party`.
  Its end-to-end test runs against a worker with `PARTY_TEST_SERVER=http://localhost:8787 swift test --filter PartyLiveServerTests`; against production it only creates throwaway users and deletes them.
- To see the Party tab render a local worker's real data, run `TABBI_PARTY_SERVER=http://localhost:8787 swift run Tabbi --snapshot snapshots-live --kit medicine`.
  Add `TABBI_PARTY_TOKEN` and `TABBI_PARTY_CODE` from a `POST /v1/register` reply to render as that user, with the friends and party you set up for it with `curl`.
  Only plain-http (local) servers are accepted there, so a snapshot never registers users on a deployed server.
- Every route is under `/v1/` except the health check `GET /`.
- Bodies are JSON objects (`Content-Type: application/json`), at most 4096 bytes.
  An empty body counts as `{}`.
  Any field not listed for a route is rejected with `unknown_field`, so never send extra keys.
- Times are unix seconds (integers).
  Days are `YYYY-MM-DD` strings.
- Every reply is JSON with `ok: true` on success, or `ok: false` with `error` (a stable code) and `message` (English, for logs only) on failure.
  Branch on `error`, never on `message`.
- Replies are `Cache-Control: no-store`; CORS is open (`*`), so a web client works too.

### Identity and auth

There are no accounts.
`POST /v1/register` returns a secret `token` (64 hex characters) and a public 8-character friend `code`.
Store the token in the Keychain; the server keeps only its SHA-256, so a lost token cannot be recovered.
Send it on every other call as `Authorization: Bearer <token>`.
The friend code is what users share; it uses `A-Z` and `2-9` without `I`, `O`, `0` and `1`.
Codes are accepted in any case and with surrounding spaces, and the server returns them upper case.

### Shared catalog

[`backend/shared/catalog.json`](../../backend/shared/catalog.json) lists the valid species, breeds per species, costumes, accessories, statuses, study methods, recommended heartbeat intervals and limits.
The app should bundle the same file so pickers only offer valid values.
`GET /v1/catalog` serves it too (no auth) if the app wants to check for a newer `version`.

## Objects

### Profile

What friends and party members see of a user.

```json
{
  "code": "K7QW2MZD",
  "name": "Ana",
  "petName": "Mochi",
  "species": "cat",
  "breed": "tabby",
  "colors": ["#F2A65A", "#FFFFFF"],
  "costume": "scrubs",
  "accessories": ["glasses", "coffee-mug"],
  "points": 1240,
  "level": 7
}
```

| Field | Rule | Default |
| --- | --- | --- |
| `name` | text, at most 24 characters after trimming; control and invisible characters are stripped | `student` |
| `petName` | text, at most 24 characters, same cleaning | `buddy` |
| `species` | `catalog.species` (`cat`, `dog`) | `cat` |
| `breed` | must belong to the species in `catalog.breeds` | first breed of the species |
| `colors` | array of at most 6 `#RRGGBB` strings, returned upper case | `[]` |
| `costume` | `catalog.costumes` | `none` |
| `accessories` | at most 4 distinct ids from `catalog.accessories` | `[]` |
| `points` | integer 0 to 100,000,000 | `0` |
| `level` | integer 1 to 999 | `1` |

When writing a profile, every field is optional.
An omitted, `null` or empty-text field keeps its current value (so a name cannot be blanked).
Changing `species` without a `breed` switches to the first breed of the new species.

### Presence

What a user is doing right now, as reported by their last heartbeat.

```json
{
  "status": "studying",
  "method": "pomodoro",
  "phaseEndsAt": 1790000000,
  "sessionMinutes": 50,
  "todayMinutes": 125,
  "streakDays": 12,
  "day": "2026-10-01",
  "lastSeen": 1789999100
}
```

- `status`: `studying`, `break`, `idle` or `offline`.
- `method`: a `catalog.studyMethods` id or `null`; `phaseEndsAt`: when the current pomodoro/break phase ends, or `null`.
  Both are only kept while `studying` or on a `break`, and `sessionMinutes` is 0 otherwise.
- `day`: the user's local calendar day that `todayMinutes` belongs to.
- `lastSeen`: server time of the last heartbeat.

Friends and party members get presence together with an `online` flag.
A user is online until 2.5 heartbeat intervals pass without a heartbeat (300 s while studying or on a break, 750 s while idle), or at once after an `offline` heartbeat.
When a user is not online, others see their presence with `status: "offline"`, `method` and `phaseEndsAt` `null` and `sessionMinutes` 0; `todayMinutes`, `streakDays` and `day` keep their last values.
Presence is `null` for a user who never sent a heartbeat.

To show a countdown, use `phaseEndsAt` and count down locally; do not poll faster to keep a timer accurate.

### Party

```json
{
  "code": "Q4RT8M",
  "host": "K7QW2MZD",
  "createdAt": 1789990000,
  "lastActive": 1789999000,
  "expiresAt": 1790042200,
  "maxMembers": 8,
  "session": { "method": "pomodoro", "phaseEndsAt": 1790000000, "startedAt": 1789998500 },
  "members": [
    { "profile": { "...": "Profile" }, "joinedAt": 1789990000, "host": true, "presence": { "...": "Presence" }, "online": true }
  ]
}
```

- `code`: 6 characters from the same alphabet as friend codes; share it to invite anyone, friend or not.
- `members` are in join order; the first one is the longest-standing member.
- `session` is `null` unless the host started a shared session.
- `expiresAt` is `lastActive + 43200`: a party disappears after 12 hours without activity.
  Creating, joining, leaving, changing the session and members' polls all count as activity (polls are recorded at most every 10 minutes, so `lastActive` may lag by that much).

## Routes

Auth column: "token" means `Authorization: Bearer <token>` is required.

| Method and path | Auth | Purpose |
| --- | --- | --- |
| `GET /` | none | health check |
| `GET /v1/catalog` | none | the shared catalog |
| `POST /v1/register` | none or token | create a user, or update the profile of an existing one |
| `GET /v1/me` | token | my profile |
| `PATCH /v1/me` | token | update my profile |
| `DELETE /v1/me` | token | delete me and everything about me |
| `GET /v1/friends` | token | my friends with profile, presence and party |
| `POST /v1/friends` | token | add a friend by code |
| `DELETE /v1/friends/{code}` | token | remove a friend |
| `POST /v1/presence` | token | heartbeat |
| `GET /v1/leaderboard` | token | this week's study minutes, me and my friends |
| `GET /v1/party` | token | my party or `null` |
| `POST /v1/party` | token | create a party |
| `POST /v1/party/join` | token | join a party by code or through a friend |
| `POST /v1/party/leave` | token | leave my party |
| `POST /v1/party/session` | token, host | start or replace the shared session |
| `DELETE /v1/party/session` | token, host | end the shared session |

### `GET /`

`200 {"ok": true, "service": "tabbi-friends", "version": 1}`

### `GET /v1/catalog`

`200 {"ok": true, "catalog": { ...catalog.json }}`

### `POST /v1/register`

Body: any profile fields (all optional), e.g. `{"name": "Ana", "petName": "Mochi", "species": "cat", "breed": "tabby"}`.

Without a token it creates a user:
`201 {"ok": true, "token": "<64 hex>", "code": "K7QW2MZD", "profile": Profile}`.
Registration is limited to 10 per minute per IP.

With a valid token it creates nothing and applies the body like `PATCH /v1/me`:
`200 {"ok": true, "code": "K7QW2MZD", "profile": Profile}`.
This makes registration safe to retry; if the reply to a first registration was lost, the app has no token yet and simply registers again.

Errors: `invalid_json`, `unknown_field`, `invalid_field`, `body_too_large`, `rate_limited`, `unauthorized` (a token was sent but is unknown), `unavailable`.

### `GET /v1/me`

`200 {"ok": true, "profile": Profile}`

### `PATCH /v1/me`

Body: any profile fields.
`200 {"ok": true, "profile": Profile}` with the full updated profile.
Unchanged profiles cost no storage write, so it is fine to send the whole profile.

Errors: `invalid_json`, `unknown_field`, `invalid_field`, `body_too_large`.

### `DELETE /v1/me`

Deletes the user, their friendships in both directions, presence, daily study minutes, and leaves their party.
`200 {"ok": true}`.
Afterwards the token is `unauthorized`; the app should drop it and its friend code.

### `GET /v1/friends`

```
{
  "ok": true,
  "friends": [
    {
      "profile": Profile,
      "since": 1789000000,
      "presence": Presence | null,
      "online": true,
      "party": { "code": "Q4RT8M", "size": 3 } | null
    }
  ]
}
```

Sorted by name, case-insensitively.
`party` is the friend's current (not expired) party; offer "Join" when `online` is true and `party` is not null.

### `POST /v1/friends`

Body: `{"code": "K7QW2MZD"}`.
Friendship is symmetric: both users see each other right away, with no request to accept.
`200 {"ok": true, "added": true, "friend": Profile}`; `added` is `false` if they were already friends (a no-op success).

Errors:

| HTTP | `error` | Meaning |
| --- | --- | --- |
| 400 | `invalid_field` | not a valid friend code |
| 400 | `self_friend` | that is my own code |
| 404 | `unknown_code` | no user has that code |
| 409 | `friend_limit` | I already have 50 friends |
| 409 | `their_friend_limit` | they already have 50 friends |

### `DELETE /v1/friends/{code}`

Removes the friendship in both directions.
`200 {"ok": true, "removed": true}`; `removed` is `false` if we were not friends.
Errors: `invalid_field` for a malformed code.

### `POST /v1/presence`

Body:

| Field | Required | Rule |
| --- | --- | --- |
| `status` | yes | `studying`, `break`, `idle` or `offline` |
| `method` | no | a `catalog.studyMethods` id or `null` |
| `phaseEndsAt` | no | unix seconds within 24 h of now, or `null` |
| `sessionMinutes` | no | integer 0 to 1440 |
| `todayMinutes` | no | integer 0 to 1440 |
| `streakDays` | no | integer 0 to 36500 |
| `day` | no | the local calendar day `todayMinutes` counts, `YYYY-MM-DD` |

Omitted counters keep their previous value, except that `todayMinutes` restarts at 0 when `day` changes.
`method` and `phaseEndsAt` are not carried over: send them with every `studying` or `break` heartbeat.
`day` defaults to the UTC day; always send the local day so minutes count toward the day the student actually studied.
It must be "today" somewhere on Earth (UTC-12 to UTC+14), which rejects a wrong clock.

`200 {"ok": true, "presence": Presence, "heartbeatSeconds": 120}`.
`heartbeatSeconds` is when to send the next heartbeat (`null` after `offline`: stop sending).

Errors: `invalid_json`, `unknown_field`, `invalid_field`, `body_too_large`.

### `GET /v1/leaderboard`

Study minutes of me and my friends in the current ISO week (Monday to Sunday of the UTC calendar), summed over each user's local days from their heartbeats.

```
{
  "ok": true,
  "week": "2026-W40",
  "from": "2026-09-28",
  "to": "2026-10-04",
  "entries": [
    { "rank": 1, "minutes": 840, "me": false, "profile": Profile },
    { "rank": 1, "minutes": 840, "me": true, "profile": Profile },
    { "rank": 3, "minutes": 95, "me": false, "profile": Profile }
  ]
}
```

Entries are sorted by minutes, then by name.
Ties share a rank and the next rank skips (1, 1, 3).
Users with no minutes are listed with `minutes: 0`.

### `GET /v1/party`

`200 {"ok": true, "party": Party | null}`.
Polling counts as party activity, which keeps the party alive while anyone has it open.

### `POST /v1/party`

Body: empty or `{}`.
Creates a party with me as host and only member, leaving any party I was in.
`201 {"ok": true, "party": Party}`.

### `POST /v1/party/join`

Body: exactly one of

- `{"code": "Q4RT8M"}`: join a party by its code (no friendship needed), or
- `{"friend": "K7QW2MZD"}`: join the party an online friend is in.

Joining leaves my previous party.
`200 {"ok": true, "joined": true, "party": Party}`; `joined` is `false` if I was already in that party.

Errors:

| HTTP | `error` | Meaning |
| --- | --- | --- |
| 400 | `invalid_field` | neither or both fields, or a malformed code |
| 404 | `party_not_found` | no active party has that code (it may have expired) |
| 403 | `not_friend` | that user is not my friend |
| 409 | `friend_offline` | that friend is not online |
| 404 | `friend_not_in_party` | that friend is not in a party |
| 409 | `party_full` | the party already has 8 members |

### `POST /v1/party/leave`

Body: empty or `{}`.
`200 {"ok": true, "left": true}`; `left` is `false` if I was not in a party.
If the host leaves, the longest-standing member becomes host; when the last member leaves, the party is deleted.

### `POST /v1/party/session`

Host only.
Body: `{"method": "pomodoro", "phaseEndsAt": 1790000000}`, both required; `phaseEndsAt` must be in the future and within 24 h.
Starts the shared session, or replaces it (send a new `phaseEndsAt` for each phase).
`200 {"ok": true, "party": Party}`.

Errors: `invalid_field`, `unknown_field`, `not_in_party` (404), `not_host` (403).

### `DELETE /v1/party/session`

Host only.
Ends the shared session: `200 {"ok": true, "party": Party}` with `session: null`.
Errors: `not_in_party` (404), `not_host` (403).

## Errors common to all routes

| HTTP | `error` | Meaning and what to do |
| --- | --- | --- |
| 400 | `invalid_json` | body is not a JSON object |
| 400 | `unknown_field` | body has a field the route does not accept |
| 400 | `invalid_field` | a field fails validation; `message` names it |
| 401 | `unauthorized` | missing, malformed or unknown token; if the user was deleted, register again |
| 404 | `not_found` | unknown route or method |
| 413 | `body_too_large` | body over 4096 bytes |
| 429 | `rate_limited` | over 60 requests per minute per token; wait for `Retry-After` seconds |
| 500 | `internal` | server bug; retry later |
| 503 | `unavailable` | temporarily unavailable; retry with backoff |

## Polling guidance

The service runs on the Cloudflare free plan, where requests (100,000 per day for everyone) are the binding limit.
Keep to these intervals, and stop every timer whose data is not on screen.

| What | When |
| --- | --- |
| `POST /v1/presence` | at launch, on every status, method or phase change, and then every `heartbeatSeconds` from the last reply (120 s while studying or on a break, 300 s while idle); send `offline` once when quitting or when the Mac sleeps |
| `GET /v1/friends` | when the friends panel opens, then every 60 s while it stays open |
| `GET /v1/party` | every 30 s while I am in a party and the party view is visible; once when the notch opens otherwise |
| `GET /v1/leaderboard` | once each time its view opens; no timer |
| `GET /v1/me`, `PATCH /v1/me` | on launch and after the user edits their pet; not on a timer |

A heartbeat whose status, method, phase and streak are unchanged is cheap but still a request, so do not send heartbeats for counters alone between scheduled ones.
Countdowns (`phaseEndsAt`, party `session.phaseEndsAt`) run locally on the client.
On `429`, back off for `Retry-After`; on `503` or network errors, retry with exponential backoff (for example 5 s, 10 s, 20 s, capped at 5 minutes).
