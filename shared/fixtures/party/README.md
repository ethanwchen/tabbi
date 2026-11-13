# Party protocol golden fixture

Written by `Tests/TabbiKitCoreTests/PartyProtocolGoldenTests.swift` from `PartyClient` and `PartyPetAppearance`.
It pins the Party wire protocol both apps speak, so a Windows port sends the same profiles and reads the same replies as the Mac app.
`backend/test/compat.test.ts` checks every body and reply in it against `shared/schemas/party.v1.schema.json`, and every id in it against `backend/shared/catalog.json`.
The rules for changing the protocol are in `docs/party-compatibility.md`.

- `protocol` and `protocolHeader`: the protocol version the app sends on every request, and the header it goes in.
- `colorRoles`: the palette roles a profile's `colors` carry, in wire order.
- `outfits` and `accessories`: the server id of each outfit and accessory, keyed by the app's own id.
- `updates`: sample pets (`pet`, in app ids, with the effective color of each role in `colorRoles`) and the pet fields of the `POST /v1/register` or `PATCH /v1/me` body the app sends for each (`body`).
  The last ones also share a Study Level (`standing`: `level` and `nameplate`), which the body carries as `studyLevel`, capped at 999, and `nameplate` (protocol 3).
- `replies`: sample server replies (`json`) with the `$defs` name of their shape in the schema (`schema`), what the app reads from them (`summary`) and the pet it draws for each profile in them, by friend code (`pets`).
  Friend lists and party replies also say the Study Level drawn for each profile (`standings`: "level rank nameplate", or null for none).
  They cover this server, a protocol 1 server (no friend requests, no `status`, no `incomingRequests`) and a newer one (fields and item ids the app does not know yet).

Rules the fixture pins that are easy to miss:

- A pet's outfit goes in `costume` and every worn item in `accessories`; with no outfit, a medical or costume hat also goes in `costume` under its catalog version 1 id (`graduation`, `pirate`, ...), for apps that only read it there.
- Reading a profile, that costume hat comes first, so an item for the same slot in `accessories` wins over it.
- Unknown costumes, accessories and breeds are dropped or fall back (a breed without art draws the drawn breed with the closest body); unknown fields are ignored; nothing fails.
- An add-friend reply without `status` (protocol 1) is a friendship when `added` is true and an existing one otherwise.
- A profile without `studyLevel` shows no level; one whose `studyLevel` is not a whole number from 0 to 999 shows none either, and an unknown `nameplate` draws plain.

A port reads only the inputs (`pet`, `json`) and compares every recorded output.
