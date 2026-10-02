# StudyNotch friends backend

A small Cloudflare Worker for StudyNotch: friends by code, "who is studying right now" presence, study parties where everyone's pets sit side by side in the notch, and a weekly study-minutes leaderboard.
No accounts, no emails, no passwords: a user is a random secret token the app receives on registration, and the public 8-character **friend code** is what people share.
See [`PRIVACY.md`](PRIVACY.md) for what is stored and [`../docs/studynotch/backend-api.md`](../docs/studynotch/backend-api.md) for the client contract.

The pet catalog (species, breeds, costumes, accessories, study methods, limits) lives in [`shared/catalog.json`](shared/catalog.json).
The server validates against it, the app can bundle the same file, and `GET /v1/catalog` serves it.

## Develop / test

Requires Node 20+.

```sh
cd backend
npm install
npm test          # vitest inside workerd via @cloudflare/vitest-pool-workers
npm run typecheck
npm run dev       # local server on http://localhost:8787 with local Durable Object storage
```

## Deploy

Use your own Cloudflare account; the free plan is enough.

```sh
cd backend
npm install
npx wrangler login
npx wrangler deploy
```

There is no storage to create by hand: the Durable Object class and its SQLite storage are declared in `wrangler.toml` (`[[migrations]] new_sqlite_classes = ["Hub"]`) and created by the first deploy.
Wrangler prints the base URL, `https://studynotch-friends.<your-subdomain>.workers.dev`.
`GET /` answers `{"ok":true,"service":"studynotch-friends","version":1}` so you can check it is up.

## Architecture

```
app ──HTTPS──> Worker (studynotch-friends) ──> Durable Object "Hub" (one instance, SQLite)
```

- The Worker answers CORS preflights, `GET /` and `GET /v1/catalog` itself, so those cost no Durable Object request.
- Every other `/v1/*` call is forwarded to a single SQLite-backed Durable Object, `Hub`, which owns all state.
  One object gives strongly consistent, transactional updates: symmetric friendships, the friend cap and party capacity cannot race.
- Tokens are stored only as SHA-256 hashes.
- Friendships are symmetric and stored as two rows (`a -> b` and `b -> a`) keyed by `(a, b)`.
  Listing my friends is one primary-key range scan, and adding a friend costs 2 row writes.
- Presence lives in Hub memory and is flushed to a `presence` row only when it matters (see below).
  A restart loses at most 10 minutes of minute counters and `lastSeen`, and the next heartbeat restores them.
- Parties are a `parties` row (host, last activity, optional shared session) plus one `party_members` row per member, keyed by user so a user is in at most one party.
  Creating or joining a party leaves the previous one; a leaving host hands over to the longest-standing member, and the last member leaving deletes the party.
  A party expires 12 h after its last activity (create, join, leave, session change, or a member's poll); expired parties are deleted when touched and swept when a new party is created.
- Rate limits (60 requests per minute per token, 10 registrations per minute per IP) are counted in the Hub's memory.
  With a single instance they are exact while it is alive, and they cost no storage writes.

## Free-tier math

Limits of the Workers Free plan as of 2026-10 ([Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/), [KV limits](https://developers.cloudflare.com/kv/platform/limits/)):

| Resource | Free plan per day |
| --- | --- |
| Worker requests | 100,000 |
| Durable Object requests | 100,000 |
| Durable Object duration | 13,000 GB-s |
| SQLite rows read | 5,000,000 |
| SQLite rows written | 100,000 |
| SQLite stored data | 5 GB total |
| KV writes (for comparison) | 1,000 |

Limits reset at 00:00 UTC; past a limit, further operations of that type fail until the reset.

### Why a Durable Object and not KV

KV allows only 1,000 writes per day on the free plan.
A presence heartbeat is a write, so even one heartbeat per minute for a single 3-hour study session (180 writes) would let only about 5 users study per day.
SQLite-backed Durable Objects are available on the free plan with 100,000 row writes per day, 100 times more, and they are strongly consistent.

### Why exactly one Durable Object

Duration is billed per object while it is in memory, at 128 MB.
One object that stays warm all day costs 86,400 s x 0.128 GB = 11,059 GB-s, under the 13,000 GB-s allowance.
Two always-warm objects would need 22,118 GB-s and exceed it, so per-user or per-party objects are ruled out on the free plan.
A single object handles hundreds of requests per second, far above the roughly 1.2 requests per second that 100,000 requests per day average out to, so throughput is not the bottleneck.

### Presence: adaptive heartbeats, write on change

The app sends `POST /v1/presence` every 120 s while studying or on a break, every 300 s while idle, and once with `offline` when it quits (intervals come from `heartbeatSeconds` in the catalog, and every reply repeats the recommended interval).
A friend counts as online until 2.5 intervals pass without a heartbeat.
Countdowns do not need fast heartbeats: the client sends `phaseEndsAt` and friends count down locally.

The Hub keeps the live presence in memory and writes the SQLite row (1 row write) only when friends would see a change (status, study method, phase end or streak) or when the last write is 10 minutes old.
Ticking minute counters alone never force a write.

Budget for a heavy user who studies 4 hours in 25+5 minute pomodoros and has the app idle for another 4 hours:

| Per user per day | Requests | Row writes |
| --- | --- | --- |
| Heartbeats while studying (4 h / 120 s) | 120 | 16 phase changes + 24 periodic flushes = 40 |
| Heartbeats while idle (4 h / 300 s) | 48 | 24 periodic flushes |
| Friend list polls (every 60 s while the panel is open, about 30 min) | 30 | 0 |
| Party polls (every 30 s while in a party, about 1 h) | 120 | 6 activity bumps |
| Start, quit, profile edits | about 5 | about 5 |
| Joining and leaving a party | 2 | about 4 |
| **Total** | **about 320** | **about 80** |

So 100,000 requests per day cover about 300 heavy users, and 100,000 row writes cover about 1,250.
Requests are the binding limit; typical users study less than 4 hours and spend less time in a party, so the free plan serves several hundred daily users.
A party poll does not write: `lastActive` is persisted at most once per 10 minutes per party, which is precise enough for a 12-hour expiry.
Rows read stay well under 5M: a friend list poll reads at most about 150 rows (50 friendships, 50 profiles, 50 presence rows), so even 500 users who all have 50 friends and poll 30 times a day read 2.25M rows.
A party poll reads at most about 30 rows (the party, 8 members, 8 profiles, 8 presence rows), so 300 users polling 120 times a day read about 1.1M rows.

## Attribution

The token and friend-code scheme, strict body validation, rate limiting and `DELETE /v1/me` are adapted from the anki-fly friends backend by the same author (MIT licensed).
