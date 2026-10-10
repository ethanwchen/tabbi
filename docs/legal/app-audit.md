# App audit: code against policy

RESEARCH NOTES - NOT LEGAL ADVICE - REVIEW WITH A LICENSED ATTORNEY BEFORE ACTING

This compares the macOS app (`Sources/`) with the site Privacy Policy (`site/_legal.py`) and `docs/appstore.md`, following the policy-monitor workflow.

## What checks out

- No analytics or third-party SDKs; Sparkle 2.10.0 is the only dependency, direct download only, with system profiling off.
- No font or CDN fetches. Calendar data (titles and times only, no attendees, locations or notes) leaves the Mac only in AI prompts.
- Crash reports: the payload is versions, edition, kind and cleaned thread names and frames, with home paths replaced by `~`. The default is to ask, and the prompt shows the exact body. None of this is in the App Store build.
- Delete Account and Delete my Party data both call `DELETE /v1/me`.
- The widget has no network entitlement.
- User-written content is limited to display name, pet name and the report note; there is no chat. Names go through `PartyNameFilter`, mirrored on the server.

## Gaps that need a fix

1. **No AI consent sheet (App Store Guideline 5.1.2(i)).** Once a provider is picked, every AI feature sends with no disclosure naming the provider and the data. The only notice is the Screen Recording priming screen. A one-time consent sheet per provider is needed in `Modules/AI`.
2. **No age gate and no legal links in the app.** No birthdate or age prompt anywhere, and no privacy or terms link in onboarding, Party setup, Sign in or Settings > About (which links a stale repo, `github.com/ethanwchen/notchdeck`).
3. **Party registers as soon as its setup step appears** (`PartyOnboardingView`), before any notice beyond "Friends see your name, your pet and when you're studying".

## Policy text that is wrong or silent

1. The short version says only Party and Sign in with Apple talk to the server; crash reports go there too (`CrashReporting.swift`), and the crash paragraph never says where reports go.
2. The App Store edition has no Party (`appstore.json` excludes `party` and `claudeUsage`), so its Party and "Delete my Party data" sections apply to the direct download only.
3. "Plan my day works out its plan on your Mac": a `.claude` plan mode exists that sends the plan request to the AI, reachable only through a custom kit.
4. What the AI features send is listed loosely:
   - Ask AI also re-sends earlier turns of the chat (up to about 24,000 characters).
   - Refine also sends event times, free slots, the current time, shared goals such as Anki cards left, and plan block titles. Planning ahead sends tomorrow's events.
   - Day review sends no events, but does send points and goal counts, as soon as Wrap up opens if a provider is ready.
5. AI Usage is not only "read-only local logs": opening it runs `claude` with the prompt "ok" on the haiku model to read rate limits, a real request through the user's account.
6. "Your name is never sent to our server": in the direct download's browser sign-in, Apple posts the name to the Worker callback on first sign-in. The server ignores it, but it does arrive.
7. Party (and sign-in) can point at a custom friends server (Settings, Party options), which the policy does not mention.
8. Artwork is fetched from whatever URL the player reports, not only `i.scdn.co` and `i1.sndcdn.com`.
9. Sparkle checks at launch as well as once a day.
10. The Pet Coach samples idle time and the frontmost app during focus phases, on the Mac only; the policy is silent.
11. There is no `PrivacyInfo.xcprivacy` privacy manifest, which App Store uploads expect for some APIs.
