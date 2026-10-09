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
- Bodies are JSON objects (`Content-Type: application/json`), at most 4096 bytes (`PUT /v1/sync`: 65536 bytes).
  An empty body counts as `{}`.
  Any field not listed for a route is rejected with `unknown_field`, so never send extra keys.
- Times are unix seconds (integers).
  Days are `YYYY-MM-DD` strings.
- Every reply is JSON with `ok: true` on success, or `ok: false` with `error` (a stable code) and `message` (English, for logs only) on failure.
  Branch on `error`, never on `message`.
- Replies are `Cache-Control: no-store`; CORS is open (`*`), so a web client works too.

### Identity and auth

There are no passwords, and an account is optional.
`POST /v1/register` returns a secret `token` (64 hex characters) and a public 8-character friend `code`.
Store the token in the Keychain; the server keeps only its SHA-256, so a lost token cannot be recovered.
Send it on every other call as `Authorization: Bearer <token>`.
The friend code is what users share; it uses `A-Z` and `2-9` without `I`, `O`, `0` and `1`.
Codes are accepted in any case and with surrounding spaces, and the server returns them upper case.

Signing in with Apple (`POST /v1/auth/apple`) is optional and only adds sync: it links the friend code to Apple's user id, so the same friend code, friends and sync document follow the user to every Mac they sign in on.
Each Mac then has its own token for the same friend code.

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

Names pass a filter, because friends and party members see them.
A `name` or `petName` with a slur or an explicit term is refused with `name_not_allowed` or `pet_name_not_allowed` (400), and nothing is saved.
The terms and the reading rules live in `backend/shared/name-filter.json`: accents, case, look-alike letters, leetspeak, separators and repeated letters are seen through, and short terms only match whole words, so names like Cassandra or Scunthorpe pass.
The app runs the same filter (`PartyNameFilter`) for instant feedback, and `backend/shared/name-filter-cases.json` holds both to the same cases.

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
  Members I blocked, or who blocked me, are left out.
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
| `POST /v1/auth/apple` | none or token | sign in with Apple: link or adopt the account's friend code |
| `POST /v1/auth/signout` | token, Apple account | sign this Mac out: its token stops working |
| `GET /v1/me` | token | my profile |
| `PATCH /v1/me` | token | update my profile |
| `DELETE /v1/me` | token | delete me and everything about me |
| `GET /v1/friends` | token | my friends with profile, presence and party |
| `POST /v1/friends` | token | add a friend by code |
| `DELETE /v1/friends/{code}` | token | remove a friend |
| `GET /v1/blocks` | token | the users I blocked |
| `POST /v1/blocks` | token | block a user |
| `DELETE /v1/blocks/{code}` | token | unblock a user |
| `POST /v1/reports` | token | report a user to the maintainer |
| `POST /v1/presence` | token | heartbeat |
| `GET /v1/leaderboard` | token | this week's study minutes, me and my friends |
| `GET /v1/party` | token | my party or `null` |
| `POST /v1/party` | token | create a party |
| `POST /v1/party/join` | token | join a party by code or through a friend |
| `POST /v1/party/leave` | token | leave my party |
| `POST /v1/party/session` | token, host | start or replace the shared session |
| `DELETE /v1/party/session` | token, host | end the shared session |
| `GET /v1/sync` | token, Apple account | my sync document and its revision |
| `PUT /v1/sync` | token, Apple account | replace my sync document if I merged into the current revision |
| `/v1/admin/...` | admin token | the maintainer's report review, rename and ban, see [Moderation](#moderation-maintainer) |

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

Errors: `invalid_json`, `unknown_field`, `invalid_field`, `name_not_allowed`, `pet_name_not_allowed`, `body_too_large`, `rate_limited`, `unauthorized` (a token was sent but is unknown), `unavailable`.

### `GET /v1/me`

`200 {"ok": true, "profile": Profile}`, plus `"banned": true` when the maintainer banned this user (see [Moderation](#moderation-maintainer)).

### `PATCH /v1/me`

Body: any profile fields.
`200 {"ok": true, "profile": Profile}` with the full updated profile.
Unchanged profiles cost no storage write, so it is fine to send the whole profile.

Errors: `invalid_json`, `unknown_field`, `invalid_field`, `name_not_allowed`, `pet_name_not_allowed`, `banned`, `body_too_large`.
`name_not_allowed` and `pet_name_not_allowed` also answer a name the maintainer replaced, set again (compared ignoring case and accents).
A banned user gets `403 banned` for any change of name or pet name; the other fields still save.

### `DELETE /v1/me`

Deletes the user, their friendships in both directions, presence, daily study minutes, their sync document and Apple account link, and leaves their party.
`200 {"ok": true}`.
For a Sign in with Apple account it then revokes the account's Apple refresh token: `200 {"ok": true, "appleRevoked": true}`, or `false` when there was no refresh token, the Apple secrets are unset or Apple refused (the data is deleted either way).
Afterwards the token, and every other Mac's token for the same friend code, is `unauthorized`; the app should drop it and its friend code.

### `POST /v1/auth/apple`

Body: `{"identityToken": "<JWT>", "authorizationCode": "<code>"}` from `ASAuthorizationAppleIDCredential` (the code is optional).
Send the Mac's current friends token as Bearer if it has one; omit the header otherwise.
The server checks the identity token's RS256 signature against Apple's keys (`https://appleid.apple.com/auth/keys`, cached), its issuer (`https://appleid.apple.com`), audience (`dev.tabbi.Tabbi`) and expiry, and reads only `sub` (never the email).

`200 {"ok": true, "token": "<64 hex>", "code": "K7QW2MZD", "profile": Profile, "newAccount": true}`.
Store `token` and `code` in place of the old ones.

- A new Apple ID with a Bearer token links that user: `token` and `code` are the caller's own, so friends keep the same code.
- A new Apple ID without one (or whose caller is already linked to another Apple ID) gets a new user.
  A Bearer token that no longer resolves (its user was deleted) counts as no token.
- An Apple ID that already has an account returns its friend code with a new token for this Mac (`newAccount: false`).
  If the caller had an anonymous user, its friends (up to the friend limit) and study minutes move to the account and the anonymous user is deleted, so the app must switch to the returned token.
  A caller that already is the account gets its own token back.

The authorization code is exchanged for an Apple refresh token, which is kept only to revoke it on `DELETE /v1/me`.
That needs the Worker secrets `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY`; without them, or when Apple refuses the code, the exchange is skipped, logged, and sign-in still succeeds.
Sign-ins are limited to 10 per minute per IP.

Errors: `invalid_identity_token` (401, the token is malformed, expired, not Apple's or not for Tabbi; ask the user to sign in again), `apple_unavailable` (503, Apple's keys could not be fetched; the server asks Apple again at most once a minute, so retry after a minute), `invalid_json`, `unknown_field`, `invalid_field`, `rate_limited`.

### `POST /v1/auth/signout`

No body.
The caller's token stops working (`unauthorized` from then on); the account, its sync document and every other Mac's token stay.
`200 {"ok": true}`.
The app sends it when the user signs out, then drops the token and its friend code; signing in again on that Mac adopts the account with a new token.
Errors: `no_account` (403, an anonymous user would lose its only token), `unauthorized`, `rate_limited`.

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
| 404 | `unknown_code` | no user has that code, that user blocked me (a block is never revealed), or that user is banned |
| 403 | `banned` | the maintainer banned me |
| 409 | `blocked` | I blocked that user; unblock them first |
| 409 | `friend_limit` | I already have 50 friends |
| 409 | `their_friend_limit` | they already have 50 friends |

### `DELETE /v1/friends/{code}`

Removes the friendship in both directions.
`200 {"ok": true, "removed": true}`; `removed` is `false` if we were not friends.
Errors: `invalid_field` for a malformed code.

### `GET /v1/blocks`

```
{
  "ok": true,
  "blocks": [
    { "code": "K7QW2MZD", "name": "Ben", "petName": "Mochi", "since": 1789000000 }
  ]
}
```

The users I blocked, newest first, with their current display name and pet name.
A user who deletes their account drops out of the list.

### `POST /v1/blocks`

Body: `{"code": "K7QW2MZD"}`.
A block hides two users from each other, whoever blocked whom:

- the friendship ends in both directions, so neither sees the other in `GET /v1/friends` or `GET /v1/leaderboard`;
- neither can add the other (`POST /v1/friends` answers the blocked user `404 unknown_code` and the blocker `409 blocked`);
- neither can join a party the other hosts (`404 party_not_found`, as if it did not exist);
- in a party both are in, the blocked user is removed when I host, I leave when they host, and otherwise the two of us are left out of each other's `members`.

The blocked user is never told.
`200 {"ok": true, "blocked": true, "block": {"code": "K7QW2MZD", "name": "Ben", "petName": "Mochi"}}`; `blocked` is `false` if I had already blocked them (a no-op success).

Errors:

| HTTP | `error` | Meaning |
| --- | --- | --- |
| 400 | `invalid_field` | not a valid friend code |
| 400 | `self_block` | that is my own code |
| 404 | `unknown_code` | no user has that code |
| 409 | `block_limit` | I already blocked 1000 users |

### `DELETE /v1/blocks/{code}`

Lifts my block on that user; only the blocker can.
The friendship is not restored: either of us can add the other again.
`200 {"ok": true, "unblocked": true}`; `unblocked` is `false` if I had not blocked them.
Errors: `invalid_field` for a malformed code.

### `POST /v1/reports`

Body: `{"code": "K7QW2MZD", "reason": "harassment", "note": "optional, up to 280 characters"}`.
`reason` is one of `inappropriate_name`, `harassment`, `spam` and `other`.
Stores a report for the maintainer with the reported user's name and pet name as they are now, my friend code, the reason, the note and the time.
The reported user is never told.
A report does not hide anyone: the app offers to block as well.
`201 {"ok": true, "created": true}`.
Reporting the same user again while my first report is still open updates it instead (`200`, `created: false`).

Errors:

| HTTP | `error` | Meaning |
| --- | --- | --- |
| 400 | `invalid_field` | not a valid friend code, an unknown reason, or a note over 280 characters |
| 400 | `self_report` | that is my own code |
| 404 | `unknown_code` | no user has that code |
| 429 | `rate_limited` | more than 5 reports in a minute; wait for `Retry-After` seconds |
| 429 | `report_limit` | 20 reports in the last 24 hours |

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
Errors: `banned` (403).

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
| 404 | `party_not_found` | no active party has that code (it may have expired), or its host and I blocked each other |
| 403 | `not_friend` | that user is not my friend |
| 409 | `friend_offline` | that friend is not online |
| 404 | `friend_not_in_party` | that friend is not in a party |
| 409 | `party_full` | the party already has 8 members |
| 403 | `banned` | the maintainer banned me |

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

### `GET /v1/sync`

Only for users linked to a Sign in with Apple account; others get `403 no_account`.
`200 {"ok": true, "revision": 3, "updatedAt": 1791504000, "document": SyncDocument}` with `ETag: "3"`.
Before the first write it is `revision: 0`, `updatedAt: null` and `document: null`.

The document is the app's `SyncDocument` (`Sources/TabbiKitCore/Sync`): a JSON object with an integer `schemaVersion`, the pet's look, points per Mac, unlock ids, study days and the longest streak.
The server stores it as sent and never merges or reads its fields, so the app can extend the format without a server deploy.

### `PUT /v1/sync`

Header `If-Match: <revision>` (a bare number or the quoted `ETag`), the revision the app merged its local progress into (0 when `GET` had no document).
Body: `{"document": SyncDocument}`, at most 65536 bytes; `document` must be an object with a positive integer `schemaVersion`.
If the revision is current it replaces the document: `200 {"ok": true, "revision": 4, "updatedAt": 1791504060}` with `ETag: "4"`.
Otherwise nothing is written and the reply is `409 revision_conflict` with the current revision in `ETag`: pull with `GET`, merge (the merge never loses progress), and retry with the new revision.
Writes are limited to 20 per minute per user.

Errors: `no_account` (403), `revision_required` (428, no `If-Match`), `invalid_revision` (400), `revision_conflict` (409), `invalid_json`, `unknown_field`, `invalid_field`, `body_too_large`, `rate_limited`.

## Moderation (maintainer)

Reports wait on the server until the maintainer reads them; nothing happens to a reported user automatically.
The `/v1/admin/` routes take the Worker secret `ADMIN_TOKEN` as Bearer token.
Set it once with `npx wrangler secret put ADMIN_TOKEN` (a long random string, for example from `openssl rand -hex 32`); until it is set, every admin route answers `404 not_found`.
A wrong token gets `401 unauthorized`, and each client IP gets at most 30 admin requests a minute.

| Method and path | Purpose |
| --- | --- |
| `GET /v1/admin/reports` | open reports, newest first (at most 100); `?status=all` includes resolved ones |
| `POST /v1/admin/reports/{id}/dismiss` | close a report without acting on the user |
| `POST /v1/admin/users/{code}/rename` | replace the user's name and pet name with the placeholders `student` and `buddy` |
| `POST /v1/admin/users/{code}/ban` | ban the user |
| `DELETE /v1/admin/users/{code}/ban` | lift a ban |

To review, read the open reports:

```sh
export TABBI=https://tabbi-friends.drosophil-anki-friends-backend.workers.dev
export ADMIN_TOKEN=...   # the secret you set
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" $TABBI/v1/admin/reports | jq
```

Each report is:

```
{
  "id": 12, "createdAt": 1789000000, "reason": "inappropriate_name", "note": "...",
  "resolvedAt": null, "resolution": null,
  "reporter": { "code": "AB34CD56", "name": "Ana" },
  "reported": {
    "code": "K7QW2MZD", "name": "name when reported", "petName": "pet name when reported",
    "currentName": "Ben", "currentPetName": "Mochi", "banned": false, "openReports": 3
  }
}
```

`name` and `petName` are what the reporter saw; `currentName` and `currentPetName` are what the user is called now.
Deleting an account removes every report by or about that user.
Then act on the user, which closes every open report about them (`resolution` becomes `renamed` or `banned`), or dismiss a single report:

```sh
curl -s -X POST -H "Authorization: Bearer $ADMIN_TOKEN" $TABBI/v1/admin/users/K7QW2MZD/rename
curl -s -X POST -H "Authorization: Bearer $ADMIN_TOKEN" $TABBI/v1/admin/users/K7QW2MZD/ban
curl -s -X POST -H "Authorization: Bearer $ADMIN_TOKEN" $TABBI/v1/admin/reports/12/dismiss
```

- **Rename** for a bad name: the name and pet name become `student` and `buddy`, and the user cannot set the old ones again (`name_not_allowed`, `pet_name_not_allowed`).
  Replies `{"ok": true, "profile": Profile}`.
- **Ban** for harassment or repeated abuse: the user leaves their party and disappears from everyone else's friend lists, parties and leaderboards.
  They cannot change their name or pet name, add friends, or create or join a party (`403 banned`), and `GET /v1/me` says `"banned": true`.
  Their data stays, so a ban can be lifted with `DELETE /v1/admin/users/{code}/ban`, which brings their friendships back as they were.
  Replies `{"ok": true, "banned": true}` (`false` if already banned).
- Sign in with Apple carries a ban, a rename and reports over when an anonymous user folds into an account.

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
| `POST /v1/auth/apple` | once, when the user taps Sign in with Apple; never on a timer |
| `POST /v1/auth/signout` | once, when the user taps Sign Out |
| `GET /v1/me`, `PATCH /v1/me` | on launch and after the user edits their pet; not on a timer |
| `GET /v1/sync` | on launch and on wake, and after a `409`; not on a timer |
| `PUT /v1/sync` | after local progress changes, debounced (for example 30 s), and once on quit |

A heartbeat whose status, method, phase and streak are unchanged is cheap but still a request, so do not send heartbeats for counters alone between scheduled ones.
Countdowns (`phaseEndsAt`, party `session.phaseEndsAt`) run locally on the client.
On `429`, back off for `Retry-After`; on `503` or network errors, retry with exponential backoff (for example 5 s, 10 s, 20 s, capped at 5 minutes).
