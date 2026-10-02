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

The per-user request and row-write budget (heartbeat interval, write-on-change) is added with the presence routes.

## Attribution

The token and friend-code scheme, strict body validation, rate limiting and `DELETE /v1/me` are adapted from the anki-fly friends backend by the same author (MIT licensed).
