# Localization

Tabbi ships in English, Arabic, German, Spanish, French, Filipino, Japanese, Korean, Brazilian Portuguese, Russian, Simplified Chinese and Traditional Chinese.
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
With `--merge`, it sets only the languages given on strings already in the catalog and keeps everything else, which is how a new language goes in at once.

## Tone

Keep translations short, natural and friendly, the way a cozy app talks to a friend.
German and French run long, so prefer the shorter of two good options and check the panel snapshots.
Follow each language's usual app conventions: informal "du" in German, "tu" in French and Spanish, "você" in Brazilian Portuguese, informal "ты" in Russian, and polite but plain wording in Japanese and Korean.
Russian keeps verbs about the user gender-neutral, with "(а)" where a past tense cannot be avoided, and names the Party tab "Party".
Filipino is the everyday Tagalog of Filipino apps: English loanwords where they are the norm ("timer", "task"), and macOS names (System Settings, Keychain, Do Not Disturb) in English, since macOS has no Filipino localization.
Arabic is friendly Modern Standard Arabic, addresses the user in the masculine singular as macOS does, and fills all six plural forms (zero, one, two, few, many, other); `testArabicPluralsFillAllSixForms` checks 0, 1, 2, 3, 11 and 100.
Traditional Chinese follows Taiwan's conventions and Apple's Taiwan terms, not a conversion of the Simplified Chinese.
A string that names a label elsewhere in the app (a tab, a button, "None") uses that label's translation, word for word.
The writing rules in AGENTS.md hold in every language: no emojis and no em dashes.

## Not translated yet

The onboarding, the tab titles and module summaries, the notch's context menu and header controls, and Settings (General, Tabs, Look, Connections, About and the Account row) are translated.
So are the notifications (focus timer, weekly recap, study reminder, Party), the recap's cheer lines, the Party celebration, and the Closet: its sections and labels, every outfit, accessory, theme, species and fur color name, and the seasonal events and limited items.
The AI consent alert, the AI provider row in Settings > Connections and the age check before Party and Sign in with Apple are translated too; their legal meaning must stay exact.
The main controls of every tab's panel (Today, Focus, Now Playing, System, AI Usage, Ask AI, Study, Anki, Party and Schedule) are translated too, with the calendar card, the focus and study timer labels and the Ask AI setup screen.
Today's Plan my day, Wrap-up and calendar onboarding step are translated as well; the summaries the AI writes there follow its English prompt, so they stay English.
The bundled kits' words for calendar events ("meetings and calls") are looked up in the catalog like the seasonal events (`UpNextEmptyState.localizedEvents`), and a kit's own phrase stays as written.
The modules' own Settings panes (the Options button in Settings > Tabs) are translated: Focus, with the focus sound names and the Shortcuts test results, Now Playing, Ask AI, Pet Coach with the daily study reminder, and Party with its server and moderation messages.
Those panes have a fixed height, so a translated footer must wrap to no more lines than the English one, or the last row is clipped: check them in `settings-tabs-<module>.png`.
App names follow the name macOS gives them in each language (Musik, ミュージック, Быстрые команды), and `MediaSource.names` joins them with the language's own "or".
Settings > Connections shows each connection's status headline and detail, its tooltips and the Party setup sheet in the user's language, and calls Apple's Music app Apple Music there, as its connection row does (`ConnectionApp.displayName`), so no sentence has to decline a translated app name.
The troubleshooter's checks ("Something not working?"), the setup walkthroughs and the screens before a macOS permission prompt are translated too, and so are the support details copied from the troubleshooter, apart from their field labels and state code.
Their steps name macOS and Anki menus and buttons as those apps show them in each language, and Terminal and Shortcuts by their macOS names (Kurzbefehle, ターミナル).
The kit questions and import review in Settings, the weekly recap card and its history, the crash report and update rows, and the Party invite, onboarding and report sheets are translated as well.
The recap card's stat captions ("sessions", "best day") sit under a number drawn on its own, so each is a caption with a singular and a plural key rather than a plural variation; Russian uses the nominative plural there, and the row drops its last stats when the captions run long, so keep them to one or two short words.
The Party invite card (titles, messages, buttons and tooltips from `PartyInviteFlow`) and the "Move to Applications" alert are translated too, and the alert names the Applications folder as macOS does in each language (Programme, アプリケーション).
The desktop widget is translated too: the extension reads the same strings from its own copy of `Tabbi_TabbiKitCore.bundle`, and `scripts/assemble.sh` gives its `Info.plist` the app's `CFBundleLocalizations`.
Its streak count uses the key `%lld streak days` (English "12 days"), because `%lld days` is the Closet chart's dative phrase.
The end-of-session moment is translated too: the headline and points, the bar toward the next unlock, the surprise gift lines and the rare fur names, the closed notch's unlock hint and the Cat wisdom toggle in Settings > General.
Cat wisdom lines are approved English copy in `CatWisdom`, which the schedule hands out by text, so `CatWisdomLine.displayText` looks each one up in the catalog by that English, as the seasonal events are, and `LocalizationTests` fails when a line lacks a language.
A wisdom line shows in at most three lines in the pet's bubble, so check a new translation in the `coach-wisdom-all-*` snapshots, which `TABBI_WISDOM_ALL=1` adds to a `--snapshot` run.
Study method names, taglines and evidence badges stay English in `study-methods.json`, which the Windows port reads too; `StudyMethodInfo.displayName`, `displayTagline` and `StudyEvidenceLevel.label` look them up in the catalog by that English, and `LocalizationTests` fails when one lacks a language.
Arabic writes "52 / 17" as "52/17", since a right-to-left line shows the spaced form as "17 / 52".
Breed names stay English, because a pet that still goes by its breed is recognized by comparing its saved name to the breed's name.
These stay English on purpose for now:

- long help text and error details,
- the bundled kits' names, summaries and questions,
- the study methods' how-to and evidence notes and the theme names, which come from bundled JSON files that the Windows port reads too.

## Right to left

Arabic reads right to left, so Tabbi lays out mirrored in it.
`L10n.isRightToLeft` says whether the chosen language does, and every root Tabbi hosts applies `.tabbiLayoutDirection()` (in `TabbiKit/Design`): the notch, each Settings pane, the pet coach's window and the snapshot renderers.
They do not wait for AppKit, whose direction follows the main bundle's languages and so stays left to right under `swift run`; `--locale ar` also sets AppKit's own direction for that run, so Settings' toolbar mirrors too.
SwiftUI then mirrors stacks, padding and alignment on its own: the tab row starts at the right, list rows put their icon on the right, and back and forward chevrons point the other way.
Use `chevron.backward` and `chevron.forward` for those, never `chevron.left` and `chevron.right`, which keep pointing the same way in a hosting view.
The notch window and its hover zones do not move: both are centered on the camera, and the closed notch's two wings are the same width, so a mirrored notch covers exactly the same area.

Some things keep their direction, through `.fixedLeftToRight()`:

- progress rings fill clockwise from twelve o'clock, like a clock face (`ProgressRing`, Today's shared checks),
- progress bars and sliders fill from the left (Party's shared session, memory pressure, the study sound levels, the unlock bar in the pet's bubble and in the closed notch),
- Now Playing's track bar and transport buttons, whose arrows are media symbols, not reading direction,
- check marks, Ask AI's code blocks, and the pet coach's walk, which leaves the notch to the right on screen while its bubble's words read right to left.

Pixel pets and other images never mirror on their own.
The Closet's activity heatmap and System's charts do mirror: their time runs from right to left, newest at the left, as Arabic calendars and GitHub's Arabic heatmap read.
Text made only of digits and signs takes the paragraph's direction, so a value such as Now Playing's "-2:21" starts with a left-to-right mark (U+200E) to keep its minus in front.
Numbers follow the locale's formatters; with Arabic and the system's default numbering they are Western digits.
Check a right-to-left change in the `--locale ar` snapshots against the English ones.

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

1. Add its `.lproj` name (such as `it`) to `L10n.languages` and to `CFBundleLocalizations` in `Resources/Info.plist`.
2. Add a translation of every string in `Localizable.xcstrings`, including each plural form the language uses, with `scripts/l10n-add.py --merge` (add the language to its `LANGUAGES` too).
   Split across translators, give each one the same glossary (tab names, Party, kit, streak, how to address the user) so the halves agree.
3. Run `scripts/compile-strings.sh`, which writes the language's `.lproj` folder.
4. Run `swift test`; `LocalizationTests` lists every string still missing.
   For a language with more plural forms than English (Russian has one, few and many), add a test that formats a few counts with that locale, as `testRussianPluralsFollowTheLastDigits` does: plural rules follow the formatting locale, not the bundle.
5. Render snapshots with `--locale <language>` and fix whatever is cut off or reads awkwardly.
