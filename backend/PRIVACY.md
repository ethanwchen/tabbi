# Privacy

The StudyNotch friends service exists so you can see which friends are studying, study together in a party where everyone's pets sit side by side, and compare weekly study minutes.
It is designed to know as little as possible.

## What is stored

Per user, identified only by a random secret token (stored as a SHA-256 hash) and a public 8-character friend code:

- the profile: a display name (up to 24 characters, any nickname works), the pet's name (up to 24 characters), species, breed, up to 6 colors, costume, up to 4 accessories, points and level, and when the friend code was created;
- presence from the last heartbeat: status (`studying`, `break`, `idle` or `offline`), the study method id (for example `pomodoro`), when the current phase ends, minutes in the current session, minutes studied today, the study streak in days, your local calendar day, and the time of the last heartbeat;
- study minutes per local calendar day, kept for 28 days, for the weekly leaderboard;
- the friend codes you are friends with;
- the party you are in, when you joined it, and, for the party itself, its 6-character code, its host, its last activity time and the shared session the host started (study method and phase end).

Nothing else.
Card content, deck names, note text, email addresses, device names and IP addresses are never accepted or stored.
Requests carrying unexpected fields are rejected.
The local calendar day you send (for example `2026-10-02`) can hint at your time zone; it is used only to count minutes toward the right day.
Cloudflare, which hosts the Worker, sees connection metadata like any web host.
The Worker uses the client IP only in memory to rate-limit registration and bad tokens, and never writes it to storage.

## Who can see it

- **Friends** (friendship is mutual and needs your friend code) see your profile, your presence (shown as `offline` once heartbeats stop), whether you are in a party with its code and size, and your weekly study minutes on the leaderboard.
- **Party members** see the profile and presence of everyone in the same party, including members who are not their friends.
  Anyone who has a party's code can join it while it has room, so share party codes only with people you want to study with.
- There is no directory or search: nobody can find you without your friend code or a shared party code.

You always see your own complete profile and presence.

## How to delete

Leaving a party (`POST /v1/party/leave`) removes your membership; a party is deleted when its last member leaves or after 12 hours without activity.
Removing a friend deletes the friendship in both directions.
Deleting your account calls `DELETE /v1/me`, which erases your profile, presence, daily study minutes and friend list, removes you from your friends' lists, and takes you out of your party.
Your secret token stops working at once.

## No analytics, no third parties

The service uses no analytics, no tracking, no advertising and no third-party services.
It is a single Cloudflare Worker with Durable Object storage, operated by whoever deployed it.
