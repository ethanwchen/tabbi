# Tabbi on the Mac App Store

Tabbi ships in two ways from the same source tree.
The direct download (Developer ID, `scripts/release.sh`) keeps every feature.
The Mac App Store edition (`scripts/release-appstore.sh`) is sandboxed and leaves out what a sandboxed app cannot do or what App Review does not allow.
This page says what differs, how to build and upload it, and what to enter in App Store Connect.

## What differs

Since 1.0.4 the App Store edition has every tab and nearly every feature of the direct download.
What a sandboxed app cannot do takes a sandboxed path instead (AI Usage, Do Not Disturb), and only two things stay direct-only: the AI command line tools and SoundCloud in a browser (see What stays direct-only).

| | Direct download | Mac App Store |
| --- | --- | --- |
| Build | `swift build` | `TABBI_APPSTORE=1 swift build` (defines `APPSTORE`) |
| Edition | `tabbi` | `appstore` (`Sources/TabbiKitCore/Editions/BundledEditions/appstore.json`) |
| App Sandbox | no | yes (`packaging/Tabbi-AppStore.entitlements`) |
| Updates | Sparkle | the App Store (Sparkle is not linked at all) |
| Move to Applications, single instance, quarantine checks | InstallHygiene | left out (the App Store installs the app) |
| Party | yes | yes, the same tab, age check, invite links, reporting and blocking (from 1.0.4), and Study Crews in the same tab (from the Crews release) |
| AI Usage | reads `~/.claude` and `~/.codex`, and asks the `claude` CLI for live limits | reads only the Claude Code or Codex folder the user picks; Claude Code shows tokens per day in place of live limits, Codex shows its limits from its logs (from 1.0.4) |
| AI providers (Settings > Connections > AI) | Claude Code, Codex and Gemini CLI, the Anthropic, OpenAI and Gemini APIs, Ollama | the Anthropic, OpenAI and Gemini APIs with the user's key, and Ollama on `localhost` |
| Ask AI | yes | yes, through the API providers and Ollama |
| Plan my day and Refine | on the Mac, or with the picked AI | the same, with an API provider or Ollama |
| Wrap up (day review) | local summary, refined by the picked AI | the same, with an API provider or Ollama |
| Now Playing | Spotify, Music, and SoundCloud in Safari or Chrome (opt-in) | Spotify and Music |
| Do Not Disturb during focus | runs the two shortcuts with `/usr/bin/shortcuts` | runs the same two shortcuts through Shortcuts Events, after macOS asks once (from 1.0.4) |
| Settings > Connections | all rows | no command line tools in the AI picker and no Claude row |
| Crash reports | asks after a crash, then sends to `POST /v1/crashes` with consent | the same (from 1.0.4; before, none of its own) |
| Sign in with Apple and sync ([sync.md](sync.md)) | yes, on the web (no profile needed) | yes, natively with the App Store profile (on the web in `--adhoc` builds) |

The compile-time switch sits in these places: `Package.swift` (the define, the Sparkle dependency and the excluded `Updates` and `InstallHygiene` folders), `AppDelegate.swift` (updater and install hygiene), `Edition+Current.swift` (the default edition and `Edition.isSandboxed`), `ClaudeUsageStore` (the App Store build never even looks for a CLI) and a few spots in Settings and the snapshot renderer.
Everything else follows the edition at run time.
`Edition.isSandboxed` is true in every App Store build and for the App Store edition in any build, so `swift run Tabbi --edition appstore` and its snapshots show what the store build shows.
`Edition.runsLocalTools` is false for the App Store edition, which hides the command line AI tools and the Claude row.
`Edition.excludedModules` can still remove modules from an edition's catalog, so kits, onboarding, Settings > Tabs and the closed-notch ticker never offer them; the App Store edition excludes none since 1.0.4.

### AI in the sandbox

A sandboxed app cannot start the `claude`, `codex` or `gemini` command line tools, so the AI picker in Settings > Connections offers only the providers that need no helper program: the Anthropic, OpenAI and Gemini APIs (the user pastes their own key, which Tabbi keeps in the Keychain) and Ollama on `localhost:11434` (free and offline).
All of them go through the `network.client` entitlement the app already has.
A command line tool saved by a direct download counts as no choice here, so Ask shows its setup state instead of failing.
Nothing is sent anywhere until the user picks a provider: a fresh install starts with None, Ask shows "Choose an AI to ask questions", and Plan my day and Wrap up stay on the Mac.
Picking a provider that sends data off the Mac (every one but Ollama) first shows a one-time consent alert naming the company and what each feature sends (Guideline 5.1.2(i)); the permission is saved per provider in `AISettings.consented`.

### Party in the sandbox

Party is the same code in both editions, with nothing behind `#if APPSTORE`: the friends server is reached over HTTPS through `network.client`, the secret token lives in the Keychain under the edition's own service, invite links arrive through the `tabbi://` URL scheme in `Resources/Info.plist` (the website's `/add/<code>` and `/join/<code>` pages open them), and the optional account signs in with Apple's native sheet.
It keeps every safeguard App Review asked for in guideline 1.2: reporting (right-click a friend or party member, then Report), blocking (the same menu, or Also block in the report sheet), the name filter (`PartyNameFilter`, the same list as the server's), and the maintainer's moderation queue, which can rename or ban an identity ([study/backend-api.md](study/backend-api.md#moderation-maintainer)).
The age question is Party's alone and optional: it shows only when the user turns Party on (onboarding's Party step, the Party tab or the Party setup sheet in Connections), with Not now beside it, and it keeps Party off for anyone under 13.
Only the date the user surely turns 13 is kept, on the Mac; nothing about it is sent (guideline 5.1.1(v)).
The wire protocol is untouched, so App Store users party with every other version on the Mac and on Windows ([party-compatibility.md](party-compatibility.md)).
No kit turns Party on, so a fresh install never shows it or the age question unless the user picks it.
Study Crews ([design/crews.md](design/crews.md)) are a section of the same Party tab and the same code in both editions: they use the Party identity and server, so they stay off with Party under 13, and crew invite links (`tabbi://crew/<code>`) arrive through the same URL scheme.
Crews keep the same safeguards: crew names and descriptions pass the name filter on the Mac and the server, a crew or a member can be reported (the flag on a crew's page, or right-click a member) and members blocked, owners can remove members, and the maintainer can rename, hide or delete a crew.

### AI Usage in the sandbox

The sandbox keeps the app out of `~/.claude` and `~/.codex`, so AI Usage starts with a card that says what it reads and where ("Tabbi can count your tokens from the logs Claude Code keeps in the .claude folder. Choose it next. Nothing leaves your Mac.") and one Continue button.
Continue opens the standard open panel in the home folder with the tool's folder selected and hidden folders shown; the panel's own line repeats what is read.
The pick is kept as a security-scoped bookmark (`files.user-selected.read-only` and `files.bookmarks.app-scope`), so it is asked once, and Settings > Tabs > AI Usage > Options shows each folder with Change and Remove (Remove forgets the bookmark at once).
A folder without the tool's logs is refused with a line saying which folder to pick.
Nothing is read until the user picks, and declining (closing the panel, or never pressing Continue) leaves the card in place; every other tab works the same.
The App Store build never looks for or runs a command line tool here (`ClaudeUsageStore.locateCLI` returns nothing under `APPSTORE`), so Claude Code's live 5-hour and weekly limits, which only its CLI reports, are replaced by the week's tokens per day, read from the logs.
Codex writes its limits into its own logs, so the Codex view keeps its rings.
A footer menu switches between Claude Code and Codex, since no command line AI can be the chosen provider in this build.

### Do Not Disturb in the sandbox

macOS has no public Do Not Disturb API, so both editions run two shortcuts the user makes with the Shortcuts app's Set Focus action, and the setup (names, the walkthrough, Test it) is the same.
A sandboxed app cannot start `/usr/bin/shortcuts`, and opening a `shortcuts://run-shortcut` link brings the Shortcuts app's window up every time a focus block starts or ends, so the App Store build sends Apple Events to Shortcuts Events, the background half of Shortcuts, which runs a shortcut without opening any window (`ShortcutsEvents`, scripts in `ShortcutsEventsScript`).
Shortcuts Events' scripting definition puts running shortcuts and reading their names in the `com.apple.shortcuts.run` access group, which the entitlements name under `com.apple.security.scripting-targets`; that is the sanctioned way to script another app from the sandbox and needs no temporary exception.
macOS asks once before the first event (Automation).
Turning the switch on in Settings > Tabs > Today (or Focus) > Options first shows a priming sheet ("Let Tabbi run your Focus shortcuts") with Continue and Not now, and Continue lets macOS ask; Not now leaves the switch off.
The Do Not Disturb row in Connections does the same through its own priming sheet, and its troubleshooter says where to turn access back on.
Nothing ever sends an Apple Event before the user allowed it: a focus block with access off runs no shortcut and logs why, and the switch shows "Shortcuts access is off" with a button to System Settings.

### What stays direct-only

- **The Claude Code, Codex and Gemini command line tools as AI providers.**
  A child process inherits the app's sandbox, so a CLI started from the App Store build cannot read its own sign-in (Claude Code keeps it in the login Keychain and `~/.claude`, Codex in `~/.codex`, Gemini in `~/.gemini`), cannot write its session files, and cannot reach tools the user installed in `/opt/homebrew` or `~/.local` without temporary file exceptions App Review does not grant for this.
  Asking the user to pick those folders would still leave the Keychain sign-in out of reach, so the provider would half work at best.
  The API providers (with the user's own key) and Ollama cover the same features.
- **SoundCloud in Safari or Chrome.**
  It runs JavaScript in the user's browser tab through Apple Events.
  Safari's `do JavaScript` command has no scripting access group, so it would need `com.apple.security.temporary-exception.apple-events` for Safari and Chrome, an exception App Review questions closely, for an app that would read the user's browser tabs.
  That risk is not worth one more player; Spotify and Music cover Now Playing.

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

On a Mac that also runs Tabbi, check under a throwaway identity so nothing touches the real app's container, Keychain items or widget group: add a temporary edition file next to `appstore.json` with its own `id`, `name` and `bundleIdentifier` (and `"distribution": "appStore"`), build it with `TABBI_APPSTORE=1 swift build -c release`, assemble it with `scripts/assemble.sh <binary> <folder> <id>`, delete the edition file again, remove the widget (`Contents/PlugIns`), and ad-hoc sign the app with `Tabbi-AppStore.entitlements` minus `applesignin` and `application-groups`.
Start that copy with `open -n -a <app>`, not from Terminal: a process started from Terminal makes macOS ask for Automation access in Terminal's name.
For Party, point it at a local server first: run `npm run dev` in `backend/`, start the copy once, quit it, and set its Party server with `defaults write ~/Library/Containers/<bundle id>/Data/Library/Preferences/<bundle id> party.settings -data <hex>`, the hex of `{"serverText":"http://localhost:8787"}`; a second Party user is a few `curl` calls with `Tabbi-Protocol: 2`, or `npm run demo-friend` against the local server.
Afterwards delete the copy, its container and its Keychain items (service `<bundle id>.party`).

The last check (October 2026) found no sandbox denials and no process launches.
Clicking the notch opened the panel and moving the pointer away closed it (global mouse monitors work), the hotkey uses `RegisterEventHotKey` (no permission needed), Today read the calendar through EventKit, and Now Playing reached Music through the Apple Events exception (macOS then asks for Automation permission, as it does for the direct download).

The check for 1.0.4 (November 2026, macOS 27.0.1) ran the release App Store build sandboxed under a throwaway bundle id against a local friends server, driven through onboarding with the accessibility API, and found no sandbox denials:

- Onboarding offered Party and AI Usage; with Party on, its step asked the birth month and year with Not now beside it, and answering an adult date registered the identity on the server and showed the friend code.
- A friend request from the app reached a second user, who accepted; a `tabbi://join/<code>` link opened the invite in the running app and joined that user's party, where both pets showed and the host's shared session counted down.
- Report (spam, with Also block) reached the moderation queue, ended the friendship and left the party; a `tabbi://add/<code>` link added the demo friend at once (it speaks protocol 1), its party showed a Join button that worked, and Block in the context menu removed it.
- AI Usage showed its card, Continue opened the open panel in the home folder, choosing `.claude` showed the week's tokens from the real logs, and after a relaunch the bookmark still worked without asking.
- Turning on Do Not Disturb showed the priming sheet, and Continue brought up macOS's Automation prompt for Shortcuts Events.
  Running a shortcut once access is allowed is covered by unit tests and gets one manual run on the TestFlight build (see the checklist).

## App Store Connect

Everything in this section is paste-ready for the App Store edition from 1.0.4, which has Party, AI Usage and Do Not Disturb; the command line AI tools and SoundCloud are not in it, so the copy below does not promise them.
For 1.0.3, which is live, the earlier copy without Party stays in git history (this file before 1.0.4).
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
- Age rating: update the questionnaire for 1.0.4, since Party adds content made by other users, and expect 13+ (the age the app's Party check and the Terms ask for); accept a higher rating if the answers give one.
  The answers (App Store Connect > App Information > Age Ratings > Edit):
  - User-Generated Content: Yes. Other users' display names and pet names show in Party, and crew names and descriptions in Study Crews; they pass a name filter on the Mac and on the server, every user can report and block, and the maintainer reviews reports and can rename or ban an identity, and rename, hide or delete a crew.
  - Messaging and Chat: No. Party and Crews have no messages between users; the optional note in a report goes only to the maintainer.
  - Unrestricted Web Access: No. Links open in the user's browser.
  - Advertising: No.
  - Contests, Gambling, Loot boxes and the content-frequency questions (violence, sexual content, profanity, mature themes, horror, medical, alcohol and tobacco and drugs, weapons): None.
  - Parental Controls: No. Age Assurance: No (the app does not verify age; Party asks the user's birth month and year and stays off under 13).
  - Answer yes wherever the questionnaire asks about AI-generated content, since Ask AI shows a provider's answers that Tabbi does not filter.
  - Study Crews change none of these answers: their only user content is a filtered crew name and description, they add no messaging, and their weekly top 3 rewards are a laurel and a trophy count, never a purchase, a prize or chance (Contests stays None).
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
cute,cat,dog,cozy,planner,calendar,flashcard,music,widget,student,todo,task,streak,friends,habit,day
```

No word repeats the name or subtitle (tabbi, notch, timer, study, pet, focus, pomodoro, to-do, list).
`todo` stays as a hedge, since Apple may index "To-Do" only as "to do".
`productivity` is left out because it is the category name, which Apple already indexes.
`friends` replaced `menubar` in 1.0.4, when Party came to the App Store edition: people search "study with friends", and Tabbi lives in the notch rather than the menu bar.
`party` is left out on purpose: it mostly matches party games and event planners.

### Promotional text (162 of 170)

```
Your notch, but cozy. Focus with calming sounds, study with friends, and earn outfits for your pixel cat or dog. Gentle streaks. No ads, no tracking, open source.
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
- Optional Do Not Disturb while you focus, through two shortcuts you make

STUDY WITH FRIENDS
- Party: see when friends are focusing and study side by side, pets and all
- Invite friends with a link or an eight-character friend code
- Report or block anyone in one click

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

For 1.0.6:

```
Study together! Study Crews arrive in the Party tab, with fifteen new outfits and the Heirloom shelf.

New
- Study Crews: start or join a crew, race for the weekly top 3 by focus hours, and earn medals for your crew's crest
- Design a crest from frames, ten cute emblems and ten colors; the Hall of Fame keeps every medal
- 15 outfits, from a Strawberry Cap and Mushroom Cap to a Varsity Jacket and Sailor Collar
- The Heirloom shelf: the Keeper's Peacoat, Rain Slicker, Koi Yukata, Sushi Chef, Snow Day Puffer and Fireflies

Fixed
- Goals outfits now show up for friends in Party
- The last row of the shop is never cut off

Thanks for focusing with Tabbi. Your pet says hi.
```

For 1.0.5:

```
Earn it! Goals come to the Closet: 48 badges from Bronze to Starlight and 16 mastery outfits you can only earn, never buy.

New
- Goals: badges for focus time, study days, streaks, sessions, flashcards, tasks, break moves, Party, study methods, steady weeks, water and monthly quests
- 16 mastery outfits unlocked by badges, from a wizard's robe to a spacesuit
- Monthly quests: three gentle goals each month, nothing lost if you miss one
- Your whole history counts, so badges you already earned unlock right away

Fixed
- The widget never goes blank or white

Thanks for focusing with Tabbi. Your pet says hi.
```

For 1.0.4:

```
Study with friends! Party comes to the App Store edition, so you can see when friends are focusing and study side by side.

New
- Party: friend codes, invite links and study parties, with report and block
- AI Usage: see your Claude Code or Codex usage from the folder you pick
- Do Not Disturb during focus, through two shortcuts you make
- Optional crash reports, sent only when you say so

Better
- Settings say plainly what happens before your Mac asks for permission

Thanks for focusing with Tabbi. Your pet says hi.
```

### App Privacy (nutrition label answer sheet)

From 1.0.4 the App Store edition sends data to the Tabbi friends server in three optional cases: Party (once the user turns it on and answers the age question), the Sign in with Apple account, and a crash or hang report the user chose to send.
[backend/PRIVACY.md](../backend/PRIVACY.md) lists everything the server stores.
App Store Connect's App Privacy answers cannot be set through the API, so enter them by hand (App Store Connect > the app > App Privacy > Edit), exactly like this:

1. "Do you or your third-party partners collect data from this app?" Yes, we collect data from this app.
2. Data types to select (and nothing else):
   - Contact Info > Name
   - Contacts
   - Identifiers > User ID
   - Identifiers > Device ID
   - User Content > Other User Content
   - Usage Data > Product Interaction
   - Diagnostics > Crash Data
   - Diagnostics > Performance Data
3. For **Name** (the display name Party shows to friends and party members; any nickname works, up to 24 characters, and the server keeps it with the Party identity):
   - Usage: App Functionality only.
   - Linked to the user's identity: Yes.
   - Used for tracking: No.
4. For **Contacts** (the friend list Party keeps on the server: the friend codes the user is friends with, friend requests sent and received, and the codes the user blocked, and the Study Crew the user belongs to; Apple's definition counts a social graph):
   - Usage: App Functionality only.
   - Linked to the user's identity: Yes.
   - Used for tracking: No.
5. For **User ID** (the random Party friend code the user's data is filed under, and, with the optional account, Apple's app-specific user id):
   - Usage: App Functionality only.
   - Linked to the user's identity: Yes.
   - Used for tracking: No.
6. For **Device ID** (the random id each Mac's points are filed under in the sync document, and the per-Mac sign-in token, which the server keeps only as a hash):
   - Usage: App Functionality only.
   - Linked to the user's identity: Yes.
   - Used for tracking: No.
7. For **Other User Content** (the pet's look and name that Party shows and the account syncs, unlocked and granted items, the name and description of a Study Crew the user makes, whether the user hides their pet on crew pages, and the reports the user files about another user or a crew: the reason and an optional note, which only the maintainer reads):
   - Usage: App Functionality only.
   - Linked to the user's identity: Yes.
   - Used for tracking: No.
8. For **Product Interaction** (Party presence that friends and party members see: studying, on a break or away, the study method, when the phase ends, minutes today and the streak; the party the user is in and its shared session; study minutes per day for the weekly leaderboard; for a Study Crew member, each finished focus session's start, end and minutes, kept 14 days, and the minutes credited per day for the crew board; and, with the account, points per Mac, the days the user studied and the longest streak):
   - Usage: App Functionality only.
   - Linked to the user's identity: Yes.
   - Used for tracking: No.
9. For **Crash Data** (a crash report, sent only after the user clicks Send in the alert after a crash or chose to always send: app and macOS version, edition, crash type and the app's stack frames, with no identifier):
   - Usage: App Functionality only.
   - Linked to the user's identity: No.
   - Used for tracking: No.
10. For **Performance Data** (a hang report, the same consent and contents when the main thread stopped answering):
    - Usage: App Functionality only.
    - Linked to the user's identity: No.
    - Used for tracking: No.

The privacy manifest the build ships (`packaging/PrivacyInfo-AppStore.xcprivacy`, copied into the app by `scripts/assemble.sh`) declares these same eight types with the same answers, and `AppStoreEntitlementsTests` checks it, so change all three together.
It also gives the required reasons for the APIs the binary links: UserDefaults (CA92.1, the app's own settings) and file timestamps (C617.1 for files in the app's container, and 3B52.1 for the Claude Code and Codex logs AI Usage scans in the folder the user picked).
The widget extension has its own manifest (`PrivacyInfo-AppStore-Widget.xcprivacy`) with the same reasons and no collected data.
If App Store Connect warns about a required reason API (ITMS-91053), add it to both manifests with the reason that matches the code.

Study Crews add no data type: a crew's name and description are Other User Content, membership belongs to the social graph under Contacts, and finished focus sessions are Product Interaction, all for App Functionality, linked to the Party identity and not used for tracking, so the selections and the privacy manifest stay exactly as they are; only the descriptions above (and `backend/PRIVACY.md`) gained the crew details.
Name, Contacts, Device ID and Product Interaction are the cautious reading: Apple's definitions are loose, and declaring a type the app arguably does not need costs nothing, while leaving out one it does is a mislabel.
Party works without an account: its identity is a random token on the Mac and a friend code on the server, and "linked" means linked to that identity, which Apple counts as the user's identity.

Why nothing else is declared:

- Email Address: never asked for or stored; Sign in with Apple asks Apple only for the name, which stays on the Mac.
- Birthday or age: Party's age question keeps only the date the user surely turns 13, on the Mac, and sends nothing, so it is not collected.
- Calendar events, tasks, focus history, study tallies, the activity log and AI chats stay on the Mac in the app's container.
- AI Usage reads the Claude Code or Codex logs in the folder the user picked and keeps its totals on the Mac; nothing from them is sent.
- Do Not Disturb runs the user's shortcuts on the Mac through Shortcuts Events; nothing is sent.
- Album artwork is loaded from the address the player reports (Spotify's `i.scdn.co`) with no identifier of the user.
- AnkiConnect and Ollama are reached on `localhost` only.
- Ask AI, Plan my day, Refine and Wrap up send text only to the AI provider the user picks, with the user's own key (Anthropic, OpenAI or Google), or to Ollama on the Mac.
  The request goes straight from the Mac to that provider under its own terms; there is no Tabbi server in between and no partner SDK in the app, so Tabbi does not collect it.
- The server's short request logs hold only the kind of request, its status and duration, with no identifier, and are deleted within 7 days; IP addresses are used only in memory for rate limits.
- The Suggest page opens in the browser with the app version, macOS version and edition in its address, and nothing is sent unless the user submits the web form, so it is the website's collection, not the app's (the site Privacy Policy covers it).
- There is no analytics, advertising or tracking of any kind.

Before submitting, check that the Worker has the Sign in with Apple secrets ([sync.md](sync.md), step 5): without them Delete Account still erases the server's data but cannot revoke the Apple grant, and the reviewer note below would then promise more than the app does.

### Notes for the reviewer

Paste these lines into App Store Connect > the version > App Review Information > Notes (3336 characters with single spaces, of the 4000 allowed), after replacing `DEMO_CODE` with the demo friend's code (below).

> Tabbi turns the area around the notch at the top of a MacBook screen into a small panel of tabs: a focus timer, today's tasks and calendar, now playing, study tools, study with friends and a pixel pet.
> There is no Dock icon and no window at launch; the app lives at the top center of the screen. Click the black notch area to open the panel, or press Control-Option-Space. On a Mac without a notch, Tabbi draws a small black pill at the top center of the menu bar.
> The first launch shows a short setup inside the panel (name, kit, tabs). Settings open from the gear at the right of the panel's header.
> Permissions are optional and each has a screen with Continue (macOS asks next) and Not now: Calendar (today's events), Automation for Music or Spotify (now playing), notifications (timer alerts), and Automation for Shortcuts Events (Do Not Disturb during focus runs two shortcuts the user makes; Settings > Tabs > Today > gear > Do Not Disturb). Declining keeps everything else working.
> AI features stay off until the user picks an AI in Settings > Connections > AI: their own API key (Anthropic, OpenAI or Gemini, in the Keychain) or Ollama on the Mac. Guideline 5.1.2(i): picking a company first shows a consent alert naming it and what each feature sends; Cancel keeps None.
> AI Usage (optional tab) shows Claude Code or Codex usage from the logs those tools keep on the Mac. It reads nothing until the user presses Continue and picks the folder in the standard open panel; nothing is sent.
> PARTY (study with friends, optional, needs no account). To test it alone:
> 1. Settings > Tabs > Add more > Party (or turn it on in setup). Open the Party tab.
> 2. It asks for birth month and year, only now and with Not now beside it; it stays off for anyone under 13 and keeps only the date the user turns 13, on the Mac. Pick any adult date and Continue.
> 3. In Friends, type our demo friend's code DEMO_CODE and press Return. It accepts at once and shows in the list.
> 4. Right-click Demo Friend > Report: pick a reason, Send Report (Also block is on by default). The report reaches our moderation queue. Or right-click > Block.
> 5. Start a party for a party code and invite link (tabbi:// links open the app).
> STUDY CREWS (same tab): click Crews at the top left of the Party tab, then Find, open Tabbi Review Crew to see its members' pets, and Ask to join; the demo account owns it and approves within a minute (an invite link joins at once). Focus minutes from then on count toward This week's top 3 (it freezes Sunday 23:59 UTC); Hall of Fame keeps the medals. Report a crew with the flag on its page; right-click a member to report or block; owners approve or decline requests and can remove members. Create a crew makes one (name, crest, public or private). Top 3 crews win only a laurel and a medal on their crest, never points or purchases.
> Names pass a filter on the Mac and the server; the maintainer reviews every report and can rename or ban an identity. Contact: support@tabbinotch.com.
> Signing in with Apple (Settings > General > Account) is optional, only syncs the pet, streaks and Party identity between the user's Macs, and asks for no personal information or birthday. Delete Account there deletes everything the server holds and revokes the grant (5.1.1(v)).
> After a crash, an alert asks before sending a crash report (Send or Don't Send), and shows exactly what is sent.
> The Privacy Policy and Terms of Use are linked from Settings > About.

Party needs a second person for its friend, report and block steps, so the reviewer gets a demo friend: an ordinary Party account on the production server that the maintainer creates once with `backend/scripts/demo-friend.ts`.
It registers as a protocol 1 app, so a friend request to it becomes a friendship at once ([party-compatibility.md](party-compatibility.md)) and nobody has to accept it; it shares only the name Demo Friend and a cat called Mochi, never adds anyone, and can be reported and blocked like anyone else.
Its secret token stays in a file of the maintainer's, outside the repository.

```sh
cd backend
npm run demo-friend -- create --url https://tabbi-friends.drosophil-anki-friends-backend.workers.dev --token-file ~/.tabbi-demo-friend.json
# prints the friend code for the notes; once is enough, the account stays
npm run demo-friend -- study --url https://tabbi-friends.drosophil-anki-friends-backend.workers.dev --token-file ~/.tabbi-demo-friend.json --hours 48 --party
# optional, while the build is in review: shows it studying in a party the reviewer can join from the friend list
npm run demo-friend -- study --url https://tabbi-friends.drosophil-anki-friends-backend.workers.dev --token-file ~/.tabbi-demo-friend.json --hours 48 --crew
# for a build with Study Crews: keeps the public crew Tabbi Review Crew the notes point to, with the demo friend's minutes on the board, and approves the reviewer's request to join it
```

Reports the reviewer files about the demo friend land in the moderation queue like any other; resolve them as "no action" and never ban it.
If a later protocol ever drops protocol 1 (`minProtocol` above 1), the demo friend needs a server-side way to accept requests at once before that release.

### App Review history

Version 1.0.0 (build 130) was rejected on 19 October 2026, reviewed on a MacBook Air with macOS 27.0, for three things, all fixed in 1.0.3:

1. Guideline 5.1.1(v), a required birthday: Sign In in Settings > General asked for the birth month and year before Apple's button.
   Signing in now never asks; the Account row shows Apple's button straight away, with the Terms and Privacy Policy links.
   The birthday is Party's alone (then direct download only; in the App Store edition too from 1.0.4), asked when Party is turned on, with Not now beside it.
2. Guideline 5.1.1(iv), "Allow Access" before the calendar prompt: the onboarding step's button now says Continue, with Not now in the footer.
   The same pass changed every screen before a macOS prompt: Settings > Connections' priming sheets lost "Click Allow." and gained Not now, Ask AI's Screen Recording card says Continue, and the study mixer's denied chip says "Spotify access is off" instead of "Allow Spotify access".
   The AI consent alert keeps Allow, since it is the consent itself (guideline 5.1.2(i)), not a step before a system prompt.
3. Guideline 2.1(a), nothing happened after the birthday: the age question lived in a sheet whose Continue swapped in SwiftUI's `SignInWithAppleButton`, so Apple's native request ran from inside that sheet.
   Reproduced on macOS 27.0.1 with the 1.0.2 code, driven step by step from a fresh sandbox container: onboarding, the calendar prompt and the birthday sheet all work, and with the web flow (ad-hoc builds) Continue shows Apple's button.
   With the native flow forced on (the reviewed build's path; an ad-hoc build cannot get the entitlement, so Apple refuses the request), pressing Apple's button in the sheet changes nothing in the sheet: the failure lands as an unlocalized line in the dimmed row behind it, and the sheet just sits there.
   The signed build's request may fail for another reason, but whatever it was, the reviewer could only see the sheet.
   The sheet is gone, the button sits in the Settings window itself, and `AppleNativeSignIn` makes the app active and hands Apple's sheet that window before it asks; a failure now shows in the row the user is looking at, in their language.

The reply to App Review is in the 1.0.3 submission notes.

Plan for the Study Crews release, so it does not repeat those rejections:

- Guideline 1.2 (user-generated content): crew names and descriptions pass the same name filter on the Mac and the server, a crew and each member can be reported, members can block each other, owners can remove members, and the maintainer can rename, hide or delete a crew from the crews moderation queue (`GET /v1/admin/crews/reports`) as well as ban the people in it; the notes above name each step.
- Guideline 5.1.1 (data and age): Crews ask for no new data and follow Party's age check, so they stay off under 13 and the server never receives an age; the App Privacy selections and age rating answers stay as they are (answer sheet above), with the descriptions updated.
- Guideline 2.1 (completeness): the reviewer can test every step alone, since the demo friend keeps a public crew (`study --crew`), and a new crew can be made and left at once.
- Guideline 3.1.1 and 5.3 (no purchases, no contests): the weekly top 3 win only a laurel on their icon, a trophy count and a featured spot; no points, prizes, payments or chance are involved.
- Before submitting: deploy the Worker with protocol 3 and the crews migration, deploy the site with its `/crew/<code>` page, run `demo-friend study --crew`, and check Find, asking to join and the approval, the board, the Hall of Fame and reporting on the TestFlight build against production.

### Checklist for 1.0.4 (what the maintainer sets by hand)

App Store Connect's App Privacy and Age Rating answers cannot be set through the API, so these steps are by hand, in this order:

1. Deploy the website first (`site/deploy.sh`): its Privacy Policy and FAQ now say the App Store edition has Party, AI Usage, Do Not Disturb and crash reports from 1.0.4, and the reviewer reads the policy at the Privacy Policy URL.
2. Create the demo friend on the production server (Notes for the reviewer above) and keep its token file in the password manager.
3. Raise `CFBundleShortVersionString` to 1.0.4 in the release change, run `scripts/release-appstore.sh`, validate and upload the package.
4. On the TestFlight build, check what an ad-hoc build cannot: Apple's native Sign in with Apple sheet; Do Not Disturb (turn it on, Continue, allow Shortcuts Events when macOS asks, and press Test with two real shortcuts); and Party against the production server with the demo friend (add, report, block).
5. App Privacy > Edit: select the eight data types in the answer sheet above, answer each one as written, and Publish (the label applies to every version once published, so do it just before submitting).
6. App Information > Age Ratings > Edit: the answers under App information above; confirm the result (13+ expected).
7. Version 1.0.5 (the 1.0.4 version in App Store Connect was renamed to 1.0.5 and never submitted): What's New from this page; Promotional text, Description and Keywords are already set.
8. App Review Information > Notes: the reviewer notes above, with `DEMO_CODE` replaced; Sign-in required stays off.
9. Keep an eye on the moderation queue (`GET /v1/admin/reports`) while the build is in review, and resolve the reviewer's test report as "no action".
10. Optional, while in review: run the demo friend's `study --party` for 48 hours so the reviewer sees it online in a party.

### Screenshots

Upload the second set, in [`appstore/screenshots-v2`](appstore/screenshots-v2), from 1.0.3 on.
They are nine 2880x1800 (16:10) flattened 8-bit PNGs in sRGB IEC61966-2.1 with no alpha.
Upload them in file name order; the first two show in search results, so they carry the story (the cozy notch and the themes).

1. `01-cozy-timer`: "Your notch, but cozy" with "A focus timer with a pixel cat who cheers you on.", the Timer in round 2 of 4 in the Cozy theme, with Mochi and the chocolate British Longhair, both in the Cozy Hoodie and Beanie.
2. `02-themes`: "Pick from 18 cozy themes", the same Timer in nine Sweet themes (Strawberry Milk, Blueberry Milk, Matcha Latte, Taro, Banana Milk, Deep Sea, Cherry Soda, Stargazer and Mint Choco), each hanging in a small screen tinted to match and named below it.
3. `03-plan-today`: "Your whole day, one glance" with "To-dos, calendar and a gentle Plan my day.", Today in Matcha Latte.
4. `04-closet`: "Dress up your own pet" with "Earn outfits by focusing. Pick a cat or a dog.", the Closet's Look section in Strawberry Milk over a lineup of seven pets (an orange tabby, a corgi, the chocolate British Longhair, Mochi, a French Bulldog in the Dinosaur Hoodie, a tuxedo cat and a Siamese).
5. `05-break-buddy`: "Stretch breaks with a friend" with "Your cat leads a little stretch, then back to it.", the Break Buddy card in Taro.
6. `06-flashcards`: "Flashcards due, at a glance" with "See what is due and jump into a deck.", the flashcards tab in Blueberry Milk (the tab shows the module's real name; captions never name it).
7. `07-music`: "Music without switching apps" with "Play, skip and like songs from your notch.", Now Playing with the fictional "Golden Hour Drive" in Stargazer, on a night sky (the Dark Mode shot).
8. `08-ask-ai`: "Ask AI, right from the notch" with "With the AI you pick. Nothing is sent until you do.", Ask AI in Deep Sea.
9. `09-week-recap`: "Your week, wrapped up" with "Gentle streaks that never punish a day off.", the weekly recap card in Banana Milk.

Every panel is the app's own snapshot of the App Store edition in demo mode, drawn 1:1 at 3 pixels per point (the theme grid at 1.4), so no UI is redrawn and no real data shows.
Party, AI Usage, birthdays and permission pre-prompts appear nowhere, and no pet wears a cape or wings.
The set stays accurate for 1.0.4, which only adds features; a Party shot (`open-party` in the demo snapshots) could replace one of the last three later.
The design: each shot takes the colors of the theme its panel wears (a light ground, a deeper floor and a soft glow of the theme's color behind the panel), with a plain translucent menu bar and the panel hanging from the top center like the open notch (no device, no Apple logo, no menus).
Below it sit a one-line Bagel Fat One headline (92 CSS px on a 1440x900 page at 2x) and a Fredoka SemiBold subline (34 px), with the pet on the floor and a few pixel sparkles in the theme's color.
Pets are drawn by the app's renderer (`swift run PetGallery <folder> store`, which writes the lineup this set uses) and scaled by whole numbers with nearest neighbor, so the pixel art stays sharp.
Both fonts are bundled in [`appstore/fonts`](appstore/fonts) with their SIL Open Font Licenses.
[`appstore/screenshots-v2/review/contact-sheet.png`](appstore/screenshots-v2/review/contact-sheet.png) is a review copy of the whole set; do not upload it.

To render the set again after a UI change, run:

```sh
docs/appstore/screens-v2/build.sh
```

It builds the app, renders the demo snapshots once per theme the set uses (`--edition appstore --tabs study,planner,anki,spotify,claudeAsk,closet --transparent --scale 3 --theme <id>`, in parallel) and the pet lineup into `docs/appstore/screens-v2/build`, then has headless Chrome screenshot [`appstore/screens-v2/shots.html`](appstore/screens-v2/shots.html) once per shot and flattens each PNG with `sips`.
`--compose` skips the rendering and composes from the last render, which is the quick way to try a headline.
The headlines, sublines, themes, panels and pets of every shot are one list at the top of `shots.html`; open it in a browser with `?shot=all` to see the whole set.
The clocks in the demo panels are live, so every run changes the shots that show a timer; commit only the images you meant to change.

The first set, in [`appstore/screenshots`](appstore/screenshots), is kept below for reference and for the App Preview, which `make-media.swift` still composes.

The screenshots in [`appstore/screenshots`](appstore/screenshots) follow the production spec (`research/screenshots.md` in the runs folder).
They are 2880x1800 (16:10) flattened 8-bit PNGs in sRGB IEC61966-2.1 with no alpha, as App Store Connect requires for Mac apps.
In file name order:

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
Party and the AI usage tab were left out of the App Store edition when this set was made, so neither appears.
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
