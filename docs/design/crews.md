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
- Public crews can be found and joined by anyone eligible; private crews are joined by invite code or link only.
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
Ranks are competition ranks over that whole order: equal tallies reached the same week share a rank.
Hidden crews are left out, as on the board, and private crews are in, as on the board.
`GET /v1/crews/hall` pages it 20 at a time with an opaque cursor; paging follows the order itself (keyset), so a walk through the pages never repeats or skips a crew.

## Visibility and privacy

- Public crews show up in Find crews and can be joined by anyone eligible while they have room.
- Private crews can only be joined with their invite code or link, which only members see.
- Every crew, public or private, can be ranked on the weekly board and featured, and anyone in Party can open a crew on the board to see its members' pets.
- A member page shows the display name, and, unless the member hid it, the pet's look and name, plus their minutes this week; once Study Level ships it shows too (`studyLevel` is optional on the wire).
- Hiding my pet (`showPet: false`) replaces my pet and its name with a quiet silhouette on every crew page, for members and visitors alike; my display name and minutes still count and show.
- Crew pages never carry friend codes: members are addressed by an opaque per-membership `ref`, so a crew on the board is not a directory of friend codes.
- Crews do not change who can add you: friend requests still need your friend code.
- `backend/PRIVACY.md` lists the new data, and the "no directory or search" sentence now says public crews can be searched by name.

## Safety and moderation

- Crew names (up to 24 characters) and descriptions (up to 120) go through the same name filter as display names, in the app (`PartyNameFilter`) and on the server (`isNameAllowed`); names are unique among crews, ignoring case.
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
New tables: `crews`, `crew_members` (current membership, with the member `ref` and `show_pet`), `crew_stints` (who belonged where and when, kept 14 days after leaving), `crew_sessions` (reported sessions, kept 14 days), `crew_day_credits` (credited minutes per user, crew and UTC day, kept 5 weeks), `crew_weeks` (each crew's week total, kept 5 weeks), `crew_awards` (every crew placed 1 to 3 in every week, kept forever with the crew's name and crest at the time), `crew_removals`, `crew_reports`, `crew_flags` and `crew_name_holds`.
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

Crews are a section of the Party tab, identical on Mac and Windows.
This section describes the first build; a full HIG-based layout and spacing spec for every Crews screen, the Hall of Fame included, is being drawn in `runs/crews/ui-design` and replaces it when it lands.
A two-way switch, Party and Crew, sits where the Party stage's title was (and on top of the party lobby), so the friends column and the party keep their room; it shortens to two icons on a narrow panel.
The Crew section keeps the Party tab's shape: a main card on the left and, where the friends column is, the weekly top 3.

- The top 3 card shows this week's live race (rank, crest wearing its current laurel, name, hours, and "Your crew" on mine) with the countdown ("Ends in 2d 5h") in its header, and a This week or Last week switch at the bottom for last week's frozen winners with the laurels they won.
  Clicking a crew opens its page in the main card.
- My crew: the crest with its laurel, the name (up to two lines), this week's hours and rank, a meta line (Public or Private, members of 20, trophies) that falls back to icons, and the members' pets side by side with name and hours, owner first; the row scrolls sideways past what fits.
  The header has Invite (copies the link), Find and a menu with Edit Crew (owner), Hide or Show My Pet on Crew Pages, and Leave Crew.
  Right-click a member: Report and Block, and for the owner Remove from Crew; right-click my own pet: Hide or Show My Pet.
- No crew yet: "Join a study crew" and "Study with a crew and climb the weekly top 3.", then New crew, Find crews and an invite code field; on a short panel the crest and then the second line give way so the ways in always show whole.
- New crew and Edit crew: name, description and the crest builder (frames with Shuffle, emblems, colors) on the left; the right column turns into a live preview with Public or Private, what that means, the line "Every crew can appear on the weekly top 3 with its members' pets.", Cancel and Create (Save when editing).
  The name filter answers as you type, in place of that line.
- Find: Back, a search field on its own row, and up to 20 public crews (crest, name, members of 20, hours this week, Join or Full); a row opens the crew's page.
- Another crew's page: Back, the same identity and pets, Join for a public crew with room, and the flag to report the crew.
- A crew invite link opens the Party tab's Crew section with "Join this crew?" and Join Crew or Not Now.

Session reporting runs in the background while Party is connected and I am in a crew: finished `focus.completed` records are merged, queued in a small versioned file in the edition's Party storage, sent in batches of up to 20, and dropped once the server answered for them (any status but a transient error).

Text never truncates in any of the 12 languages at any panel size: long labels move to a shorter form through `ViewThatFits` (Windows: the same fallbacks), names wrap to two lines where they would otherwise cut, user-written names that still do not fit end in an ellipsis with a tooltip, and Arabic mirrors the layout while the pixel art stays unmirrored.

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
