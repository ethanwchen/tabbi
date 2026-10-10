# IP review: trademarks, licenses and third-party terms

RESEARCH NOTES - NOT LEGAL ADVICE - REVIEW WITH A LICENSED ATTORNEY BEFORE ACTING

This is a first pass, not a clearance opinion.
A trademark clearance opinion requires a full professional search (USPTO, state registries, common law sources, international registries, app stores, domains and social handles) and attorney judgment on likelihood of confusion.
A "no obvious conflicts" result here means this triage did not find anything; it does not mean a mark is clear.

It follows the ip-legal clearance and oss-review workflows and the product-legal marketing-claims-review workflow, run in provisional mode against `profile.md` (US first, worldwide distribution, individual operator, open source under MIT).
Reviewed on 9 October 2026 against the code on branch `gnhf/legal-review`.

## Bottom line

- REQUIRED, fixed: the direct download shipped Sparkle.framework without Sparkle's license text, which its MIT, BSD (bsdiff) and zlib (ed25519) terms require in binary copies.
  `scripts/assemble.sh` now copies the license from SwiftPM's checkout into `Tabbi.app/Contents/Resources/Acknowledgements/Sparkle-LICENSE.txt` and fails the build if it cannot find it.
- HIGH, open (maintainer decision): the planned App Store name `Tabbi: Notch Focus Timer` contains, word for word, the name of an existing Mac App Store app, "Notch Focus Timer" by Balaji Venkatesh (id6477333821), which also does a focus timer around the notch.
  The words are descriptive, but the overlap is exact, in the same store, category and function, which invites a complaint under App Review Guideline 4.1 (copycats) and 5.2 (intellectual property) and a likelihood-of-confusion argument.
- MEDIUM, open: the word mark TABBI is used by others, including Tabbi (a US bar and restaurant payment app), a Firefox add-on called Tabbi, and a pending ASK TABBI application for disinfectants.
  None is a desktop productivity app that this triage found, but a Class 9 or 42 search has not been run.
- LOW, fixed: Terms section 3 said the app bundles fonts; it bundles none (it uses Apple's system fonts), so it now names Sparkle and the website's OFL fonts instead.
- Everything else inventoried below is original, permissively licensed with its notice present, or used only descriptively.

## 1. Trademark triage

### TABBI (house mark)

Goods and services: downloadable macOS productivity software (Nice Class 9) and an online social service for study groups (Class 42 or 45).
Jurisdictions: United States first; distributed worldwide.

Knockout factors:

- Distinctiveness: TABBI is a coined spelling of "tabby" (a cat coat) and a play on "tabs".
  For productivity software that shows tabs it is at most suggestive, so it is likely registrable on distinctiveness.
- No surname, geographic, deceptive or prohibited-matter issue found.

Similar marks found (web search only; no USPTO or TSDR access in this environment):

| Mark | Owner and use | Overlap |
| --- | --- | --- |
| TABBI | Tabbi, a mobile payment app for bars and restaurants (Greenville, US; the maintainer reports it as "Tabbi Inc") | Same word, both apps; different function (payments vs productivity) |
| Tabbi | A Firefox browser add-on (addons.mozilla.org/firefox/addon/tabbi) | Same word, software, possibly tab management |
| ASK TABBI | US application 99557137, filed 19 December 2025, disinfectants | Same word, unrelated goods |
| TABBY | Tabby (buy-now-pay-later, UAE and Saudi Arabia) and the Tabby terminal app | Sound-alike, software; one is a fintech with registrations in many classes |

Likelihood-of-confusion factors (Second Circuit Polaroid, since the operator is in New York), flagged and not concluded:

- Similarity of marks: identical spelling for Tabbi; near-identical sound for Tabby.
- Proximity of goods: all are apps, which weighs toward confusion; the functions differ.
- Strength of the senior marks: unknown without a registry search.
- Bridging the gap: a payments app is unlikely to move into notch productivity, but a tab manager add-on is close.
- Actual confusion: none known.
- Good faith: the name was picked for the cat and the tabs, with no intent to trade on others.
- Sophistication of buyers: free apps; low care at download time, which weighs toward confusion.

Recommended next steps: a full USPTO and EUIPO search in Classes 9, 42 and 45 and an App Store and domain sweep, then decide whether to file an intent-to-use or use-based application for TABBI in Class 9.
Until then the app and site use the name with no (R) symbol, which is correct for an unregistered mark.

### NOTCH FOCUS TIMER (App Store subtitle in the name field)

- "Notch Focus Timer" is the full name of an existing free Mac App Store app with the same function (focus timer that wraps the notch).
- Descriptive phrases are weak marks, but App Review looks at listing similarity, and the other developer could object through Apple's App Store content dispute form.
- `docs/appstore.md` used to say the name "names no other company's product"; it now flags the conflict and suggests alternatives.
- Options: keep the descriptive keywords but change their order and add a word (for example `Tabbi: Notch Timer & Study Pet`), or move "notch" and "focus timer" to the subtitle and keywords.
  The renaming is a product and ASO decision, so it is left to the maintainer (see review.md).

### Third-party marks used by Tabbi

| Mark | Where | Use | Assessment |
| --- | --- | --- | --- |
| Apple, Mac, MacBook, Apple Music, Sign in with Apple, App Store | Site, README, listing, app | To say what Tabbi runs on and works with | Descriptive (nominative) use. Apple's guidelines ask for the full mark spelled correctly, never possessive or plural, and no Apple logo; the copy follows this. "notch" is a common word, not an Apple mark. Sign in with Apple uses the system button. |
| Spotify, SoundCloud | Now Playing copy | To say which players Now Playing controls | Nominative use, no logos. See section 3 for their terms. |
| Anki, AnkiConnect | Anki tab, Med School kit | To say which flashcard app it reads | Nominative use. Anki is open source (AGPL); Tabbi bundles none of its code. |
| Claude, Claude Code, Anthropic, OpenAI, Codex, Gemini, Google, Ollama | AI provider picker, consent alert, docs | To name the provider the user picks and who receives data | Nominative use, and required by Guideline 5.1.2(i) to name the recipient. No provider logos are bundled (the picker uses SF Symbols). |

The Terms of Use (section 3) say these names belong to their owners, are used only to say what Tabbi works with, and that Tabbi is not affiliated with or endorsed by any of them.

## 2. Open source and asset licenses

Deployment model: distributed binary (direct download, signed and notarized, with Sparkle; and the Mac App Store build, without Sparkle).
Outbound license: MIT (`LICENSE`), copyright the maintainer.

### Dependencies

| Package | License (read from the text in `.build/checkouts/Sparkle/LICENSE`) | Class | Ships in | Obligation | Status |
| --- | --- | --- | --- | --- | --- |
| Sparkle 2.10.0 | MIT (Sparkle authors), plus bsdiff (BSD-2-Clause style), ed25519 (zlib), sais-lite (MIT) and others listed under External Licenses | Permissive | Direct download only (`Package.swift` drops it under `TABBI_APPSTORE=1`) | Keep the copyright and permission notices in copies; the BSD part asks binary copies to reproduce them in documentation or other materials provided with the distribution | Fixed: the license now ships in the app bundle |

There are no other Swift package dependencies (`Package.resolved` lists only Sparkle), so there is no copyleft in the shipped binary.
The backend has no runtime npm dependencies (`backend/package.json` lists only dev tools: Wrangler, Vitest, TypeScript and Cloudflare's types), so nothing third-party is deployed with the Worker beyond what Wrangler bundles from its own code.

Compatibility: MIT outbound with MIT, BSD and zlib inbound is compatible.

### Bundled assets

| Asset | Source | License or ownership | Notes |
| --- | --- | --- | --- |
| App icon (`Resources/AppIcon.icns`) and brand art (`docs/brand/assets`) | Made by `scripts/make-icon.swift` from `docs/brand/source/tabbi-cover.png` | The cover was generated with OpenAI's image model (its C2PA manifest is signed by OpenAI) from the maintainer's prompt; OpenAI's terms assign output rights to the user | In the US, purely AI-generated imagery gets little or no copyright protection (Copyright Office guidance, Thaler v. Perlmutter), so others may be able to copy the cover art itself. The squircle mask, glyph and code-drawn parts are the maintainer's. Trademark rights in the icon come from use and are unaffected. |
| Pet sprites (`Sources/TabbiKitCore/Pets/PetArt/*.json`) | Hand-made pixel art in JSON, drawn in code | Original, MIT with the repo | No third-party sprite sheets found. |
| Focus sounds (rain, fire, cafe and noise colors) | `TabbiKitCore/Focus` | Original code, MIT | Synthesized at run time following recipes from Andy Farnell's "Designing Sound"; techniques are not protected expression, and no recorded audio ships. The rebuilt cafe ambience is synthesized too. |
| Fonts in the app | Apple system fonts (SF Pro Rounded) through the system | Apple's macOS license | Nothing bundled. |
| Website fonts (`site/fonts`) | Nunito and Fredoka | SIL Open Font License 1.1, texts in `site/fonts/OFL-*.txt` | Compliant; the OFL allows web embedding and asks only that the license travel with the font files. |
| Screenshot font (`docs/appstore/fonts/Fredoka.ttf`) | Fredoka | OFL 1.1, text beside it | Compliant. |
| Website images, hero video and press kit | Rendered from the app's own snapshots | Original | Demo data names fictional songs and decks. |

## 3. Third-party terms for integrations

| Integration | How Tabbi uses it | Terms that apply | Risk |
| --- | --- | --- | --- |
| Spotify | AppleScript to the user's Spotify app; artwork from `i.scdn.co` | Spotify's Terms of Use for the user; no Spotify Developer Platform use (no Web API, no client id) | Low. If Tabbi ever uses the Web API, the Developer Terms and Design Guidelines (attribution, no caching of artwork) apply. |
| Apple Music | AppleScript to Music | Apple Media Services terms for the user | Low. |
| SoundCloud | AppleScript runs a small script in the user's open SoundCloud tab in Safari or Chrome, off by default | SoundCloud's Terms of Use for the user; no API key | Low to medium: SoundCloud's terms restrict automated access, but this controls the user's own player in their own session and sends nothing to Tabbi. A lawyer may want to confirm. |
| AnkiConnect | HTTP to `127.0.0.1:8765` | AnkiConnect is GPL-licensed; Tabbi bundles none of it and only talks to it over HTTP | Low; no copyleft reaches Tabbi. |
| Claude Code, Codex and Gemini CLIs (direct download) | Runs the user's own installed CLI with the user's own sign-in; Tabbi never reads its credentials | Anthropic, OpenAI and Google consumer or commercial terms for the user | Medium: providers have narrowed how subscription plans may be used by third-party tools. Tabbi runs the vendor's official CLI as the user, which is the most defensible form, but each provider's current terms should be checked before release. |
| Anthropic, OpenAI and Gemini APIs | The user's own key, stored in the Keychain | The provider's API terms bind the user; Tabbi is a client | Low, with the consent alert naming the recipient. |
| Ollama | Localhost | MIT | None. |
| Sign in with Apple | AuthenticationServices and a web flow | Apple Developer Program License Agreement | Low; the account deletion button meets Guideline 5.1.1(v). |

## 4. Marketing claims

Claims on the site, README and listing that need substantiation, checked against the code:

| Claim | Where | Substantiated? |
| --- | --- | --- |
| "Free" and "free forever" | Site, README, listing | True today (MIT, no paid tier). "Free forever" is a promise about the future; keep it only if the maintainer means it, or use "free and open source". |
| "No ads, no tracking, no analytics, no telemetry" | Site, README, FAQ | True: no SDKs, no analytics; the server keeps only aggregate counts; crash reports are opt-in. |
| "No account needed" | Site, README, listing | True; Sign in with Apple is optional. |
| "It only connects where a tab needs to: album artwork, AnkiConnect and the friends server" | README Privacy | Incomplete: it leaves out update checks (Sparkle, direct download), opt-in crash reports, the Suggest form, sync and the AI provider the user picks (named two lines later). Fix in the README privacy pass. |
| "Events never leave your Mac" | README permissions table | Not quite: Refine and Wrap up send event titles and times to the AI the user picked, which the next lines of the README say. Fix in the README privacy pass. |
| "Tabs only refresh while you can see them" | README | Mostly true by design rule; timers and the ticker run while closed by design, so "only" is broad. Low risk. |

## 5. Lawyer items from this review

1. A full trademark search for TABBI (Classes 9, 42, 45; US, EU, UK) and whether to file.
2. Whether the App Store name `Tabbi: Notch Focus Timer` should change given the existing "Notch Focus Timer" app.
3. Whether running the user's own Claude Code, Codex and Gemini CLIs from Tabbi fits each provider's current terms for subscription plans.
4. Whether the AI-generated icon art needs any further protection (for example registering the icon as a trademark once in use).
