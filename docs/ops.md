# Operating the Tabbi backend

How to watch the friends service (`backend/`, the `tabbi-friends` Cloudflare Worker) once it runs.
The API is in [`study/backend-api.md`](study/backend-api.md), and security, backups and secrets are in [`security.md`](security.md).

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
