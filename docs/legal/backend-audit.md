# Friends service audit: code against policy

RESEARCH NOTES - NOT LEGAL ADVICE - REVIEW WITH A LICENSED ATTORNEY BEFORE ACTING

This compares `backend/src` with `backend/PRIVACY.md` and the site Privacy Policy (`site/_legal.py`), following the policy-monitor workflow.
REQUIRED means a policy sentence is false as written today.
ADVISABLE means the policy is silent or loose.

## What checks out

- Tokens are stored only as SHA-256 hashes.
- No IP address is written to storage or logs. `CF-Connecting-IP` (IPv6 cut to /64) is only a key in the in-memory rate-limit map (`lib.ts` `clientKey`). No User-Agent or `request.cf` data is read.
- An hourly alarm (`hub.ts` `sweepRetention`) enforces the 12-hour party, 28-day study minutes, 365-day suggestion and 90-day crash report limits.
- `DELETE /v1/me` removes everything the policy lists, in one transaction, then revokes the Apple grant.
- Invocation logs are off (`wrangler.toml`), and Apple (`appleid.apple.com`) is the only outside host the Worker fetches.

## REQUIRED

1. **Logging of failed requests.** The policy says every failed request is logged. The code always logs only 5xx errors and requests slower than 2 seconds; 4xx responses fall into the 1 in 100 sample (`log.ts`).
2. **Pending web sign-in "at most two minutes".** The row expires after two minutes but is deleted only when the app collects it or by the hourly sweep, so an abandoned sign-in keeps Apple's user id and refresh token for up to about an hour, and that refresh token is never revoked (`hub.ts`). Fix in code: delete expired rows on read and revoke abandoned refresh tokens, or reword.
3. **Crash reports "the service refuses a report that does".** The only content check is a case-sensitive `/Users/` or `/home/` match on frames, not thread names (`crashes.ts`). The server cannot detect typed text, names or tokens. Reword to what the app leaves out and what the server checks, and widen the server check.
4. **Re-deleting after a restore "right away".** This is a manual procedure (`docs/security.md`), and no record of deleted accounts survives a restore from an offsite export. Reword as a commitment to the procedure, or keep a deletion ledger.
5. **"Requests carrying unexpected fields are rejected".** The sync document is any JSON object up to 64 KB stored as sent (`sync.ts`), and the Apple web callback ignores unknown fields on purpose (`webauth.ts`). Narrow the sentence to the friends-service endpoints.
6. **"Only the 20 most recent" Mac tokens.** Up to 21 tokens work: 19 kept rows plus the new one in `device_tokens`, and the first Mac's token in `users.token_hash` (`hub.ts`, `lib.ts`).
7. **Short version: "Only the optional Party tab and the optional Sign in with Apple talk to a Tabbi server".** Opt-in crash reports and the website's Suggest form (which can hold an email address) go to the same Worker.
8. **IP use "only to rate-limit registration, sign-ins and bad tokens".** It also rate-limits suggestions, crash reports and admin authentication failures.

## ADVISABLE

- The account merge also moves name holds and granted items, caps friends at the friend limit, and drops friends involved in a block; for a new Apple ID the existing code simply becomes the account.
- The aggregate counts also include banned users, party members, and request and row counters.
- Unlisted stored fields: when a friendship, party, party session, Apple link and Mac token were created, the Apple client id, and a report's resolution and resolution time.
- Log retention "up to 7 days" is Cloudflare's plan maximum (Free 3 days, Paid 7 days), not a setting in the repo.
- Identity token hashes live until Apple's expiry plus 60 seconds, plus up to an hour before the sweep, not a flat "about ten minutes".
- Backups (30-day point-in-time history and operator exports) can keep suggestions and crash reports about 30 days past their limits; say so next to those limits.
- `DELETE /v1/me` leaves pending web sign-in rows holding the user's Apple id until they expire.

## Status

The site Privacy Policy rewrite (`site/_legal.py`, 9 October 2026) rewords REQUIRED items 1 and 3 to 8 to match the code: log sampling, what the crash check does, re-deleting after a restore as a commitment, unexpected fields limited to the Party endpoints, "about the 20 most recent" Mac tokens, crash reports and suggestions named as server traffic, and every use of the IP address in memory.
Item 2 is reworded to "usable for two minutes, then erased within about an hour"; the code fix (delete expired rows on read, revoke abandoned refresh tokens) is still advisable.
From ADVISABLE, the policy now lists the extra stored timestamps, the report resolution, request counts in the totals, the merge moving items, and backup copies of suggestions and crash reports.
`backend/PRIVACY.md` still needs the same corrections.
