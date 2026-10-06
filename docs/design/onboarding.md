# Tabbi onboarding

On the first launch the notch opens on setup and stays open until it ends.
Everything happens inside the notch, with no extra window, and every step can be skipped.
**Run Setup Again** in **Settings > Tabs** (under More options) starts the same flow from the current kit and tabs.

## The flow

1. **Pick a kit.** One card per kit in the library (the bundled Essentials and Med School, plus any imported kit) shows the tabs it turns on, plus **Start from Scratch**, which starts with a single tab.
2. **The kit's questions.** A single-choice question moves on with one tap; a multi-select one (such as Essentials' "What does your day look like?") waits for **Continue**; the answers decide which tabs are on and which starter tasks are added (see [docs/kits.md](../kits.md)).
3. **Tabs.** Turn tabs on or off and drag to reorder them; the last tab can't be turned off.
4. **Setup steps, only for the tabs that are on.** Each module declares the steps it needs in its descriptor's `setup`, each step is asked once, in rank order:

| Step | Asked by | What it does in the notch |
| --- | --- | --- |
| Your pet | Closet | Cat or dog, a breed from sprite tiles, a fur color and a name. |
| Connect Anki | Anki | The Anki tab's own connection guide, checked again while visible, then today's due cards. |
| Calendar access | Today | What Today does with the calendar, one **Allow Access** button, and a live Up next preview. |
| Your timer | Timer | The kit's methods as one-tap tiles, with each method's rhythm and evidence. |
| Study parties | Party | The pet's public name, visibility, the friend code and an Add-a-friend field. |

The kit and tabs are applied as soon as the flow leaves the tab step, so the setup steps build on what was picked.
A module whose step has no view of its own gets a card that points to its tab.
The progress dots count the steps for the current choices, so they change as tabs are turned on or off.

## Where it lives

- `Sources/TabbiKitCore/Onboarding/`: `OnboardingFlow`, the order and skipping rules as plain state, and `OnboardingSetupStep`, tested in `OnboardingFlowTests` (the store in `OnboardingStoreTests`).
- `Sources/Tabbi/Onboarding/`: `OnboardingStore` runs the flow and applies the choices; its views fill the open notch through `NotchContent.takeover`.
- Each setup step's view is the module's own, from `makeSetupView(for:done:)` in its folder (for example `TodayCalendarSetupView`), so a step and the tab share one connection flow.
- [AGENTS.md](../../AGENTS.md#adding-a-module) shows how a new module declares a step.

## Why it works this way

- **Fast and optional.** Apple asks for onboarding that is "fast, fun, and optional" and that teaches through interaction, so each step is one tap and Skip Setup is always there.
- **Ask in context.** Apple asks apps to request data only when the feature that needs it is in use; asking for every permission at first launch is a top complaint about notch apps (NotchNook reviews).
  So a permission is asked for only by a tab that is on, inside a step that first shows what it is for.
- **Few choices at once.** Kits and the tab step let users drop tabs they don't need, which keeps the tab bar short and the permissions few (Hick's law).
- **Delight early.** Choosing and naming a pet is a one-step moment, framed like Finch's pet hatch but without a long questionnaire.
- **Live status.** Like the permission checklists in Bartender and Screen Studio, the Anki and calendar steps show the connection's state as it changes, so nothing needs a relaunch.

## Sources

- Apple HIG, Onboarding: https://developer.apple.com/design/human-interface-guidelines/onboarding
- Apple HIG, Privacy: https://developer.apple.com/design/human-interface-guidelines/privacy
- Bartender permissions: https://macbartender.com/Bartender5/PermissionInfo
- Screen Studio permissions guide: https://screen.studio/guide/setting-up-permissions
- Boring Notch, installation guidance request: https://github.com/TheBoredTeam/boring.notch/issues/905
- NotchNook launch coverage: https://mezha.media/en/2024/07/22/the-notchnook-app-has-been-released-for-macbook-which-makes-the-camera-cutout-on-top-of-the-screen-functional
- Finch design critique: https://ixd.prattsi.org/2025/09/design-critique-finch-ios-app-2/
