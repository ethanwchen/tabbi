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
| Apprentice Robe | outfit | 50 finished focus sessions | 2 to 3 weeks |
| Scholar's Robe | outfit | 200 finished focus sessions | 2 to 3 months |
| Sage's Robe (its gold stole glints) | outfit | 600 finished focus sessions | 6 to 7 months |
| Astronaut Suit | outfit | 200 hours focused | about 3 months |
| Starry Cloak (its stars twinkle) | outfit | 500 hours focused | about 8 months |
| Explorer's Hat | head | 4 steady weeks (3 or more study days each) | a month |
| Owl Spectacles | face | 10,000 flashcards reviewed | 3 weeks to 3 months |
| Busy Bee Antennae | head | 200 tasks checked off | 2 to 3 months |
| Sporty Sweatband | head | 50 break moves with the pet | about a month |
| Friendship Bandana | neck | 20 Party sessions with friends | 2 to 3 months |
| Baker's Apron (with a tiny cake) | outfit | 4 different study methods tried | whenever you explore |
| Tiny Lantern (its flame flickers) | aura | 6 months of monthly quests | 6 months or more |

Rules for the art, all held by the existing fit tests:

- Drawn in the `pets.v1` sprite format with the existing palette roles, so one drawing fits every breed and body shape (cat, round cat, Sphynx, Fold, longhair, every dog, the dachshund), sitting, walking, stretching and napping.
- Readable on dark coats: thin lines are at least two pixels or sit on a light fill, and nothing green sits beside the black cat's green eyes.
- No capes and no wings, anywhere (the owner's rule for marketing).
  The Starry Cloak is a cloak worn on the body, closed at the chest with a gold star clasp, and never streams behind.
- Three items are animated on the shared item clock, still under Reduce Motion: the Starry Cloak's twinkle, the Sage's Robe's glint and the Tiny Lantern's flicker; the Blossom Sprout lets a petal go now and then.

The robes are one family tiered by mastery: the Apprentice Robe is plain navy with a white collar, the Scholar's Robe adds a crimson stole, and the Sage's Robe a gold one that catches the light.
Worn with the shop's graduation cap or wizard hat, they make full sets, as the Astronaut Suit does with the shop's Astronaut Helmet and the Baker's Apron with the Chef Hat.

### 2. Badges: a collection with rare tiers

Twelve badges, one per thing the user does, each with four tiers: Bronze, Silver, Gold and Starlight.
The early tiers come within days, so a new user sees the collection light up; Starlight takes months even for heavy users.

| Badge | Bronze | Silver | Gold | Starlight |
| --- | --- | --- | --- | --- |
| Focus time | 10 h | 50 h | 200 h | 500 h |
| Study days | 7 | 30 | 100 | 250 |
| Gentle streak | 7 days | 30 days | 90 days | 180 days |
| Sessions | 10 | 50 | 200 | 600 |
| Flashcards | 500 | 2,500 | 10,000 | 50,000 |
| Tasks | 10 | 50 | 200 | 500 |
| Break moves | 10 | 50 | 150 | 400 |
| Party | 1 | 5 | 20 | 60 |
| Study methods | 2 | 3 | 4 | 6 |
| Steady weeks | 2 | 4 | 12 | 26 |
| Water | 20 glasses | 100 | 300 | 1,000 |
| Monthly quests | 1 month | 3 | 6 | 12 |

That is 48 tiers, and each mastery outfit hangs off one of them, so the Goals section reads as one ladder per habit.

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
- **Titles shown in Party** were left out: showing them to friends needs a new profile field and a Party protocol bump (`docs/party-compatibility.md`, rule 5), which the iPhone app's planned connection (PR #156) also builds on.
  They fit better as a later, separate protocol change.
- **A room or desk for the pet** was left out: the notch has no room for a scene beside the panel, and it would need a new art pipeline.
- **Collectible stickers** were folded into the badges: the same collection, without a second set of art to keep readable at notch size.
- **Seasonal quests** already exist as seasonal events; monthly quests are the year-round, item-free version.

## Where it lives

The Closet gets a seventh section, **Goals** (a rosette), between Limited and Streak:

- A banner at the top for this month's quests: the month, how many of the three are done, a ring for each quest (hover for its goal and progress), and the next unfinished quest on its second line.
- **Outfits to earn**: the sixteen mastery outfits as tiles, greyed until earned, each with its progress ("142/200") and a thin bar.
  Hovering a tile tries the outfit on the big pet and says how to earn it; clicking an earned one wears it or takes it off.
- **Badges**: twelve medallions in their tier's color, each ringed by its progress to the next tier, with four small pips for the tiers earned.
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
