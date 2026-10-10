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
| AI Usage | yes | compiled out (it reads the `claude` CLI and Codex logs) |
| AI providers (Settings > Connections > AI) | Claude Code, Codex and Gemini CLI, the Anthropic, OpenAI and Gemini APIs, Ollama | the Anthropic, OpenAI and Gemini APIs with the user's key, and Ollama on `localhost` |
| Ask AI | yes | yes, through the API providers and Ollama |
| Plan my day and Refine | on the Mac, or with the picked AI | the same, with an API provider or Ollama |
| Wrap up (day review) | local summary, refined by the picked AI | the same, with an API provider or Ollama |
| Now Playing | Spotify, Music, and SoundCloud in Safari or Chrome (opt-in) | Spotify and Music (a sandboxed app cannot script browsers) |
| Do Not Disturb during focus | through Shortcuts | hidden (it runs `/usr/bin/shortcuts`) |
| Settings > Connections | all rows | no command line tools in the AI picker, no Claude or Do Not Disturb rows |
| Party | yes | left out by the edition for now (one switch turns it on) |
| Crash reports | asks after a crash, then sends to `POST /v1/crashes` with consent | none of its own (Apple's crash reports, which users share through macOS, already cover it) |
| Sign in with Apple and sync ([sync.md](sync.md)) | yes, on the web (no profile needed) | yes, natively with the App Store profile (on the web in `--adhoc` builds) |

The compile-time switch sits in these places: `Package.swift` (the define and the Sparkle dependency), `ModuleList.swift` (AI Usage), `AIService.swift` (the sandboxed provider list), `AppDelegate.swift` (updater and install hygiene), `Edition+Current.swift` (the default edition) and a few spots in Settings and the snapshot renderer.
Everything else follows the edition at run time.
`Edition.excludedModules` removes modules from the catalog, so kits, onboarding, Settings > Tabs and the closed-notch ticker never offer them, and a kit that lists one still applies without a warning.
`Edition.runsLocalTools` is false for the App Store edition, which hides every feature that would start a helper program.

### AI in the sandbox

A sandboxed app cannot start the `claude`, `codex` or `gemini` command line tools, so the AI picker in Settings > Connections offers only the providers that need no helper program: the Anthropic, OpenAI and Gemini APIs (the user pastes their own key, which Tabbi keeps in the Keychain) and Ollama on `localhost:11434` (free and offline).
All of them go through the `network.client` entitlement the app already has.
A command line tool saved by a direct download counts as no choice here, so Ask shows its setup state instead of failing.
Nothing is sent anywhere until the user picks a provider: a fresh install starts with None, Ask shows "Choose an AI to ask questions", and Plan my day and Wrap up stay on the Mac.
Picking a provider that sends data off the Mac (every one but Ollama) first shows a one-time consent alert naming the company and what each feature sends (Guideline 5.1.2(i)); the permission is saved per provider in `AISettings.consented`.

Party comes back by removing `"party"` from `excludedModules` in `appstore.json`.
Party now has reporting, blocking, a name filter (App Review guideline 1.2) and an age check that keeps it off for anyone under 13, so the remaining work before turning it on is a sandboxed run of Party, a privacy label that declares the display name and party activity it shares, a new age rating answer (see App information), and reviewer notes on the age check and how to report and block someone (see Notes for the reviewer).

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

Everything in this section is paste-ready for the App Store edition as it builds today: AI Usage, the command line AI tools, SoundCloud, Do Not Disturb and Party are not in it, so the copy below does not promise them (the keyword note explains why `party` is not a keyword).
Character counts were checked with Python `len`, and every field is plain ASCII, so bytes equal characters.
The listing copy comes from the listing research (October 2026), with only the facts that did not match the App Store build changed.

### App information

- Name: `Tabbi: Notch Focus Timer` (24 of 30)
- Subtitle: `Pomodoro, To-Do & Study Pet` (27 of 30)
- Category: Productivity (secondary: Education)
- Privacy Policy URL: https://tabbinotch.com/privacy
- Support URL: https://tabbinotch.com/support
- Marketing URL: https://tabbinotch.com
- Copyright: the maintainer's name and the year
- Age rating: 4+ (no user-generated content while Party is out, no web browsing, no ads).
  Answer the questionnaire as the build stands, and say yes wherever it asks about AI-generated content or chat, since Ask AI shows a provider's answers that Tabbi does not filter; if that answer raises the rating, accept the higher rating rather than leave it out.
  When Party comes back it adds user content (display names, study presence and reports), so answer yes to user-generated content and expect a rating of at least 13+, which matches the 13+ age check in the app and the Terms.
- Sign-in information: not required (signing in is optional and only syncs the pet and streaks)
- Pricing: free
- Export compliance: the build sets `ITSAppUsesNonExemptEncryption` to `NO` (it only uses HTTPS through the system)

The subtitle and keywords name no other company's product.
The name does: "Notch Focus Timer" is the full name of an existing Mac App Store app (id6477333821) that does the same job, and "Tabbi" is close to other marks ([legal/ip-review.md](legal/ip-review.md) has the search).
Before submitting, pick a descriptor that is not another app's name (for example `Tabbi: Cozy Notch Focus` or `Tabbi: Notch Study Pet`), or have a lawyer clear the current one; Apple can reject or remove a name another developer complains about (Guidelines 2.3.7 and 5.2).
The description names Apple Music and Spotify once, only to say what Now Playing works with.

### Keywords (99 of 100 bytes)

```
cute,cat,dog,cozy,planner,calendar,flashcard,music,widget,student,todo,task,streak,menubar,list,day
```

No word repeats the name or subtitle (tabbi, notch, focus, timer, pomodoro, to-do, study, pet).
`todo` stays as a hedge, since Apple may index "To-Do" only as "to do".
`productivity` is left out because it is the category name, which Apple already indexes.
`party` is left out while the App Store edition leaves Party out (see Party above), since App Review asks keywords to describe the app as submitted.

### Promotional text (157 of 170)

```
Your notch, but cozy. Focus with calming sounds, plan your day, and earn outfits for your pixel cat or dog. Gentle streaks. No ads, no tracking, open source.
```

Promotional text can change at any time without a review, so use it for seasonal items and events.

### Description

```
Tabbi turns your laptop notch into a cozy little panel of tabs for focus, planning and calm.
Start a focus timer, check off today's to-dos, and watch your pixel pet cheer when you finish.
Free and open source. No ads, no tracking, no account needed.

FOCUS
- Focus timer with Pomodoro and other study methods
- Stop early and still keep credit for the time you put in
- Calming focus sounds, with presets for your favorite mix
- Music controls with a like button. Works with Apple Music and Spotify
- Review flashcards from the notch with an optional local add-on

PLAN YOUR DAY
- Today's to-dos and calendar in one glance
- Peek at yesterday and plan tomorrow
- Tap "Plan my day" to line up what matters
- A desktop widget keeps your pet and streak in view

YOUR PET
- Adopt a pixel-art cat or dog that celebrates when you finish
- Earn points by focusing and spend them on outfits and animated cosmetics
- Unlock limited items by reaching milestones
- Seasonal looks to collect through the year

GENTLE BY DESIGN
- Streak freezes, so one off day never ruins your progress
- An optional daily reminder, never nagging
- A weekly recap card to see how far you have come

PRIVATE BY DEFAULT
- No ads, no tracking, no account needed
- Optional Sign in with Apple to sync your pet and streaks
- Optional AI help, using the AI provider you pick
- Open source, so anyone can see how it works

Your notch has been waiting for a friend. Download Tabbi and start your first cozy focus session today.
```

### What's New

Apple does not show What's New for a first version.
For 1.0, if asked:

```
Hello from Tabbi! Your laptop notch is now a cozy home for focus, planning and a pixel pet who cheers you on. Start a session, earn your first outfit, and keep a gentle streak going.
```

For later versions, one warm line naming the headline change, then short New, Better and Fixed lists in plain words, ending with "Thanks for focusing with Tabbi. Your pet says hi."

### App Privacy (nutrition label answer sheet)

Without an account, the App Store edition sends nothing to the Tabbi server.
The optional Sign in with Apple account stores a little there ([backend/PRIVACY.md](../backend/PRIVACY.md) lists all of it).
Answer App Store Connect's questions exactly like this:

1. "Do you or your third-party partners collect data from this app?" Yes, we collect data from this app.
2. Data types to select (and nothing else):
   - Identifiers > User ID
   - Identifiers > Device ID
   - User Content > Other User Content
   - Usage Data > Product Interaction
3. For **User ID** (Apple's app-specific user id, and the random friend code the account is filed under):
   - Usage: App Functionality only.
   - Linked to the user's identity: Yes.
   - Used for tracking: No.
4. For **Device ID** (the random id each Mac's points are filed under in the sync document, and the per-Mac sign-in token, which the server keeps only as a hash):
   - Usage: App Functionality only.
   - Linked to the user's identity: Yes.
   - Used for tracking: No.
5. For **Other User Content** (the synced pet's look and name, and unlocked and granted items):
   - Usage: App Functionality only.
   - Linked to the user's identity: Yes.
   - Used for tracking: No.
6. For **Product Interaction** (points earned and spent per Mac, the days the user studied and the longest streak, which are records of how the app was used):
   - Usage: App Functionality only.
   - Linked to the user's identity: Yes.
   - Used for tracking: No.

The privacy manifest the build ships (`packaging/PrivacyInfo-AppStore.xcprivacy`, copied into the app by `scripts/assemble.sh`) declares these same four types with the same answers, so change both together.
It also gives the required reasons for the APIs the binary links: UserDefaults (CA92.1, the app's own settings) and file timestamps (C617.1: the AI Usage log scanners in TabbiKitCore are linked but never run in this edition, and the sandbox keeps any file they could reach inside the app's container).
The widget extension has its own manifest (`PrivacyInfo-AppStore-Widget.xcprivacy`) with the same reasons and no collected data.
If App Store Connect warns about a required reason API (ITMS-91053), add it to both manifests with the reason that matches the code.

Device ID and Product Interaction are the cautious reading: Apple's definitions are loose, and declaring a type the app arguably does not need costs nothing, while leaving out one it does is a mislabel.

Why nothing else is declared:

- Name and Email Address: the app asks Apple only for the name, keeps it on the Mac, and the server never stores a name or an email.
- Calendar events, tasks, focus history, study tallies, the activity log and AI chats stay on the Mac in the app's container.
- Album artwork is loaded from the music service's image host (`i.scdn.co`) with no identifier of the user.
- AnkiConnect and Ollama are reached on `localhost` only.
- Ask AI, Plan my day, Refine and Wrap up send text only to the AI provider the user picks, with the user's own key (Anthropic, OpenAI or Google), or to Ollama on the Mac.
  The request goes straight from the Mac to that provider under its own terms; there is no Tabbi server in between and no partner SDK in the app, so Tabbi does not collect it.
- Diagnostics: the App Store edition has no crash reporting of its own (`AppDelegate` installs no `CrashHandler` and shows no crash prompt under `APPSTORE`), so crashes reach the developer only through Apple's reports, which the user shares in macOS.
  The server's short request logs hold only the kind of request, its status and duration, with no identifier, and are deleted within 7 days.
- The Suggest page opens in the browser with the app version, macOS version and edition in its address, and nothing is sent unless the user submits the web form, so it is the website's collection, not the app's (the site Privacy Policy covers it).
- There is no analytics, advertising or tracking of any kind.

When Party comes back, also declare its display name and study presence: Contact Info > Name (or User Content > Other User Content) and Usage Data > Product Interaction, both App Functionality, linked, not tracking.
Its anonymous Party identity is a random id with a secret token, which Identifiers > User ID already covers; reports a user files are Other User Content.

Before submitting, check that the Worker has the Sign in with Apple secrets ([sync.md](sync.md), step 5): without them Delete Account still erases the server's data but cannot revoke the Apple grant, and the reviewer note below would then promise more than the app does.

### Notes for the reviewer

> Tabbi turns the area around the notch at the top of a MacBook screen into a small panel of tabs: a focus timer, today's tasks and calendar, now playing, study tools and a pixel pet.
> There is no Dock icon and no window at launch; the app lives at the top center of the screen.
> To open the panel, click the black notch area at the top center of the screen, or press Control-Option-Space.
> On a Mac without a notch, Tabbi draws a small black pill at the top center of the menu bar; click it the same way.
> The first launch shows a short setup inside the panel (pick a kit, then tabs).
> Settings open from the gear button at the right of the panel's header.
> Calendar access is optional and only used to show today's events in the Today tab and to plan the day.
> Automation access to Music or Spotify is optional and only used to show and control what is playing; macOS asks for it the first time Now Playing reaches either app.
> Notifications are optional: alerts when a focus timer ends, a daily study reminder the user turns on, and the weekly recap.
> The flashcards tab reads review counts from the free AnkiConnect add-on of the Anki desktop app over localhost (127.0.0.1:8765). Tabbi downloads and runs no code; without Anki it shows how to set it up.
> AI features (Ask AI, Plan my day's Refine and the day review) stay off until the user picks an AI in Settings > Connections > AI. The Settings footer says nothing is sent until then. They use the user's own API key (Anthropic, OpenAI or Google Gemini), saved in the Keychain, or Ollama running on the Mac. To try them, pick Ollama with a local model, or paste a key.
> Guideline 5.1.2(i): picking Anthropic, OpenAI or Gemini first shows a one-time consent alert that names the company receiving the data and lists what each AI feature sends (Ask AI: questions, the chat and any screenshot attached; Refine: calendar event titles and times, tasks, goals and the plan; day review: study points, goal counts and the titles of finished and carried-over tasks). Nothing is sent unless the user taps Allow, and Cancel keeps None. Ollama runs on the Mac, so it needs no consent.
> No account is needed.
> Signing in with Apple (Settings > General > Account) is optional and only syncs the pet and study streaks between the user's Macs.
> Accounts are for people 13 and older: the first Sign In asks the birth month and year (a neutral question, kept on the Mac), then shows Apple's button with links to the Terms and Privacy Policy. An under-13 answer keeps signing in off until the user turns 13.
> Delete Account in the same place deletes everything the server holds and revokes the Sign in with Apple grant (Guideline 5.1.1(v)).
> The Privacy Policy and Terms of Use are linked from Settings > About.

When Party comes back, add these lines to the notes:

> Party (the friends tab) asks for the user's birth month and year before it contacts the server, and stays off for anyone under 13; only the date the user turns 13 is saved, on the Mac.
> To report someone, right-click their name in Party and choose Report; Block in the same menu hides them at once. Names pass a filter, and the maintainer reviews reports and can rename or ban an identity. Contact: support@tabbinotch.com.

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
