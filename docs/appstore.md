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
| Party | yes | left out by the edition for now (one switch turns it on) |
| Sign in with Apple and sync ([sync.md](sync.md)) | yes, with the Developer ID profile | yes, with the App Store profile (not in `--adhoc` builds) |

The compile-time switch sits in these places: `Package.swift` (the define and the Sparkle dependency), `ModuleList.swift` (the Claude modules), `AppDelegate.swift` (updater and install hygiene), `Edition+Current.swift` (the default edition) and a few spots in Settings and the snapshot renderer.
Everything else follows the edition at run time.
`Edition.excludedModules` removes modules from the catalog, so kits, onboarding, Settings > Tabs and the closed-notch ticker never offer them, and a kit that lists one (Essentials lists Ask Claude) still applies without a warning.
`Edition.runsLocalTools` is false for the App Store edition, which hides every feature that would start a helper program.

Party comes back by removing `"party"` from `excludedModules` in `appstore.json`.
Party now has reporting, blocking and a name filter (App Review guideline 1.2), so the remaining work before turning it on is a sandboxed run of Party, a privacy label that declares the display name and party activity it shares, and reviewer notes on how to report and block someone.

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

1. Identifiers: make sure the App ID `dev.tabbi.Tabbi` exists (explicit, macOS) and has Sign in with Apple turned on (the same capability the direct download uses, see [sync.md](sync.md)).
2. Certificates: create an **Apple Distribution** certificate (it signs the app) and a **Mac Installer Distribution** certificate (it signs the package; Keychain Access shows it as "3rd Party Mac Developer Installer").
   Install both in the login keychain with their private keys.
3. Profiles: create a **Mac App Store Connect** distribution profile for `dev.tabbi.Tabbi` with the Apple Distribution certificate, download it, and save it as `packaging/Tabbi-AppStore.provisionprofile`.
   Create it after turning on Sign in with Apple, or download it again afterwards: the script refuses a profile that does not grant the capability.
   Do the same for the widget extension's App ID `dev.tabbi.Tabbi.Widget` and save that profile as `packaging/TabbiWidget-AppStore.provisionprofile` ([widget.md](widget.md)).
4. App Store Connect: create the app (platform macOS, bundle id `dev.tabbi.Tabbi`, SKU `tabbi-mac`), and an API key under Users and Access > Integrations for `altool`.

`packaging/Tabbi-AppStore.entitlements` claims `com.apple.developer.applesignin`.
The script signs with it for the App Store and leaves it out of `--adhoc` builds, since macOS does not launch an app that claims it without a matching profile; there the Account row in Settings > General says that sign-in is not available in this build.

## Sandbox check

Run this after changing entitlements, the edition or anything that touches files, processes or other apps.

1. `scripts/release-appstore.sh --adhoc`
2. Start the app from Terminal so it does not activate another installed copy: `build/appstore/Tabbi.app/Contents/MacOS/Tabbi`.
3. In a second Terminal, watch for denials: `/usr/bin/log stream --predicate 'sender == "Sandbox" AND eventMessage CONTAINS "Tabbi"'` (in zsh, plain `log` is a builtin).
4. Open the notch, visit every tab, start and stop a focus session, open Music or Spotify, and open Settings.
5. Data lands in `~/Library/Containers/dev.tabbi.Tabbi/Data/Library/Application Support/Tabbi`.

Sign in with Apple needs the signed build: install the package from a TestFlight build to try it sandboxed.

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
- Sign-in information: not required (signing in is optional and only syncs the pet)
- Pricing: free
- Export compliance: the build sets `ITSAppUsesNonExemptEncryption` to `NO` (it only uses HTTPS through the system)

### Privacy nutrition label (draft)

Without an account, nothing leaves the Mac.
The optional Sign in with Apple account stores a little on the Tabbi server ([backend/PRIVACY.md](../backend/PRIVACY.md) lists all of it), so the label declares:

- Identifiers > User ID: Apple's app-specific user id, linked to the user, used for App Functionality.
- User Content > Other User Content: the synced pet (look, name, outfit), its points and unlocks, the days the user studied and the longest streak, linked to the user, used for App Functionality.
- Nothing is used for tracking, and no other data type is collected (the server never stores the name or email from Apple).

What the label does not need to list:

- Calendar events, tasks, focus history and study tallies stay on the Mac in the app's container.
- Album artwork is loaded from the music service's image host (`i.scdn.co`) without any identifier of the user.
- AnkiConnect is reached on `localhost` only.
- There is no analytics, advertising or crash reporting.

When Party comes back, add its display name and study presence (Name or Other User Content, and Product Interaction) to the label.

### Notes for the reviewer (draft)

> Tabbi turns the area around the MacBook notch into a small panel of tabs: a focus timer, today's tasks and calendar, now playing, study tools and a pixel pet.
> There is no Dock icon and no window at launch; the app lives at the top center of the screen.
> To open the panel, click the black notch area at the top center of the screen, or press Control-Option-Space.
> On a Mac without a notch, Tabbi draws a small black pill at the top center of the menu bar; click it the same way.
> The first launch shows a short setup inside the panel (pick a kit, then tabs).
> Settings open from the gear button at the right of the panel's header.
> Calendar access is optional and only used to show today's events in the Today tab.
> Automation access to Music or Spotify is optional and only used to show and control what is playing.
> No account is needed.
> Signing in with Apple (Settings > General > Account) is optional and only syncs the pet and study streaks between the user's Macs.
> Delete Account in the same place deletes everything the server holds and revokes the Sign in with Apple grant.

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
> Private by design: no tracking, no ads, and no account needed.
> Sign in with Apple if you want your pet and streaks on all your Macs; everything else stays on your Mac.
> Macs without a notch get a small virtual one at the top of the screen.

### Screenshots

The screenshots in [`appstore/screenshots`](appstore/screenshots) are 2880x1800 (16:10) flattened 8-bit sRGB PNGs with no alpha, as App Store Connect requires for Mac apps.
Upload them in file name order:

1. `1-cozy`: "Your notch, but cozy", the Timer tab with the tab bar, the pet in a hat and the Deep focus chip.
2. `2-focus`: "Focus in one glance", the Focus timer running with its ring partly done.
3. `3-today`: "Today, right up top", 4 to-dos (2 checked) and 2 events, on the dark canvas.
4. `4-closet`: "Earn points, dress your cat", the Closet wardrobe with points.
5. `5-flashcards`: "Flashcards between tasks", the flashcards tab (Party is left out of the App Store edition, so it has no shot).
6. `6-music`: "Music without switching apps", Now Playing with original artwork.
7. `7-free`: "Free and open source", the tab picker from first-run setup.

All names, songs and decks in the demo data are fictional, and no shot shows a date or a price.
[`appstore/screenshots/small`](appstore/screenshots/small) holds a 1280x800 copy of each, only to check that captions and panels still read at small sizes; do not upload those.

Every shot shares one layout: a cream canvas with a soft golden glow, a one-line caption and a subcaption in Fredoka, and the top edge of a generic screen (an original warm wallpaper, a menu bar strip and a black notch) with the real open Tabbi panel hanging from it.
No device bezel is drawn, since Apple only allows its own unmodified device frames.
A small original pixel cat sits in a lower corner of the wallpaper.
The Today shot uses the dark variant of the canvas.

The panels are App Store edition demo snapshots rendered at 2.7 pixels per point with a transparent background, so they are placed 1:1 and stay crisp.
Fredoka is bundled in [`appstore/fonts`](appstore/fonts) with its SIL Open Font License.

To render them and the App Preview again after a UI change, run:

```sh
swift docs/appstore/make-media.swift
```

The script renders demo snapshots of the Essentials and Med School kits with `--edition appstore --scale 2.7 --transparent`, so no tab the App Store build leaves out can appear, then composes the screenshots and the preview.
To compose from snapshot folders you already rendered that way, pass the Essentials folder and then the Med School folder.
The clocks in the demo panels are live, so every run changes the shots that show a timer; commit only the images you meant to change.

### App Preview

[`appstore/preview/tabbi-app-preview.mp4`](appstore/preview/tabbi-app-preview.mp4) is the App Preview: 22.8 seconds of 1920x1080 H.264 (High profile, 30 fps) with a silent stereo AAC track, since App Store Connect expects previews to carry audio.
It is made only from app renders, on the same canvas, screen strip and captions as the screenshots, with no hands or hardware:

1. The closed notch, then the panel opens out of it within the first 2 seconds ("Your notch, but cozy").
2. The focus timer ("Focus in one glance").
3. Today with its to-dos and events ("Today, right up top").
4. The Closet wardrobe ("Earn points, dress your cat").
5. Flashcards ("Flashcards between tasks").
6. An end card with the app icon and name.

Each caption holds for at least 3 seconds.
Between scenes the caption and panel fade out to the bare backdrop and the next ones fade in, so two captions never overlap.
The Today scene uses the light canvas, so the background does not flash between scenes.
There is no music bed: no track with a clear license was available, so the preview stays silent.
`swift docs/appstore/make-media.swift` writes it together with the screenshots; the scenes are composed at the screenshots' pixel scale and scaled down, so the panel is never scaled up.
