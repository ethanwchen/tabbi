# Progression: goals that take weeks and months

Tabbi's owner put the problem plainly: people max out the costumes, and the app needs other objectives too.
This page measures how fast that happens today, then lays out what this change adds: harder, more creative costumes earned from long goals, a badge collection with rare tiers, and gentle monthly quests.
Everything here is earned by studying and never sold, like every item before it (docs/economy.md).

## How fast people max out today

Points are 1 per focused minute plus 10 for each finished block of 25 minutes or more (`PetPointsRules`).
With Pomodoro blocks that is about 84 points per hour of focus.

| What | Size | 1 h a day | 2 h a day | 3 h a day | 6 h a day |
| --- | --- | --- | --- | --- | --- |
| Starter and mid-tier items (17) | 4,390 pts | 52 days | 26 days | 17 days | 9 days |
| The whole shop (32 paid items) | 29,240 pts | 348 days | 174 days | 116 days | 58 days |
| Bond level 10 (the top) | 7,000 bond pts | 78 days | 47 days | 33 days | 18 days |
| Golden Laurel (50 h focused) | 3,000 min | 50 days | 25 days | 17 days | 8 days |
| Flame Headband (7-day streak) | 7 days | 7 days | 7 days | 7 days | 7 days |
| Team Medal (one Party session) | 1 session | one session | one session | one session | one session |

Days assume study every day; at the shop's typical pace (75 minutes on 5 days a week) the whole shop takes about 56 weeks.

Release 7 (1.0.6) adds 15 shop items, six of them on a new Heirloom tier of 6 to 12 typical weeks each (docs/economy.md), because students were still unlocking everything and running out of things to aim for.
The whole shop is now 47 paid items and 66,190 points: about 788 days at 1 hour a day, 394 at 2 hours, 263 at 3 hours and 131 at 6 hours.
The Heirloom shelf alone (27,500 points) is about five months at 2 hours a day.

So the shop itself is not short, but the variety runs out fast:

- Within two to four weeks of steady study, every cheap and mid-tier item, all three milestone items and most of the bond are done.
- What is left is fifteen showpieces on one currency, so the next month feels like the same bar filling slowly, with nothing new to aim at.
- Heavy users (six hours or more a day, common with the Med School kit and long lecture timers) own literally everything in about two months.
- Only focused minutes count. Flashcards, tasks, break moves, water and Party, which the app already logs, earn nothing of their own.

The fix is not higher prices.
It is more kinds of goals, each long, each about something the user already does.

## What this adds

### 1. Mastery outfits (16 new items)

New costume items that points cannot buy.
Each unlocks on its own when a long goal is reached, from activity the app already logs, and stays owned for good.
They live in a new **Goals** section of the Closet, never in the shop, so the shop's prices and tiers stay exactly as they are.

| Item | Slot | Earned by | Time at 2 h a day |
| --- | --- | --- | --- |
| Little Sprout | head | 30 study days | about a month |
| Blossom Sprout (a petal drifts off) | head | 100 study days | about 3 months |
| Nightcap | head | a 30-day gentle streak | a month |
| Cozy Pajamas | outfit | a 90-day gentle streak | 3 months |
| Apprentice Robe | outfit | 75 finished focus sessions | 3 to 5 weeks |
| Scholar's Robe | outfit | 300 finished focus sessions | 2 to 5 months |
| Sage's Robe (its gold stole glints) | outfit | 800 finished focus sessions | 5 months to a year |
| Astronaut Suit | outfit | 200 hours focused | about 3 months |
| Starry Cloak (its stars twinkle) | outfit | 500 hours focused | about 8 months |
| Explorer's Hat | head | 4 steady weeks (3 or more study days each) | a month |
| Owl Spectacles | face | 10,000 flashcards reviewed | 3 weeks to 3 months |
| Busy Bee Antennae | head | 200 tasks checked off | 2 to 3 months |
| Sporty Sweatband | head | 50 break moves with the pet | about a month |
| Friendship Bandana | neck | 20 Party sessions with friends | 2 to 3 months |
| Baker's Apron (with a tiny cake) | outfit | 4 different study methods tried | whenever you explore |
| Tiny Lantern (a framed lantern on a ribbon, its flame flickers) | neck | 6 months of monthly quests | 6 months or more |

Rules for the art, all held by the existing fit tests:

- Drawn in the `pets.v1` sprite format with the existing palette roles, so one drawing fits every breed and body shape (cat, round cat, Sphynx, Fold, longhair, every dog, the dachshund), sitting, walking, stretching and napping.
- Readable on dark coats: thin lines are at least two pixels or sit on a light fill, and nothing green sits beside the black cat's green eyes.
- No capes and no wings, anywhere (the owner's rule for marketing).
  The Starry Cloak is a cloak worn on the body, closed at the chest with a gold star clasp, and never streams behind.
- Four items are animated on the shared item clock, still under Reduce Motion: the Starry Cloak's twinkle, the Sage's Robe's glint, the Tiny Lantern's flicker and the Blossom Sprout, which lets a petal go now and then.

The robes are one family tiered by mastery, each with wide sleeves and its own color: the Apprentice Robe is brown with an open cream-edged front, cream cuffs and a rope belt with a knot and tassels, the Scholar's Robe navy with a crimson stole and gold buttons, and the Sage's Robe white with a gold stole that catches the light, a violet hem and a violet wizard hat whose cone bends over with a gold star at the tip, a moon glint and a gold brim band resting on the head.
The Astronaut Suit comes with a glass bubble helmet, and the Baker's Apron goes with the shop's Chef Hat.

### 2. Badges: a collection with rare tiers

Twelve badges, one per thing the user does, each with four tiers: Bronze, Silver, Gold and Starlight.
The early tiers come within days, so a new user sees the collection light up; Starlight takes months even for heavy users.

| Badge | Bronze | Silver | Gold | Starlight |
| --- | --- | --- | --- | --- |
| Focus time | 10 h | 50 h | 200 h | 500 h |
| Study days | 7 | 30 | 100 | 250 |
| Gentle streak | 7 days | 30 days | 90 days | 180 days |
| Sessions | 15 | 75 | 300 | 800 |
| Flashcards | 500 | 2,500 | 10,000 | 30,000 |
| Tasks | 10 | 50 | 200 | 500 |
| Break moves | 10 | 50 | 150 | 400 |
| Party | 1 | 5 | 20 | 60 |
| Study methods | 2 | 3 | 4 | 6 |
| Steady weeks | 2 | 4 | 12 | 26 |
| Water | 20 glasses | 100 | 300 | 1,000 |
| Monthly quests | 1 month | 3 | 6 | 12 |

That is 48 tiers, and each mastery outfit hangs off one of them, so the Goals section reads as one ladder per habit.
The ladders scale alike: each tier asks about 5x, 4x and 2.5x to 3x the one before, and Starlight lands near a year of two hours a day (500 h of focus is 800 finished 25-minute blocks, so Sessions and Focus time pay out together; 30,000 cards is 80 a day for a year).

- **Gentle streak** is the longest run of study days the Streak section has ever counted, with its freezes: one free day off a week and any extra freezes bought.
  It is the longest run ever, never the current one, so a broken streak never takes a badge or an outfit away.
- **Steady weeks** count Monday-to-Sunday weeks (the weekly recap's weeks) with 3 or more study days, in any order, so a month of steady weekly recaps earns the Explorer's Hat.
- **Study methods** count the named methods (Pomodoro, 52/17, Ultradian, Flowtime, Anki sprint, Question block) used for at least one logged focus stretch.
  The outfit needs four, so nobody needs Anki for it; all six is the Starlight tier.
- **Party** counts shared sessions that ran to their end with at least one friend studying along.

### 3. Monthly quests

Each calendar month offers three small goals, such as "Focus for 10 hours", "Review 600 cards" or "Do 8 break moves with your pet".
They are optional and gentle on purpose:

- The amounts are well under the typical habit (about 27 focused hours a month), so a light month still finishes them.
- One quest is always about focus (hours, study days or sessions); the other two come from what the user actually does.
  Flashcards, tasks, break moves, Party and water join the pool only after the user has done them before that month, so nobody is asked to review cards without Anki.
- The three are picked by a fixed hash of the month, the same on every Mac and on Windows, and stay put all month.
- Finishing all three counts one month toward the Monthly quests badge and, at six months, the Tiny Lantern.
  Months do not need to be in a row, a missed month costs nothing, and no month has an item of its own, so there is nothing to miss out on.

## Why these three, and not the others

Every candidate was judged against the notch canvas (about 500 by 150 pt per panel), the brand (cozy, gentle, honest) and the rule that everything comes from activity the app already logs.

- **Mastery outfits** answer the request directly: more creative costumes behind much harder goals.
  They reuse the sprite system, the Limited tiles and the item ledger, so they sync and work in Party like every item.
- **Badges** give every habit its own long ladder, including the ones that earned nothing so far (cards, tasks, break moves, water, Party).
  Four tiers with a rare Starlight top give returning users something new to light up for months, and a badge is a 24 pt medallion, which fits twelve to a card.
- **Monthly quests** give someone who has everything a fresh, small reason to come back each month.
  A month that started late or went badly costs nothing, which keeps them free of FOMO and of streak pressure.
- **Titles shown in Party** were left out of 1.0.5: showing them to friends needs a new profile field and a Party protocol bump (`docs/party-compatibility.md`, rule 5).
  The Study Level (below) made that change in 1.0.6: protocol 3 shares the level, whose rank is the title, and the nameplate color.
- **A room or desk for the pet** was left out: the notch has no room for a scene beside the panel, and it would need a new art pipeline.
- **Collectible stickers** were folded into the badges: the same collection, without a second set of art to keep readable at notch size.
- **Seasonal quests** already exist as seasonal events; monthly quests are the year-round, item-free version.

## Where it lives

The Closet gets a seventh section, **Goals** (a rosette), between Limited and Streak:

- A banner at the top for this month's quests: the month, how many of the three are done, a ring for each quest (hover for its goal and progress), and the next unfinished quest on its second line.
- **Outfits to earn**: the sixteen mastery outfits as tiles, greyed until earned, each with its progress ("142/200") and a thin bar.
  Hovering a tile tries the outfit on the big pet and says how to earn it; clicking an earned one wears it or takes it off.
- **Badges**: twelve pixel badges in the pet's own sprite language (`badge.json`, 28 by 28, drawn at 1.5 pt per pixel, 2 pt on the large panel): a quiet gray coin before Bronze, a bronze medal, a silver medal on a rosette with ribbon tails, a gold medal with a laurel vine, and a violet star with a sparkle that blinks slowly (still under Reduce Motion and in snapshots).
  The badge itself never shows a meter: the progress to the next tier is in the tooltip, the footer and the four small pips for the tiers earned.
  Hovering one says its tier, its progress and what the next tier asks.
- A footer that counts outfits and badges earned, or details the hovered tile.

It scrolls and fades out at the bottom edge like the Wardrobe and Limited sections.
A small accent dot on the Goals pill says something new was earned since the section was last opened, and goes away once it is.
When a badge tier, an outfit or a month of quests is earned while Tabbi runs, the pet celebrates and the panel sparkles, like a purchase.
Progress the app already had when this shipped unlocks quietly at launch (with the dot), so nobody is flooded with celebrations.

## Data and persistence

- **Pure logic** lives in `Sources/TabbiKitCore/Progression/` (new folder, tested in `Tests/TabbiKitCoreTests/Progression*Tests.swift`):
  `ProgressTrack` (the twelve badges, their tiers and units), `ProgressTally` (reads `ActivityRecord`s, each once by id), `GentleStreak` (the longest run with freezes), `MonthlyQuests` and `ProgressionSave`.
- It reads only the activity log: `focus.completed` (minutes, outcome, method, Party friends), `cards.reviewed`, `task.completed` (distinct task ids), `break.move` and `water.logged`.
  Nothing reaches into another module's store; the Closet, which owns the pet's save, replays the whole log at launch and follows new records, as it already does for milestones.
- **Mastery outfits** are limited edition items with a new source, `mastery(badge)` (`PetLimitedEdition`), so they are granted into the ledger, synced through Sign in with Apple as granted unlocks, refused by the shop and never cost points.
  They are earned on this Mac's Goals shelf only: the server's grantable list (`backend/shared/limited-items.json`) leaves them out and the app ignores a server grant of one, and the Limited section leaves them to Goals.
- **`Pet/progression.json`** (a `VersionedJSON` document, schema 1) keeps what the log alone could lose if day files were deleted by hand: each track's best value so far, the badge tiers reached and when, the months of quests completed, and which tiers were already seen.
  Progress shown is the larger of the log and the best value saved, so deleting old day files never takes progress back.
  It is never synced, like the pet's journal; a file that cannot be read is left alone and never overwritten.

## Study Level (1.0.6)

The badges and outfits reward many habits, each with an end.
The Study Level is the one ladder with no end: a level earned only from total focus hours, shown on the pet and to friends in Party.

### The rules

- Levels come only from total focus hours: the same focused minutes the Focus time badge counts (`focus.completed`, from the activity log).
- A level never resets and nothing is ever lost.
  `Pet/progression.json` keeps the best focus total and the highest level reached, so deleting day files never lowers a level, and a future change to the curve could not either.
- History counts retroactively.
  On the first launch with this version a long-time user lands at their real level quietly: the Goals pill shows its dot, and nothing celebrates.
- Levels give no points.
  Points stay tied to studying itself (`PetPointsRules`), and `StudyLevelTests` and `ClosetStudyLevelAppTests` prove a level up leaves the points ledger exactly as the same study would anywhere else.
- Every level, the pet celebrates and the number beside its name goes up; only a level that unlocks a name color or a rank also sparkles over the open panel.
  The closed notch shows nothing new.
- Every 5 levels a new nameplate color unlocks, up to Level 60; every 10 levels a new rank and its emblem.

### The curve

The total hours to reach level `n` are `round(4 * n^1.6)` (`StudyLevel.hoursToReach`, the one place the curve lives).
Level 1 takes 4 hours, so a new user levels up within days; each later level asks a little more than the one before (whole hours round, so neighbours can differ by an hour), never a wall.
Level 0 is everyone's start, under 4 hours.

The numbers are the design's, kept as they were: nothing in the tests or the snapshots asked for a change.
The design note said "about 52 h" for Level 5; the exact value is 53 h (`4 * 5^1.6` is 52.5), and the table below is exact.
The days assume study every day.

| Level | Total hours | This level | 1 h a day | 2 h a day | 3 h a day | Brings |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 4 | 4 | 4 days | 2 days | 1 day |  |
| 2 | 12 | 8 | 12 days | 6 days | 4 days |  |
| 3 | 23 | 11 | 23 days | 12 days | 8 days |  |
| 4 | 37 | 14 | 37 days | 18 days | 12 days |  |
| 5 | 53 | 16 | 53 days | 26 days | 18 days | Peach name color |
| 6 | 70 | 17 | 2 months | 35 days | 23 days |  |
| 7 | 90 | 20 | 3 months | 45 days | 30 days |  |
| 8 | 111 | 21 | 4 months | 56 days | 37 days |  |
| 9 | 135 | 24 | 4 months | 2 months | 45 days |  |
| 10 | 159 | 24 | 5 months | 3 months | 53 days | Ember rank, Ember name color |
| 11 | 185 | 26 | 6 months | 3 months | 2 months |  |
| 12 | 213 | 28 | 7 months | 3 months | 2 months |  |
| 13 | 242 | 29 | 8 months | 4 months | 3 months |  |
| 14 | 273 | 31 | 9 months | 4 months | 3 months |  |
| 15 | 305 | 32 | 10 months | 5 months | 3 months | Honey name color |
| 16 | 338 | 33 | 11 months | 6 months | 4 months |  |
| 17 | 372 | 34 | 12 months | 6 months | 4 months |  |
| 18 | 408 | 36 | 13 months | 7 months | 4 months |  |
| 19 | 445 | 37 | 15 months | 7 months | 5 months |  |
| 20 | 483 | 38 | 16 months | 8 months | 5 months | Comet rank, Sky name color |
| 21 | 522 | 39 | 17 months | 9 months | 6 months |  |
| 22 | 562 | 40 | 18 months | 9 months | 6 months |  |
| 23 | 604 | 42 | 20 months | 10 months | 7 months |  |
| 24 | 646 | 42 | 21 months | 11 months | 7 months |  |
| 25 | 690 | 44 | 23 months | 11 months | 8 months | Mint name color |
| 26 | 735 | 45 | 2.0 years | 12 months | 8 months |  |
| 27 | 780 | 45 | 2.1 years | 13 months | 9 months |  |
| 28 | 827 | 47 | 2.3 years | 14 months | 9 months |  |
| 29 | 875 | 48 | 2.4 years | 14 months | 10 months |  |
| 30 | 924 | 49 | 2.5 years | 15 months | 10 months | Nova rank, Rose name color |
| 31 | 973 | 49 | 2.7 years | 16 months | 11 months |  |
| 32 | 1,024 | 51 | 2.8 years | 17 months | 11 months |  |
| 33 | 1,076 | 52 | 2.9 years | 18 months | 12 months |  |
| 34 | 1,128 | 52 | 3.1 years | 19 months | 12 months |  |
| 35 | 1,182 | 54 | 3.2 years | 19 months | 13 months | Lilac name color |
| 36 | 1,236 | 54 | 3.4 years | 20 months | 14 months |  |
| 37 | 1,292 | 56 | 3.5 years | 21 months | 14 months |  |
| 38 | 1,348 | 56 | 3.7 years | 22 months | 15 months |  |
| 39 | 1,405 | 57 | 3.8 years | 23 months | 15 months |  |
| 40 | 1,463 | 58 | 4.0 years | 2.0 years | 16 months | Nebula rank, Nebula name color |
| 41 | 1,522 | 59 | 4.2 years | 2.1 years | 17 months |  |
| 42 | 1,582 | 60 | 4.3 years | 2.2 years | 17 months |  |
| 43 | 1,643 | 61 | 4.5 years | 2.2 years | 18 months |  |
| 44 | 1,704 | 61 | 4.7 years | 2.3 years | 19 months |  |
| 45 | 1,767 | 63 | 4.8 years | 2.4 years | 19 months | Coral name color |
| 46 | 1,830 | 63 | 5.0 years | 2.5 years | 20 months |  |
| 47 | 1,894 | 64 | 5.2 years | 2.6 years | 21 months |  |
| 48 | 1,959 | 65 | 5.4 years | 2.7 years | 21 months |  |
| 49 | 2,025 | 66 | 5.5 years | 2.8 years | 22 months |  |
| 50 | 2,091 | 66 | 5.7 years | 2.9 years | 23 months | Galaxy rank, Gold name color |
| 51 | 2,159 | 68 | 5.9 years | 3.0 years | 24 months |  |
| 52 | 2,227 | 68 | 6.1 years | 3.0 years | 2.0 years |  |
| 53 | 2,296 | 69 | 6.3 years | 3.1 years | 2.1 years |  |
| 54 | 2,365 | 69 | 6.5 years | 3.2 years | 2.2 years |  |
| 55 | 2,436 | 71 | 6.7 years | 3.3 years | 2.2 years | Aurora name color |
| 56 | 2,507 | 71 | 6.9 years | 3.4 years | 2.3 years |  |
| 57 | 2,579 | 72 | 7.1 years | 3.5 years | 2.4 years |  |
| 58 | 2,652 | 73 | 7.3 years | 3.6 years | 2.4 years |  |
| 59 | 2,725 | 73 | 7.5 years | 3.7 years | 2.5 years |  |
| 60 | 2,800 | 75 | 7.7 years | 3.8 years | 2.6 years | Galaxy II rank, Starlight name color |

Past Level 60 the curve keeps going without a cap: Level 64 at 3,104 h, Level 70 at 3,583 h, Level 100 at 6,340 h.
Friends are told at most Level 999 (about 252,000 hours), which only stops a garbled number.

### Ranks

| Levels | Rank | Emblem |
| --- | --- | --- |
| 0 to 9 | Spark | a warm four point sparkle |
| 10 to 19 | Ember | an orange flame with a hot core |
| 20 to 29 | Comet | a pale blue comet with its tail |
| 30 to 39 | Nova | a pink star bursting with rays |
| 40 to 49 | Nebula | a violet cloud with a pink and white swirl |
| 50 to 59 | Galaxy | an indigo spiral galaxy with a gold core |
| 60, 70, 80 ... | Galaxy II, III, IV ... | the Galaxy with one small gold star per numeral in its corners, up to four (Galaxy V on) |

The emblems are drawn in the pet's sprite language, like the badges: a 16 by 16 grid per named rank and the small star in `Pets/PetArt/rank.json` (`pets.v1`), stamped one pixel in from the edge of an 18 by 18 canvas and colored through each rank's `RankPalette` (`RankArt`).
They render through `PetCanvas` at whole device pixels per sprite pixel, nearest neighbor: 1 pt per pixel beside the pet's name, 1.5 pt on the Level card and 0.5 pt (one Retina pixel) in Party's tight rows.
The Windows port draws them from the same file, and `shared/fixtures/progression/levels.json` pins every emblem's pixels.

### Nameplate colors

A nameplate color tints the pet's name under it in the Closet and the person's name on their Party card.
Plain is everyone's; then Peach (5), Ember (10), Honey (15), Sky (20), Mint (25), Rose (30), Lilac (35), Nebula (40), Coral (45), Gold (50), Aurora (55) and Starlight (60).
From Nebula on, the name also glows softly.
Every color reads at 7:1 or better on the black notch.
The palette ends at Level 60, where Galaxy II begins; past that the ranks keep counting.

### Where it shows

- **The pet's name line** in the Closet: "Mochi  [emblem] Lv 12 Ember", the name in its nameplate color.
  Where the card is narrow it drops the rank's name, then "Lv", and only a name too long for the card scrolls, so nothing is ever cut off in any language or panel size; the tooltip always says it in full.
- **The Level card** at the top of the Goals section: the emblem, "Level 12  Ember", what the next level brings ("Next: Honey name color at Lv 15", or "Lv 15: Honey name color" where room is short), a bar toward the next level with "230 of 242 h to Level 13" (or "230/242 h"), and the thirteen nameplate colors as dots.
  Unlocked dots are clicked to wear, the worn one is ringed, and locked ones wait dimmed with their level in the tooltip.
- **Party**: the rank's emblem before each member's name and the name in their nameplate color, and in the friends list "Lv 12" beside the name (shortened to "12", then to the emblem alone, before the name would be cut); every tooltip names the level and rank.
  Someone on an older app shows neither, never a wrong level.

### Data

- `StudyLevel`, `StudyRank`, `Nameplate` and `StudyStanding` (`Progression/StudyLevel.swift`) and `RankArt` are pure TabbiKitCore.
- `PetProgression` derives the level from the focus total and the save, reports levels gained in a refresh (`Change.levels`), and keeps the picked nameplate.
- `Pet/progression.json` goes to schema 2, additively: `level` (the highest reached), `levelSeen` (the highest seen on the Goals shelf) and `nameplate` (the color picked, absent for plain).
  A version 1 file reads as level 0 never seen, which is what makes the first launch land quietly with the dot.
  The Closet now writes the file whenever anything in it changes, not only when a tier is reached, so every new best focus total is kept.
- Party gets the level and nameplate from the Closet (`ClosetStore.standings`) and shares them in the profile (protocol 3, `docs/party-compatibility.md`).

## Party and Windows

- The Party catalog (`backend/shared/catalog.json`) goes to version 4 with an id for every new item.
  Two reuse ids the catalog already had and nothing drew: `pajamas` for the Cozy Pajamas and `bandana` for the Friendship Bandana.
  The other fourteen are new, and ids are only ever added.
- Older apps drop the ids they do not know and draw the rest of the pet, as the compatibility policy requires.
- A server still on catalog version 3 refuses the newer ids; the app then sends the profile again without them before falling back to version 1, so Party stays online and friends see as much as that server carries.
- The Windows port (`windows/src`) mirrors the items, art mapping, catalog ids, progress tracking, quests and the Goals section, and checks itself against the new golden fixture `shared/fixtures/progression/progression.json` and the re-recorded closet, pets and party fixtures.

## What it does not do

- No loot boxes, no randomness in rewards, nothing sold, no premium currency.
- No streak that can be lost for a badge: every count only grows.
- No shame copy: progress reads as how far along, never as what was missed.
- The shop, its prices and the existing limited items are unchanged.
