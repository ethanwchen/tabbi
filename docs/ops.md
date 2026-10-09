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
