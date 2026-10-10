# Operating the Tabbi backend

How to watch the friends service (`backend/`, the `tabbi-friends` Cloudflare Worker) once it runs.
The API is in [`study/backend-api.md`](study/backend-api.md), and security, backups and secrets are in [`security.md`](security.md).

## Monitoring

Three things watch the service, all free:

- **An external uptime check** on `GET /v1/health` emails the maintainer when the service is down or failing.
- **Workers Logs** keep the Worker's structured log lines for a few days, so a failure can be looked up afterwards.
- **The dashboard's Metrics** show requests, errors, CPU time and Durable Object usage against the plan limits.

### Health check

`GET /v1/health` needs no token and goes all the way to the Hub, which reads its SQLite storage before it answers.

- `200 {"ok": true}`: the Worker, the Hub and its storage work.
- `503 {"ok": false, "error": "degraded"}`: at least 5 requests failed with a 500 (an unexpected exception) in the last 10 minutes.
  It turns back to 200 on its own once those failures are 10 minutes old.
- `503 {"ok": false, "error": "unavailable"}`: the Worker could not reach the Hub.
- Anything else (a timeout, a Cloudflare error page): the Worker itself is down.

So one plain HTTP monitor covers both uptime and error alerting: Cloudflare has no built-in alert for a Worker's error rate, and the health check turns a burst of errors into a failed check.
Each check costs one Worker request and one Durable Object request, so a 5-minute interval adds 288 of each per day.
The failure count lives in the Hub's memory and starts from zero when the Hub restarts.

### Set up the uptime check (UptimeRobot, free)

UptimeRobot's free plan checks every 5 minutes and emails on failure; it is free for personal, non-commercial and open-source projects.

1. Create an account at [uptimerobot.com](https://uptimerobot.com) and confirm the email address alerts should go to.
2. Choose **New monitor** and set:
   - Monitor type: **HTTP(s)**.
   - Friendly name: `Tabbi friends`.
   - URL: `https://<your worker host>/v1/health` (the same base URL the app uses, for example `https://tabbi-friends.<account>.workers.dev/v1/health`).
   - Monitoring interval: **5 minutes**.
3. Under alert contacts, tick your email.
   UptimeRobot counts any status other than 2xx or 3xx as down, so the `503 degraded` reply alerts like an outage.
4. Save, then check that the monitor turns green within a few minutes.
5. Optional: add a second monitor for `https://<staging host>/v1/health` to watch staging too, and, under **Integrations**, add a phone app or Slack channel.

To test the alert, point the monitor at a path that does not answer 200 (for example `/v1/health-test`, which answers 401) for one interval, and change it back once the email arrives.

Any other HTTP monitor (Better Stack, Cronitor, a self-hosted Uptime Kuma) works the same way: alert when `GET /v1/health` does not return 200.

### Logs

The Worker writes one JSON object per log line (`src/log.ts`), which Workers Logs indexes field by field:

| `event` | `level` | When | Fields besides `level` and `event` |
| --- | --- | --- | --- |
| `request` | `error` | every response with status 500 or higher | `method`, `route`, `status`, `ms`, `sampled: false` |
| `request` | `warn` | every request that took 2 seconds or more | same |
| `request` | `info` | a random 1% of all other requests, client errors included | same, with `sampled: true` |
| `hub_exception` | `error` | an unexpected exception inside the Hub (the request got a 500) | `route`, `errorName`, `errorMessage` (first line, at most 200 characters) |
| `hub_unreachable` | `error` | the Worker could not reach the Hub (503 `unavailable`) | `errorName`, `errorMessage` |
| `apple_*` | `error` or `warn` | Apple's keys, code exchange or revoke failed, or the Apple secrets are unset | Apple's HTTP status and error code |
| `admin_restore` | `warn` | the maintainer started a storage restore | the target time, or `bookmark: true` |

`route` is the path with every id replaced, for example `/v1/friends/:id` or `/v1/admin/users/:id/ban`, and every path outside `/v1/` is `other`.
`ms` is the wall time from the Worker receiving the request to the Hub's reply.

What is never logged: tokens, friend codes, party codes, names, request or response bodies, IP addresses and full URLs.
Cloudflare's own invocation logs are turned off in `wrangler.toml` (`invocation_logs = false`), because they record each request's full URL and headers.
Uncaught exceptions that escape the code still show in `wrangler tail` and the dashboard's error counts, but the code catches everything it can and logs it as above.

Useful queries in the dashboard (Workers and Pages, `tabbi-friends`, Observability, Events):

- Every error: filter `level` equals `error`.
- Which routes fail: filter `event` equals `request` and `status` at least 500, group by `route`.
- Latency per route: filter `event` equals `request` and `sampled` equals `true`, show the P95 of `ms` grouped by `route` (multiply counts by 100 for an estimate of the real traffic).
- Rate limiting at work: filter `status` equals `429`, group by `route`.

`npx wrangler tail --format pretty` streams the same lines live; `--status error` shows failed requests only.
Tail output includes full request URLs and headers, so treat it as sensitive and do not share or save it.

Volume and cost: at the 1% sample, about one line per hundred requests is kept, plus every error.
The Workers Free plan keeps 200,000 log events per day for 3 days, enough for about 20 million requests a day; the Paid plan includes 20 million events a month for 7 days, then $0.60 per million.
From December 1, 2026 Cloudflare moves logs to [Observability pricing](https://developers.cloudflare.com/observability/pricing/): 0.5 GB per day free, and 50 GB per month on the Paid plan, both kept for 7 days.
A request line is about 150 bytes, so either plan covers the service many times over.

### Metrics

The dashboard (Workers and Pages, `tabbi-friends`, Metrics) shows every request, unsampled: requests, errors, CPU time and wall time, and, under Durable Objects, requests, duration and SQLite rows read and written.
Check them after a release and once a week against the plan limits in [`backend/README.md`](../backend/README.md#free-tier-math): on the Free plan, calls fail once the day's requests or row writes run out, until 00:00 UTC.

## Product metrics

Tabbi has no telemetry: the app sends nothing for metrics.
The maintainer still gets counts from two places that already exist:

- **Installs:** GitHub counts every download of a release asset.
  A DMG download (`Tabbi-<version>.dmg` or the `Tabbi.dmg` the website links to) is an install; a zip download is Sparkle fetching an update.
- **Party users:** `GET /v1/admin/stats` counts rows the service keeps anyway: friend codes, Apple sign-ins, users with a heartbeat in the last day, week and month, new friend codes per UTC day for 30 days, open parties and waiting suggestions.
  It returns totals only (see [Stats](study/backend-api.md#stats-maintainer)).

`npm run stats` in `backend/` prints both:

```sh
cd backend
TABBI_ADMIN_TOKEN=<the ADMIN_TOKEN secret> npm run stats            # readable summary
TABBI_ADMIN_TOKEN=<the ADMIN_TOKEN secret> npm run stats -- --json  # the same as JSON
```

Without `TABBI_ADMIN_TOKEN` it shows only the GitHub numbers.
`TABBI_BACKEND_URL` points it at another deployment (for example staging), `GITHUB_REPO` at another repository, and `GITHUB_TOKEN` (any token, no scopes needed) lifts GitHub's limit of 60 unauthenticated requests an hour.

What the numbers mean:

- Active users are Party users: the app sends heartbeats only while the Party tab is on, so someone who runs Tabbi without Party is counted as an install but never as active.
- A user is active in a window when their last heartbeat falls inside it, so the weekly count is the number of distinct users seen in the last 7 days, not a sum of daily counts.
- Sign-ups count friend codes, which the app creates when the Party tab first connects.
  Deleting an account removes it from every count, including its sign-up day.
- Each stats call reads about two SQLite rows per user, so a weekly look costs nothing noticeable; do not poll it from a dashboard.
- The reply's `hub` part (requests and SQLite rows read and written since the Hub last started) is for capacity checks; see [Scale](#scale).

## Scale

The whole service is one Worker in front of one SQLite-backed Durable Object, the Hub.
This section is the measured answer to "how many users can that serve, and what does it cost", and says when to change the design.

### How the Hub spends requests and rows

Every `/v1/*` call is one Worker request plus one Durable Object request.
Presence lives in the Hub's memory: a heartbeat updates it there and writes SQLite only when friends would see a change (status, study method, phase end, streak), on a new day, or when the last write is 10 minutes old.

Measured with the load test below (a user with 6 friends, some of them in parties of 4):

| Request | SQLite rows read | Rows written |
| --- | --- | --- |
| Steady heartbeat (no visible change) | 4 (finding the caller by token) | 0 |
| Heartbeat that changes status or phase, or flushes after 10 minutes | 4 | 1, plus 1 study-day row when the minutes changed |
| Mixed peak-hour traffic (heartbeats, friend lists, party polls, leaderboard) | about 12.5 on average | close to 0 within a 10-minute window |

A friend list grows with friends (about 3 rows per friend), and a party poll with members; see the per-route maximums in [`backend/README.md`](../backend/README.md#presence-adaptive-heartbeats-write-on-change).

### Load test

`scripts/loadtest.ts` simulates a population of users against `wrangler dev`.
It registers every user from a fake client IP of its own, links each one to 6 friends, puts every tenth user in a party of four and sends every user's first heartbeat.
Then each stage sends the request mix of the busiest hour at a multiple of its rate, open loop (requests leave on schedule even when earlier ones are still waiting), and reads `GET /v1/admin/stats` before and after to get rows per request.

The busiest-hour model (`PEAK_MODEL` in the script): 35% of all registered users online at once, half of them in a session (a heartbeat every 120 s) and half idle (every 300 s), the Party panel open for 10% of them (friend list every 60 s, party every 30 s for those in a party), and one leaderboard load per online user per hour.
That is about 2.8 requests per second per 1,000 registered users.

```sh
cd backend
npx wrangler dev --port 8787 --persist-to /tmp/tabbi-load --var ADMIN_TOKEN:$(openssl rand -hex 32 | tee /tmp/tabbi-load-token)
# in a second terminal:
TABBI_ADMIN_TOKEN=$(cat /tmp/tabbi-load-token) npm run loadtest -- --users 50000 --stages 1,2,4,6
```

Options: `--users`, `--friends` (3 adds each, so 6 friends), `--duration` (seconds per stage, 30), `--stages` (multiples of the peak rate, `1,2,4,8`), `--url` and `--json`.
The script refuses the production URL.
Use a fresh `--persist-to` folder per run, and delete it afterwards.

Results on 2026-10-09 (Apple M-series laptop, wrangler 4.146, one Hub, 30 s per stage):

| Users | Stage | Requests per second | p50 | p95 | p99 | Failed |
| --- | --- | --- | --- | --- | --- | --- |
| 10,000 | peak x1 | 28 | 3.5 ms | 4.3 ms | 22 ms | 0 |
| 10,000 | peak x4 | 113 | 2.9 ms | 3.9 ms | 14 ms | 0 |
| 10,000 | peak x16 | 453 | 2.9 ms | 74 ms | 179 ms | 0 |
| 10,000 | peak x32 | 841 of 907 sent | 779 ms | 2.8 s | 8.2 s | 0.6% |
| 50,000 | peak x1 | 142 | 4.9 ms | 16 ms | 52 ms | 0 |
| 50,000 | peak x2 | 284 | 4.5 ms | 23 ms | 88 ms | 0 |
| 50,000 | peak x4 | 568 | 8.1 ms | 123 ms | 287 ms | 0 |
| 50,000 | peak x6 | 747 of 852 sent | 2.1 s | 3.2 s | 9.0 s | 0.01% |

Setup ran at about 700 to 900 requests per second (registrations and friend adds, which write).
The failures in the overloaded stages were the local dev proxy dropping connections; the Hub itself logged no exception.

What the numbers say:

- One Hub serves about 500 to 600 mixed requests per second before latency climbs, in line with Cloudflare's guidance of roughly 1,000 simple requests per second per object.
- 50,000 registered users need about 142 requests per second in the busiest hour, a quarter of that, with a p99 of about 50 ms.
- The Hub's in-memory state is about 0.6 KB per recently active user (live presence and a rate-limit window), so about 30 MB at 50,000 users, well inside an object's 128 MB.
  The hourly alarm writes and then drops the live presence of users who have sent no heartbeat for an hour, and ended rate-limit windows are dropped at most once a minute, so memory follows the users active in the last hour rather than everyone seen since the last restart.
- Row reads and writes are nowhere near a limit; at this scale requests are what cost money (below).

### Decision: one Hub until the busiest hour passes 300 requests per second

A single object keeps friends, presence, parties and the leaderboard strongly consistent with plain SQL joins, and needs no cross-object protocol.
Sharding would buy throughput the service does not need at 50,000 users, at the cost of a fan-out on every friend list and leaderboard (friends live on different shards) and a data migration.
So the design stays as it is, with a clear trigger to revisit it:

- Watch the Durable Object request rate on the dashboard (Workers and Pages, `tabbi-friends`, Metrics, Durable Objects) after each release.
- When the busiest hour passes about 300 requests per second (roughly 100,000 registered users with this model, half of the measured capacity), start the split: parties into one object each, and presence and friends sharded by friend code, with the Hub copying its rows into the shards before it routes to them.
- Re-run the load test with the real numbers of friends and party sizes from `GET /v1/admin/stats` before deciding.

### Costs

Pricing as of 2026-10 ([Workers](https://developers.cloudflare.com/workers/platform/pricing/), [Durable Objects](https://developers.cloudflare.com/durable-objects/platform/pricing/)).
The Workers Paid plan is $5 a month and includes 10 million Worker requests (then $0.30 per million), 30 million CPU ms (then $0.02 per million ms), 1 million Durable Object requests (then $0.15 per million), 400,000 GB-s of Durable Object duration (then $12.50 per million GB-s), 25 billion SQLite rows read (then $0.001 per million), 50 million rows written (then $1.00 per million) and 5 GB stored.

Per daily active user and day, assuming a typical user (3 hours online, half of it in a session, a few panel openings) and the heavy user from [`backend/README.md`](../backend/README.md#presence-adaptive-heartbeats-write-on-change):

| Per user per day | Typical | Heavy |
| --- | --- | --- |
| Requests (Worker and Durable Object each) | about 90 | about 330 |
| SQLite rows written | about 40 | about 120 |
| SQLite rows read | about 1,100 | about 11,000 |

One always-warm Hub costs 86,400 s x 0.128 GB = 11,059 GB-s a day, about 332,000 a month, inside the included 400,000.
Worker CPU per request is about 1 ms (the Worker only forwards to the Hub).

| Daily active users | Typical users per month | Heavy users per month |
| --- | --- | --- |
| up to about 1,100 | Free plan (100,000 requests a day) | Free plan up to about 300 |
| 10,000 | about $14 ($5 plan, $5.10 Worker requests, $3.90 DO requests) | about $48 |
| 50,000 | about $75 ($5 plan, $37.50 Worker requests, $20.10 DO requests, $10 rows written, $2.10 CPU) | about $365 |

Rows read stay inside the included 25 billion: about 1.7 billion a month at 50,000 typical users, and 16.5 billion at 50,000 heavy users who all have 50 friends (the worst case in the README).
Stored data is a few hundred bytes per user plus 28 days of study minutes, far under 5 GB.
Requests dominate, so the client's polling intervals (`heartbeatSeconds` in the catalog and the Party panel's refresh plan) are the main cost lever.
