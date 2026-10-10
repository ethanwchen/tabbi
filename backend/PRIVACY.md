# Privacy

The Tabbi friends service exists so you can see which friends are studying, study together in a party where everyone's pets sit side by side, and compare weekly study minutes.
It is designed to know as little as possible.
Party and Sign in with Apple are for people 13 and older.
Before Party sends anything, the app asks the user's birth month and year and keeps the answer on the Mac; the service never receives a birth date or an age.

## What is stored

Per user, identified only by a random secret token (stored as a SHA-256 hash) and a public 8-character friend code:

- the profile: a display name (up to 24 characters, any nickname works), the pet's name (up to 24 characters), species, breed, up to 6 colors, costume, up to 4 accessories, points and level, and when the friend code was created;
- presence from the last heartbeat: status (`studying`, `break`, `idle` or `offline`), the study method id (for example `pomodoro`), when the current phase ends, minutes in the current session, minutes studied today, the study streak in days, your local calendar day, and the time of the last heartbeat;
- study minutes per local calendar day, kept for 28 days (older days are deleted daily, whether or not you still use the service), for the weekly leaderboard;
- the friend codes you are friends with, and when each friendship started;
- the friend codes you blocked, and when;
- reports you send about another user: their friend code, their name and pet name at that moment, your friend code, the reason you picked, your optional note (up to 280 characters), the time, and, once the maintainer handles it, the outcome and when;
- if the maintainer acts on a report: whether you are banned, and every name and pet name they replaced, so they cannot be set again;
- the ids of limited edition pet items the maintainer gave you for free (for example the launch-week cap), and when;
- the party you are in, when you joined it, and, for the party itself, its 6-character code, its host, when it was created, its last activity time and the shared session the host started (study method, phase end and when it started).

Only if you choose to sign in with Apple, so your pet and progress follow you across your Macs:

- Apple's stable, app-specific user id, linked to your friend code, with the Apple client id it came from and when the link was made;
- an Apple refresh token, kept only so the service can revoke your Sign in with Apple grant when you delete your account (it is never used to read anything from Apple);
- one secret token per Mac you signed in on, and when it was made (stored as SHA-256 hashes; only about the 20 most recent sign-ins are kept, so a Mac you no longer use is dropped over time);
- a SHA-256 hash of each Apple sign-in token, kept until shortly after that token expires (Apple's expiry plus about a minute, erased by the hourly cleanup) so it cannot be used twice;
- when you sign in through the web page instead of the Mac's own sign-in, a pending sign-in (Apple's user id and refresh token, and hashes of a one-time code and of the app's random sign-in state) usable for two minutes; the app picks it up, or the hourly cleanup erases it within about an hour;
- your sync document and when it last changed: the pet's look (species, breed, name, outfit), points earned and spent per Mac (each Mac is a random id), the ids of unlocked items, the calendar days you studied (at most 400) and your longest streak.

Nothing else.
Card content, deck names, note text, email addresses, device names and IP addresses are never accepted or stored.
Party requests carrying unexpected fields are rejected.
The sync document is stored as the app sends it (a JSON object of at most 64 KB), and the app sends only the fields listed above.
The local calendar day you send (for example `2026-10-02`) can hint at your time zone; it is used only to count minutes toward the right day.
The service never stores your name or email from Apple: the app asks Apple only for your name, never your email, and the service reads nothing but Apple's user id from the identity token.
To check a sign-in and to revoke it on deletion, the Worker talks to Apple (`appleid.apple.com`); it sends Apple only the token or code the app received from Apple.
Cloudflare, which hosts the Worker, sees connection metadata like any web host.
The Worker uses the client IP only in memory to rate-limit registration, sign-ins, bad tokens, suggestions, crash reports and failed admin logins, and never writes it to storage.
For troubleshooting, the Worker keeps short log lines at Cloudflare for as long as the Cloudflare plan keeps them (3 days on Free, 7 on Paid): the kind of request (for example `POST /v1/friends/:id`, with every code and id removed), its status and duration, and the name of any internal error.
It logs every server error and every request slower than 2 seconds, and a random 1 in 100 of the rest, including failed requests such as a rejected token.
Logs never contain tokens, friend or party codes, names, request contents or IP addresses.

## Suggestions from the website

The website's Suggest form sends the service an idea: its category, the message and, only if you add one, an email address to reply to, with the time it arrived.
When you open the form from Tabbi, it also carries the Tabbi version, the macOS version and the edition, so a bug report says where it happened.
A suggestion is not linked to a friend code, an account or an IP address.
Only the maintainer reads it, uses the email only to ask about or reply to that idea, and deletes it when it is no longer needed, at the latest after 365 days (backup copies can remain up to 30 days longer).

## Crash reports

Tabbi sends a crash report only when you agree to it after a crash, or after you chose to always send them.
That choice can be changed at any time in Settings > About.
A report holds the Tabbi version, the macOS version, the edition, the type of crash, and the names and stack frames of the app's threads, with the time it arrived.
The app leaves out what you typed, names, tasks, tokens and file paths in your home folder.
The service cannot check all of that itself; it refuses a report whose stack frames still contain a home folder path (`/Users/` or `/home/`).
A report is not linked to a friend code, an account or an IP address.
Only the maintainer reads it, to fix the crash, and deletes it when it is no longer needed, at the latest after 90 days (backup copies can remain up to 30 days longer).

## Who can see it

- **Friends** (friendship is mutual and needs your friend code) see your profile, your presence (shown as `offline` once heartbeats stop), whether you are in a party with its code and size, and your weekly study minutes on the leaderboard.
- **Party members** see the profile and presence of everyone in the same party, including members who are not their friends.
  Anyone who has a party's code can join it while it has room, so share party codes only with people you want to study with.
- There is no directory or search: nobody can find you without your friend code or a shared party code.
- **Blocking** someone ends your friendship and hides the two of you from each other in friend lists, parties and the leaderboard.
  They cannot add you again or join a party you host, and they are not told that you blocked them.
  Only you see your blocked list, and you can unblock someone at any time.
- **Reports** are read only by the maintainer who runs the service, to decide whether to rename or ban someone.
  The person you report is not told who reported them, or that they were reported.
- **Banned** users keep their data but disappear from everyone else's friend lists, parties and leaderboards, and cannot change their name or join parties.

You always see your own complete profile and presence.
Your sync document and Apple account link are never shown to anyone, friends included.

## How to delete

Leaving a party (`POST /v1/party/leave`) removes your membership; a party is deleted when its last member leaves, or within an hour once it has had 12 hours without activity.
Removing a friend deletes the friendship in both directions.
Unblocking someone deletes the block.
A report stays until the account of the reporter or of the reported user is deleted.
Deleting your account calls `DELETE /v1/me`, which erases your profile, presence, daily study minutes, friend list, sync document, Apple account link, blocks (yours, and others' blocks of you), reports by you or about you, any ban or replaced name, and your limited edition items, removes you from your friends' lists, and takes you out of your party.
If you signed in with Apple, it then revokes the app's Sign in with Apple grant with Apple.
A pending web sign-in that was never picked up can still hold your Apple user id until the hourly cleanup erases it.
Your secret token, and the token of every other Mac you signed in on, stops working at once.
Signing out on one Mac (`POST /v1/auth/signout`) deletes that Mac's token on the server; your account and other Macs stay signed in.
Signing in with Apple on a Mac that already had a friend code of its own moves that code's friends (up to the friend limit, leaving out anyone either side blocked), blocks, reports, any ban or replaced name, limited edition items and study minutes to your account and deletes the old code.
If that Apple ID has no account yet, the existing code simply becomes the account.
Reports between that code and your account are deleted, since they would now be about yourself.

Deleted data leaves the live service at once.
Copies can remain in backups for up to 30 days: Cloudflare keeps a 30-day point-in-time history of the storage, and the operator keeps encrypted exports for at most 30 days, used only to recover from an outage or a mistake.
If the service is ever restored from a backup, the operator deletes again every account that was deleted after that backup, following the restore procedure in `docs/security.md`.

## Aggregate counts

The maintainer can see a few totals the service counts from the data above, so they know how many people use it: how many friend codes and Apple sign-ins exist, how many users sent a heartbeat in the last day, week and month, how many new friend codes were created on each of the last 30 days, how many parties and party members there are, how many users are banned, how many suggestions wait, and how many requests and rows the service handles.
These are counts only: they never name or identify anyone, and nothing is stored or sent for them.
The app sends nothing extra; Tabbi has no tracking, analytics or telemetry of any kind.
The number of installs comes from GitHub's public download count for each release, not from the app.

## No analytics, no third parties

The service uses no analytics, no tracking, no advertising and no third-party services.
It is a single Cloudflare Worker with Durable Object storage, operated by whoever deployed it.
The only other service it talks to is Apple's Sign in with Apple, and only for users who chose to sign in.
The Suggest form and opt-in crash reports reach the same Worker; nothing else in the app or the website talks to it.
