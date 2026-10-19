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
The script signs with it for the App Store and leaves it out of `--adhoc` builds, since macOS does not launch an app that claims it without a matching profile; there Apple's button in Settings > General signs in on Apple's web page instead (`AppleSignInMethod`).

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

- Name: `Tabbi: Notch Timer & Study Pet` (30 of 30)
- Subtitle: `Focus, Pomodoro & To-Do List` (28 of 30)
- Category: Productivity (secondary: Education)
- Privacy Policy URL: https://tabbinotch.com/privacy
- Support URL: https://tabbinotch.com/support
- Marketing URL: https://tabbinotch.com
- Copyright: the maintainer's name and the year
- Age rating: 4+ (no user-generated content while Party is out, no web browsing, no ads).
  Answer the questionnaire as the build stands, and say yes wherever it asks about AI-generated content or chat, since Ask AI shows a provider's answers that Tabbi does not filter; if that answer raises the rating, accept the higher rating rather than leave it out.
  When Party comes back it adds user content (display names, study presence and reports), so answer yes to user-generated content and expect a rating of at least 13+, which matches the 13+ age check in the app and the Terms.
- Sign-in information: not required (signing in is optional and only syncs the pet and streaks)
- Pricing: free.
  The app has no tip, coffee or other external payment link in either edition, and this listing has none (Guideline 3.1.1); the website's optional Support Tabbi link lives only on the website.
  If an optional supporter tier comes later, the App Store edition must offer it through In-App Purchase, and the Description changes in the same submission.
- Export compliance: the build sets `ITSAppUsesNonExemptEncryption` to `NO` (it only uses HTTPS through the system)

The name, subtitle and keywords name no other company's product.
The name used to be `Tabbi: Notch Focus Timer`, which contained "Notch Focus Timer", the full name of an existing Mac App Store app (id6477333821) that does the same job, so it was changed (Guidelines 2.3.7 and 5.2).
"Tabbi" is close to other marks, so a trademark search is still on the lawyer list ([legal/ip-review.md](legal/ip-review.md) has the search).
The description names Apple Music and Spotify once, only to say what Now Playing works with.

### Keywords (100 of 100 bytes)

```
cute,cat,dog,cozy,planner,calendar,flashcard,music,widget,student,todo,task,streak,menubar,habit,day
```

No word repeats the name or subtitle (tabbi, notch, timer, study, pet, focus, pomodoro, to-do, list).
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
- Birthday or age: the App Store edition never asks for one (signing in does not, and Party, which does, is left out). When Party comes back, its age check keeps only the date the user turns 13 on the Mac and sends nothing, so it is still not collected.
- Calendar events, tasks, focus history, study tallies, the activity log and AI chats stay on the Mac in the app's container.
- Album artwork is loaded from the address the player reports (Spotify's `i.scdn.co`, SoundCloud's `i1.sndcdn.com`) with no identifier of the user.
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
> Calendar access is optional and only used to show today's events in the Today tab and to plan the day. Setup's calendar step explains it with a Continue button, which lets macOS ask, and Not now beside it; declining keeps Today working, with a note and a button to System Settings > Privacy & Security > Calendars.
> Automation access to Music or Spotify is optional and only used to show and control what is playing; macOS asks for it the first time Now Playing reaches either app.
> Notifications are optional: alerts when a focus timer ends, a daily study reminder the user turns on, and the weekly recap.
> The flashcards tab reads review counts from the free AnkiConnect add-on of the Anki desktop app over localhost (127.0.0.1:8765). Tabbi downloads and runs no code; without Anki it shows how to set it up.
> AI features (Ask AI, Plan my day's Refine and the day review) stay off until the user picks an AI in Settings > Connections > AI. The Settings footer says nothing is sent until then. They use the user's own API key (Anthropic, OpenAI or Google Gemini), saved in the Keychain, or Ollama running on the Mac. To try them, pick Ollama with a local model, or paste a key.
> Guideline 5.1.2(i): picking Anthropic, OpenAI or Gemini first shows a one-time consent alert that names the company receiving the data and lists what each AI feature sends (Ask AI: questions, the chat and any screenshot attached; Refine: calendar event titles and times, tasks, goals and the plan; day review: focus and study minutes, sessions and points, goal counts and the titles of finished and carried-over tasks). Nothing is sent unless the user taps Allow, and Cancel keeps None. Ollama runs on the Mac, so it needs no consent.
> No account is needed.
> Signing in with Apple (Settings > General > Account) is optional and only syncs the pet and study streaks between the user's Macs.
> Signing in asks for no personal information: the Account row shows Apple's button directly, with links to the Terms and Privacy Policy. The app never asks for a birthday.
> Delete Account in the same place deletes everything the server holds and revokes the Sign in with Apple grant (Guideline 5.1.1(v)).
> The Privacy Policy and Terms of Use are linked from Settings > About.

When Party comes back, add these lines to the notes:

> Party (the friends tab) asks for the user's birth month and year only when the user turns Party on, before it contacts the server, and Not now skips it; it stays off for anyone under 13, and only the date signing up opens (the first day of the month after the user turns 13) is saved, on the Mac. Nothing else in the app asks for a birthday.
> To report someone, right-click their name in Party and choose Report; Block in the same menu hides them at once. Names pass a filter, and the maintainer reviews reports and can rename or ban an identity. Contact: support@tabbinotch.com.

### App Review history

Version 1.0.0 (build 130) was rejected on 19 October 2026, reviewed on a MacBook Air with macOS 27.0, for three things, all fixed in 1.0.3:

1. Guideline 5.1.1(v), a required birthday: Sign In in Settings > General asked for the birth month and year before Apple's button.
   Signing in now never asks; the Account row shows Apple's button straight away, with the Terms and Privacy Policy links.
   The birthday is Party's alone (direct download only), asked when Party is turned on, with Not now beside it.
2. Guideline 5.1.1(iv), "Allow Access" before the calendar prompt: the onboarding step's button now says Continue, with Not now in the footer.
   The same pass changed every screen before a macOS prompt: Settings > Connections' priming sheets lost "Click Allow." and gained Not now, Ask AI's Screen Recording card says Continue, and the study mixer's denied chip says "Spotify access is off" instead of "Allow Spotify access".
   The AI consent alert keeps Allow, since it is the consent itself (guideline 5.1.2(i)), not a step before a system prompt.
3. Guideline 2.1(a), nothing happened after the birthday: the age question lived in a sheet whose Continue swapped in SwiftUI's `SignInWithAppleButton`, which ran Apple's native request from inside that sheet, without making the Dock-less app active.
   The same code works with the web flow on macOS 26.6 (ad-hoc App Store build, driven step by step), and the native flow needs the signed build, so it could not be run here; it is the only part the reviewer ran that the check did not, and it had two ways to end with nothing on screen: Apple's sheet with no active window to appear over, and a failure reported in the row behind the sheet.
   The sheet is gone, the button sits in the Settings window itself, and `AppleNativeSignIn` makes the app active and hands Apple's sheet that window before it asks; a failure now shows in the row.

The reply to App Review is in the 1.0.3 submission notes.

### Screenshots

The screenshots in [`appstore/screenshots`](appstore/screenshots) follow the production spec (`research/screenshots.md` in the runs folder).
They are 2880x1800 (16:10) flattened 8-bit PNGs in sRGB IEC61966-2.1 with no alpha, as App Store Connect requires for Mac apps.
Upload them in file name order:

1. `1-timer`: "A cozy timer in your notch", the Timer running in round 2 of 4 with two focus sounds on.
2. `2-cheer`: "Every session ends in a cheer" with the subcaption "Earn points, unlock outfits, and hear from your cat.", the closed notch centered at the top edge with the session-end card hanging below it ("That's a wrap. Well done!", +35 and the bar toward the next unlock, "1 more session to Ninja Headband"), and the big cheering cat on the dunes saying a Cat wisdom line ("The pawn keeps moving forward. One square at a time, it can become anything it wants.").
3. `3-closet`: "Earn points, dress your cat" with the subcaption "Every focus day fills your chart.", the Closet's Activity section (the study heatmap, 30 days of focus time, best day and streak) beside Mochi in the Cozy Hoodie and Beanie, with 240 points (`open-large-closet`).
   The preview's Closet beat still picks the Wardrobe, since that beat shows an item being worn.
4. `4-today`: "Today, right up top", Today with tasks, Up next and the mini timer.
   It reads "2 of 5 done": the demo day has three tasks, under the Focus time and flashcard rows that other tabs share, so the whole list fits without scrolling (the spec lists a walk in place of the flashcard row).
5. `5-tomorrow`: "Plan tomorrow tonight", the Tomorrow view with two planned tasks and tomorrow's calendar, on the night canvas (the Dark Mode shot).
6. `6-music`: "Music without switching apps", Now Playing with the fictional "Golden Hour Drive" by Maple Avenue, its original drawn cover, the like heart and a generic music badge.
7. `7-flashcards`: "Flashcards between tasks", the flashcards tab with neutral decks (the tab shows the module's real name; captions never name it).
8. `8-recap`: "Your week, wrapped up", the weekly recap card (it ships in the App Store build, so the spec's closer 8a applies).
   Demo runs leave the week's dates off the card, so no date shows in store media.

Localized sets (`appstore/screenshots/<locale>/`) are not rendered yet: the app has no localizations on main so far, so only the English set exists.

Every shot uses one layout: the tabs Timer, Today, Flashcards and Now Playing plus the Closet paw, at the Large panel size.
Party and the AI usage tab are left out of the App Store edition, so neither appears.
All names, songs and decks in the demo data are fictional, and no caption has a price or a third-party name.
[`appstore/screenshots/small`](appstore/screenshots/small) (1280x800) and [`appstore/screenshots/gallery`](appstore/screenshots/gallery) (540x338, the size the web product page shows) hold review copies; do not upload those.

The design: a cream canvas with the site's paper grain and a soft glow tinted 6 percent toward the active tab's accent, a one-line Fredoka SemiBold headline (168 px, baseline at y=310) and a Fredoka Medium subcaption (76 px, baseline at y=430), over a full-bleed original dune wallpaper from y=540 with a plain translucent menu bar (no device, no Apple logo, no menus).
The real panel hangs from the menu bar, drawn 1:1 from snapshots rendered at 3 pixels per point, with only its own shadow.
Shot 2 has no open panel, so it shows the closed notch (190 by 32 pt, at the panels' 3 pixels per point) centered at the top of the stage like a MacBook's; the menu bar there is as tall as the notch.
In the app the pet says the session-end card and then its Cat wisdom line in one bubble beside the notch; the shot shows both at once so the moment reads at gallery size: the card centered below the notch and the wisdom bubble beside the big cat, each cut from the app's own coach snapshots at 5 pixels per point (`coach-session-end` and `coach-wisdom-all-0`, which `TABBI_WISDOM_ALL=1` renders).
The card leaves out its tail, which points at the small pet beside the notch, and the wisdom bubble's tail is redrawn toward the big cat; the script warns if the wisdom bubble runs past the margin or crowds the card.
The demo pet, Mochi, sits on the front dune in a different mood and costume per shot: the panel's Cozy Hoodie and Beanie typing (Timer), a party hat and bow tie cheering (the session end), the same look as the panel (Closet and recap), a flower crown (Today), the Dinosaur Hoodie asleep (Tomorrow), headphones and sunglasses with a mug (music) and a graduation cap and glasses (flashcards).
It is drawn by the app's own pet renderer (`swift run PetGallery <folder> accents`) and scaled up with nearest neighbor by whole numbers (12x, 13x in the Closet shot), so the pixel art stays sharp.
Shot 5 uses the night variant of the canvas: dusk dunes, pixel stars and a darker menu bar.
Fredoka is bundled in [`appstore/fonts`](appstore/fonts) with its SIL Open Font License.

To render them and the App Preview again after a UI change, run:

```sh
swift docs/appstore/make-media.swift
```

The script renders App Store edition demo snapshots of the store layout (`--edition appstore --tabs study,planner,anki,spotify,closet --transparent --scale 3`), the same again at `--scale 5` with `TABBI_WISDOM_ALL=1` for the coach, and the pet's frames, records the App Preview's footage (below), then composes the screenshots and the preview.
To compose from folders you already rendered that way, pass the 3x folder, the 5x coach folder and the accents folder, and optionally a recording folder that holds `opening/` and `story/`; without one the preview is recorded fresh.
Add `--screenshots-only` to compose the screenshots and leave the preview alone.
It warns when a caption runs into the side margins or the pet touches the panel.
The clocks in the demo panels are live, so every run changes the shots that show a timer; commit only the images you meant to change.

Known gaps to close before upload:

- The spec's shot 5 prefers the Tomorrow plan proposal, but at the Regular size it truncates task names, so the plain Tomorrow view is used, as the spec allows.

### App Preview

[`appstore/preview/tabbi-app-preview.mp4`](appstore/preview/tabbi-app-preview.mp4) is the App Preview: 27.2 seconds of 1920x1080 H.264 (High profile, Level 4.0, 30 fps, Rec. 709 tags) with a silent stereo AAC track, since App Store Connect expects previews to carry audio.
It is footage of the running app, as Guideline 2.3.4 asks: the real notch with the live demo stores, the ticking clock, the app's own springs, check-off, heart and paw confetti, recorded at 30 fps.
[`appstore/preview/poster.png`](appstore/preview/poster.png) is the frame at 2.5 s (the Timer open and ticking with its caption), the poster frame the spec picks; set it in App Store Connect, since the default 5 s frame shows the focus block at its last second.

How it was recorded: not a screen recording of the Mac's display, but a recording of the app's own notch window.
`--record` hosts the real `NotchView` with the app's modules in a window kept behind the desktop picture, plays the spec's storyboard as the app's own actions, and records only that window with ScreenCaptureKit at 30 fps and 2 pixels per point (the panel's native size on a Retina screen):

```sh
TABBI_DEMO=1 TABBI_DEMO_FOCUS_LEFT=1126 swift run -c release Tabbi --record <folder>/opening --part opening --edition appstore --tabs study,planner,anki,spotify,closet
TABBI_DEMO=1 TABBI_DEMO_FOCUS_LEFT=5 swift run -c release Tabbi --record <folder>/story --part story --edition appstore --tabs study,planner,anki,spotify,closet
```

`opening` is the closed notch with the pet, then the panel springs open on the Timer at 18:42 and ticks.
`story` starts five seconds before the focus block ends, so the session finishes on camera (paw confetti, the digits roll into Break), the panel closes to the pet celebrating in the notch, then it opens the Closet, checks off Read chapter 4 in Today, plans tomorrow (the blocks arrive), likes the track in Now Playing, shows Flashcards and closes to the pet again, so the end matches the first frame for a clean loop.
Each part writes transparent `frame-NNNN.png` files and a `frames.json` with every frame's time, the storyboard's beats and the length; the stream sends a frame only when something changed, so a frame lasts until the next one's time.
Record from a release build: in a debug build, closing the notch stalls for about 2 seconds while the closed notch's pet builds its animation clips on the main thread, and the clock freezes on camera.
Pets in the recording draw with SwiftUI (`rendersToImage`), the same frames the snapshots use.
The app's layer-backed pet only animates while its window is visible, so in a window behind the desktop it would stay blank.
Nothing shows on the Mac's display and no other app or desktop content can be in a frame, but the terminal that runs it needs Screen Recording permission.

`make-media.swift` composes the parts on the dune desktop (the same wallpaper as the screenshots, full frame, with a plain menu bar as tall as the notch) with the notch window drawn 1:1 from the top center.
The opening runs 4 seconds, then a dissolve of 8 frames joins the story's last seconds of the focus block, with a small "25 minutes later" pill for 2 seconds.
The storyboard's captions sit bottom left in cream pills (Fredoka SemiBold 60 px, 28 px corners, 28 by 16 px padding, baseline at y=1000), each on screen at least 2.5 seconds and fading over 8 frames; the closing pill reads "Tabbi" beside the app icon at 120 px.
While the panel is closed after the session ends, the session-end moment shows right of the notch: the coach's pet with its card ("That's a wrap. Well done!", +35 and the bar, "1 more session to Ninja Headband"), the same moment as shot 2.
The app draws the coach in a window of its own, which `--record` does not capture, so `make-media.swift` takes the pet and card from the app's `coach-session-end` snapshot (5 pixels per point, scaled to the footage's 2) and places them where the app hangs them, from the notch's bottom edge at its right edge.
They drop in over 8 frames once the panel has closed (4 seconds into the story) and fade out just before the Closet opens, so the card shows for about 2 seconds.
No pointer or other UI is drawn over the footage: the clicks are the app's own actions, and the spec rules out a fake pointer.
There is no music bed: no track with a clear license was available, so the preview stays silent.
If wanted, the maintainer can instead record the sandboxed App Store build on a notched Mac with QuickTime or ScreenCaptureKit, as the spec's capture method describes, and keep these captions.
`swift docs/appstore/make-media.swift` writes it together with the screenshots.
