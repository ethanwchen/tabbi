# Kits

A kit is a premade setup of NotchDeck for one audience: which tabs are on, in what order, and the defaults they start with.
NotchDeck ships three kits, and anyone can write their own as a small JSON file and share it.

| Kit | Id | Tabs |
| --- | --- | --- |
| Productivity | `productivity` | Now Playing, System, Claude Usage, Today, Ask Claude |
| Medicine (StudyNotch) | `medicine` | Study, Today, Anki, Party, Now Playing, Ask Claude, Closet |
| Student | `student` | Study, Today, Now Playing, Ask Claude, Closet (Anki off) |

The bundled kits live in [`Sources/NotchKitCore/Kits/Bundled`](../Sources/NotchKitCore/Kits/Bundled).
They are good starting points for your own kit.

## Using kits

On first launch, a welcome window asks which kit to start with.
It lists every kit with the tabs it turns on, and preselects the edition's kit (Productivity for NotchDeck, Medicine for StudyNotch).
Closing the window keeps the preselected kit, and the window doesn't come back.
If the chosen kit has [onboarding questions](#onboarding), **Continue** leads to them; **Back** returns to the kit list.
Every question can be skipped, and a row of tab icons previews what the answers turn on or off.
**Start** applies the kit for those answers and adds their starter tasks to Today.

To change kits later, open **Settings > Modules**.
The **Kit** section lets you:

- **Switch kit.** If the kit has onboarding questions, a sheet asks them first, the same way first-run setup does; **Cancel** keeps your current kit. Your tabs change to the new kit's tabs for your answers, and its notch previews, focus sound, study methods and daily study goal replace yours if the kit sets them (a study block already under way keeps going). The kit's starter tasks, plus those your answers add, go on Today, skipping any already on the list. Every other preference stays as it is.
- **Reset to Kit Defaults.** Puts the tabs, notch previews and focus sound back the way the kit ships them, without adding starter tasks again. The button is disabled when nothing would change.
- **Import Kit…** Pick a `.json` kit file. Tabbi checks it and asks the kit's questions if it has any, then shows what the kit will do before anything is saved: the tabs it turns on and off, the permissions those new tabs may ask for, the starter tasks Today gets, whether the closed-notch previews change, and what this version skips (such as a module from a newer release).
If you imported a kit with the same id before, the sheet says so (with both versions, when the files have a `version`), so a re-import never replaces the earlier copy unasked.
**Switch Kit** saves the kit and switches to it, **Add Only** saves it so you can pick it later under Current kit, and **Cancel** saves nothing.
When the kit is the one you use, the buttons read **Apply Update** and **Keep My Tabs**.
- **Remove Kit.** Shown for imported kits only. Tabbi switches back to the default kit.
- **Undo.** After a switch, an import or a removal, the message under the buttons has an Undo button.
It puts back the tabs, notch previews and focus sound you had, removes the starter tasks the switch added that you haven't checked off or renamed, and puts the kit files back as they were (an import is taken out again, a replaced import comes back, a removed kit returns).
Only the last change can be undone; Reset to Kit Defaults is not undoable.

After switching, you can still turn tabs on and off and reorder them below the Kit section.

Imported kits are stored as `<id>.json` in `~/Library/Application Support/NotchDeck/Kits` (or `.../StudyNotch/Kits` for the StudyNotch edition).
Each edition keeps all of its files apart in its own folder: kits, Today's checklist and reviews, the activity log, the study log, the pet and the Claude Usage scan index.
Deleting a file there removes the kit the next time NotchDeck starts.

## A minimal kit

```json
{
  "formatVersion": 1,
  "id": "deep-work",
  "name": "Deep Work",
  "modules": ["planner", "spotify"]
}
```

That is a complete kit.
Everything else is optional.

## The format

A kit file is a JSON object with these fields.

| Field | Required | Type | Meaning |
| --- | --- | --- | --- |
| `formatVersion` | yes | number | Kit format version. Use `1`. |
| `version` | no | string | Your own version of the kit, such as `1.3`, up to 32 characters. Tabbi shows it but never compares it. |
| `requires` | no | object | What the kit can't work without. See [Versioning](#versioning). |
| `id` | yes | string | Stable id: lowercase letters, digits and dashes, such as `law-school`. It is saved in settings, so never change it after sharing the kit. It can't be the id of a kit that ships with this version of Tabbi; a kit that a later version ships under the same id appears beside yours and never replaces it. |
| `name` | yes | string | Name shown in the kit picker. |
| `summary` | no | string | One line shown under the name. |
| `symbol` | no | string | [SF Symbol](https://developer.apple.com/sf-symbols/) name shown beside the name. Defaults to `square.grid.2x2`. |
| `accent` | no | string | Module id whose accent color tints the symbol, such as `planner`. Defaults to the first tab, so set it when your kit opens on the same tab as another kit. |
| `modules` | yes | array | The tabs, in order. At least one. See [Modules](#modules). |
| `defaults` | no | object | Settings the kit starts with. See [Defaults](#defaults). |
| `onboarding` | no | array | Questions first-run setup and Settings ask to tailor the kit. See [Onboarding](#onboarding). |
| `starterTasks` | no | array of strings | Tasks added to Today when the user picks or switches to the kit. Titles already on the list are skipped. |
| `pickerOrder` | no | integer | Bundled kits only: where the kit sits in the picker, lowest first (kits without one follow by id). Imported kits always come after the bundled ones, by name, and ignore it. |

Fields the format doesn't know are ignored with a warning, so a kit written for a newer version still loads and a typo such as `tickers` is easy to spot.

### Modules

Each entry is either a bare module id, or an object to ship a tab switched off:

```json
"modules": ["study", "planner", { "id": "anki", "enabled": false }]
```

A switched-off tab is listed in Settings in that position, ready to turn on.
Modules the kit doesn't mention are also listed in Settings, switched off, after the kit's own tabs.

| Id | Tab |
| --- | --- |
| `spotify` | Now Playing (Spotify and Apple Music) |
| `system` | System (CPU and GPU) |
| `claudeUsage` | Claude Usage |
| `planner` | Today (calendar, tasks, focus timer; with `study` on, it shows the Study timer instead of its own) |
| `claudeAsk` | Ask Claude |
| `focus` | Focus (the same timer as Today's, with focus mode, as its own tab) |
| `study` | Study timer and study methods |
| `anki` | Anki reviews |
| `party` | Study party |
| `closet` | Closet (your study pet) |

The open notch shows up to nine tabs comfortably, and the number keys 1-9 jump to the first nine.

### Defaults

```json
"defaults": {
  "ticker": ["focus", "tasks", "meeting", "nowPlaying", "pet"],
  "theme": "notch",
  "moduleSettings": {
    "study": { "methods": ["pomodoro", "ankiSprint", "questionBlock"], "method": "pomodoro", "dailyGoalMinutes": 240 },
    "focus": { "sounds": [{ "sound": "rain", "level": 0.8 }, { "sound": "brown", "level": 0.4 }] },
    "closet": { "pet": { "breed": "orangeTabby", "name": "Miso" } }
  }
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `ticker` | array of strings | Which live previews the closed notch rotates through: built-in previews and the ids of modules whose highlights should show. Leave it out to show them all. |
| `theme` | string | Theme id. `notch` is the built-in hardware-black theme. |
| `moduleSettings` | object | Settings for individual modules, keyed by module id. Each module reads its own section and declares the keys it accepts, so a typo or a value out of range shows as a warning when importing. |

Only settings that span modules sit directly in `defaults`.
Everything a single module uses lives in that module's section.

Accepted values:

- **Ticker previews:** `meeting`, `nowPlaying`, `focus`, `tasks`, `progress` (shared study goals such as Anki cards left), `party` (party members' pets beside yours while in a study party), `pet` (the study pet, from the Closet module; it naps after 20 minutes without a session), and the id of any module that publishes highlights, such as `claudeUsage` (a usage window above 80%).

Module settings the built-in modules read, all optional:

- **`study`:**
  - `methods`, the study methods the Study timer offers, in order: `pomodoro`, `fiftyTwoSeventeen`, `ultradian`, `flowtime`, `ankiSprint`, `questionBlock`, `custom`. Leave it out to offer them all.
  - `method`, the method the timer starts on. Defaults to the first of `methods`. Today's on-device planner (`planMode` `study`) sizes study blocks on it too.
  - `dailyGoalMinutes`, the minutes a day to aim for (15 to 720, rounded to a quarter hour; 120 when left out). The Study tab shows today's time against it, and Today lists it as a goal.
- **`focus`:** `sounds`, the focus sound mix that Study, Today and Focus play: up to three objects with a `sound` (`brown`, `pink`, `white`, `rain`, `fireplace`, `cafe`) and an optional `level` from 0 to 1 (default 1). An empty list turns the sound off.
- **`closet`:**
  - `pet`, the study pet someone starts with when they have none yet: an optional `breed` (`orangeTabby`, `grayTabby`, `blackCat`, `whiteCat`, `tuxedo`, `calico`, `siamese`, `britishShorthair`, `goldenRetriever`, `labrador`, `frenchBulldog`, `corgi`, `dachshund`, `beagle`) and `name` (up to 16 characters). An existing pet is never changed.
  - `coachLines`, extra lines the study pet's coach can say, keyed by bubble kind: `distraction` (a while in a distracting app), `offerPause` (offering to pause the timer), `idleCheck` (no input for a while) and `autoPause` (the timer was paused while the user was away).
    They join the built-in lines, which name no subject, so a few lines give the coach your kit's flavor.
    Each kind takes a list of lines or a single line.
    Keep them kind and at most 64 characters; longer, blank or non-text entries are skipped without dropping the others.

```json
"moduleSettings": {
  "closet": {
    "coachLines": {
      "distraction": ["The Krebs cycle is saving your seat."],
      "idleCheck": ["Thinking through a vignette? Tap if you're here."]
    }
  }
}
```

Older kits wrote four of these directly in `defaults`: `studyMethods`, `studyMethod`, `focusSounds` and `pet`.
This version still reads them as `study.methods`, `study.method`, `focus.sounds` and `closet.pet`, with a warning on import that names the new place; a key in the module's section wins over its old name.
A later version will stop reading the old names, so move them when you next edit the kit.

Today (`planner`) reads these `moduleSettings.planner` keys, all optional:

| Key | Type | Meaning |
| --- | --- | --- |
| `planMode` | string | `claude` (default) asks the local `claude` CLI to plan the day. `study` plans on device: review blocks for other modules' goals (such as Anki reviews), study blocks the length of the kit's `study.method`, and breaks. |
| `reviewsFirst` | bool | Schedule review blocks in the first free time (default `true`), or last. |
| `eventBufferMinutes` | number | Free time kept clear before and after each calendar event (default 10). |
| `studyBlockTitle` | string | Title for study blocks once every open task has one (default "Study block"). |
| `secondsPerCard` | number | Typical time per review card, for sizing review blocks (default 10). |
| `upNextEvents` | string | What the calendar holds, lowercase, for the Up next card's empty states, such as "lectures, labs, and shifts" (default "meetings and calls"). |
| `dayEndHour` | number | Hour (0-22) when Plan My Day stops planning, such as 21 for evening study (default 18). Planning late still leaves at least two hours, up to 10 pm. |
| `sampleDay` | string | Which realistic day demo mode (`NOTCHDECK_DEMO=1`) shows on Today: `work` (default) or `medicine` (a lecture, a lab, clinical skills, question banks). Never affects real data. |

Switching kits, picking one on first run, and resetting apply the tabs, `ticker` and every module's section: Study's methods and goal, the focus sound, Today's planning settings and the coach's lines.
A field the kit leaves out keeps the user's current setting, and only the sound mix changes in focus mode: the user's volume, playlist and Do Not Disturb shortcuts stay.
A stopped Study timer moves to the kit's `method`; one that is running is never interrupted.

### Onboarding

Questions let one kit fit several kinds of user.
Each answer can switch modules on or off and add starter tasks.

```json
"onboarding": [
  {
    "id": "anki",
    "prompt": "Do you use Anki?",
    "options": [
      { "id": "yes", "label": "Yes, every day", "symbol": "rectangle.stack", "enables": ["anki"] },
      { "id": "no", "label": "Not right now", "symbol": "xmark", "disables": ["anki"] }
    ]
  }
]
```

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Question id, unique within the kit. |
| `prompt` | string | The question. |
| `allowsMultiple` | bool | Whether several answers may be picked. Defaults to `false`. |
| `options` | array | The answers. |
| `options[].id` | string | Answer id, unique within the question. |
| `options[].label` | string | The answer text. |
| `options[].symbol` | string | Optional SF Symbol shown beside the label. |
| `options[].enables` | array of module ids | Tabs this answer switches on. |
| `options[].disables` | array of module ids | Tabs this answer switches off. |
| `options[].tasks` | array of strings | Starter tasks this answer adds to Today. |

Answers are applied in question order, so when two answers disagree about a tab, the later question wins.
The answers are saved with the kit, so **Reset to kit defaults** rebuilds the tabs they chose.
Switching kits in Settings asks the new kit's questions and saves those answers instead, since answers belong to the kit that asked them.
Importing a kit asks its questions the same way before switching to it.
Duplicate and blank starter tasks are dropped.

## Errors and warnings

Tabbi refuses a kit file only when it can't be used at all:

- it isn't valid JSON, or a required field is missing or has the wrong type;
- `formatVersion` is below 1, or newer than this version of Tabbi reads;
- `id` has characters other than lowercase letters, digits and dashes, is longer than 64 characters, or is a bundled kit's id;
- `name` is empty, or `modules` is empty;
- an onboarding question has no answers;
- `requires.modules` names a module this version of Tabbi doesn't have;
- it goes past one of the limits below.

| Limit | Maximum |
| --- | --- |
| File size | 64 KB |
| `modules` entries | 16 |
| Onboarding questions | 10 |
| Answers per question | 8 |
| `starterTasks`, and `tasks` per answer | 20 each |
| `name` and answer labels | 80 characters |
| `summary` and question prompts | 160 characters |
| `version` | 32 characters |
| Task titles | 120 characters |

Everything else is a warning, shown in the import sheet before you switch, and the value is skipped: an unknown module or ticker preview, a module listed twice, a question id used twice, an answer id used twice in one question, a field the format doesn't know (such as `defaults.tickers`), or an old field name that has moved into a module's section (such as `defaults.studyMethods`, which still works for now).
This keeps kits written for newer versions working on older ones.
Each module checks its own `moduleSettings` section against the keys it declares: an unknown key (such as `moduleSettings.planner.reviewsFrist`), a value of the wrong kind or out of range (such as a `dailyGoalMinutes` of 2000, a focus sound `level` above 1, or a study method this version doesn't have, named by its place such as `moduleSettings.study.methods[2]`) is a warning, and the module skips the value or keeps it in range.
A section for a module this version doesn't have is a warning too.
Today, Study, Focus and Closet declare their keys; the other built-in modules read no kit settings, and their sections aren't checked.
Module settings are plain values only: a module never accepts a URL, file path, command or anything else that runs.

## Versioning

`formatVersion` changes only for changes older versions would misread.
New optional fields are added without a version bump, and older versions ignore them with a warning.

`formatVersion` says how to read the file, not what the app must offer.
A kit whose whole point is a module from a newer release lists it in `requires`, so older versions refuse it with a clear message instead of quietly skipping that tab:

```json
"requires": { "modules": ["anki"] }
```

Modules listed only in `modules` stay optional: an older version skips them with a warning.

## For developers

The format is defined by `KitManifest` in [`Sources/NotchKitCore/Kits`](../Sources/NotchKitCore/Kits):

- `KitManifest.decode(from:)` parses and validates a file, including the `KitLimits` caps, and throws a `KitError`.
- `issues(catalog:)` lists the non-fatal `KitIssue` warnings, including fields the format doesn't read (`unknownFields`) and old field names (`KitDefaults.legacyFields`, see `KitLegacyField`), which decoding has already moved into their module's section.
- A module declares its section's keys as `kitSettings: KitSettingsSchema([...])` on its descriptor (types: `bool`, `number` in a range, `text`, `choice`, `lines`, `list` of any type, and `object`) and reads the section with `defaults.settings(for: id)`. `KitValue` takes JSON-like literals, so a test can write `KitDefaults(moduleSettings: ["focus": ["sounds": [["sound": "rain"]]]])`.
- `missingRequirements(catalog:)` lists `requires.modules` the catalog lacks; `ImportedKitStore.inspect(from:catalog:)` refuses such a kit.
- `ImportedKitStore.inspect(from:catalog:)` reads and checks a file without saving it and returns a `KitImportCandidate`, which names the earlier import it would replace; `install(_:)` saves it.
- `KitChangePreview` says what switching to a kit would change for given answers (tabs on and off, new permissions, starter tasks, previews), which the import sheet shows.
- `layout(catalog:answers:)` turns a kit and onboarding answers into a `ModuleLayout`, and `starterTasks(answers:)` collects starter tasks.
- `KitLibrary` holds the bundled kits in picker order plus imported kits, and `ImportedKitStore` keeps imported files on disk.
- Inside the app an imported kit goes by `KitLibrary.importedID(_:)` of its author's id (`imported.deep-work` for `deep-work`), so it never shares an id with a bundled kit; that is the id saved as the active kit, and the file stays `<author id>.json`. Settings from before this rule get the new id through a `SettingsSchema` step.

To ship a new bundled kit, add `<id>.json` (the file name must match its `id`) with a `pickerOrder` to `Sources/NotchKitCore/Kits/Bundled`, and check that its tests report no issues.
`KitLibrary.bundled` lists that folder, so no code changes; `KitLibraryTests` checks that every file loads under its own name and has a picker order.
To render it, run `swift run NotchDeck --snapshot snapshots-<id> --kit <id>`.
A module reads its own `moduleSettings` section with `KitDefaults.settings(for:)` and `KitValue.decode(_:)`, and declares its keys as `ModuleDescriptor.kitSettings` (a `KitSettingsSchema` of booleans, numbers in a range, bounded text, choices, lines and nested objects), which `issues(catalog:)` checks.
