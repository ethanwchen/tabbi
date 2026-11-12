# Study Crews

Study Crews (Crew in the UI) are standing groups of up to 20 people who study under one name and a crest they build from a frame, an emblem and a color, like a game clan's badge.
Every week the three crews with the most focus hours win a gold, silver or bronze laurel for their crest, a medal that stays with the crew forever in the all-time Hall of Fame, and the featured spot.
Crews live in the Party tab, use the Party identity and server, and work the same on the Mac direct download, the Mac App Store edition and Windows.
This page is the design and the contract: the server, both apps and the shared fixtures follow it.

## Goals and non-goals

Crews give a reason to come back every week and a small, friendly sense of belonging, without turning study into a grind.
Rewards are cosmetic only: a laurel, a trophy count and being featured.
Crews never award pet points; points still come only from studying (`PetPointsRules` is untouched).
There is no chat, no messages, no user-uploaded image and no free text beyond a crew's name and a one-line description, both filtered.

## Owner decisions

- Name: Study Crews in full, Crew in the UI.
- Ranking: total focus hours per crew for the week; a crew holds at most 20 members.
- Rewards: the weekly top 3 get a gold, silver or bronze laurel on the crew's crest for the following week, a trophy count on the crew page that grows forever, and the featured spot.
- Visibility: every crew, public or private, can be ranked and featured, and clicking a featured crew shows its members' pets (pet look, pet name, display name, and Study Level once that ships).
- Public crews can be found by anyone eligible, who asks to join and gets in when the owner approves; private crews are joined by invite code or link only, and an invite code or link always joins at once, public or private, since the owner handed it out.
- The create flow says plainly that every crew can appear on the weekly board with its members' pets, and each member can hide their own pet from crew pages (visible by default).
- Crests (the owner's later direction, replacing single icons): Clash Royale style clan badges built from a frame shape, an emblem and a crew color, composited at runtime, with a gold, silver or bronze laurel for the weekly top 3; no uploaded images.

## The week

A crew week runs from Monday 00:00 UTC to the next Monday 00:00 UTC (shown as "Sunday 23:59 UTC").
Its id is the ISO week key, for example `2026-W46`, the same key the friends leaderboard uses.
At rollover the board freezes: the week's places are recorded and no later report changes them.
The laurels from that week show on the winners' crests for the whole following week, and the winners take the featured spot for that week.
The app shows the week's countdown ("Ends in 2d 5h") from the server's `endsAt`, so every time zone and both apps agree.
UTC was chosen over local weeks because a board everyone shares needs one edge; the countdown makes the edge visible wherever you are.

## Counting

A crew's week total is the sum of focus minutes its members studied while they belonged to it.
A member's minutes count for the crew they belonged to when the minutes were studied: leaving or switching moves no past minutes, and a crew keeps what a former member gave it that week.
Joining mid-week counts only from the moment of joining: a session that started before the join counts only for its part after the join.
A session that spans the week's rollover counts each part toward its own week, and only the part in the current week can still be credited.
Hours on the board are minutes divided by 60, shown with one decimal below 10 hours and as whole hours above.
One crew per person at a time.
A second crew is not needed for the first version: one crew keeps "my crew" unambiguous, means minutes never split or double count, and stops one person from carrying several crews to the top 3; a "study group and a club" use case can come later as a separate, uncounted membership if people ask for it.
Places use standard competition ranking on the week's minutes: equal minutes share a place and the next place skips.
Every crew placed 1 to 3 wins that place's medal and laurel, so two crews tied first both win gold and the next crew is third, with no silver that week.
Ties for third can put more than three crews on the board, and the featured spot holds every crew that placed.
The board lists placed crews by minutes, most first, then by crew id, so the order never changes between two looks.
A crew with no minutes in a week is never ranked or awarded.

## Anti-cheat

The server never trusts a raw total.
The app reports finished focus sessions, each with `start`, `end` and `minutes`, from the activity log both apps already keep (`focus.completed` records from the Focus timer, Study and shared Party sessions).
The app merges overlapping records first (a shared Party session and the user's own timer can log the same stretch), so one stretch of time is reported once.
The heartbeat's `todayMinutes`, which the friends leaderboard sums, is never used for crews.

The server checks each session:

- `end` after `start`, both whole unix seconds, `end` no later than 2 minutes from now (`future` otherwise);
- `minutes` from 1 to the session's length in minutes rounded up, and a session no longer than 12 hours (`invalid` otherwise);
- the session's end inside the current week or, for the current week's part only, overlapping it (`week_closed` when it lies wholly in a frozen week);
- no overlap with a session the same user already reported (`overlap`), except the exact same start and end, which is a harmless retry (`duplicate`, nothing credited twice);
- the user belonged to a crew for some of it (`no_crew` otherwise, and nothing is stored).

Accepted minutes are spread evenly over the session's seconds, clipped to the user's crew stints, and credited per UTC day.
A user is credited at most 16 hours (960 minutes) per UTC day and 80 hours (4,800 minutes) per week; the rest is dropped and the session answers `capped` with what was credited.
Reports are rate-limited to 6 requests a minute per user, with at most 20 sessions per request.
Outliers go to the maintainer's moderation queue as flags, at most one per user, week and kind: `daily_cap` (a day hit its cap), `weekly_cap`, `overlaps` (5 or more overlapping reports in a day) and `future` (3 or more future-dated reports in a day).
The maintainer can dismiss a flag or void it, which removes that user's credited minutes for that week from their crew while the week is still open.
Banning a user takes them out of their crew and voids their minutes for the open week.

## Hall of Fame

Every weekly place is a medal: first is gold, second silver and third bronze, ties included.
A crew's medals are counted forever on its row, so they survive renames and edits, and a deleted crew's medals leave the Hall of Fame with it.
The weekly rollup writes the medals when a week closes; it runs once per week, so re-running a closed week changes nothing, and it catches up several missed weeks oldest first.
The Hall of Fame lists every crew with at least one medal in Olympic order: most golds, then silvers, then bronzes, then whoever reached that exact tally first, then crew id.
"Reached" is the end of the week that gave the crew its current tally, so a crew that got there earlier stays ahead of one that only caught up.
Ranks are distinct: 1 plus the crew's place in that whole order, so equal tallies from the same week are ordered by crew id.
Hidden crews are left out, as on the board, and private crews are in, as on the board.
The weekly board pages the places below the top 3 the same way, 20 at a time, and both answer where my crew stands (`mine`).
`GET /v1/crews/hall` pages it 20 at a time with an opaque cursor; paging follows the order itself (keyset), so a walk through the pages never repeats or skips a crew.

## Visibility and privacy

- Public crews show up in Find crews, where anyone eligible can ask to join; the owner approves or declines each request.
- A request waits at most 7 days, one at a time per person (a new one replaces it), at most 50 per crew, and a decline is never announced: the request just disappears.
- The heartbeat reply tells an owner how many requests wait, so the Party tab can badge them without polling.
- Private crews can only be joined with their invite code or link, which only members see.
- Every crew, public or private, can be ranked on the weekly board and featured, and anyone in Party can open a crew on the board to see its members' pets.
- A member page shows the display name, and, unless the member hid it, the pet's look and name, plus their minutes this week; once Study Level ships it shows too (`studyLevel` is optional on the wire).
- Hiding my pet (`showPet: false`) replaces my pet and its name with a quiet silhouette on every crew page, for members and visitors alike; my display name and minutes still count and show.
- Crew pages never carry friend codes: members are addressed by an opaque per-membership `ref`, so a crew on the board is not a directory of friend codes.
- Crews do not change who can add you: friend requests still need your friend code.
- `backend/PRIVACY.md` lists the new data, and the "no directory or search" sentence now says public crews can be searched by name.

## Safety and moderation

- Crew names (up to 20 characters) and descriptions (up to 120) go through the same name filter as display names, in the app (`PartyNameFilter`) and on the server (`isNameAllowed`); names are unique among crews, ignoring case.
- Members can report a crew (its name, description or crest) or a member (`POST /v1/crews/reports`), leave at any time, and block a member (`POST /v1/crews/block`), which is the same block as everywhere in Party.
- A block between a member and the owner takes the member out: the owner blocking removes them for good, a member blocking the owner leaves; any other block just hides the two from each other on crew pages.
- A crew whose owner blocked me, or whom I blocked, looks like it does not exist to me (404), as a party does.
- Owners can remove members; a removed member cannot join that crew again.
- When the owner leaves, the longest-standing member becomes owner; the last member leaving deletes the crew.
- The maintainer can rename a crew (to "Crew" plus four characters of its id, with the old name held so no crew can take it again), hide it (gone from Find, the board and the featured spot, while members keep it), or delete it, and reviews crew reports and anti-cheat flags (`backend/` admin routes, docs/study/backend-api.md).
- Banned users cannot create or join crews and disappear from other people's crew pages.
- Crews follow Party's age check: Party, and so Crews, stays off on a Mac where the user answered under 13, and the server never receives an age.

## Server

Everything lives in the existing SQLite Durable Object (`Hub`), as one new migration step (`CREWS_SCHEMA`), which runs on the next deploy and only adds tables.
New tables: `crews`, `crew_members` (current membership, with the member `ref` and `show_pet`), `crew_stints` (who belonged where and when, kept 14 days after leaving), `crew_sessions` (reported sessions, kept 14 days), `crew_day_credits` (credited minutes per user, crew and UTC day, kept 5 weeks), `crew_weeks` (each crew's week total, kept 5 weeks), `crew_awards` (every crew placed 1 to 3 in every week, kept forever with the crew's name and crest at the time), `crew_results` (every crew's final place and minutes per week, kept 5 weeks, for the last three weeks on a crew page), `crew_join_requests` (kept 7 days), `crew_removals`, `crew_reports`, `crew_flags` and `crew_name_holds`.
The hourly alarm runs the weekly rollup (`rollupCrews`) and the crews retention sweep; every crews route runs the rollup first too, so the board freezes at rollover even before the alarm fires.
The rollup is idempotent: a week already in `crew_awards` is never rolled up again.

## Protocol

Crews are protocol 3, and additive: older apps never call the new routes and keep using Party as before.
Apps from this release send `Tabbi-Protocol: 3`; the server answers `GET /` with `protocol: 3` and still serves protocol 1 and 2.
No existing route, reply or request body changes.
The wire shapes are in `shared/schemas/crews.v1.schema.json`, the routes in docs/study/backend-api.md, and `shared/fixtures/crews/crews.json` pins what the Mac app sends and reads; the Windows app replays it.

Routes (all need the Party token):

| Route | What it does |
| --- | --- |
| `GET /v1/crews/mine` | My crew (`crewDetail`) or null, and the current `week` |
| `POST /v1/crews` | Creates a crew with me as owner; `409 in_crew` while I am in one |
| `PATCH /v1/crews/mine` | Owner edits name, description, crest (frame, emblem, color) or visibility |
| `PATCH /v1/crews/mine/me` | My own settings in my crew: `showPet` |
| `POST /v1/crews/join` | Joins by `{ code }` (an invite code) or `{ crew }` (a public crew's id) |
| `POST /v1/crews/leave` | Leaves my crew |
| `POST /v1/crews/mine/members/{ref}/remove` | Owner removes a member |
| `GET /v1/crews?q=` | Public crews matching the search, most minutes this week first, up to 20 |
| `GET /v1/crews/board` | This week's live places 1 to 3 and last week's frozen places (the featured crews) |
| `GET /v1/crews/hall?cursor=` | The all-time Hall of Fame, 20 crews a page |
| `GET /v1/crews/{id}` | A crew page: mine, a public crew, or one on the board |
| `POST /v1/crews/sessions` | Reports finished focus sessions; the reply says what each credited |
| `POST /v1/crews/reports` | Reports a crew or one of its members |
| `POST /v1/crews/block` | Blocks a member of a crew by `ref` |

Objects:

- `week`: `{ id, startsAt, endsAt }`, unix seconds, `endsAt` exclusive.
- `crewSummary`: `{ id, name, description, frame, emblem, color, visibility, laurel, trophies, memberCount, maxMembers, weekMinutes }`; `laurel` is `gold`, `silver`, `bronze` or null (what the crew wears this week), `trophies` counts every medal ever (every place 1 to 3).
- `crewDetail`: a `crewSummary` plus `{ createdAt, medals: { gold, silver, bronze }, rank, members, mine, owner, inviteCode, hidden }`; `rank` is this week's live rank or null with no minutes, `mine` says I belong, `owner` that I own it, `inviteCode` is only sent to members, `hidden` only to members.
- `crewMember`: `{ ref, name, pet, studyLevel?, badges, weekMinutes, owner, me }`; `pet` is `{ petName, species, breed, colors, costume, accessories }` (the same fields and ids as a Party profile) or null when the member hid it.
- `boardEntry`: `{ rank, minutes, crew: crewSummary }`; in `featured`, `laurel` on the summary is the tier that week won.

Ids: a crew `id` is 10 characters and an invite `code` 7, both from the friend code alphabet (`A-Z` and `2-9` without `I`, `O`, `0`, `1`); a member `ref` is 10.
The catalog of frame, emblem and color ids and the limits is `backend/shared/crews.json`; once shipped, ids are only ever added, and an app draws a frame, emblem or color it does not know as the first one, so an older app always shows a crest.
Invite links are `tabbi://crew/<code>` and `https://tabbinotch.com/crew/<code>`, handled like the Party invite links.

## Crests

A crew's crest is built like a game clan's badge: a frame (the silhouette, filled with the crew color), an emblem stamped into the frame's slot, and the crew color, plus a laurel in gold, silver or bronze for a crew that placed in the weekly top 3 and up to three trophy pips (one per medal, at most three).
The art and the rules are one data file, `Sources/TabbiKitCore/Pets/PetArt/crew.json` (format `crewCrests.v1`), drawn by the design pass in `runs/crews/icons-v5` at the Goals badges' detail level: a 32 by 32 grid, the pet's outline, two or three tones per material.
Every layer is a grid of palette characters, `.` is clear, and a later layer paints only its own cells: the laurel first (under everything), then the frame, then the emblem at the frame's slot, then the pips.
The characters `C`, `D` and `H` take the crew color's base, shade and highlight, a crew color may set further roles of its own (the emblem outline turns light on a dark crew color), `g` and `h` take the rank's leaf and shade, and every other character has a fixed color.
Drawing is nearest neighbor only: 1 pt per sprite pixel at 32 pt, 1.5 pt at 48 pt (3 device pixels on Retina, the badge rule), and larger on the crew page.
Both apps composite the same file the same way (`CrewCrestArt` on the Mac, `crewCrestArt.ts` on Windows), and `shared/fixtures/crews/crests.json` pins a spread of crests (every frame with every emblem, every color, laurel and pip count) as characters with every palette; those pixels match the design's reference compositor (`tools/crests.py`) exactly.
The frames, emblems and colors are provisional while the owner reviews them; cutting or adding one is editing the data file and the id lists in `backend/shared/crews.json`, which a test keeps equal.
The builder in New crew and Edit crew has a frame, an emblem and a color picker, a Shuffle button and a live preview at a large size and in a crew row.
Reference points for the level of expression (looked at, not copied; nothing saved in the repo) are listed at the end of this page.

## App

Crews are a mode of the Party tab, identical on Mac and Windows, built to the approved UI spec in `runs/crews/ui-design` (spec.md and prototype.html).
A Party | Crews switch sits at the left of the Party header and of the lobby, so the live party stays the tab's hero and crews are one click away; on a narrow panel the header drops its labels in a fixed order (titles, then the share button) before anything is cut.
Crews mode is one card with a pill row of four sections, My crew, This week, Hall of Fame and Find, and at most one pushed screen (a crew's page or the crest editor) with a back pill to the section that opened it.
The pill row shows every title when they fit, then only the open section's title, then icons only; the trailing slot holds the section's own control (the countdown "New week in 3d 4h", the Hall of Fame caption, Create a crew, or Invite link and a More button).

- This week: the top 3 as tiles (place chip, crest wearing last week's laurel, the three most active members' pets, a name that wraps to two lines, hours) beside a list of the other crews, and my crew pinned under a hairline when it is not in view.
  At Compact the tiles become featured rows.
  Ties share a place, shown as "5=" in the list; a quiet week shows the sleeping pet and "A quiet start to the week"; loading shows skeleton rows.
- Hall of Fame: the same layout ranked by medals in Olympic order, each crew's gold, silver and bronze tally, and my crew pinned with "-" and 0 0 0 before its first medal.
- My crew: a 168 pt side column (the 48 pt crest with up to three gold pips and up to four members' pets, the name, the week as a sentence, the place with Public or Private, the medal tally, and "No medals yet" when it is empty) beside the members, most hours first, each with pet, name, Study Level and hours.
  The owner sees join requests on top with approve and decline, and "· 2 want to join" in the caption; the tab and the pill show a badge while requests wait.
  The More button opens an in-panel menu with Edit crew (owner), Hide or Show My Pet on Crew Pages, and Leave crew.
  Right-click a member to report or block, and for the owner to remove.
- Without a crew: a waving pet with Create a crew and Find crews; while my request waits, "Waiting to join %@" with Cancel request.
- Find: a search field and whole rows of public crews (crest, name, members of 20, hours this week, Full); a row opens the crew's page, where a public crew offers Ask to join (Requested once sent) and the flag reports it.
- A crew's page: the hero column with the last three weeks (week, medal, place, hours) and the members.
- New crew and Edit crew: a preview tile with the crest, the name as a tile wraps it, Shuffle and the Public or Private toggle, the name and description fields, and the frame, emblem (one scrolling row) and color pickers with "Every crew can appear on the weekly top 3 with its members' pets." under them.
- A crew invite link opens My crew with "Join this crew?" and Join Crew or Not Now; an invite joins at once, while a public crew found in Find asks its owner.

Lists show whole rows only: what does not fit scrolls, with "+N more" or a hairline at the cut, and rows snap as they scroll.
Long crew names get soft hyphens from the name's own language (then English) so a tile breaks "Bibliotheks-ratten" at a syllable, even in a language with no hyphenation of its own.
Numbers and ordinals follow the app's locale formatting, as every other number in Tabbi does.
Medals are a 9 x 10 pixel sprite (`CrewMedalArt`) in gold, silver and bronze.

Session reporting runs in the background while Party is connected and I am in a crew: finished `focus.completed` records are merged, queued in a small versioned file in the edition's Party storage, sent in batches of up to 20, and dropped once the server answered for them (any status but a transient error).

Text never truncates in any of the 12 languages at any panel size: each screen steps down through shorter forms with `ViewThatFits` (Windows: the same order).
The hero drops "No medals yet", then takes the short "%@ this week", then drops history weeks one at a time, then the place caption; the members caption drops "this week", then the waiting count; the editor's Shuffle and Public buttons fall back to their glyphs, and the name under the preview goes when a two-line name would push the fields out.
Names wrap to two lines where they would otherwise cut, and Arabic mirrors the layout while the pixel art stays unmirrored.

New emblem sets are data: `scripts/crews-import-art.py emblems.json [frames-patch.json]` writes crew.json and the server's crews.json, the builder's tooltips read frame and emblem names from the data through the string catalog (the script lists names still missing a translation, and a test checks them), and the crest fixture is re-recorded with `TABBI_RECORD_FIXTURES=1`.

## App Store

Crews add no new data type to the App Privacy label: crew names and descriptions are Other User Content, crew membership is part of the social graph already declared under Contacts, and focus sessions are Product Interaction, all App Functionality only and linked to the Party identity, as Party's answers already say.
The age rating answers do not change: User-Generated Content was already Yes for Party, and crews add no messaging.
docs/appstore.md has the reviewer steps with the demo friend.

## Rollout

1. Merge; the backend tests cover protocol 1, 2 and 3 apps side by side.
2. Deploy the Worker to staging, try it with a local build, then to production; the migration runs on the first request.
3. Deploy the site with the `/crew/<code>` invite page.
4. Release the apps (Mac direct, Mac App Store with the review notes, Windows).

## Expression references

The mascots were calibrated against these (search results only; nothing was copied or saved in the repo):

- https://reffpixels.itch.io/pixelemoji
- https://hermoza100.gumroad.com/l/PixelArtEmojiIconSet
- https://opengameart.org/content/pixelart-emoji-pack
- https://dustdfg.itch.io/pixel-art-emotes
- https://communityone.io/emoji/mascotcheer-1497361801367654530/
- https://origin.pixie.haus/pixelart/400863/anthropomorphic-cat-thumbs-up-sprite
- https://pixie.haus/pixelart/201134/energetic-cartoon-fox-standing-playful-stance
- https://pixie.haus/pixelart/300629/fierce-cat-profile-ornate-crest-symbol
- https://pixie.haus/pixelart/581200/chibi-warrior-blue-armor-sword-ready
- https://apyryon.itch.io/fantasyportraits
- https://guild-drawing.pages.dev/

What they agree on, and what the crew mascots follow: a big readable face, bold silhouettes that differ in shape (tall, wide, diagonal), few tiny details, and one clear mood per character (determined, sleepy, smug, cheerful, fierce but cute).
