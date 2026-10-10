# Localization

Tabbi ships in English, German, Spanish, French, Japanese, Korean, Brazilian Portuguese and Simplified Chinese.
This page covers how strings are looked up, how to add or change one, and how to add a language.

## How it works

Every user-facing string lives in one String Catalog, `Sources/TabbiKitCore/Localization/Localizable.xcstrings`.
The key is the English text, and each entry holds a comment for translators and one translation per language.
`Package.swift` declares `defaultLocalization: "en"` and lists the catalog as a processed resource of TabbiKitCore, so `swift build` compiles it into `.lproj` folders inside `Tabbi_TabbiKitCore.bundle`.
`scripts/assemble.sh` copies that bundle into `Tabbi.app/Contents/Resources`, and `Resources/Info.plist` lists the same languages in `CFBundleLocalizations`.

Code looks strings up in `Bundle.tabbi` (`L10n` in `Localization/L10n.swift`), never in the main bundle.
Under `swift run` and `swift test` the main bundle has no languages, and a SwiftPM resource bundle follows the main bundle's language.
So `L10n` picks the best of the user's preferred languages itself and hands out that language's `.lproj` folder, and the app, snapshots and tests all read the same strings.

## Writing a string

In SwiftUI, pass the bundle: `Text("Done", bundle: .tabbi)`.
Where an API takes a `String` (a button title, a `.help` tooltip, a model value), use `String(localized: "Done", bundle: .tabbi)`.
A bare `Text("Done")` or `Button("Done")` looks in the main bundle and stays English, so always go through `.tabbi`.
Leave logs, identifiers, kit ids and file names alone.

Interpolate values instead of joining strings, so a translation can move them: `String(localized: "\(count) cards due", bundle: .tabbi)`.
The catalog key is then `%lld cards due`, with `%lld` for integers, `%@` for strings and `%f` for doubles.
Plurals are variations in the catalog (`one`, `other`, and whatever forms a language needs), never `count == 1 ? ... : ...` in code.
Format dates, times, numbers and durations with Foundation formatters (`.formatted()`, `Duration.formatted`, `Date.FormatStyle`), which follow the user's locale, never by gluing a number to a unit.

Add each new string to the catalog with a `comment` that says where it shows and anything a translator could misread (is "Look" a verb or a noun?).
Mark it `"extractionState" : "manual"`, because SwiftPM does not extract keys from code the way Xcode does.
A string that must stay as is in every language (a brand name) gets `"shouldTranslate" : false`.
The build generates a Swift symbol for every key, so it fails on a key with no letters (`%@: %@`) or one that differs from another only in case or punctuation (`Checking` and `Checking…`).
Reuse the existing key where the meaning is the same, and otherwise give the entry `"generatesSymbol" : false`.

`scripts/l10n-add.py strings.json` writes entries for you: it takes the English keys with a comment and one translation per language (an object of plural forms for a plural), adds them with that state and rewrites the catalog sorted, in Xcode's layout.
The script's header shows the input format.

## Tone

Keep translations short, natural and friendly, the way a cozy app talks to a friend.
German and French run long, so prefer the shorter of two good options and check the panel snapshots.
Follow each language's usual app conventions: informal "du" in German, "tu" in French and Spanish, "você" in Brazilian Portuguese, and polite but plain wording in Japanese and Korean.
The writing rules in AGENTS.md hold in every language: no emojis and no em dashes.

## Not translated yet

The onboarding, the tab titles and module summaries, the notch's context menu and header controls, and Settings (General, Tabs, Look, Connections, About and the Account row) are translated.
So are the notifications (focus timer, weekly recap, study reminder, Party), the recap's cheer lines, the Party celebration, and the Closet: its sections and labels, every outfit, accessory, theme, species and fur color name.
The main controls of the Today, Focus, Now Playing, System and AI Usage panels are translated too.
The other tabs' panels (Ask AI, Study, Anki, Party, Schedule), the Today calendar card and the modules' own Settings panes follow tab by tab.
Breed names stay English, because a pet that still goes by its breed is recognized by comparing its saved name to the breed's name.
These stay English on purpose for now:

- long help text and error details,
- the bundled kits' names, summaries and questions,
- the AI provider setup hints in Settings > Connections,
- the connection status headlines and details and the setup sheets in Settings > Connections.

## Checking

`LocalizationTests` runs `StringCatalogAudit` over the catalog, so `swift test` fails when a string lacks a language, a translation is not marked `translated`, or a translation's format specifiers differ from the English.
To see the app in a language, render snapshots with `--locale`:

```sh
swift run Tabbi --snapshot snapshots-de --locale de
TABBI_DEMO=1 swift run Tabbi --snapshot snapshots-ja --locale ja
```

`--locale` sets the language and the region formats for that one run and saves nothing; it works for the live app too.
Look at the panels in every size the renderer draws (`open-compact-*`, `open-*` and the `-large` shots) and fix any truncation.

## Adding a language

1. Add its `.lproj` name (such as `it` or `zh-Hant`) to `L10n.languages` and to `CFBundleLocalizations` in `Resources/Info.plist`.
2. Add a translation of every string in `Localizable.xcstrings`, including each plural form the language uses.
3. Run `swift test`; `LocalizationTests` lists every string still missing.
4. Render snapshots with `--locale <language>` and fix whatever is cut off or reads awkwardly.
