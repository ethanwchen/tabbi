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
