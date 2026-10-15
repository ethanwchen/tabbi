# Kit golden fixtures

Written by `Tests/TabbiKitCoreTests/KitGoldenTests.swift` from `KitLibrary`, `KitManifest.decode(from:)`, `KitManifest.issues(catalog:)`, `KitManifest.layout(catalog:answers:)`, `AppSettings.apply(_:answers:catalog:)` and `KitChangePreview`.
They pin how a kit file is read, refused, warned about and applied, so a kit imported on Windows behaves as it does on the Mac.

The file has `schema` (`tabbi.kits.golden`) and `version` (1).
Every list of ids keeps the order the Swift code produces; sets (disabled modules, disabled previews, picked answers) are sorted.

- `limits`: `KitLimits` and `currentFormatVersion`, the newest kit format this build reads.
- `catalogs`: the module catalogs kits are checked against, as data, since the Windows port must use the same ones for these runs.
  `builtIn` mirrors the modules Tabbi ships and `appStore` is the same list without `claudeUsage` and `party`, which that edition leaves out (`unavailable`).
  Each module has its `permissions`, its `network` hosts (`isLocal` for a service on the same computer), whether it has closed-notch `highlights`, and the `kitSettings` schema its `moduleSettings` section is checked against (absent means a free-form section).
  A schema node has a `type`: `bool`, `number` (`minimum` to `maximum`, inclusive), `text` (at most `maxLength` characters), `choice` (one of `values`), `lines` (a string, or a list of at most `maxCount` strings, each at most `maxLength` characters), `object` (`fields`, every key optional) or `list` (at most `maxCount` items, each an `item`).
  `tickerKinds` is every closed-notch preview the catalog can show, in rotation order.
- `library`: the files in `Sources/TabbiKitCore/Kits/Bundled`, the bundled kit ids in picker order (`pickerOrder`, then id), the default kit, retired kit ids and their replacements, and `lookups` of `KitLibrary.kit(_:)` (a missing or retired id gives the default kit; an absent `id` is nil).
- `bases`: the settings kits are applied to, each with its `catalog`, `kitID`, `kitAnswers`, layout (`order` and `disabled`, read like a saved layout: unknown ids dropped, missing modules appended switched off), `disabledPreviews` and `themeID`.
  `fresh` has every module on, `essentials` is `fresh` after applying the Essentials kit, `custom` is a hand-tuned setup, and `fresh-appStore` is `fresh` for the `appStore` catalog.
- `cases`: one kit each, with its inputs `name`, `catalog` and `source`, and `applications` (a base name and onboarding `answers`, question id to answer ids).
  `source` is a bundled `file` in `Sources/TabbiKitCore/Kits/Bundled` (read the file itself, never a copy), or inline `json`, padded with spaces (0x20) to `padToBytes` bytes when that is set.
  - `error` is set when the kit is refused: `kind` is the `KitError` case, with `reason` (`malformed`), `version` (`unsupportedVersion`, `invalidFormatVersion`), `value` (the id, question id or exceeded limit) or `modules`, and `message` is the text the import sheet shows.
    A refused kit has no other outputs.
  - `decoded` is the kit as read: absent `summary` is empty, absent `symbol` is `square.grid.2x2`, a bare module id is an enabled entry, `moduleIDs` drops repeats, `resolvedTheme` is the theme the `theme` field names (absent when unknown), `legacyFields` lists old top-level `defaults` fields already moved into `moduleSettings`, and `unknownFields` lists fields the format does not read, as sorted paths.
  - `validation` is what the case's catalog makes of it: the `issues` (warnings, in the order reported, each with `kind`, the fields of its `KitIssue` case and the warning `message`), `missingRequirements`, `reservedID` (the id is a bundled kit's), `accentModule` and `resolvedTicker` (absent keeps the user's previews).
  - `applied` has one result per application: the `chosenAnswers`, the `layout` (`order` and `enabled`), the merged `starterTasks`, the `settings` after applying (kit, answers, disabled previews, theme), whether the base already `baseUsesDefaults` of the kit, and the `preview` of the switch from the base.

Rules the fixture pins that are easy to miss:

- Checks run in a fixed order and the first failure wins: size (bytes, before parsing), JSON shape (the first missing field or wrong type the decoder meets, in field order), `formatVersion` below 1, above the current one, the id, a blank name, no modules, a question without answers, then the first limit in `KitLimits` order.
- Malformed reasons name the path the way the decoder does, so the second module of `modules` is `modules.[1]`, and the top level is `the top level`.
  A number that does not fit a whole-number field (`"formatVersion": 1.5`) reads as `not valid JSON`, like a truncated file.
- Lengths count user-perceived characters (grapheme clusters), so `e` followed by a combining accent counts once.
- A kit id is 1 to 64 characters of `a` to `z`, `0` to `9` and `-`.
- Unknown modules, repeats, unknown previews, an unknown theme, repeated question or answer ids, unknown fields and bad `moduleSettings` values are warnings, never errors.
  A module the catalog leaves out on purpose (`unavailable`) is not warned about, and neither is its preview or its settings section.
- A module listed twice is reported as a repeat each time after the first; an unknown module is reported once, whether it comes from `modules`, an answer or `accent`.
- `moduleSettings` sections are checked in sorted key order, and the keys of an object in sorted order, so warnings read in a stable order.
  A list longer than its `maxCount` is one warning for the whole list; otherwise each bad item is its own warning (`methods[1]`).
- A legacy field still works and is reported; when the kit also sets the new key, the new key wins.
- Applying puts the kit's modules first, in kit order and without unknown ones, then every other module switched off; chosen answers then switch modules on or off in question and option order, so a later answer wins.
  A single-choice question uses only its first picked answer in option order, and answers to unknown questions or options are ignored.
  If nothing is left on, the first module in the order is switched back on.
- An empty `ticker` list turns every preview off; an absent one leaves the user's previews alone.
- Starter tasks are the kit's then the chosen answers', trimmed, without blanks or repeats.
- The change preview lists permissions and off-device hosts only for tabs that turn on and only when no tab on now already needs them; local hosts are never listed.
- `expected` in a settings warning formats numbers the way the Mac does in English (`0`, `1`, `720`).

A port replays only the inputs (catalogs, bases, sources and applications) and compares every recorded output.
