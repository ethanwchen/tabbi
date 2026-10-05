# Kits

A kit is a premade setup of Tabbi for one audience: which tabs are on, in what order, and the defaults they start with.
Tabbi ships two kits, and anyone can write their own as a small JSON file and share it.

| Kit | Id | Tabs |
| --- | --- | --- |
| Essentials | `essentials` | Study (the timer), Today (the to-do list), Now Playing, Ask Claude |
| Med School | `medicine` | Study, Today, Anki, Now Playing, Ask Claude |

Essentials is the default for every new user, and Med School is Essentials plus Anki, with study methods, a daily study goal, a focus sound and a study pet tuned for med school.
Both keep the notch to a few tabs on purpose, and both also turn on the Closet, which opens from the paw at the far right of the header rather than taking a tab.
Every other module (System, Claude Usage, Party, Focus and any added later) starts switched off and waits in the **Add More** library in Settings, one click away.

Earlier versions shipped Productivity (`productivity`) and Student (`student`) kits.
Someone who used either moves to Essentials on their first launch of this version and keeps every tab they had, in their order; only the old kit's onboarding answers are dropped.

The bundled kits live in [`Sources/TabbiKitCore/Kits/Bundled`](../Sources/TabbiKitCore/Kits/Bundled).
They are good starting points for your own kit.

## Using kits

On first launch, the notch opens on a short setup inside the notch itself, with no extra window.
The first step lists every kit with the tabs it turns on, plus **Start from Scratch**, and rings the edition's kit (Essentials for Tabbi).
One tap on a kit moves on to its [onboarding questions](#onboarding), one tap per answer, and a row of tab icons previews what the answers turn on or off.
The next step shows every tab: click one to turn it on or off, and drag to reorder.
After that come only the setup steps the enabled tabs need (the pet, Anki, calendar access, the study method, study parties), each asked once.
Every step can be skipped, and **Skip Setup** keeps what was picked so far, so setup doesn't come back.
The kit is applied when the tab step is done: its tabs, its theme and the starter tasks for those answers.
**Settings > Modules > Run Setup Again** runs the same setup later.

Your tabs and the library are at the top of **Settings > Modules**:

- **Tabs** lists the tabs the notch shows. Drag a row to reorder them; the tab bar, arrow keys, number keys and swipes follow that order. The minus button at the end of a row moves that tab back to the library. The last tab can't be removed.
- **Add More** lists every other module with its icon and a one-line description. **Add** makes it the last tab right away, without reshuffling the tabs you have.

To change kits later, use the **Kit** section below them, which lets you:

- **Switch kit.** If the kit has onboarding questions, a sheet asks them first, the same way first-run setup does; **Cancel** keeps your current kit. Your tabs change to the new kit's tabs for your answers, and its notch previews, focus sound, study methods and daily study goal replace yours if the kit sets them (a study block already under way keeps going). The kit's starter tasks, plus those your answers add, go on Today, skipping any already on the list. Every other preference stays as it is.
- **Reset to Kit Defaults.** Puts the tabs, notch previews and focus sound back the way the kit ships them, without adding starter tasks again. The button is disabled when nothing would change.
- **Import Kit…** Pick a `.json` kit file. Tabbi checks it and asks the kit's questions if it has any, then shows what the kit will do before anything is saved: the tabs it turns on and off, the permissions those new tabs may ask for, the servers off this Mac they connect to (such as Party's friends server), the starter tasks Today gets, whether the closed-notch previews change, and what this version skips (such as a module from a newer release).
If you imported a kit with the same id before, the sheet says so (with both versions, when the files have a `version`), so a re-import never replaces the earlier copy unasked.
**Switch Kit** saves the kit and switches to it, **Add Only** saves it so you can pick it later under Current kit, and **Cancel** saves nothing.
When the kit is the one you use, the buttons read **Apply Update** and **Keep My Tabs**.
- **Remove Kit.** Shown for imported kits only. Tabbi switches back to the default kit.
- **Undo.** After a switch, an import or a removal, the message under the buttons has an Undo button.
It puts back the tabs, notch previews and focus sound you had, removes the starter tasks the switch added that you haven't checked off or renamed, and puts the kit files back as they were (an import is taken out again, a replaced import comes back, a removed kit returns).
Preferences a kit doesn't set, such as the hotkey, hover and launch at login, keep any change you made since the switch.
Undoing **Add Only** or **Keep My Tabs** only takes that import back, since your tabs didn't change.
Only the last change can be undone; Reset to Kit Defaults is not undoable.

After switching, you can still add, remove and reorder tabs above the Kit section.

Imported kits are stored as `<id>.json` in `~/Library/Application Support/Tabbi/Kits`.
Each edition keeps all of its files apart in its own folder: kits, Today's checklist and reviews, the activity log, the study log, the pet and the Claude Usage scan index.
Deleting a file there removes the kit the next time Tabbi starts.

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

A switched-off tab is offered in the Settings **Add More** library, ready to add.
Modules the kit doesn't mention are offered there too, after the kit's switched-off tabs.
So a kit only needs to list the tabs it starts with; the rest stay available.

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
| `closet` | Closet (your study pet; opens from the paw at the far right of the header, or P, instead of a tab) |

The open notch shows up to nine tabs comfortably, and the number keys 1-9 jump to the first nine.

### Defaults

```json
"defaults": {
  "ticker": ["focus", "tasks", "meeting", "nowPlaying", "pet"],
  "theme": "midnight",
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
| `theme` | string | The look of the open panel: `midnight`, `graphite`, `liquidGlass`, `neon`, `monochrome`, `cozy`, `sakura` or `forest`. Applying the kit switches to it, and the user can pick another in Settings. `notch` still works and means `midnight`. An unknown id shows as a warning and keeps the user's theme. |
| `moduleSettings` | object | Settings for individual modules, keyed by module id. Each module reads its own section and declares the keys it accepts, so a typo or a value out of range shows as a warning when importing. |

Only settings that span modules sit directly in `defaults`.
Everything a single module uses lives in that module's section.

Accepted values:

- **Ticker previews:** `meeting`, `nowPlaying`, `focus`, `tasks`, `progress` (shared study goals such as Anki cards left), `party` (party members' pets beside yours while in a study party), `pet` (the study pet, from the Closet module; it naps after 20 minutes without a session), and the id of any module that publishes highlights, such as `claudeUsage` (a usage window above 80%).

Module settings the built-in modules read, all optional:

- **`study`:**
  - `methods`, the study methods the Study timer offers, in order: `pomodoro`, `fiftyTwoSeventeen`, `ultradian`, `flowtime`, `ankiSprint`, `questionBlock`, `custom`, `timer` (a plain countdown with no breaks, 5, 10 or 25 minutes in one click). Leave it out to offer them all.
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
| `sampleDay` | string | Which realistic day demo mode (`TABBI_DEMO=1`) shows on Today: `work` (default) or `medicine` (a lecture, a lab, clinical skills, question banks). Never affects real data. |

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

The format is defined by `KitManifest` in [`Sources/TabbiKitCore/Kits`](../Sources/TabbiKitCore/Kits):

- `KitManifest.decode(from:)` parses and validates a file, including the `KitLimits` caps, and throws a `KitError`.
- `issues(catalog:)` lists the non-fatal `KitIssue` warnings, including fields the format doesn't read (`unknownFields`) and old field names (`KitDefaults.legacyFields`, see `KitLegacyField`), which decoding has already moved into their module's section.
- A module declares its section's keys as `kitSettings: KitSettingsSchema([...])` on its descriptor (types: `bool`, `number` in a range, `text`, `choice`, `lines`, `list` of any type, and `object`) and reads the section with `defaults.settings(for: id)`. `KitValue` takes JSON-like literals, so a test can write `KitDefaults(moduleSettings: ["focus": ["sounds": [["sound": "rain"]]]])`.
- `missingRequirements(catalog:)` lists `requires.modules` the catalog lacks; `ImportedKitStore.inspect(from:catalog:)` refuses such a kit.
- `ImportedKitStore.inspect(from:catalog:)` reads and checks a file without saving it and returns a `KitImportCandidate`, which names the earlier import it would replace; `install(_:)` saves it.
- `KitChangePreview` says what switching to a kit would change for given answers (tabs on and off, new permissions, new hosts off this Mac from each module descriptor's `network`, starter tasks, previews), which the import sheet shows.
- `layout(catalog:answers:)` turns a kit and onboarding answers into a `ModuleLayout`, and `starterTasks(answers:)` collects starter tasks.
- `KitLibrary` holds the bundled kits in picker order plus imported kits, and `ImportedKitStore` keeps imported files on disk.
- Inside the app an imported kit goes by `KitLibrary.importedID(_:)` of its author's id (`imported.deep-work` for `deep-work`), so it never shares an id with a bundled kit; that is the id saved as the active kit, and the file stays `<author id>.json`. Settings from before this rule get the new id through a `SettingsSchema` step.

To retire a bundled kit, delete its file and add its id to `KitLibrary.retiredKitIDs` with the kit that replaces it, plus a `SettingsSchema` step that moves a saved kit id there; never reuse a retired id.

To ship a new bundled kit, add `<id>.json` (the file name must match its `id`) with a `pickerOrder` to `Sources/TabbiKitCore/Kits/Bundled`, and check that its tests report no issues.
`KitLibrary.bundled` lists that folder, so no code changes; `KitLibraryTests` checks that every file loads under its own name and has a picker order.
To render it, run `swift run Tabbi --snapshot snapshots-<id> --kit <id>`.
A module reads its own `moduleSettings` section with `KitDefaults.settings(for:)` and `KitValue.decode(_:)`, and declares its keys as `ModuleDescriptor.kitSettings` (a `KitSettingsSchema` of booleans, numbers in a range, bounded text, choices, lines and nested objects), which `issues(catalog:)` checks.
