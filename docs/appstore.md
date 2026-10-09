# Tabbi on the Mac App Store

Tabbi ships in two ways from the same source tree.
The direct download (Developer ID, `scripts/release.sh`) keeps every feature.
The Mac App Store edition (`scripts/release-appstore.sh`) is sandboxed and leaves out what a sandboxed app cannot do or what App Review does not allow.
This page says what differs, how to build and upload it, and what to enter in App Store Connect.

## What differs

| | Direct download | Mac App Store |
| --- | --- | --- |
| Build | `swift build` | `TABBI_APPSTORE=1 swift build` (defines `APPSTORE`) |
| Edition | `tabbi` | `appstore` (`Sources/TabbiKitCore/Editions/BundledEditions/appstore.json`) |
| App Sandbox | no | yes (`packaging/Tabbi-AppStore.entitlements`) |
| Updates | Sparkle | the App Store (Sparkle is not linked at all) |
| Move to Applications, single instance, quarantine checks | InstallHygiene | left out (the App Store installs the app) |
| Claude Usage, Ask Claude | yes | compiled out (they run the `claude` CLI) |
| Plan my day | on the Mac, or with Claude | on the Mac only, no Refine with Claude |
| Wrap up (day review) | local summary, refined by Claude | local summary only |
| Do Not Disturb during focus | through Shortcuts | hidden (it runs `/usr/bin/shortcuts`) |
| Settings > Connections | all rows | no Claude or Do Not Disturb rows |
| Party | yes | left out by the edition until it has moderation |

The compile-time switch sits in these places: `Package.swift` (the define and the Sparkle dependency), `ModuleList.swift` (the Claude modules), `AppDelegate.swift` (updater and install hygiene), `Edition+Current.swift` (the default edition) and a few spots in Settings and the snapshot renderer.
Everything else follows the edition at run time.
`Edition.excludedModules` removes modules from the catalog, so kits, onboarding, Settings > Tabs and the closed-notch ticker never offer them, and a kit that lists one (Essentials lists Ask Claude) still applies without a warning.
`Edition.runsLocalTools` is false for the App Store edition, which hides every feature that would start a helper program.

Party comes back by removing `"party"` from `excludedModules` in `appstore.json`, once it has reporting, blocking and a name filter (App Review guideline 1.2).

## Build and upload

1. Create the certificates and the profile once (next section).
2. Save the profile as `packaging/Tabbi-AppStore.provisionprofile` (gitignored), or point `APPSTORE_PROFILE` at it.
3. Run `scripts/release-appstore.sh` from a full clone (the build number is the commit count).
4. Check the package: `xcrun altool --validate-app -f build/appstore/Tabbi-<version>.pkg -t macos --apiKey <key> --apiIssuer <issuer>`.
5. Upload it with Transporter, or with `xcrun altool --upload-app` and the same arguments.

The script never uploads anything.
It stops before building, with numbered setup steps, when a signing identity or the profile is missing, expired, for another app or not an App Store profile.
When the keychain holds more than one matching identity, set `APPSTORE_IDENTITY` and `INSTALLER_IDENTITY`.
The version comes from `CFBundleShortVersionString` in `Resources/Info.plist`; raise it for each release that goes to review.

`scripts/release-appstore.sh --adhoc` needs no certificates.
It ad-hoc signs the app with the sandbox entitlements, so it runs sandboxed on this Mac, and makes an unsigned package that the App Store does not accept.

## Certificates and profiles

The team is the Individual team `B9VRALHV8S`, and the bundle id is `dev.tabbi.Tabbi` (the same as the direct download).
In the Apple Developer portal, under Certificates, Identifiers & Profiles:

1. Identifiers: make sure the App ID `dev.tabbi.Tabbi` exists (explicit, macOS).
   Turn on Sign in with Apple there once the sync feature is in the App Store build.
2. Certificates: create an **Apple Distribution** certificate (it signs the app) and a **Mac Installer Distribution** certificate (it signs the package; Keychain Access shows it as "3rd Party Mac Developer Installer").
   Install both in the login keychain with their private keys.
3. Profiles: create a **Mac App Store Connect** distribution profile for `dev.tabbi.Tabbi` with the Apple Distribution certificate, download it, and save it as `packaging/Tabbi-AppStore.provisionprofile`.
4. App Store Connect: create the app (platform macOS, bundle id `dev.tabbi.Tabbi`, SKU `tabbi-mac`), and an API key under Users and Access > Integrations for `altool`.

When sync ships in this build, add `com.apple.developer.applesignin` (an array with `Default`) to `packaging/Tabbi-AppStore.entitlements` and download the profile again after turning on the capability.

## Sandbox check

Run this after changing entitlements, the edition or anything that touches files, processes or other apps.

1. `scripts/release-appstore.sh --adhoc`
2. Start the app from Terminal so it does not activate another installed copy: `build/appstore/Tabbi.app/Contents/MacOS/Tabbi`.
3. In a second Terminal, watch for denials: `/usr/bin/log stream --predicate 'sender == "Sandbox" AND eventMessage CONTAINS "Tabbi"'` (in zsh, plain `log` is a builtin).
4. Open the notch, visit every tab, start and stop a focus session, open Music or Spotify, and open Settings.
5. Data lands in `~/Library/Containers/dev.tabbi.Tabbi/Data/Library/Application Support/Tabbi`.

The last check (October 2026) found no sandbox denials and no process launches.
Clicking the notch opened the panel and moving the pointer away closed it (global mouse monitors work), the hotkey uses `RegisterEventHotKey` (no permission needed), Today read the calendar through EventKit, and Now Playing reached Music through the Apple Events exception (macOS then asks for Automation permission, as it does for the direct download).

## App Store Connect

- Name: Tabbi
- Category: Productivity (secondary: Education)
- Privacy Policy URL: https://tabbinotch.com/privacy
- Support URL: https://tabbinotch.com/support
- Marketing URL: https://tabbinotch.com
- Copyright: the maintainer's name and the year
- Age rating: 4+ (no user-generated content while Party is out)
- Pricing: free
- Export compliance: the build sets `ITSAppUsesNonExemptEncryption` to `NO` (it only uses HTTPS through the system)

### Privacy nutrition label (draft)

With Party and sync left out, the App Store edition collects no data, so the answer is **Data Not Collected**.

- Calendar events, tasks, focus history, study tallies and the pet's save stay on the Mac in the app's container.
- Album artwork is loaded from the music service's image host (`i.scdn.co`) without any identifier of the user.
- AnkiConnect is reached on `localhost` only.
- There is no analytics, advertising or crash reporting.

When sync ships in this build, revisit the label: an email address or Apple user id (Contact Info, Identifiers) linked to the user for App Functionality, and the synced pet and progress (Other User Content) linked to the user for App Functionality, none used for tracking.

### Notes for the reviewer (draft)

> Tabbi turns the area around the MacBook notch into a small panel of tabs: a focus timer, today's tasks and calendar, now playing, study tools and a pixel pet.
> There is no Dock icon and no window at launch; the app lives at the top center of the screen.
> To open the panel, click the black notch area at the top center of the screen, or press Control-Option-Space.
> On a Mac without a notch, Tabbi draws a small black pill at the top center of the menu bar; click it the same way.
> The first launch shows a short setup inside the panel (pick a kit, then tabs).
> Settings open from the gear button at the right of the panel's header.
> Calendar access is optional and only used to show today's events in the Today tab.
> Automation access to Music or Spotify is optional and only used to show and control what is playing.
> No account or sign-in is needed, and the app sends no data anywhere.

### Listing copy (draft)

The name and keywords avoid third-party trademarks; the description may name compatible apps where needed to explain a feature.

- Name: Tabbi
- Subtitle: Focus timer and tasks in your notch
- Promotional text: A tiny panel at the top of your screen for today's tasks, a focus timer, your music and a pixel cat who studies with you.
- Keywords: focus,pomodoro,timer,tasks,todo,planner,study,notch,productivity,pet,calendar,flashcards

Description:

> Tabbi puts a small, quiet panel in your MacBook's notch.
> Click the notch (or press Control-Option-Space) and your day is right there, then it tucks away again.
>
> Today: your tasks, today's calendar events and a simple plan for the day.
> Focus: a Pomodoro timer with calm background sounds.
> Study: sessions, streaks and points for exams and classes, with optional Anki review counts.
> Now Playing: see and control what is playing in Music or Spotify.
> System: battery, CPU and memory at a glance.
> A pixel cat keeps you company, earns outfits as you focus and naps when you take a break.
>
> Kits set Tabbi up for you in one step: Essentials for everyday work and Med School for long study days.
> Pick only the tabs you want, in the order you want.
>
> Private by design: everything stays on your Mac, and there is no account, no tracking and no ads.
> Macs without a notch get a small virtual one at the top of the screen.

### Screenshots

The five screenshots in [`appstore/screenshots`](appstore/screenshots) are 2880x1800 opaque JPEGs, a size App Store Connect accepts for Mac apps.
Upload them in file name order: Today, Study, the pet's closet, Focus and Schedule.
Each shows the open notch panel from the App Store edition's demo data on a soft wallpaper, with a short caption below it.
Now Playing is left out on purpose, since its panel shows another company's app badge.

To render them again after a UI change, run:

```sh
swift docs/appstore/make-screenshots.swift
```

The script renders demo snapshots of the Essentials and Med School kits with `--edition appstore`, so no tab the App Store build leaves out can appear, then composes the screenshots.
To compose from snapshot folders you already rendered, pass the Essentials folder and then the Med School folder.
