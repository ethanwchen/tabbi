# Party compatibility

People on different Tabbi versions, and on the Mac and the Windows app, must always be able to Party and be friends with each other.
This page is the policy every Party change follows, and what each protocol version changed.

## The contract

The wire format is written down once, in [`shared/schemas/party.v1.schema.json`](../shared/schemas/party.v1.schema.json) and, for Study Crews, [`shared/schemas/crews.v1.schema.json`](../shared/schemas/crews.v1.schema.json), with the endpoints and errors in [the API doc](study/backend-api.md).
[`shared/fixtures/party/party.json`](../shared/fixtures/party/party.json) pins how the Mac app writes profiles and reads sample replies, including replies from older and newer servers.
`PartyProtocolGoldenTests` keeps the Mac app equal to that fixture, `backend/test/compat.test.ts` checks the server's replies and the fixture against the schema, and the Windows port checks itself against the same files.
Nothing in the contract is Mac-only: there are no macOS fields, and Sign in with Apple is an optional way to keep one friend code across devices, never a requirement.

## Versions

Every app request carries a `Tabbi-Protocol` header with the protocol the app speaks, and a request without one is protocol 1.
`GET /` answers with the server's newest `protocol` and the oldest it still serves, `minProtocol`.
The server keeps, per user, the highest protocol any of their apps sent, and an older app on another Mac never lowers it.
The catalog (`backend/shared/catalog.json`) has its own `version`, which counts changes to the item ids.

| Protocol | Apps | What changed |
| --- | --- | --- |
| 1 | up to 1.0.0 | Instant friendships, catalog version 1 |
| 2 | 1.0.1 up to Study Crews | Friend requests, every Closet item has a server id (catalog version 2), ten profile colors, the tab badge count in heartbeat replies |
| 3 | from Study Crews | Study Crews: new `/v1/crews` routes (the weekly board and the all-time Hall of Fame among them) and the `crews` catalog beside `catalog` in `GET /v1/catalog`; no existing route, body or reply changes |

## Rules for every change

1. The server serves every protocol from `minProtocol` up, and `minProtocol` only rises when no supported app still speaks the older one.
2. Replies only gain fields: no field is removed, renamed or changes type, and a field an older app needs stays in every reply it reads.
3. Apps ignore reply fields they do not know, and draw a pet without any item, color or breed they do not know, instead of failing.
4. The server keeps accepting every id and limit an older app sends: catalog ids are only added, and limits only grow.
5. A request body field is only added for apps that send the protocol that introduced it, since the server refuses unknown fields to keep card and deck content out.
6. A feature an older app cannot show must still work for its user, so the server falls back to the older behavior for them (see friend requests below).
7. Every change adds a backend test with an older and a current app in the same friend pair and the same party, and updates the shared schema and fixture.

## Friend requests across versions

Since protocol 2, adding someone by code sends a friend request, and nothing is shared until they accept.
- A protocol 1 app adding someone who has a protocol 2 app sends a request too, which that person accepts or declines; the older app shows the person only once they accept.
- A request to someone whose apps are all protocol 1, which cannot show requests, becomes a friendship at once, as every add was before.
- Two protocol 1 apps keep making instant friendships.
- Someone whose app updates to protocol 2 gets requests from then on, and can still accept one by adding the sender back, as a protocol 1 app does.
- `POST /v1/friends` keeps its reply: `added` is true only when a friendship was made, and the new `status` says `requested` when the request waits.
- `GET /v1/friends` keeps `friends` as it was, and adds `incoming` and `outgoing` requests beside it.

## Pets across versions

Since catalog version 2, `costume` carries the outfit and `accessories` every worn item, hats included, so friends see a pet exactly as it looks in its owner's Closet.
An app on catalog version 1 drops the ids it does not know and still draws the rest of the pet.
When no outfit is worn, the app also puts a medical or costume hat in `costume`, as catalog version 1 apps did, so their users still see it.
A self-hosted server still on catalog version 1 refuses the newer ids, and the app then sends the profile again with only what that catalog has.

Catalog version 4 adds the mastery outfits from the Closet's Goals section (`docs/design/progression.md`): six outfits and eight accessories with new ids, while the Cozy Pajamas and the Friendship Bandana reuse `pajamas` and `bandana`, which catalog version 1 already listed and nothing drew.
Older apps drop the new ids and draw the rest of the pet.
A server still on catalog version 3 refuses them, so the app first sends the profile again without just those ids (`PartyProfileUpdate.forCatalogVersion3()`) and only falls back to what catalog version 1 takes if that is refused too.

Catalog version 5 adds release 7's shop items (`docs/economy.md`): seven outfits and eight accessories with new ids, appended after version 4's.
Older apps drop the new ids and draw the rest of the pet.
A server still on catalog version 4 refuses them, so the app first sends the profile again without just those ids (`PartyProfileUpdate.forCatalogVersion4()`), then without version 4's ids as well, and only then as catalog version 1 takes it, one catalog at a time.

## Crews across versions

Study Crews are protocol 3 and only add: new routes under `/v1/crews`, new tables, and one new field in the `GET /v1/catalog` reply (`crews`, beside the unchanged `catalog`).
- An app on protocol 1 or 2 never calls a crews route, and every route it does call answers exactly as before: friends, friend requests, parties, presence and the leaderboard are untouched, and no Party reply gains a crews field.
- A user can be in a crew on a protocol 3 app and use Party on an older app (another Mac, or Windows before its update) at the same time; the older app just shows no Crew section.
  Their crew membership stays, and their minutes count only from the sessions a protocol 3 app reports.
- The heartbeat reply gains one field, `crews` (my crew and its waiting join requests); older apps ignore it, and nothing else in the reply changes.
- The friends leaderboard keeps summing heartbeat minutes; crews never use them, so an older app's heartbeats neither help nor hurt a crew.
- Crews routes need no `Tabbi-Protocol` header, so a third-party or older client that reaches one gets the same answer as a current app.
- Board lists and Hall of Fame pages have no fixed length (ties share a place), and Hall of Fame cursors are opaque, so an app must read them as given and never build one.
- Crest frame, emblem and color ids, like catalog ids, are only ever added once shipped; an app draws an id it does not know as the first one, so a newer server never breaks an older crews app.
- `backend/test/crews.test.ts` keeps a protocol 1, a protocol 2 and a protocol 3 app friends and in one party while the protocol 3 user is in a crew, and `backend/test/compat.test.ts` checks the shared crews fixture against the schema.
