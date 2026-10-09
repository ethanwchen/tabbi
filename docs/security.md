# Security and operations

How the Tabbi friends backend (`backend/`, the `tabbi-friends` Cloudflare Worker) protects its users, and how to run it: backups, secrets, rollbacks, monitoring and staging.
The client contract is [`study/backend-api.md`](study/backend-api.md), what is stored is [`../backend/PRIVACY.md`](../backend/PRIVACY.md), and deployment is in [`../backend/README.md`](../backend/README.md).

## Threat model

The service holds nicknames, pet looks, study presence, friend lists and, for users who sign in with Apple, an Apple user id, a refresh token and a sync document.
It holds no email addresses, passwords or IP addresses.
What it defends against:

- **Account takeover.** A user is a random 256-bit token; only its SHA-256 hash is stored, so a leaked database cannot be replayed as tokens.
  Guessing is refused per client (60 failed authentications per minute per IPv4 address or IPv6 /64), and the check comes before any lookup.
- **Forged Apple sign-ins.** Identity tokens are verified against Apple's published keys (RS256 only), with issuer, audience (the app's bundle id) and expiry checked.
  Each identity token signs in once: the Hub keeps its SHA-256 hash until it expires, so a copied token (from a proxy, a crash log or a retried request) cannot open a second session.
  The app does not bind tokens to a nonce, since the token goes straight from AuthenticationServices to the Worker over TLS; a token stolen before the app uses it is the remaining gap, and it lasts at most the token's ten minutes.
- **Abuse and cost.** Bodies are capped (4096 bytes, 65536 for sync) while streaming, unknown fields are rejected, every text field is length-limited and stripped of control characters, and registrations, sign-ins and requests per token are rate-limited in the Hub's memory.
  Requests are the binding free-plan limit, so rate limits also protect everyone else's quota.
  An account keeps at most 20 Mac tokens besides the first Mac's, oldest out first, so signing in over and over cannot grow storage.
- **Data exposure.** There is no directory or search: a profile is visible only to mutual friends and party members, and sync documents only to their owner.
  Error replies carry a stable code and a short English message, never stack traces or internal values.
- **Abuse by other users.** Users can block each other and report a name or behaviour; reports are capped (5 a minute, 20 a day per user) and wait for the maintainer, who can rename or ban through the admin routes.
  A user who blocked you, or a banned user, answers every friend, block and report request with the same `404 unknown_code` as a code no one has, so no route reveals a block or a ban.
  A banned user disappears from friend lists, parties and leaderboards, and a ban follows the user through Sign in with Apple.
- **Data kept too long.** An hourly Durable Object alarm deletes what is past its retention even when nobody touches it again: parties idle for 12 hours, study minutes older than 28 days (checked once a day) and spent Apple identity token hashes.
- **Operator mistakes.** Schema changes are append-only versioned steps, deploys can be rolled back, and storage can be restored to any point in the last 30 days.

The Worker logs only what an operator needs: unexpected errors, Apple key and token exchange failures (status codes and Apple's error code), and admin restores.
It never logs tokens, names, request bodies or IP addresses.

The Tabbi app talks to the service only through `PartyClient` and `SyncClient` in `Sources/TabbiKitCore`, keeps its tokens in the Keychain (`PartyCredentialStore`), and never logs them.
It allows plain `http://` only for `localhost`, so a token never crosses the network unencrypted, and URLSession drops the `Authorization` header when a reply redirects.

## Secrets

| Secret | What it is for | Without it |
| --- | --- | --- |
| `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` | exchanging Sign in with Apple codes and revoking the grant on Delete Account | sign-in still works; the Worker logs that it skipped the exchange and the revoke |
| `ADMIN_TOKEN` | the operator endpoints under `/v1/admin/`: reports, rename, ban, export and restore | they do not exist (404) |

Secrets live only in Cloudflare (`wrangler secret put`), never in the repository or `wrangler.toml`.
Staging has its own set: add `--env staging` to every command below.

### Rotating secrets

Each `wrangler secret put` deploys a new version of the Worker at once, so no separate deploy is needed.

- `ADMIN_TOKEN`: generate a new one and replace it; the old one stops working with the new version.
  It must be at least 32 characters, or the admin endpoints stay off.

  ```sh
  openssl rand -hex 32 | npx wrangler secret put ADMIN_TOKEN
  ```

- Sign in with Apple key: create a new key in the Apple Developer account (Certificates, Identifiers and Profiles, Keys, with Sign in with Apple enabled), then upload its id and file together so the Worker never runs with a mismatched pair.
  Revoke the old key in Apple's portal only after the new version is live.

  ```sh
  # apple.json: {"APPLE_KEY_ID": "NEWKEYID01", "APPLE_PRIVATE_KEY": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"}
  npx wrangler secret bulk apple.json
  rm apple.json
  ```

- User tokens: there is nothing to rotate globally.
  A user who thinks a Mac's token leaked signs out on that Mac (the server deletes the token) or deletes the account.

## Backups and restore

Two layers, both without extra Cloudflare products:

1. **Point-in-time recovery.** SQLite-backed Durable Objects keep a 30-day history of their storage.
   `POST /v1/admin/restore` with `{"at": <unix seconds>}` brings the Hub back to that moment: the reply carries an `undoBookmark`, and the Hub restarts right after replying with the old state.
   To undo a restore, send `{"bookmark": "<undoBookmark>"}` to the same endpoint.
   Writes after the chosen moment are lost, so restore to just before the incident.

   ```sh
   curl -X POST https://tabbi-friends.<subdomain>.workers.dev/v1/admin/restore \
     -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
     -d "{\"at\": $(date -v-2H +%s)}"
   ```

2. **Offsite exports.** `GET /v1/admin/export` returns every table as JSON with the schema version.
   Run it on a schedule from a machine you control (for example a daily `cron` job) to keep a copy that survives losing the Cloudflare account.

   ```sh
   curl -sf https://tabbi-friends.<subdomain>.workers.dev/v1/admin/export \
     -H "Authorization: Bearer $ADMIN_TOKEN" | gzip > "tabbi-friends-$(date +%F).json.gz"
   ```

   An export contains token hashes, Apple user ids and refresh tokens, and sync documents, so store it encrypted, keep at most 30 days of them (as `PRIVACY.md` promises), and delete older ones.
   Presence that is only in the Hub's memory (at most 10 minutes of minute counters) is not in an export.
   To rebuild from an export, load its rows into the tables of a fresh deployment (for example with a one-off script against a staging Worker first); point-in-time recovery is the fast path for anything within 30 days.

Local `wrangler dev` and the tests have no point-in-time recovery; there a restore answers 501 `restore_unavailable`.

## Rolling back a deploy

Every deploy and every secret change is a Worker version.

```sh
npx wrangler deployments list      # recent deployments with their version ids
npx wrangler rollback              # back to the previous version
npx wrangler rollback <version-id> # or to a specific one
```

A rollback changes code only, not storage.
Schema steps (`MIGRATIONS` in `src/hub.ts`) only add tables and columns, so older code keeps working on a newer database.
If a bad deploy damaged data, roll back the code first, then restore storage to just before the deploy.

## Monitoring

- `npx wrangler tail` streams live requests, logs and exceptions (`--status error` for failures only, `--env staging` for staging).
  Tail output includes request URLs and headers, so treat it as sensitive and do not share or save it.
- The Cloudflare dashboard (Workers and Pages, `tabbi-friends`, Metrics) shows requests, errors, CPU time and Durable Object usage against the free-plan limits.
  Watch requests per day (100,000) and Durable Object rows written (100,000): past them, calls fail until 00:00 UTC.
- Cloudflare Notifications can email when the Worker's error rate rises or usage nears a limit.

Workers Logs (persisted logs) are off: turning them on keeps Worker logs at Cloudflare, which `PRIVACY.md` would then have to say.

## Staging

`wrangler.toml` defines a `staging` environment: a separate Worker, `tabbi-friends-staging`, with its own Durable Object, storage and secrets.

```sh
cd backend
npm run deploy:staging                              # https://tabbi-friends-staging.<subdomain>.workers.dev
npx wrangler secret put ADMIN_TOKEN --env staging   # and the Apple secrets, if sign-in is to be tested
PARTY_TEST_SERVER=https://tabbi-friends-staging.<subdomain>.workers.dev swift test --filter PartyLiveServerTests
npm run deploy                                      # production, once staging looks right
```

Point a development build of Tabbi at staging in Settings, Party server, to try a change end to end.
Staging data is test data: never copy production exports into it.
