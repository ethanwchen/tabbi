# Study Crews golden fixtures

Written by `Tests/TabbiKitCoreTests/CrewsGoldenTests.swift` from `PartyClient+Crews`, `CrewFormat`, `CrewSessionQueue`, `CrewDraftCheck`, `CrewCode` and `CrewIconArt`.
They pin the Study Crews contract both apps follow (docs/design/crews.md), so the Windows port sends the same requests, reads the same replies and draws the same icons as the Mac app.
`backend/test/compat.test.ts` checks every request body and every reply in `crews.json` against `shared/schemas/crews.v1.schema.json`.

`crews.json`:

- `protocol`: the Party protocol the app sends in `Tabbi-Protocol` (3 since Crews).
- `requests`: what the app sends for each call: method, path (with the search query encoded, `+` as `%2B`), and the body with its `$defs` name in the schema (`schema`), or no schema for a body-less route, which sends `{}`.
- `replies`: sample server replies (`json`) with their `$defs` name (`schema`) and what the app reads from them (`summary`), one line per fact.
  The lines are built by `CrewsFixture.summary(of:schema:)`; a port builds the same lines from its own models.
  Replies named `newer server ...` carry ids and fields a newer server could send (an unknown icon, color, laurel, visibility or session status, a Study Level, extra fields), to pin the fallbacks: unknown icons and colors draw as the first, an unknown laurel is none, an unknown visibility is private, an unknown status counts as answered.
  The backend does not check those two against the schema.
- `hours`: minutes to the board's form, `tenths` below 600 minutes and `whole` hours from 600, rounded down.
  The text is the catalog key `%@ h` (the tenths as a number with one decimal in the user's locale) or `%lld h`.
- `remaining`: seconds left in the week to the countdown's form and numbers, rendered with the catalog keys `<1m`, `%lldm`, `%lldh %lldm` and `%lldd %lldh`, inside `Ends in %@`.
- `weeks`: unix times to the crew week that contains them (Monday 00:00 UTC to the next Monday, ISO week id).
- `queue`: finished focus records (start, end, minutes) added one by one, and the sessions the queue then holds to report.
- `drafts`: crew names and descriptions and the problem `CrewDraftCheck` finds, if any.
- `invites`: pasted text or links and the crew invite code found in them, if any.

`icons.json`:

- `canvas`: the icon canvas side.
- `icons`: each icon of `Sources/TabbiKitCore/Pets/PetArt/crew.json` composed as characters, `plain` without and `laurel` with the laurel (the laurel's shape is the same for every tier).
- `palettes`: per crew color and per laurel (`none`, `gold`, `silver`, `bronze`), the hex color of every character.
  A port draws an icon by looking each character up in the palette for its color and laurel.

Regenerate both with `TABBI_RECORD_FIXTURES=1 swift test --filter CrewsGoldenTests` after an intended change, such as a new icon set.
