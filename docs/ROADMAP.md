# Roadmap

This page describes where NotchDeck is going and why.
Nothing here is a promise or a date; it is the direction that guides day-to-day decisions.

## Vision

NotchDeck is open source and fully customizable.
You choose exactly the tabs and integrations you want: a Pomodoro timer, Anki reviews, your calendar, Spotify, Ask Claude, and more.

One app serves many audiences.
First-run setup offers premade [kits](kits.md), each a starting point for one kind of user, which you can then tweak tab by tab.
A kit can also ship as a branded edition of the same binary, such as StudyNotch for medical students.

Three ideas drive every design decision:

- **Modules, not features.** Every tab is a self-contained module with its own folder, settings, lifecycle and data. Adding one never means editing another.
- **Providers, not wiring.** Modules share data through small protocols (things to do today, calendar events, study progress, focus state). Today, Plan my day and the closed-notch ticker read every provider, so a new module shows up in them without new plumbing.
- **Data before code.** Kits and content packs are plain files anyone can write, review and share. They are the safe path for community contributions.

## Kits

| Kit | Status | For |
| --- | --- | --- |
| Productivity | Shipping | Music, system stats, your day, Claude usage and Ask Claude. NotchDeck's original tabs. |
| Medicine (StudyNotch) | In progress | Medical students: a study timer with evidence-based methods, Anki reviews, study parties, music, Ask Claude and a study pet. |
| Student | In progress | High school and college students: study timer, classes and homework, music and a pet. |
| Tech | Planned | Developers and CS students. |
| Law | Planned | LSAT takers and law students. |
| Casual learner | Planned | Anyone learning for fun: a language, an instrument, a hobby. |

## Future verticals

### Tech

- **LeetCode:** the daily problem, your streak, and a progress source so today's problem appears in Today.
- **Project-based learning:** a project tab that breaks a side project into small daily steps and tracks them as tasks.
- **Teaching concepts:** Ask Claude presets that explain a concept, quiz you on it, or review your solution, all through your local `claude` CLI.

### Law

- **LSAT prep:** practice sets, timed sections and score trends, from whatever resources the user already uses (LawHub, a prep book, a course).
- **Law school:** case briefs and reading assignments as tasks, outlines, and exam countdowns.
- The same study timer and methods as StudyNotch, tuned through kit defaults rather than new code.

### Casual learners

- Language learning streaks, practice reminders and a gentle pet that grows with consistency.
- A light kit with fewer tabs and no pressure: music, a timer, today's one thing.

Each vertical should be mostly a kit plus one or two modules.
If a vertical needs changes to shared code, that is a sign the provider protocols are missing something.

## Content packs

Content packs are data-only bundles a kit or user can install.
They contain no code, so they are safe to share, easy to review, and can't break the app.

Planned pack types:

- **Kits:** the JSON manifests described in [kits.md](kits.md). Already supported, including import from a file.
- **Study methods:** timer presets (focus, break and review lengths, cycles), the same shape as the built-in Pomodoro or 52/17 methods.
- **Sounds:** focus soundscapes as audio files plus a small manifest with names and default levels.
- **Pet sprites:** new breeds, costumes and accessories for the Closet, as sprite sheets plus a manifest.
- **Themes:** color tokens and accents that stay within the design rules (hardware-black notch, one accent per module).

Each pack type gets a versioned manifest, validation with readable warnings (as kits have today), and an import button in Settings.
A shared folder or a simple community index can come later.

**Code plugins come later, if at all.**
Running third-party code inside an app that can control Spotify, read the calendar and call `claude` needs a real security story first: signing, a permission model per plugin, and probably process isolation.
Until then, new modules are added by pull request, where they get reviewed like any other code.

## Sustainability (open core)

These are options under consideration, not decisions.

The code stays MIT licensed and free, including every module and kit in this repository.
Possible paid layers on top:

- **Hosted sync and social features at scale:** study parties, shared streaks and sync across Macs, where running servers costs money.
- **Premium cosmetic packs:** pets, costumes and themes under a separate asset license. The code that renders them stays open.
- **Hosted AI:** for users without their own Claude subscription. Users with the `claude` CLI keep using it for free.
- **A kit marketplace:** with a revenue share for kit and pack creators.
- **Group and cohort licenses:** for study groups, schools and residency programs.
- **Convenience builds:** signed and notarized downloads, or distribution through Setapp.

Constraints to keep in mind:

- **App Store sandboxing conflicts with the AppleScript and Shortcuts integrations** that Now Playing and other modules rely on. A Mac App Store build would lose features, so direct downloads stay the main channel.
- **Protect the name.** A trademark on NotchDeck (and StudyNotch) lets forks exist under the MIT license while keeping the official builds and marketplace recognizable.
- **No telemetry, ever,** paid tier or not. Any hosted feature is opt-in and documented in the README's privacy section.

## Near-term engineering

- Apply the kit's study methods and pet defaults once the Study and Closet modules read them (tabs, ticker previews, focus sounds and starter tasks already apply).
- Move the remaining module-specific settings (e.g. the Claude pane) into `NotchModule.makeSettingsPane()`; Focus already lives in Today's pane.
- Focus as its own module.
- Finish the `NotchKit` split: move the notch controller and root view and the settings infrastructure out of the app target (the notch's open/close and tab state, its tab bar, and focus audio already live in `NotchKit`).
- Real Study, Anki, Party and Closet modules replacing today's previews.
