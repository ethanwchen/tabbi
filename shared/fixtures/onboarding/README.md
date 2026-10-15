# Onboarding golden fixtures

Written by `Tests/TabbiKitCoreTests/OnboardingGoldenTests.swift` from `OnboardingFlow`, `OnboardingSetupStep` and `OnboardingExtra`.
They pin the steps of first-run onboarding, their order and what moves between them, so the Windows port asks the same things in the same order.

The file has `schema` (`tabbi.onboarding.golden`) and `version` (1).

- `setupSteps`: every just-in-time setup step the built-in modules declare, with its `rank`; lower runs first.
- `extras`: every optional extra in the order the extras screen lists them, each with the `module` whose tab must be on for it to show (absent means it always shows).
- `catalogs`: the module catalogs the runs use, as data: module ids in canonical order, each with the setup step ids its descriptor declares.
  `builtIn` mirrors the modules Tabbi ships and `appStore` is the same list without `claudeUsage` and `party` (`unavailable`).
- `kits`: the kits the runs can pick, by `id`: a bundled `file` in `Sources/TabbiKitCore/Kits/Bundled` (read the file itself, never a copy), or inline `json`.
  The kit format and its rules are pinned by the `kits` fixture.
- `runs`: each starts a flow from `setup` and lists `steps`, each an `input` and the flow's `state` after it; `initial` is the state before any input.
  - `setup` has the `catalog`, the starting tabs (`order` and `disabled`, read like a saved layout: unknown ids dropped, missing modules appended switched off, and the first module switched back on if none is), the preselected `kit` and its `answers`, whether the flow `asksName`, and the `extras` it may mention.
  - `input.action` is `choose` (`kit`), `startFromScratch`, `answer` (`answer`, an answer id of the current question), `setEnabled` (`module`, `enabled`), `move` (`from`, offsets into the layout's full `order`, and `to`, with SwiftUI `onMove` semantics), `next` (also how a step is skipped), `back` or `finish`.
  - `state` has the `stage` (`kind` is `name`, `kit`, `question` or `setup` with an `id`, `modules`, `extras` or `finished`), every `stages` the flow will go through for the current choices, `stageIndex` (the stage's position in `stages`, `stages` length once finished, 0 when the stage is no longer listed), `canGoBack`, the chosen `kit`, `startedFromScratch`, the `answers` (sorted), the layout's `order` and `enabled` modules, the `setupSteps` the enabled tabs need, the `currentExtras`, `currentQuestion` and `currentSetupStep`, and `result`, what `setEnabled` returned.

Rules the fixture pins that are easy to miss:

- The stages are the name step (only when asked), the kit step, one per kit question in kit order, the tabs step, one per setup step, and one extras step when any extra applies.
- Setup steps come from the enabled tabs, each step once, by `rank`, ties in tab order; turning a tab on or off changes them at once.
- Choosing a kit answers the kit step from wherever the flow is (even the name step or after finishing) and moves on.
  Choosing a different kit, or any kit after Start from Scratch, starts over from that kit's tabs and clears the answers; choosing the same kit again keeps the user's tab changes and answers.
- Start from Scratch clears the kit and leaves only the first catalog module on, unless the flow already started from scratch, which keeps the tabs.
- Answering a single-choice question picks that answer alone and moves on; clicking the picked answer again clears it and stays.
  A multiple-choice question toggles answers and stays.
  Every answer rebuilds the tabs from the kit and all answers so far, so it replaces tab changes made since.
  An answer id the question does not have keeps the picks (an unanswered question then records an empty list) but still rebuilds the tabs.
  An answer while not on a question changes nothing.
- `setEnabled` refuses (returns false) to turn off the last enabled module, and returns true for a module the catalog does not have without changing the tabs.
- `next` on a stage that is no longer listed (a setup step whose tab was turned off while on it) finishes, and `back` there does nothing.
- `back` does nothing on the first stage or once finished; `next` and `finish` once finished stay finished.
- A kit that repeats a question id lists the question twice, and `next` from it lands on the same question again, so only `finish` gets past it.

A port replays only the inputs (catalogs, kits, setups and inputs) and compares every recorded output.
