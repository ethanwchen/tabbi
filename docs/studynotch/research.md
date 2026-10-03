# StudyNotch research notes

Researched 2026-10-01 for the coding agents building StudyNotch (macOS 14+, Swift/SwiftUI).
Confidence labels: **[verified]** = checked against primary source or tested on this machine (macOS 26.6.2); **[source]** = from a cited secondary/primary page, not tested; **[memory/uncertain]** = from background knowledge, check before relying on it.

---

## 1. AnkiConnect (add-on 2055492159)

Sources: README https://git.sr.ht/~foosoft/anki-connect/blob/master/README.md ; source `plugin/__init__.py`, `plugin/web.py`, `plugin/util.py`, `plugin/config.json` in the same repo (the GitHub repo FooSoft/anki-connect is just a redirect to sr.ht). The code below was read from `master` on 2026-10-01.

### 1.1 Version and transport [verified]
- **API version: 6** (`util.py` default `'apiVersion': 6`; README: "Currently versions `1` through `6` are defined"). Always send `"version": 6`. If you leave out `version` it defaults to 4, and then the reply is only the bare `result` with no `error` field.
- Minimum Anki the add-on supports: `required_anki_version = (23, 10, 0)` (`__init__.py`).
- Transport: HTTP `POST http://127.0.0.1:8765` (bind address `127.0.0.1`, port `8765` by default). Body is JSON `{"action": String, "version": 6, "params": {...}?, "key": String?}`.
- Reply is always `{"result": <any>, "error": <string|null>}`. Errors look like `{"result": null, "error": "unsupported action"}`. **The HTTP status is 200 even when there is an application error.** Check `error`.
- An empty-body POST from an allowed origin returns `{"apiVersion": "AnkiConnect v.6"}`, which works as a cheap probe.
- `multi` batches several actions: `{"action":"multi","version":6,"params":{"actions":[{"action":"deckNames"},{"action":"getNumCardsReviewedToday"}]}}`. It returns a list of per-action `{result,error}` objects. Inner actions inherit version 4 semantics unless you put `"version":6` inside each one, so do that.
- The default config (`plugin/config.json`) is:
  ```json
  {"apiKey": null, "apiLogPath": null, "webBindAddress": "127.0.0.1", "webBindPort": 8765,
   "webCorsOriginList": ["http://localhost"], "ignoreOriginList": []}
  ```
- **App Nap:** the README warns that macOS App Nap suspends Anki when it is in the background, and then AnkiConnect stops answering. Its suggested fix is `defaults write net.ankiweb.dtop NSAppSleepDisabled -bool true` and restarting Anki. Show this as a troubleshooting tip when requests time out while Anki is running. (On newer launcher builds the domain may be `net.ankiweb.anki`; see 1.6.)

### 1.2 CORS / origin: does a native app need it? [verified from web.py]
`allowOrigin()` in `web.py`:
- If `"*"` is in `webCorsOriginList`, everything is allowed.
- If the request **has an `Origin` header**, it must be in the list, or be `http://127.0.0.1[:port]` or a `chrome-/moz-/safari-web-extension://` origin when `http://localhost` is in the list.
- **If there is no `Origin` header, `allowed = True`.**

`URLSession` does not add an `Origin` header to a plain POST. **So a native Swift app needs no CORS configuration and no change to `webCorsOriginList`.** Do not set an `Origin` header yourself. CORS only matters for browsers and WKWebView.

### 1.3 requestPermission flow [verified]
- `requestPermission` is the only action allowed from an untrusted origin, and it skips the API key check.
- Trusted caller (which includes a native app with no Origin) → `{"permission":"granted","requireApikey":false,"version":6}` and no popup.
- Untrusted origin → Anki shows a Qt dialog. Yes adds the origin to `webCorsOriginList`. No with "ignore" ticked adds it to `ignoreOriginList`.
- **Key-name gotcha:** the README says `requireApiKey`, but the code returns **`requireApikey`** (lower-case k). Decode both spellings.
- If the user has set an `apiKey`, every other action needs `"key": "<value>"`. Otherwise the error is `"valid api key must be provided"`. Provide an optional API-key field in Settings, stored in the Keychain.
- Recommended handshake: `requestPermission` → if `granted`, store `version` (and require it to be ≥ 6) → if `requireApikey`, prompt for the key.

Request / response:
```json
{"action": "requestPermission", "version": 6}
{"result": {"permission": "granted", "requireApikey": false, "version": 6}, "error": null}
```

### 1.4 Actions you need

| Need | Action | Notes |
|---|---|---|
| Probe / version | `version` | `{"result":6,"error":null}` |
| List decks | `deckNames` → `["Default","Step1::Cardio"]`; `deckNamesAndIds` → `{"Default":1,...}` | Use ids as stable keys. Names use `::` for nesting. |
| Per-deck due counts | `getDeckStats` `{"decks":[names]}` | Gives `new_count`, `learn_count`, `review_count`, `total_in_deck`, read from Anki's `deck_due_tree()`, so they match the numbers in Anki's deck list (daily limits applied, children rolled up). The result is keyed by **deck id as a string**. |
| Reviewed today | `getNumCardsReviewedToday` | SQL counts `revlog` rows since the day cutoff. This counts **reviews (button presses)**, so a card answered twice counts twice. It respects the user's "next day starts at" setting. |
| Per-day history | `getNumCardsReviewedByDay` | `[["2026-09-30", 412], ...]`, newest first, all history, local time shifted by the rollover hour. This is the data for a heatmap or streak. |
| Raw review log | `cardReviews` `{"deck": name, "startID": msEpoch}` | 9-tuples `(reviewTime ms, cardID, usn, ease, newIvl, lastIvl, factor, durationMs, type)`. `startID` is exclusive. Use `getLatestReviewID {"deck"}` to sync incrementally. **Child decks are not included** (`cid in (select id from cards where did=?)` matches the exact deck id), so query each subdeck or use `findCards` + `getReviewsOfCards`. |
| Reviews per card | `getReviewsOfCards` `{"cards":[ids]}` | Dicts with keys `id, usn, ease, ivl, lastIvl, factor, time, type`. |
| Open deck overview | `guiDeckOverview` `{"name"}` → `true/false` | |
| Start review | `guiDeckReview` `{"name"}` → `true/false` | Selects the deck and moves to the review state. **It does not bring Anki to the front**, so also call `NSRunningApplication.activate()` (see 1.6). |
| Deck list screen | `guiDeckBrowser` | |
| Sync | `sync` → `{"result":null,"error":null}` | Errors with `"sync: auth not configured"` if the user has not logged in to AnkiWeb. It can also raise if a full sync is required. It runs on Anki's main thread and can take seconds, so use a timeout of 60 s or more and show a spinner. |
| Stats HTML | `getCollectionStatsHTML {"wholeCollection":true}` | A large HTML report. Not useful for native UI. |
| Search | `findCards {"query":"deck:\"Step1\" rated:1"}` → card ids | Anki search syntax: https://docs.ankiweb.net/searching.html |

**Retention-ish stats (no dedicated action):** work it out from the review log.
- **True retention** over the last N days: take `revlog` rows with `type == 1` (review; 0 = learn, 2 = relearn, 3 = filtered/cram, 4 = manual/rescheduled) and compute `1 - (count(ease==1) / count)`. `ease` is 1 = Again, 2 = Hard, 3 = Good, 4 = Easy.
- Cheap alternative with `findCards`: `rated:7` = cards answered in the last 7 days and `rated:7:1` = cards answered Again in that window. Then `1 - |rated:7:1| / |rated:7|`. This is a card-level approximation and it mixes in learning cards. Limit it with `is:review` if you want to.
- Time studied in Anki: sum `durationMs` (tuple index 7) over today's reviews.

Example `getDeckStats` (from the README):
```json
{"action":"getDeckStats","version":6,"params":{"decks":["Japanese::JLPT N5","Easy Spanish"]}}
{"result":{"1651445861967":{"deck_id":1651445861967,"name":"Japanese::JLPT N5","new_count":20,"learn_count":0,"review_count":0,"total_in_deck":1506},
           "1651445861960":{"deck_id":1651445861960,"name":"Easy Spanish","new_count":26,"learn_count":10,"review_count":5,"total_in_deck":852}},"error":null}
```
Example `cardReviews`:
```json
{"action":"cardReviews","version":6,"params":{"deck":"default","startID":1594194095740}}
{"result":[[1594194095746,1485369733217,-1,3,4,-60,2500,6157,0],[1594201393292,1485369902086,-1,1,-60,-60,0,4846,0]],"error":null}
```
Other examples:
```json
{"action":"getNumCardsReviewedToday","version":6}            → {"result":0,"error":null}
{"action":"getNumCardsReviewedByDay","version":6}            → {"result":[["2021-02-28",124],["2021-02-27",261]],"error":null}
{"action":"guiDeckReview","version":6,"params":{"name":"Default"}} → {"result":true,"error":null}
```

### 1.5 Telling the states apart [verified locally + reasoning]
| Observation | Meaning |
|---|---|
| Anki process not running | "Anki is closed" → offer an "Open Anki" button |
| Anki running, but `POST 127.0.0.1:8765` fails with `NSURLErrorCannotConnectToHost` (connection refused, curl exit 7) | AnkiConnect is missing or disabled, **or Anki is still starting up**. Retry with backoff for about 15 s after launch before you show "Install AnkiConnect (code 2055492159)". |
| Connection refused and Anki is not running | Anki is closed (same as the first row) |
| Timeout while Anki is running | App Nap, or a modal dialog is blocking Anki's main thread (AnkiConnect runs requests on the main thread). Show the App Nap tip. |
| HTTP 403 with an empty body | An `Origin` header was sent and rejected. This should not happen from a native app. |
| `error: "valid api key must be provided"` | The user has set an apiKey |
| `error: "unsupported action"` | The add-on version is too old for that action |
| `error: "collection is not available"`-style errors | The profile window is open and no collection is loaded |

Use a short `timeoutIntervalForRequest` (2–3 s) for polling and a long one for `sync`. Poll only while the notch is visible or a session is running. Every 60 s is enough. Use `multi` to batch requests.

ATS: `http://127.0.0.1` is plain HTTP. `NSAllowsLocalNetworking` (or the ATS localhost exemption) covers it. If the app is sandboxed it needs `com.apple.security.network.client`.

### 1.6 Detecting Anki by bundle id [verified on this Mac, partly uncertain]
- **The installed Anki on this machine (launcher build, `CFBundleShortVersionString` 26.9.2, signed "Developer ID Application: Anki Software LLC (ZL66D3NMZM)") has `CFBundleIdentifier = net.ankiweb.anki`.**
- The AnkiConnect README and older crash reports and app catalogs use **`net.ankiweb.dtop`** (e.g. https://doesitarm.com/app/anki and https://appcatalog.cloud/apps/anki report `net.ankiweb.dtop`, signed by Ankitects Pty Ltd 7ZM8SLJM4P). Since 25.07, Anki on macOS ships as a launcher (https://forums.ankiweb.net/t/always-getting-only-the-launcher-not-the-full-app-when-downloading-anki-from-the-official-site/64502), and the bundle id seems to have changed with it. **[uncertain: exact version of the change]**
- **Recommendation:** match either id, `["net.ankiweb.anki", "net.ankiweb.dtop"]`, through `NSWorkspace.shared.runningApplications` plus `didLaunch`/`didTerminateApplicationNotification`. Treat the HTTP probe as the source of truth for "AnkiConnect reachable". **[uncertain]** With the launcher, the running GUI process may be a child Python process, so it is not certain which bundle id `NSRunningApplication` reports. Fall back to `localizedName == "Anki"` and confirm with the HTTP probe.
- Launch: `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` (try both ids), then `openApplication(at:configuration:)`. Bring to front: `NSRunningApplication.activate()`. On macOS 14 `activate(options:)` with `.activateIgnoringOtherApps` is deprecated; plain `activate()` is fine.
- No special permissions are needed for any of this.

---

## 2. Study timer methods

**Evidence summary:**
- **What is well supported:** two study techniques, **retrieval practice (self-testing) and distributed/spaced practice**, rated "high utility" (Dunlosky et al. 2013, *Psychological Science in the Public Interest* 14(1), https://doi.org/10.1177/1529100612453266; Roediger & Karpicke 2006, https://doi.org/10.1111/j.1467-9280.2006.01693.x).
- **Breaks:** **taking scheduled breaks** has modest experimental support.
- **Specific interval lengths** (25, 52, 90) are mostly folklore.
- **Study 1:** Biwer, de Bruin & Persoon 2023 (*Br J Educ Psychol*, n = 87, https://cris.maastrichtuniversity.nl/en/publications/understanding-effort-regulation-comparing-pomodoro-breaks-and-sel, PMID 36859717). Self-regulated breaks led to longer sessions with "higher levels of fatigue and distractedness, and lower levels of concentration and motivation". Systematic (Pomodoro) breaks "had mood benefits and appeared to have efficiency benefits (i.e., similar task completion in shorter time)".
- **Study 2:** Smits, Wenzel & de Bruin 2025 (*Behavioral Sciences* 15(7):861, n = 94, https://pmc.ncbi.nlm.nih.gov/articles/PMC12292963/) compared self-regulated, Pomodoro and Flowtime breaks. "Pomodoro breaks led to a faster increase in fatigue, and Pomodoro and Flowtime breaks led to a faster decrease in motivation compared with self-regulated breaks", but there were **no overall differences** in fatigue, motivation, productivity, task completion or flow.
- **Takeaway:** "take regular breaks and pick a rhythm you'll stick to". No interval is proven best. Present the methods as presets, not as science.

Popover copy (2–3 sentences each), plus the default parameters:

1. **Pomodoro (25 / 5, long break 15–30 after 4)**. Created by Francesco Cirillo, late 1980s.
   *Popover:* "Work on one thing for 25 minutes, then take a 5-minute break away from the screen. After four rounds, take a longer 15–30 minute break. Short, fixed rounds make it easy to start and help keep fatigue down."
   *Evidence:* scheduled breaks beat ad-hoc breaks for mood and efficiency in one study (Biwer 2023). The 25-minute length itself is convention.

2. **52 / 17**.
   *Popover:* "Focus for 52 minutes, then take a full 17-minute break. Use the break to actually rest: stand up, move, get water. Good for longer reading or question blocks."
   *Evidence:* folklore. It comes from a 2014 DeskTime blog analysis of its most productive app users (correlational, not a study of learning; https://desktime.com/blog/17-52-ratio-most-productive-people). **[memory/uncertain]** DeskTime later published different numbers (e.g. 112/26 in 2021), which suggests the exact ratio is noise.

3. **Ultradian 90 / 20**.
   *Popover:* "Do one deep 90-minute block, then rest for about 20 minutes. Best for hard, deep work like a dense lecture or a long practice block. Do at most 3–4 of these a day."
   *Evidence:* weak. The "basic rest-activity cycle" comes from Kleitman's sleep research, and evidence for strict 90-minute daytime cycles is thin. Ericsson et al. 1993 (*Psych Review* 100(3), https://doi.org/10.1037/0033-295X.100.3.363) found elite performers practised in sessions of about an hour or more, roughly 4 h/day at most. That supports "limit deep work per day" more than the exact 90 minutes.

4. **Flowtime (open-ended, proportional breaks)**. Popularised by Zoë Read-Bivens.
   *Popover:* "Start the timer and study until your focus starts to slip, then stop. Your break scales with how long you worked (about 5 min after 25 or less, 8 min after 25–50, 10 min after 50+). It keeps you in flow without hard interruptions."
   *Implementation:* break = 5 min if work ≤ 25, 8 if ≤ 50, else 10 (the scheme used in Smits 2025). Offer a "work ÷ 5" option as an alternative.
   *Evidence:* no better or worse than Pomodoro overall (Smits 2025).

5. **Anki sprint (card-count goal)**. A StudyNotch-specific method.
   *Popover:* "Pick a number of cards, for example 100, and go through them without stopping. The timer counts cards (from AnkiConnect), not minutes, and ends when you hit the goal. Do your due reviews before adding new cards."
   *Implementation:* the goal is the delta of `getNumCardsReviewedToday` since the sprint started. Default the goal to `review_count + learn_count` from `getDeckStats`. Show cards/min and an ETA. Suggest a 5-minute break every 200 cards or about 30 minutes.
   *Evidence:* the underlying spaced-retrieval technique is very well supported. Anki use is associated with higher USMLE Step 1 scores (Deng et al. 2015, *Med Educ Online* 20:29436 [memory/uncertain on exact citation]; Lu et al. 2021, *Med Sci Educ* [memory/uncertain]). These are correlational studies.

6. **Question block (timed practice block)**. Matched to the USMLE format.
   *Popover:* "Do a timed block of practice questions (up to 40 in 60 minutes, like the real Step 1), then spend at least as long reviewing every explanation, including the ones you got right. Testing yourself under exam conditions is one of the best-supported ways to learn."
   *Facts:* Step 1 is seven 60-minute blocks with up to 40 questions each (https://www.usmle.org/step-exams/step-1 [source; check the current wording]).
   *Evidence:* retrieval practice is high utility (Dunlosky 2013).

7. **Active recall block (blurting / free recall)**. Optional.
   *Popover:* "Study a topic for 25 minutes, then close your notes and write or say everything you remember for 5–10 minutes. Then check what you missed and fill the gaps. Recalling is harder than rereading, and that is why it works."
   *Evidence:* the free-recall testing effect (Roediger & Karpicke 2006).

**Info popover footnote suggestion:** "Interval lengths are conventions. What research supports is regular breaks, testing yourself, and spacing reviews over days."

---

## 3. Focus sounds

### 3.1 What the research says
- **Coloured noise (white/pink):**
  - Nigg et al. 2024 meta-analysis, *JAACAP* 63(8) (https://pmc.ncbi.nlm.nih.gov/articles/PMC11283987/): 13 studies, 335 participants with ADHD or elevated ADHD symptoms. **Small benefit (g ≈ 0.25)** for that group. In **non-ADHD comparison groups the effect was negative.**
  - The proposed mechanism is the "moderate brain arousal" / stochastic resonance model (Söderlund et al. 2007, *J Child Psychol Psychiatry*).
  - **Brown noise** has essentially no direct controlled research. Its popularity comes from social media. Present noise as "some people, especially those with ADHD, find this helps; try it", and make silence the default.
- **Irrelevant speech effect:** background speech you can understand reliably impairs verbal working memory and serial recall, while steady noise does not (Salamé & Baddeley 1982; review by Ellermeier & Zimmer). This is the strongest finding in this area. **Avoid intelligible speech in focus sounds**, so the cafe sound must be murmur with no recognisable words.
- **Music with lyrics vs without:**
  - Lyrical music hurt reading comprehension more than instrumental music or silence (Perham & Currie 2014, *Applied Cognitive Psychology* 28(2), https://doi.org/10.1002/acp.2994).
  - Meta-analysis Kämpfe, Sedlmeier & Renkewitz 2011 (*Psychology of Music* 39(4)): overall effect of background music on cognitive tasks ≈ 0. It helps mood and arousal slightly and hurts reading and memory slightly.
  - Takeaway: instrumental or none for reading and memorisation.
- **Moderate ambient noise and creativity:** about 70 dB ambient (cafe-like) noise improved creative, abstract tasks compared with 50 dB, and 85 dB hurt (Mehta, Zhu & Cheema 2012, *J Consumer Research* 39(4), https://doi.org/10.1086/665048). This is about creativity, not memorisation. Keep the default volume low.
- **Nature sounds:** natural soundscapes (water, birdsong) are associated with better mood and stress recovery and some attention-restoration effects (meta-analysis Buxton et al. 2021, *PNAS* 118(14), https://doi.org/10.1073/pnas.2013097118). The evidence for better learning during study is limited. Rain and fire work mostly as pleasant broadband masking.
- **Product guidance:** default off. Low level (users should still hear their own thoughts). No speech. Offer noise for masking noisy environments. Fade in and out over 2–3 s and never start abruptly.

### 3.2 Synthesis recipes (AVAudioEngine + AVAudioSourceNode)
General rules:
- **Generator and processing:**
  - Render Float32 at the engine's output sample rate (`engine.outputNode.inputFormat(forBus:0).sampleRate`, usually 48 kHz). Mono generator → `AVAudioMixerNode` for pan and volume, or render stereo with decorrelated generators per channel.
  - **Do not call `Float.random` in the render block.** It uses the system CSPRNG and is too slow and lock-prone for the real-time thread. Use xorshift32: `x ^= x << 13; x ^= x >> 17; x ^= x << 5; white = Float(Int32(bitPattern: x)) / 2147483648`.
  - No allocation, locks or Swift class-reference retains in the render block. Keep state in an `UnsafeMutablePointer`-backed struct.
- **Control:**
  - Parameter changes (volume, mix) should be smoothed with a one-pole filter (`p += (target - p) * 0.001` per sample) to avoid zipper noise.
  - Events (droplets, crackles): Poisson scheduling. Per sample, trigger if `rand01 < rate / sampleRate`. Or draw the next inter-arrival time `-ln(U)/rate`.
- **Filter building blocks:**
  - One-pole lowpass: `a = exp(-2π·fc/fs); y = (1-a)·x + a·y`. Highpass is `x - lowpass(x)`.
  - Biquads: RBJ Audio EQ Cookbook (https://www.w3.org/TR/audio-eq-cookbook/). `w0 = 2π f0/fs`, `α = sin(w0)/(2Q)`. Bandpass (constant 0 dB peak): `b0 = α, b1 = 0, b2 = -α, a0 = 1+α, a1 = -2cos w0, a2 = 1-α`. Normalise by a0. You can also use `AVAudioUnitEQ` bands downstream instead of hand-rolled biquads.
- Final soft limiter: `y = tanh(x)`, or keep the summed gain below about 0.5.

**Pink noise: Paul Kellet's refined filter** (designed for 44.1 kHz, ±0.05 dB above 9.2 Hz; at 48 kHz it is still close enough for ambience) [verified: https://www.firstpr.com.au/dsp/pink-noise/]
```
b0 = 0.99886*b0 + white*0.0555179
b1 = 0.99332*b1 + white*0.0750759
b2 = 0.96900*b2 + white*0.1538520
b3 = 0.86650*b3 + white*0.3104856
b4 = 0.55000*b4 + white*0.5329522
b5 = -0.7616*b5 - white*0.0168980
pink = b0+b1+b2+b3+b4+b5+b6 + white*0.5362
b6 = white*0.115926
out = pink * 0.11      // gain normalisation, roughly unity peak
```
Economy version (±0.5 dB):
```
b0 = 0.99765*b0 + white*0.0990460
b1 = 0.96300*b1 + white*0.2965164
b2 = 0.57000*b2 + white*1.0526913
pink = b0+b1+b2 + white*0.1848   // scale ~0.2–0.25
```
Alternative: **Voss-McCartney**. Keep N (about 16) random rows. On each sample, pick the row given by the number of trailing zeros of a counter and replace that row's value. Output = the sum of the rows plus one white value per sample. It has constant cost (same source).

**Brown (red) noise: leaky integrator** [standard technique]
```
brown = (brown + 0.02*white) / 1.02     // leak keeps it bounded, ≈ 1-pole LP at ~150 Hz @48k
out = brown * 3.5
```
Equivalent: `brown = 0.98*brown + 0.02*white` with gain about 3.5. Add a DC-blocking highpass (`y = x - x1 + 0.995*y1`) so it doesn't drift. Optionally low-pass at 500 Hz for "deep brown".

**Rain**
1. **Bed:** pink noise → highpass about 400 Hz → lowpass 6–9 kHz ("light rain" uses a higher LP, "heavy rain" a lower HP and higher gain). Slow amplitude wander: multiply by `1 + 0.15*lfo`, where lfo is brown noise low-passed below 0.3 Hz. This gives gusts.
2. **Distant body:** brown noise low-passed at about 250 Hz, -12 dB below the bed.
3. **Droplets:** Poisson rate 30–150/s (density control). Each drop is a short damped sinusoid with an upward chirp, which models the Minnaert bubble resonance of a drop hitting water:
   - `f(t) = f0·(1 + k·t)`, with `f0` uniform 1.5–5 kHz and `k` about 20–60 /s
   - `env = exp(-t/τ)`, with τ 3–15 ms and a 0.3 ms attack
   - Amplitude log-uniform across −30 to −12 dB, random pan
   - Mix about 20% of drops as noise "ticks" instead: a 2 ms white burst bandpassed at 2–4 kHz with Q ≈ 2, for drops hitting surfaces.
4. Optional roof or window variant: lower `f0` (300–1200 Hz) and a longer τ (20–40 ms) on a few "heavy drops" at 0.5–2/s.
   Reference: Andy Farnell, *Designing Sound* (MIT Press 2010), chapters on rain and water. [memory/uncertain on exact parameter values; tune by ear]

**Fireplace**
1. **Roar/rumble:** brown noise → lowpass about 300 Hz. Modulate amplitude with slow noise (LP 0.5–1.5 Hz) at depth 0.3–0.5 so it "breathes".
2. **Hiss:** white noise → highpass 2.5–4 kHz at −24 dB, amplitude-modulated by the same slow noise (flames).
3. **Crackles:** Poisson 3–12/s, clustered. When a crackle fires, raise the rate ×4 for 50–200 ms so you get bursts.
   - Each crackle: 0.5–3 ms white burst → bandpass with centre uniform 1.5–6 kHz, Q 1–3.
   - `env = exp(-t/τ)`, τ 1–6 ms, peak log-uniform −24 to −6 dB.
4. **Pops (larger, wood-splitting):** Poisson 0.05–0.4/s. Bandpass centre 300–1200 Hz, τ 20–60 ms, with a 1–2 ms noisy attack, sometimes followed by 3–8 small crackles over 300 ms ("settling").
5. Low hum: an optional 60–90 Hz sine at −36 dB with slow amplitude drift for "warmth" (more of a stylistic choice).
   Reference: Farnell, *Designing Sound*, "Fire" chapter (hiss / crackle / lapping decomposition). [memory; tune by ear]

**Cafe murmur** (must stay unintelligible because of the irrelevant speech effect)
1. **Babble:** 8–16 independent "voices".
   - Each voice: pink noise → bandpass 300–3000 Hz, with 2 resonant peaks. F1 is random 400–900 Hz and F2 is random 1000–2500 Hz. Re-randomise them every syllable and glide the change over about 30 ms.
   - Gate each voice with a syllabic envelope: syllables last 120–300 ms (3–6 Hz rhythm) and phrases 1–4 s, with 0.3–1.5 s pauses.
   - Overall voice level random −30 to −18 dB, and pan voices across the stereo field.
   - Sum, then lowpass at about 3.5 kHz. A gentle reverb makes it sound like a room: `AVAudioUnitReverb` with the `.mediumRoom` preset at 30–40% wet.
2. **Room tone:** brown noise LP 200 Hz at −30 dB.
3. **Clinks (cups/cutlery):** Poisson 0.2–1/s. Sum 3–4 inharmonic partials, e.g. f × {1, 2.76, 5.40, 8.93} with f 1.8–3.5 kHz. Decay τ 60–250 ms, random level −30 to −18 dB.
4. **Optional espresso-machine hiss:** occasional 2–4 s highpassed noise swell at 0.01/s.
5. Default level at about −20 LUFS-ish "background". The Mehta 2012 benefit was at moderate (~70 dB SPL) loudness, and louder hurt.

Alternative to all of this: ship short CC0 loops (e.g. from freesound.org, CC0 filter) and crossfade them. Procedural keeps the app small and loop-free.

---

## 4. macOS focus and inactivity detection without special permissions

| API | Permission needed? | Use |
|---|---|---|
| `CGEventSource.secondsSinceLastEventType(.combinedSessionState / .hidSystemState, eventType: CGEventType(rawValue: ~0)!)` (in Swift the C name `CGEventSourceSecondsSinceLastEventType` is unavailable; use this) | **None [verified]**. Tested on macOS 26.6.2: it returned the correct idle seconds while `CGPreflightListenEventAccess()` was `false` (no Input Monitoring). It reports only time since the last event, never the content. Also widely used by idle-time utilities. | Idle detection: poll every 5–15 s while a session runs. More than 120 s idle → "are you still there?"; more than 5 min → auto-pause. |
| `NSWorkspace.shared.notificationCenter`: `didActivateApplicationNotification` (`userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication` → `bundleIdentifier`, `localizedName`), `frontmostApplication` | **None** | Distraction nudges based on the frontmost **app** (e.g. user-chosen "distracting apps" list) |
| `NSWorkspace` `screensDidSleepNotification` / `screensDidWakeNotification`, `willSleepNotification` / `didWakeNotification`, `sessionDidResignActiveNotification` / `sessionDidBecomeActiveNotification` (fast user switching) | None | Pause the timer automatically |
| `DistributedNotificationCenter.default()` names `"com.apple.screenIsLocked"` / `"com.apple.screenIsUnlocked"` (also `"com.apple.screensaver.didstart"` / `"didstop"`) | None. Undocumented but long-standing and widely used. **[source: community; not Apple-documented]** | Lock = pause / treat as break |
| `CGSessionCopyCurrentDictionary()` → `"CGSSessionScreenIsLocked"` key | None (undocumented key) | Lock state on startup |
| **Window titles** (`CGWindowListCopyWindowInfo` `kCGWindowName`) | **Screen Recording** (since 10.15, titles of other apps' windows are stripped without it) | **Avoid** |
| Browser tab URL/title (AppleScript to Safari or Chrome) | **Automation** (Apple Events, TCC prompt per target app) | Avoid, or make it strictly opt-in |
| AX API (focused window, UI elements) | **Accessibility** | Avoid |
| Global key/mouse monitors (`NSEvent.addGlobalMonitorForEvents`, `CGEventTap`) | Accessibility (keyboard) / Input Monitoring (`listenOnly` tap) (https://developer.apple.com/forums/thread/122492) | Avoid. Idle time does not need them. |

Privacy-friendly nudge design:
1. Track only **app bundle ids**, never window titles, URLs, keystrokes or screenshots. Say so on screen ("StudyNotch only sees which app is in front").
2. The user chooses the distracting-apps list. Nothing is pre-filled from analytics. Suggest common ones (Messages, Discord, YouTube in Safari can't be detected without titles, so be honest about that).
3. All of this stays on the device. Never send app names to the party backend. Share only coarse state (`studying` / `break` / `idle`).
4. Gentle escalation: the pet looks over after 30 s in a distracting app, does a speech bubble or nudge after 2 min, and offers to pause after 5 min. Never shame, never use a loud sound, and limit nudges (e.g. at most one every 10 minutes).
5. Idle is not "distracted". Reading a textbook or paper looks idle. Ask ("Still studying? 👀 Yes / Pause"); never auto-penalise.
6. Allow "focus apps" (Anki, UWorld, browser) to be whitelisted, and a "Do not nudge" toggle per session.
7. Respect the system Focus modes and screen lock (pause automatically, and don't count the time).

---

## 5. Cloudflare Workers free plan (as of Oct 2026)

Sources:
- https://developers.cloudflare.com/workers/platform/limits/
- https://developers.cloudflare.com/kv/platform/pricing/ and /kv/platform/limits/
- https://developers.cloudflare.com/durable-objects/platform/pricing/ and /durable-objects/platform/limits/
- https://developers.cloudflare.com/durable-objects/best-practices/websockets/

All fetched 2026-10-01. Daily limits reset at 00:00 UTC, and requests over a limit fail; they are not billed.

| Resource | Free limit |
|---|---|
| Worker requests | **100,000 / day**; 10 ms CPU per request; 50 subrequests per request; 128 MB memory |
| KV reads | 100,000 / day |
| KV writes | **1,000 / day** (and at most 1 write/s to the same key); deletes 1,000/day; lists 1,000/day; 1 GB storage |
| Durable Objects | **Available on Free, SQLite-backed only** (KV-backed DOs are Paid-only). 100 DO classes per account |
| DO requests | **100,000 / day**. This includes HTTP, RPC, **WebSocket messages**, and alarms. **Incoming WS messages are billed at 20:1** (100 messages = 5 requests) |
| DO duration | 13,000 GB-s / day. Hibernated or idle objects are not billed for duration. At 128 MB per object that is about 104,000 awake-seconds per day |
| DO SQLite | rows read **5,000,000 / day**, rows written **100,000 / day**, 5 GB total storage (10 GB per object). Storage billing has been enabled since January 2026. (One secondary source said 1.25 M reads per day; the official pricing page says 5 M.) |
| WebSocket | Hibernation API available. Received message ≤ 32 MiB. Soft limit of about 1,000 req/s per object |

**Takeaways:**
- **Never put heartbeats in KV.** 1,000 writes/day is about 3 users at a 5-minute heartbeat.
- Every HTTP request uses one Worker request plus one DO request.
- WebSocket messages into a hibernating DO cost only 1/20 of a request and don't use the Worker request quota after the upgrade.

**Recommended architecture (hundreds of users):**
- **Storage:** one Worker, `tabbi-friends`, with SQLite-backed DOs.
  - `UserDO`, one per user, keyed by `idFromName(userId)`: stores the profile, friend list, and presence row. Friend lookups do a fan-out read via RPC.
  - Or, simpler at this scale: a single **`PresenceDO`** (or 4–16 shards keyed by hash of userId) that keeps presence **in memory** and writes to SQLite **only on status change** (studying ↔ break ↔ idle ↔ offline), not on every heartbeat. "Online" = `lastSeen` within 2× the heartbeat interval, computed on read. Use an alarm every 5–10 minutes to mark stale users offline and persist them.
- **`PartyDO`**, one per party code: members, shared session (`method`, `phaseEndsAt`), last activity. Clients connect by **WebSocket with the Hibernation API**:
  - `ctx.acceptWebSocket(ws, [userId])`, `webSocketMessage`, `webSocketClose`
  - `ws.serializeAttachment()` for per-connection state (max 16 KB)
  - `ctx.getWebSockets()` to broadcast
  - `ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping","pong"))` for application-level keepalive pings that **don't wake the DO** **[memory: verify API name in current docs]**. Protocol-level ping frames are auto-answered (per docs).
  - An alarm deletes the party after 12 h without activity (`deleteAll()`).
- Heartbeat over HTTP is fine if WebSockets are too much work for v1. Make it adaptive: every 60 s while the notch is open and the user is studying, every 5 min when idle, nothing when the app is quit. Send an explicit `offline` on quit. Write only on change.

**Budget math (assumptions: 500 daily users, each with the app open 4 h/day):**
- HTTP heartbeat every 120 s: 500 × 4 × 30 = **60,000 Worker req + 60,000 DO req/day**. That fits, with about 40% headroom left for friend-list polls. Friend-list polling every 120 s doubles it, so **combine them**: the heartbeat response returns the friends' presence. Then about 60k/day total.
- WebSocket alternative: 500 upgrades/day ≈ 500 Worker requests. Heartbeats as WS messages every 60 s: 500 × 240 = 120,000 messages → **6,000 billable DO requests**. Outbound broadcasts are not billed as requests. Awake time is roughly 120k wakes × about 5 ms, which is negligible against 13,000 GB-s.
- SQLite writes: about 10 status changes per user per day × 500 = 5,000 rows/day (limit 100k).
- KV: use it only for rarely changing data (friend-code → userId index), or skip KV entirely and keep everything in DO SQLite.
- **Ceiling:** with HTTP heartbeats at 120 s, about 800 users × 4 h fits. With WebSocket presence, several thousand fit. Add a client-side backoff on HTTP 429/503 or Cloudflare error 1027 (daily limit exceeded) so the app degrades to "friends offline" rather than spinning.

---

## 6. Pixel-art pet references

| Reference | Sprite size | Frames / timing |
|---|---|---|
| **Neko / oneko.js** (https://github.com/adryd325/oneko.js) [verified from source] | **32×32** cells on a grid sprite sheet | Ticks every **100 ms** (10 fps), moves 10 px per tick. **2 frames per walking direction** (8 directions). Idle: scratch animations of about 9 ticks; sleep alternates 2 sprites over a long idle (tired pose first). |
| **Shimeji-ee** (https://github.com/chaoskagami/shimeji-ee) [source] | **128×128** canvas per frame | **46 images** (`shime1.png`…`shime46.png`) shared across all actions. Duration is set per frame in `actions.xml` (units of 1/25 s, typical 4–8 → 160–320 ms) [memory/uncertain on the unit] |
| **VS Code Pets** (https://github.com/tonybaloney/vscode-pets) [verified from repo] | GIFs per state, e.g. `media/dog/brown_idle_8fps.gif` is 115×90 (upscaled pixel art). Sizes: `nano`, `small`, `medium`, `large` | States: idle, walk, walk_fast, run, lie, swipe, with_ball. **8 fps** convention (idle GIF: **4 frames × 130 ms**) |

**Conventions for StudyNotch (notch height is about 32–37 pt):**
- **Sizes and states:**
  - Draw at **16×16 to 24×24** (or 32×32 at most) native pixels.
  - Display at integer scale: 2× or 3× in points. On Retina that becomes 4× or 6× device pixels. Use nearest-neighbour: `Image(...).interpolation(.none)`, or `CALayer.magnificationFilter = .nearest`.
  - Never scale by a non-integer factor.
- **Frame counts:**
  - idle/breathe: 2–4 frames
  - walk: 4 frames (2 at minimum, as in neko)
  - sleep: 2 frames + "Zz" particle
  - happy/celebrate: 4–6 frames
  - nudge/look: 2–3 frames
  - eat/treat: 4 frames
- **Timing:**
  - 6–10 fps (100–170 ms per frame) for walk, slower for idle (250–500 ms, or hold frame 1 longer).
  - Randomise idle blinks every 2–6 s so the pet looks alive without constant motion.
  - Drive animations from one `TimelineView(.animation(minimumInterval: 0.125))`, or a timer that pauses when the notch is hidden (CPU and battery).
- **Readability on a black notch background:**
  - Use a **1 px dark outline that is not pure black**. Use a dark tinted outline (e.g. #2B1E2E) plus a 1 px light rim or highlight on the top and back edges. A black outline disappears on black, so on black the readable silhouette comes from the light/mid fill. Alternatively, add a subtle 1 px outer glow or "selection outline" in a muted light colour.
  - Value contrast beats hue contrast. Keep the main body mid-to-light (L* above about 55), and make the eyes the highest-contrast element (2×2 px with a 1 px white highlight at 24 px size).
  - Limited palette: 4–8 colours per pet, with hue-shifted shading (shadows cooler, highlights warmer) rather than pure darkening.
  - Silhouette test: the pet must be recognisable as a solid white shape on black. Exaggerate ears and tail; avoid 1 px protrusions that flicker when moving.
  - Avoid single-pixel jitter between frames (sub-pixel "boiling"). Keep the anchor/feet baseline fixed.
  - Respect `accessibilityReduceMotion`: freeze on the idle frame and keep only state changes.

---

## 7. Cozy-but-clean UI (Forest, Finch, Study Bunny, Flora)

These are observations from the apps' public design and store pages (analysis, not formal sources):
- https://www.forestapp.cc
- https://finchcare.com
- Study Bunny (App Store)
- Flora (https://flora.appfinca.com)

**What makes them cozy:**
- **Forest:** one metaphor (a growing tree) carries the whole timer, and the tree "dies" if you leave the app. That gives loss-aversion without nagging, and the real-tree planting is a meaningful reward. Earthy greens, big circular timer, almost no chrome.
- **Finch:** a soft pastel palette, very rounded shapes, and the pet's emotional reactions as the main feedback. Small daily goals, gentle copy, and no punishment for missed days (the pet just goes on an "adventure"). It is cosmetics-driven: rewards are clothing and furniture.
- **Study Bunny:** the companion visibly reacts to study time. Coins buy cosmetics. Timer and stats are simple.
- **Flora:** Forest-like trees with social and group focus and a commitment mechanic.
- **Common pitfalls:**
  - Shops, currencies and inventory screens creeping into the main surface
  - Notification spam
  - Guilt mechanics that make users quit after a broken streak
  - Too many pastel tints, which make the UI muddy and low-contrast
  - Gamification that pulls attention away from studying

**10 design rules for StudyNotch:**
1. **One glanceable state per view.** The closed notch shows only the pet plus one number (time left or cards left). Everything else goes in the expanded panel.
2. **The palette is a near-black base plus one warm accent and one secondary.** For example, base #0E0E10, surfaces #1A1A1F; the accent is a warm peach or amber (#FFB27A); the secondary is a soft sage (#9ED9B0) for "on track". Make the pet the most colourful thing on screen. Text is 87% white for primary and 60% for secondary.
3. **Rounding:** use continuous corners (`.rect(cornerRadius:, style: .continuous)`) on a scale of 8 / 12 / 20. Pills for buttons and chips. Use one radius scale everywhere.
4. **Motion is springy but brief.** Use spring(response 0.35, damping 0.8) for expanding, and celebrations under 1.2 s. Ambient pet motion is the only thing that moves continuously. Honour Reduce Motion.
5. **Sound is optional and soft:** a gentle chime at phase changes and no other UI sounds by default. Match the volume to the focus-sound level.
6. **Rewards are cosmetic and never punitive.** Points unlock costumes and accessories. Missed days give a "rested" pet, never a dead or sad one. Streaks have freeze days.
7. **Copy is kind and short:** "Nice block! 5-minute stretch?" instead of "Break time." Never shame ("You got distracted 6 times").
8. **Keep the shop and stats out of the focus loop.** Only the pet, the timer and the next action are visible during a session. Collections and history live in a separate tab.
9. **Social is ambient:** friends appear as small pets beside yours, with a tiny status dot. No feeds, likes or leaderboards on the main surface. The weekly leaderboard is opt-in and friends-only.
10. **Every screen has one primary action** (Start, Resume, Review deck), shown as the accent-filled button. Everything else is secondary or ghost style. Limit any panel to at most about 5 interactive elements.
11. (Bonus) **Information honesty:** the info popovers explain the method in 2–3 sentences and say plainly when evidence is weak. That builds trust with a science-literate med-student audience.

---

## Open items / flagged uncertainties
- Anki's bundle id varies by build (`net.ankiweb.anki` on the 26.x launcher installed here; `net.ankiweb.dtop` historically). Which id the running GUI process reports under the launcher is unverified. Check it with `NSWorkspace.shared.runningApplications` while Anki is open.
- `requireApikey` (code) vs `requireApiKey` (docs).
- The `setWebSocketAutoResponse` API name comes from memory. Confirm it in the Cloudflare docs before coding.
- The DeskTime 112/26 update, the exact Anki/USMLE study citations, and Shimeji frame-duration units come from memory.
- The synthesis parameter ranges are starting points from DSP practice (Farnell) and need tuning by ear.
