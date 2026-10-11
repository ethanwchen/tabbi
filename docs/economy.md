# The Closet economy

Tabbi's pet earns study points while the user studies, and the Closet sells costume items for those points.
This page explains how points are earned, how prices are set, and how long each item takes.
The rules live in `Sources/TabbiKitCore/Pets/PetUnlocks.swift` (`PetPointsRules`, `PetItem.cost`) and `Sources/TabbiKitCore/Closet/PetEconomy.swift` (`PetEconomy`, `PetPriceTier`).
`PetEconomyTests` checks every rule on this page, so a price change that breaks the economy fails `swift test`.

Points are only ever earned by studying.
No item can be bought with money, and nothing in the shop mentions payments.

## Earning points

| Rule | Points |
| --- | --- |
| Each full focused minute | 1 |
| A session shorter than 5 minutes | 0 (so starting and stopping a timer is not a way to farm points) |
| Finishing a focus block of 25 minutes or more | +10 completion bonus |
| A Party shared session that runs to its end | the same as a finished block, plus a team bonus |
| Party team bonus | +5 per friend who studied along, at most +15 |
| A Party stay cut short (you stepped out, or the host ended it early) | the minutes studied, without either bonus |

So one finished 25 minute block pays 25 + 10 = 35 points.
A block stopped early pays the minutes studied, without the bonus.

## The typical student

Prices are set against a typical study habit, not a heavy one, so a regular student sees steady progress:

- 3 finished 25 minute focus blocks on a study day (75 focused minutes),
- 5 study days a week.

That gives:

- a typical day: 3 x 35 = **105 points**,
- a typical week: 5 x 105 = **525 points**.

A student who studies more (say six blocks a day) simply gets there twice as fast.
A Party session with two friends pays 35 + 10 = 45 points for the same 25 minutes.

Party pays every member the same way, host or not: each member's Tabbi tracks its own stay in the shared session.
A member who joins late is paid from when they joined, and still gets both bonuses if they stay to the end (the completion bonus only for a stay of 25 minutes or more).
A member who steps out is paid the minutes studied until then, and is paid again from when they rejoin.
A stay cut short gets no bonuses, so stepping out and back in is never worth more than staying (for example, leaving at minute 10 of 25 with three friends pays 10 + (15 + 15) = 40, while staying pays 25 + 10 + 15 = 50).
Every stay is also logged as study minutes in the activity log: a finished one as a completed session, a cut-short one as minutes only.

## Price tiers

Every paid price sits inside one tier, and there are gaps between tiers, so the tier always says how long an item takes.

| Tier | Price range | Time at the typical pace | Items |
| --- | --- | --- | --- |
| Free | 0 | owned from the start | Cozy Scarf, Party Hat, Bow Tie (one per playful theme) |
| Starter | 35 to 105 | one day or less | Beanie 35, Round Glasses 50, Ninja Headband 65, Bunny Ears 75, Cool Sunglasses 90, Flower Crown 105 |
| Mid-tier | 210 to 525 | 2 to 5 study days | Frog Hat 210, Scrubs 240, Stethoscope 270, Cowboy Hat 300, Surgical Cap 330, Chef Hat 360, Cozy Hoodie 390, Chunky Headphones 420, Head Mirror 450, Witch Hat 480, Pirate Hat 520 |
| Showpiece | 1050 to 2100 | 2 to 4 study weeks | Tiny Crown 1050, Wizard Hat 1150, White Coat 1250, Superhero Cape 1400, Dinosaur Hoodie 1500, Tiny Rain Cloud 1600, Wizard Robe 1650, Cherry Petals 1700, Sparkle Trail 1750, Astronaut Helmet 1800, Halo 1900, Blindfolded Sorcerer 1950, Angel Wings 2000, King's Cape 2050, Graduation Cap 2100 |

The ranges come straight from the typical pace:

- Starter: 1 to 105 points, at most one typical day.
- Mid-tier: 2 x 105 = 210 to 525 points, two days to one week.
- Showpiece: 2 x 525 = 1050 to 4 x 525 = 2100 points, two to four weeks.

The cheapest paid item (the Beanie, 35) costs exactly one finished focus block, so the first session already buys something.
Every price is distinct, so the shop's cheapest-first order never depends on ids.

## Rules the tests hold

- One typical block is 35 points, a day 105, a week 525.
- The tiers do not overlap and leave gaps between them.
- Every catalog price falls inside a tier.
- The cheapest paid item costs one typical block.
- Each tier has at least three items, and the shop lists cheaper tiers first.
- Starters take one typical day, mid-tier items 2 to 5 days, showpieces 10 to 20 study days.

## What the shop shows

The shop states what the next item asks of you in study time, not just points (`PetEconomy.studyToEarn`).
Up to a day's points it counts focus blocks ("1 focus block", "3 focus blocks"), up to a week's it counts study days ("about 4 study days"), and beyond that weeks ("about 3 weeks").
Each count rounds up at the typical pace above.
The Wardrobe footer says "Next unlock Pirate Hat 140 pts, 4 focus blocks to go", a brand-new pet reads "Beanie unlocks after 1 focus block", and hovering a locked item says how much study is left for it.
The Compact panel drops the study time before anything would clip.

## Changing prices

Older saves store points earned and spent, not prices, so changing a price never takes away an item someone owns.
When an item becomes free, add its old price to `PetPointsLedger.refundedPrices` so saves that bought it get the points back once.
Pick a new price inside the tier you want the item in, keep it distinct from every other price, and run `swift test`.

## Limited edition items

Some items are not in the shop at all.
Points cannot buy them, and they are never tied to money or donations: they are earned from study milestones or granted for free for an event (`PetLimitedEdition` in `TabbiKitCore/Closet/PetLimited.swift`).

| Item | How it is earned | Effect |
| --- | --- | --- |
| Backwards Cap | Granted to everyone who used Tabbi in its launch week (event `launch-week`) | sparkle |
| Flame Headband | 7 days in a row with at least 5 focused minutes each | flicker |
| Golden Laurel | 50 hours (3000 minutes) focused in total | shimmer |
| Team Medal | A Party shared session finished with the user in it | sparkle |
| Founder's Pin | Granted to every Sign in with Apple account made in Tabbi's first 100 days (Founding Member, see below) | sparkle |

Milestones are read from the activity log (`PetMilestoneProgress`): every `focus.completed` record counts its minutes, from any module and whether it finished or not.
A day with 5 or more focused minutes in total is a study day, the same floor that earns points.
The Flame Headband asks for more than the typical habit (5 study days a week), a week without a day off.
The typical student focuses 3 x 25 = 75 minutes a day and 375 a week, so the Golden Laurel takes 3000 / 375 = 8 typical weeks, a long-term goal beyond every showpiece.
Once given, a limited item stays owned (`PetPointsLedger.granted`), even if the log that earned it is gone or a grant is later withdrawn.
On launch the Closet replays the whole activity log into the milestones, so a milestone reached before this feature shipped unlocks quietly, without paying any points again; new records after that unlock with a celebration.
The Closet shows them in their own Limited section beside Wardrobe and Look, each tile with a sparkle badge and, until it is earned, its milestone's progress in its own unit (`PetLimitedProgress`: "4/7 days", "31/50 h", "0/1 session") or Event for a granted item; hovering a tile tries the item on and says how to earn it.
The streak tile counts the current run, since a broken streak starts over, and hours round down, so a tile never shows the goal before the item unlocks.
With Sign in with Apple, limited items travel in the account's `unlocks` like bought items, but come back as granted, so they never count as spent points on another Mac.
Event items come from the Tabbi server: the maintainer grants them per friend code (or to everyone registered in a window, such as the launch week) through the admin routes in [the API doc](study/backend-api.md#limited-edition-grants-maintainer), and `PartyClient.grants()` reads them from `GET /v1/grants`.
That route answers for any friends token, so a signed-out Party identity gets its items as well as a signed-in account.
The app asks it once per launch, wake and identity: Party after it connects (signed in or not), and sync after its first round on a signed-in Mac, so a grant arrives even with Party off.
New items celebrate in the Closet like a milestone unlock.
The server's list of grantable ids is `backend/shared/limited-items.json`, which `PetLimitedTests` holds to `PetLimitedEdition`.

### Founding Member

Everyone who signs in with Apple in the first 100 days after launch is a Founding Member, and so is every account made before the launch (the beta testers).
A Founding Member gets the Founder's Pin, a small gold pin with crimson ribbon tails worn in the neck slot, and a Founding badge.
The badge shows on the Account row in Settings > General, and friends and party members see a small gold seal next to the name in Party; hovering it reads "Founding Member: you joined Tabbi in its first 100 days."
It is free, permanent and never sold, like every limited item.

The window is server configuration: the Worker variable `FOUNDING_LAUNCH` (unix seconds or an ISO 8601 date such as `2026-11-03`, which means midnight UTC) starts it, and it ends 100 days later.
It is set to `2026-10-11`, the 1.0 release, so the window closes at midnight UTC on 2027-01-19.
Until `FOUNDING_LAUNCH` is set, nobody is left out, so every account is founding.
A value the server cannot read grants nothing new rather than everything, since a founding grant cannot be taken back.
What counts is when the account first signed in with Apple (`apple_accounts.created_at`), not when its Party friend code was made, and a Party identity that never signed in is not founding.
The server records the entitlement by itself at every sign-in and whenever the app asks for its grants, so no maintainer run is needed and beta accounts get it on their next launch.
It comes back through `GET /v1/grants` on every Mac and after a reinstall, and stays recorded even if `FOUNDING_LAUNCH` changes later.
Deleting the account deletes it; an account made again after the window is not founding.

### Seasonal events

A year of seasonal events offers limited items earned by focusing while the event runs, never with points or money.
The events are data: `Sources/TabbiKitCore/Events/events.json` (format `shared/schemas/events.v1.schema.json`, read by `SeasonalEventCatalog`).
Each event runs from local midnight of its first day through the end of its last day in the user's time zone, and comes back every year.

| Event | Days | Items (focused minutes during the event) | Headline effect |
| --- | --- | --- | --- |
| Lunar New Year | Chinese calendar month 1, days 1 to 15 | Lion Dance Hat (180) | sparkle |
| Valentine's Week | February 8 to 14 | Heart Glasses (180) | sparkle |
| Cherry Blossom Season | March 20 to April 19 | Sakura Sprig (180) | drift |
| Exam Season | April 27 to June 14 | Study Hoodie (300) | shimmer |
| Summer | June 21 to August 31 | Sunset Shades (300) | sparkle |
| Halloween | October 17 to 31 | Moonlit Witch Hat (90), Pumpkin Hat (300) | flicker |
| Winter Holidays | December 14 to January 6 | Reindeer Antlers (90), Snowy Scarf (300) | sparkle |

Only `focus.completed` minutes that end inside the run count (`SeasonalEventProgress`).
The steepest pace is Valentine's Week, about 26 focused minutes a day; every other event asks for 20 or fewer, well under the typical student's 75, so nobody has to change their habit to earn an item.
An earned item stays owned after the event; one not earned starts over from zero when the event returns the next year.
Each event's last item is its headline item and the only one with an effect.
While an event runs, a small banner at the top of the Closet's Limited section shows its name, last day and line of copy, plus the focus logged toward its next item.
Between events, that shelf shows when the next one starts.
The first time Tabbi runs during an event, the pet beside the closed notch does one little dance (after the notch closes, if a panel is open), and never again for that run (`SeasonalEventGreeting`, saved as `Pet/events.json`).
With `TABBI_DEMO=1`, the Closet reads events at a moment two days into the current or next event, with an hour of focus logged there (`SeasonalEventDemo`), so demos and snapshots always show an event in progress.

## Streak freezes

A study day is a local day with at least 5 focused minutes.
The streak counts study days in a row, and a missed day can be protected by a freeze (`StreakFreezeRules` and `StudyStreak` in `TabbiKitCore/Streaks/StudyStreak.swift`, tested by `StudyStreakTests`).

| Rule | Value |
| --- | --- |
| Free freezes | 1 per calendar week, applied automatically |
| Extra freeze price | 105 points (one typical study day) |
| Extra freezes held at once | at most 2 |

- A missed day while a streak runs uses that week's free freeze first, then the oldest extra freeze, and otherwise ends the streak.
- A frozen day keeps the streak going but does not add to its length.
- Today is never frozen: it still has time for study.
- An extra freeze protects only days after the day it was bought, so it cannot repair a streak that already ended.
- Weeks start on the first weekday of the user's locale, and days follow the Mac's time zone.
- Extra freezes are bought through the points ledger (`PetPointsLedger.buyStreakFreeze`), which keeps the purchase dates in the pet save; which freezes are used is never stored, it is replayed from the study days.

So a regular student who skips one day a week never loses a streak, and a second day off in the same week costs one study day's points.

## Daily study reminder

The streak has one gentle helper: an optional daily notification in the pet's voice, such as "Mochi misses you" with "10 minutes? That keeps your 6-day streak going."
It is off by default, and the user turns it on and picks its time under **Settings > Tabs > Closet > Options** (the Pet Coach pane, Daily reminder section).
The rules live in `StudyReminder` and `StudyReminderSave` (`TabbiKitCore/Streaks/StudyReminder.swift`, tested by `StudyReminderTests` and `StudyReminderSaveTests`), and `StudyReminderScheduler` in the Closet module keeps one pending notification at the planned moment.

- It comes at most once a day, at the chosen time in the Mac's time zone (default 7:00 PM).
- It skips a day the user already studied (a study day as above) or whose Study focus goal is met, and studying before the time withdraws that day's reminder.
- Notification permission is asked only when the user turns the reminder on; if macOS has Tabbi's notifications off, the section points to System Settings.
- It uses the default interruption level, so Focus modes silence it like any other app's notification.
- The pending notification stays when Tabbi quits, so macOS still delivers it, and the next day is planned when Tabbi runs again.
- A time skipped by a daylight saving change moves to the next valid moment.
- The choice is saved in `Pet/reminder.json` in the edition's folder; demo and snapshot runs save and post nothing.

## Entitlements

The server keeps a small entitlements model tied to the Sign in with Apple account (`backend/src/entitlements.ts`, tested by `backend/test/entitlements.test.ts`), so something recorded once is honored on every Mac and in both editions.
The catalog is `backend/shared/entitlements.json`: each entitlement has an id, whether it shows a badge to others, and the limited items it brings.
Founding Member (`founding`) is the first and today the only one.
Each row in the `entitlements` table names the user, the entitlement, its `source` (how it was recorded), an optional `reference`, a start and an optional end.
`GET /v1/grants` returns the maintainer's grants plus the items of the caller's active entitlements, and the ids of those entitlements; friends lists and party rosters carry each profile's `badges`.
In the app, owning the Founder's Pin is what shows the badge on the user's own Account row, and `PartyProfile.badges` shows it on others.

Nothing is for sale, and there are no purchase routes, prices or payment code.
If an optional supporter tier (Tabbi Plus) ever comes, it would plug in here without changing the model.
A purchase would be one more row: its store as `source` (`app-store` for StoreKit in the App Store edition, or the merchant of record, such as Paddle, for the direct download), the store's original transaction or subscription id as `reference`, which a unique index lets be recorded only once, and `ends_at` for a subscription period.
The App Store edition would verify a signed StoreKit transaction (with the account's id as its `appAccountToken`) and the direct edition would take the merchant's signed webhook, and both would write that row for the same account, so a purchase made in one edition is honored in the other.
Such a tier would only add cosmetics and Party hosting perks: no premium currency, no loot boxes, no paid streak freezes and nothing that helps anyone earn points or items faster.
Everything shipped before it, Founding Member included, stays free.
