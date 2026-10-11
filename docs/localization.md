# Localization

Tabbi ships in English, German, Spanish, French, Japanese, Korean, Brazilian Portuguese and Simplified Chinese.
This page covers how strings are looked up, how to add or change one, and how to add a language.

## How it works

Every user-facing string lives in one String Catalog, `Sources/TabbiKitCore/Localization/Localizable.xcstrings`.
The key is the English text, and each entry holds a comment for translators and one translation per language.
`scripts/compile-strings.sh` compiles the catalog with `xcrun xcstringstool` into one folder per language, `Localization/Strings/<language>.lproj`, each with a `Localizable.strings` and a `Localizable.stringsdict` for the plurals.
Those folders are generated, committed and never edited by hand.
`Package.swift` copies the `Strings` folder as is into `Tabbi_TabbiKitCore.bundle` and keeps the catalog itself out of the build.
SwiftPM is not trusted with the catalog because what it does with one depends on its version: Swift 6.3 copies it uncompiled, so every string and plural stays English, and its older build system lowercases the `.lproj` names it processes.
A copied folder comes out the same on every toolchain, in `swift build`, `swift test` and the release and App Store builds.
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
Lengths of time go through `DurationFormat` ("45 min", "1h 15m", "in 12 min"), whose units are catalog strings, and spans of days through `DateRangeFormat` ("Oct 5 - 11", "5.-11. Okt.", "10月5日～11日").
When a paragraph is built from several translated sentences, join them with `Sentences.join`, which adds no space after a Japanese or Chinese full stop ("。").
Seasonal event names and taglines stay in English in `events.json`, which the Windows port reads too; `SeasonalEvent.displayName` and `displayTagline` look the translation up in the catalog by that English text, and `LocalizationTests` fails when an event lacks one.

Add each new string to the catalog with a `comment` that says where it shows and anything a translator could misread (is "Look" a verb or a noun?).
Mark it `"extractionState" : "manual"`, because SwiftPM does not extract keys from code the way Xcode does.
A string that must stay as is in every language (a brand name) gets `"shouldTranslate" : false`.
Xcode would generate a Swift symbol for every key, and fail on a key with no letters (`%@: %@`) or one that differs from another only in case or punctuation (`Checking` and `Checking…`).
Reuse the existing key where the meaning is the same, and otherwise give the entry `"generatesSymbol" : false`, so the catalog stays valid there too.

After any change to the catalog, run `scripts/compile-strings.sh` and commit the regenerated `Strings` folder with it.
`LocalizationTests` fails until the compiled files hold exactly the catalog's strings and plural forms.

`scripts/l10n-add.py strings.json` writes entries for you: it takes the English keys with a comment and one translation per language (an object of plural forms for a plural), adds them with that state, rewrites the catalog sorted, in Xcode's layout, and runs `scripts/compile-strings.sh`.
The script's header shows the input format.

## Tone

Keep translations short, natural and friendly, the way a cozy app talks to a friend.
German and French run long, so prefer the shorter of two good options and check the panel snapshots.
Follow each language's usual app conventions: informal "du" in German, "tu" in French and Spanish, "você" in Brazilian Portuguese, and polite but plain wording in Japanese and Korean.
The writing rules in AGENTS.md hold in every language: no emojis and no em dashes.

## Not translated yet

The onboarding, the tab titles and module summaries, the notch's context menu and header controls, and Settings (General, Tabs, Look, Connections, About and the Account row) are translated.
So are the notifications (focus timer, weekly recap, study reminder, Party), the recap's cheer lines, the Party celebration, and the Closet: its sections and labels, every outfit, accessory, theme, species and fur color name, and the seasonal events and limited items.
The AI consent alert, the AI provider row in Settings > Connections and the age check before Party and Sign in with Apple are translated too; their legal meaning must stay exact.
The main controls of every tab's panel (Today, Focus, Now Playing, System, AI Usage, Ask AI, Study, Anki, Party and Schedule) are translated too, with the calendar card, the focus and study timer labels and the Ask AI setup screen.
The modules' own Settings panes (the Options button in Settings > Tabs) and the module setup views follow pane by pane.
Breed names stay English, because a pet that still goes by its breed is recognized by comparing its saved name to the breed's name.
These stay English on purpose for now:

- long help text and error details,
- the bundled kits' names, summaries and questions,
- the connection status headlines and details and the setup sheets in Settings > Connections,
- the study method names and taglines and the theme names, which come from bundled JSON files that the Windows port reads too and need a localized field there first,
- the calendar card sentences that name the kit's word for events (a kit field, so it waits for localized kit text).

## Checking

`LocalizationTests` runs `StringCatalogAudit` over the catalog, so `swift test` fails when a string lacks a language, a translation is not marked `translated`, or a translation's format specifiers differ from the English.
It also fails when the compiled `Strings` folder is out of date with the catalog, and when a language's strings or plurals do not load from the built resource bundle.
To see the app in a language, render snapshots with `--locale`:

```sh
swift run Tabbi --snapshot snapshots-de --locale de
TABBI_DEMO=1 swift run Tabbi --snapshot snapshots-ja --locale ja
```

`--locale` sets the language and the region formats for that one run and saves nothing; it works for the live app too.
It takes effect before `NSApplication.shared` is created, because AppKit fixes `Locale.current` for the process from then on: set any later, the strings would change language while dates and numbers stayed in the system's format.
Look at the panels in every size the renderer draws (`open-compact-*`, `open-*` and the `-large` shots) and fix any truncation.

## Adding a language

1. Add its `.lproj` name (such as `it` or `zh-Hant`) to `L10n.languages` and to `CFBundleLocalizations` in `Resources/Info.plist`.
2. Add a translation of every string in `Localizable.xcstrings`, including each plural form the language uses.
3. Run `scripts/compile-strings.sh`, which writes the language's `.lproj` folder.
4. Run `swift test`; `LocalizationTests` lists every string still missing.
5. Render snapshots with `--locale <language>` and fix whatever is cut off or reads awkwardly.
