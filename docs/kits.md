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

- **Switch kit.** If the kit has onboarding questions, a sheet asks them first, the same way first-run setup does; **Cancel** keeps your current kit. Your tabs change to the new kit's tabs for your answers, and its notch previews and focus sound replace yours if the kit sets them. The kit's starter tasks, plus those your answers add, go on Today, skipping any already on the list. Every other preference stays as it is.
- **Reset to Kit Defaults.** Puts the tabs, notch previews and focus sound back the way the kit ships them, without adding starter tasks again. The button is disabled when nothing would change.
- **Import Kit…** Pick a `.json` kit file. NotchDeck checks it, saves a copy, asks the kit's questions if it has any, and switches to it.
If you cancel the questions, the kit stays in the list so you can pick it later. If the kit mentions things this version doesn't know, such as a module from a newer release, you see a warning listing them, and they are skipped.
- **Remove Kit.** Shown for imported kits only. NotchDeck switches back to the default kit.

After switching, you can still turn tabs on and off and reorder them below the Kit section.

Imported kits are stored as `<id>.json` in `~/Library/Application Support/NotchDeck/Kits` (or `.../StudyNotch/Kits` for the StudyNotch edition).
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
| `id` | yes | string | Stable id: lowercase letters, digits and dashes, such as `law-school`. It is saved in settings, so never change it after sharing the kit. It can't be the id of a bundled kit. |
| `name` | yes | string | Name shown in the kit picker. |
| `summary` | no | string | One line shown under the name. |
| `symbol` | no | string | [SF Symbol](https://developer.apple.com/sf-symbols/) name shown beside the name. Defaults to `square.grid.2x2`. |
| `accent` | no | string | Module id whose accent color tints the symbol, such as `planner`. Defaults to the first tab, so set it when your kit opens on the same tab as another kit. |
| `modules` | yes | array | The tabs, in order. At least one. See [Modules](#modules). |
| `defaults` | no | object | Settings the kit starts with. See [Defaults](#defaults). |
| `onboarding` | no | array | Questions first-run setup and Settings ask to tailor the kit. See [Onboarding](#onboarding). |
| `starterTasks` | no | array of strings | Tasks added to Today when the user picks or switches to the kit. Titles already on the list are skipped. |

Unknown top-level fields are ignored, so a kit written for a newer version still loads.

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
| `planner` | Today (calendar, tasks, focus timer) |
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
  "studyMethods": ["pomodoro", "ankiSprint", "questionBlock"],
  "studyMethod": "pomodoro",
  "focusSounds": [{ "sound": "rain", "level": 0.8 }, { "sound": "brown", "level": 0.4 }],
  "ticker": ["focus", "tasks", "meeting", "nowPlaying", "pet"],
  "pet": { "breed": "orangeTabby", "name": "Miso" },
  "theme": "notch",
  "moduleSettings": { "anki": { "deck": "AnKing" } }
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `studyMethods` | array of strings | Study methods the Study timer offers, in order. Leave it out to offer them all. |
| `studyMethod` | string | The method the timer starts on. Defaults to the first of `studyMethods`. |
| `focusSounds` | array of objects | The focus sound mix: `sound` and an optional `level` from 0 to 1 (default 1). |
| `ticker` | array of strings | Which live previews the closed notch rotates through. Leave it out to show them all. |
| `pet` | object | The study pet: optional `breed` and `name`. |
| `theme` | string | Theme id. `notch` is the built-in hardware-black theme. |
| `moduleSettings` | object | Settings for individual modules, keyed by module id. Each module reads its own section, in a shape that module documents. |

Accepted values:

- **Study methods:** `pomodoro`, `fiftyTwoSeventeen`, `ultradian`, `flowtime`, `ankiSprint`, `questionBlock`, `custom`.
- **Focus sounds:** `brown`, `pink`, `white`, `rain`, `fireplace`, `cafe`.
- **Ticker previews:** `meeting`, `nowPlaying`, `focus`, `tasks`, `progress` (shared study goals such as Anki cards left), `claudeUsage`, `pet` (the study pet, from the Closet module; it naps after 20 minutes without a session).
- **Pet breeds:** `orangeTabby`, `grayTabby`, `blackCat`, `whiteCat`, `tuxedo`, `calico`, `siamese`, `britishShorthair`, `goldenRetriever`, `labrador`, `frenchBulldog`, `corgi`, `dachshund`, `beagle`.

Today (`planner`) reads these `moduleSettings.planner` keys, all optional:

| Key | Type | Meaning |
| --- | --- | --- |
| `planMode` | string | `claude` (default) asks the local `claude` CLI to plan the day. `study` plans on device: review blocks for other modules' goals (such as Anki reviews), study blocks of the kit's `studyMethod` length, and breaks. |
| `reviewsFirst` | bool | Schedule review blocks in the first free time (default `true`), or last. |
| `eventBufferMinutes` | number | Free time kept clear before and after each calendar event (default 10). |
| `studyBlockTitle` | string | Title for study blocks once every open task has one (default "Study block"). |
| `secondsPerCard` | number | Typical time per review card, for sizing review blocks (default 10). |
| `upNextEvents` | string | What the calendar holds, lowercase, for the Up next card's empty states, such as "lectures, labs, and shifts" (default "meetings and calls"). |
| `dayEndHour` | number | Hour (0-22) when Plan My Day stops planning, such as 21 for evening study (default 18). Planning late still leaves at least two hours, up to 10 pm. |
| `sampleDay` | string | Which realistic day demo mode (`NOTCHDECK_DEMO=1`) shows on Today: `work` (default) or `medicine` (a lecture, a lab, clinical skills, question banks). Never affects real data. |

Switching kits, picking one on first run, and resetting apply the tabs, `ticker` and `focusSounds`.
A field the kit leaves out keeps the user's current setting, and only the sound mix changes: the user's volume, playlist and Do Not Disturb shortcuts stay.
The other defaults are read and checked, and will be applied as the modules that use them (Study, Closet) land.

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

NotchDeck refuses a kit file only when it can't be used at all:

- it isn't valid JSON, or a required field is missing or has the wrong type;
- `formatVersion` is newer than this version of NotchDeck reads;
- `id` has characters other than lowercase letters, digits and dashes, or is a bundled kit's id;
- `name` is empty, or `modules` is empty.

Everything else is a warning shown after importing, and the value is skipped: an unknown module, study method, focus sound, ticker preview or pet breed, a module listed twice, or a question id used twice.
This keeps kits written for newer versions working on older ones.

## Versioning

`formatVersion` changes only for changes older versions would misread.
New optional fields are added without a version bump, and older versions ignore them.

## For developers

The format is defined by `KitManifest` in [`Sources/NotchKitCore/Kits`](../Sources/NotchKitCore/Kits):

- `KitManifest.decode(from:)` parses and validates a file and throws a `KitError`.
- `issues(catalog:)` lists the non-fatal `KitIssue` warnings.
- `layout(catalog:answers:)` turns a kit and onboarding answers into a `ModuleLayout`, and `starterTasks(answers:)` collects starter tasks.
- `KitLibrary` holds the bundled kits in picker order plus imported kits, and `ImportedKitStore` keeps imported files on disk.

To ship a new bundled kit, add `<id>.json` to `Sources/NotchKitCore/Kits/Bundled`, add the id to `KitLibrary.bundledIDs`, and check that its tests report no issues.
To render it, run `swift run NotchDeck --snapshot snapshots-<id> --kit <id>`.
A module reads its own `moduleSettings` section with `KitDefaults.settings(for:)` and `KitValue.decode(_:)`.
