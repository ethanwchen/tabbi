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

## Price tiers

Every paid price sits inside one tier, and there are gaps between tiers, so the tier always says how long an item takes.

| Tier | Price range | Time at the typical pace | Items |
| --- | --- | --- | --- |
| Free | 0 | owned from the start | Cozy Scarf, Party Hat, Bow Tie (one per playful theme) |
| Starter | 35 to 105 | one day or less | Beanie 35, Round Glasses 50, Ninja Headband 65, Bunny Ears 75, Cool Sunglasses 90, Flower Crown 105 |
| Mid-tier | 210 to 525 | 2 to 5 study days | Frog Hat 210, Scrubs 240, Stethoscope 270, Cowboy Hat 300, Surgical Cap 330, Chef Hat 360, Cozy Hoodie 390, Chunky Headphones 420, Head Mirror 450, Witch Hat 480, Pirate Hat 520 |
| Showpiece | 1050 to 2100 | 2 to 4 study weeks | Tiny Crown 1050, Wizard Hat 1150, White Coat 1250, Superhero Cape 1400, Dinosaur Hoodie 1500, Wizard Robe 1650, Astronaut Helmet 1800, Blindfolded Sorcerer 1950, Graduation Cap 2100 |

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

## Changing prices

Older saves store points earned and spent, not prices, so changing a price never takes away an item someone owns.
When an item becomes free, add its old price to `PetPointsLedger.refundedPrices` so saves that bought it get the points back once.
Pick a new price inside the tier you want the item in, keep it distinct from every other price, and run `swift test`.
