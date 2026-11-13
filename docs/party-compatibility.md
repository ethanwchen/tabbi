# Party compatibility

People on different Tabbi versions, and on the Mac and the Windows app, must always be able to Party and be friends with each other.
This page is the policy every Party change follows, and what each protocol version changed.

## The contract

The wire format is written down once, in [`shared/schemas/party.v1.schema.json`](../shared/schemas/party.v1.schema.json), with the endpoints and errors in [the API doc](study/backend-api.md).
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
| 2 | from this release | Friend requests, every Closet item has a server id (catalog version 2), ten profile colors, the tab badge count in heartbeat replies |
| 3 | from 1.0.6 | The Study Level and nameplate color in the profile (`studyLevel`, `nameplate`), the catalog's `nameplates` list and `limits.maxStudyLevel` |

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

## Study Level across versions

Protocol 3 adds two optional profile fields: `studyLevel`, the Study Level from 0 (`docs/design/progression.md`), and `nameplate`, the id of the name color picked, from the catalog's `nameplates`.
The rank is never sent: it follows from the level, so every app names it in its own language.

- They are display only.
  The server clamps `studyLevel` to 0 through `limits.maxStudyLevel` (999), refuses anything that is not a whole number and any nameplate id the catalog does not list, and never derives anything from them: not points, not the older `level` field, not the leaderboard.
- Replies carry them only for users whose app sent them, so a reply about someone on an older app looks exactly as before, and apps show no level for that person rather than a wrong one.
- Older apps (protocol 1 and 2) never send them and ignore them in replies, so an older and a current app share a party and a friends list as before.
- A current app talking to a server from before protocol 3 has the two fields refused as unknown; it sends the profile again without them (`PartyProfileUpdate.withoutStudyLevel()`), before any of the older catalog fallbacks, so Party stays online and friends there see the pet without a level.
- A value an app cannot read (a string, a level out of range, an unknown nameplate) reads as no level, or as plain, never as an error.
- The catalog's `version` stays as it was: the nameplate ids are their own list, added with the protocol, and like every id they are only ever added.

`backend/test/compat.test.ts` runs a protocol 2 app and a current app as friends in one party, an app with no protocol header beside them, and the server's validation; `PartyAccountTests` runs a current app against a server that refuses the fields; `shared/fixtures/party/party.json` pins the bodies and how replies with and without a level read on the Mac and on Windows.
