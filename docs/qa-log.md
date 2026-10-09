# QA log

What the whole-app quality pass found and fixed, newest first, one sentence per line.

- VoiceOver found nothing to press on the notch: the closed notch now has an "Open Tabbi" button, the camera gap that closes the open panel is a "Close" button (it was an unlabeled shape), and the onboarding progress dots read "Step 1 of 7".
- `swift build -c release` (what `scripts/bundle.sh` runs) warned that `InMemoryDefaults` restated `UserDefaults`' unavailable `Sendable` conformance, while debug builds were silent; the explicit conformance is gone.
- In first-run setup for a kit with many steps (Med School has nine), "Skip Setup" wrapped onto two lines beside the progress dots; the dots now narrow, then drop, so the label always stays on one line.
- `ModuleListTests` failed now and then because every `SettingsStore.ephemeral` (each snapshot run and many tests) shared one on-disk defaults suite, so a concurrent run saving another kit made a Med School store load Essentials tabs; ephemeral stores now use a fresh `InMemoryDefaults` each.
- Settings footers that wrapped set their later lines flush right (a grouped Form trails its footers), and sat 10 pt left of the section headers; every pane now shares one leading, inset `SectionFooter`.
- Baseline: `swift build` has no warnings, `swift test` (1628 XCTest and 49 Swift Testing tests), `scripts/check-style.sh`, and the backend `npm test` and `npm run typecheck` all pass.
