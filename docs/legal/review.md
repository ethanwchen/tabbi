# Legal review: findings, changes and the lawyer list

RESEARCH NOTES - NOT LEGAL ADVICE - REVIEW WITH A LICENSED ATTORNEY BEFORE ACTING

This review covers Tabbi's Privacy Policy, its Terms of Use, the macOS app, the friends service and the App Store listing.
It follows Anthropic's claude-for-legal workflows (reviewed at commit 4a6c651).
Those are privacy-legal (use-case-triage, pia-generation, reg-gap-analysis and policy-monitor), product-legal (launch-review, feature-risk-assessment, marketing-claims-review and is-this-a-problem) and ip-legal (clearance and oss-review).
The facts about the operator come from `profile.md`.
The detailed work is in `app-audit.md`, `backend-audit.md`, `terms-memo.md` and `ip-review.md`; this file sums it up.

It is not a substitute for a licensed attorney.
The last section lists what a lawyer should confirm before the maintainer relies on it.

## Summary

Tabbi collects very little, and most of it stays on the Mac.
The legal risk was mostly in what the documents said, not in what the code did.
Before this review, the Privacy Policy, `backend/PRIVACY.md`, the FAQ and the README made several statements that were false as written.
The app also had no AI consent step, no age check and no legal links.
That mattered because of FTC Act Section 5, GDPR Article 13 and App Store Guidelines 5.1.1 and 5.1.2.
All of these are fixed.
What remains open is mainly naming (the App Store name and the TABBI mark), one missing age question at Sign in with Apple, two small backend hardening items, and questions only a lawyer can settle.

Severity scale:

- **Critical**: a likely legal violation or App Store rejection.
- **High**: a false public statement, or a real exposure for minors or for IP.
- **Medium**: a gap a regulator, Apple or a rights holder could reasonably raise.
- **Low**: wording, completeness or good practice.

## Findings and what was done

### Critical

| # | Finding | Status |
| --- | --- | --- |
| C1 | No disclosure or consent before personal data went to a third-party AI provider (Guideline 5.1.2(i), GDPR Art. 13). | **Fixed.** A one-time alert per provider names the company, how the data gets there and what each feature sends. No request is sent until the user taps Allow. Ollama, which runs on the Mac, is exempt. Code: `TabbiKitCore/AI/AIConsent.swift`, `AISettings.consented`, Settings > Connections. The App Review notes in `docs/appstore.md` describe it. |
| C2 | Party registered with the server as soon as its setup step appeared, with no age question, no notice and no links (COPPA actual knowledge, GDPR Art. 8, Guideline 1.3 and 5.1.4). | **Fixed.** Party asks a neutral birth month and year question with Terms and Privacy links before anything is sent. An under-13 answer keeps Party off until the user turns 13, cannot be changed, and deletes an anonymous identity this Mac made earlier. Only the date the user turns 13 is stored, on the Mac. Code: `TabbiKitCore/Party/PartyAgeCheck.swift`, `PartyAgeCheckView`. |

### High

| # | Finding | Status |
| --- | --- | --- |
| H1 | The Privacy Policy had at least 10 statements that the code contradicted (FTC Act Section 5 deception risk). Examples: crash reports were not named as server traffic, AI payloads were under-described, AI Usage's "ok" request was not disclosed, the browser sign-in name hand-off and custom friends servers were missing. | **Fixed.** The policy was rewritten against the code (`app-audit.md` items 1 to 10). |
| H2 | `backend/PRIVACY.md` and the policy had 8 statements the Worker contradicted: log sampling, the crash content check, the pending sign-in lifetime, re-deletion after restore, field rejection, the token count, the "only Party and sign-in" claim and IP uses. | **Fixed** in the policy, `backend/PRIVACY.md` and the FAQ (`backend-audit.md`). |
| H3 | The policy had no GDPR legal bases, no international transfer section, no retention schedule, no state law rights and no children section. | **Fixed.** It now has a legal bases table, transfers (Cloudflare SCCs, UK addendum, DPF), a retention summary, rights with an appeal path, a GPC and DNT note, Switzerland, and a children and teens section. |
| H4 | The Terms were thin: no eligibility, no user content license, no moderation or appeal, no AI disclaimer, no copyright procedure and no consumer carve-outs. | **Fixed.** Rewritten into 18 sections; the reasoning is in `terms-memo.md`. |
| H5 | The planned App Store name `Tabbi: Notch Focus Timer` contains the full name of an existing Mac App Store app, "Notch Focus Timer", which does the same thing (Guidelines 2.3.7, 4.1, 5.2; likelihood of confusion). `docs/appstore.md` claimed the name "names no other company's product". | **Flagged.** The false claim is removed, and alternative names are listed. Renaming is the maintainer's decision. |
| H6 | The direct download shipped Sparkle.framework without its license text, which its MIT, BSD (bsdiff) and zlib (ed25519) terms require in binary copies. | **Fixed.** `scripts/assemble.sh` copies the license into `Contents/Resources/Acknowledgements` and fails if it is missing. |

### Medium

| # | Finding | Status |
| --- | --- | --- |
| M1 | No legal links anywhere in the app, and Settings > About linked a stale repo. | **Fixed.** Settings > About links the Privacy Policy, the Terms and the current repo in both editions. |
| M2 | No App Store privacy manifest, although the app uses UserDefaults and file timestamp APIs (required-reason APIs). | **Fixed.** `packaging/PrivacyInfo-AppStore.xcprivacy` and the widget's manifest match the privacy label answers and are copied into App Store builds only. |
| M3 | The privacy label left out the per-Mac sync id and study day counts. | **Fixed.** The answer sheet in `docs/appstore.md` declares Device ID and Product Interaction (the cautious reading). |
| M4 | Sign in with Apple has no age question. A child could create an account (an Apple user id and synced pet and streaks) without one. A signed-in user who answers under 13 at Party keeps their account until they use Delete Account. | **Fixed.** Sign In now opens the same neutral birth month and year question first (`AccountAgeSheet`), sharing Party's stored answer so it is asked once; under 13, signing in stays off until the user turns 13, and nothing is sent. Still open: a user already signed in who later answers under 13 in Party keeps the account until Delete Account (see residual risks). |
| M5 | The word mark TABBI is used by others (a US restaurant payment app, a Firefox add-on, a pending ASK TABBI application). No Class 9 or 42 search has been run. | **Open.** See `ip-review.md` section 1. |
| M6 | The README said Tabbi "only connects" for artwork, AnkiConnect and Party, and that calendar events "never leave your Mac". Both were false (update checks, crash reports, sign-in and AI; Refine sends event titles and times). | **Fixed** with a minimal README edit, which also links the Privacy Policy. |
| M7 | Party's Report and Block controls are only in a right-click menu, which reviewers and users may miss (Guideline 1.2). | **Mitigated.** The App Review notes for Party's return say where they are. Party is not in the App Store edition today. |
| M8 | Account deletion revokes the Apple grant only if the Worker has the `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` secrets (Guideline 5.1.1(v)). | **Flagged.** A pre-submit check in `docs/appstore.md`. |

### Low

| # | Finding | Status |
| --- | --- | --- |
| L1 | Abandoned web sign-ins keep Apple's user id and an unrevoked refresh token for up to about an hour. | **Disclosed accurately**; the code fix (delete on read, revoke) is still advisable. |
| L2 | The server's crash report check matches only case-sensitive `/Users/` and `/home/` in frames. | **Disclosed accurately**; widening it to thread names and case is still advisable. The app already strips home paths before sending. |
| L3 | Terms section 3 said the app bundles fonts (it bundles none) and named ChatGPT instead of the providers actually used. | **Fixed.** |
| L4 | "Free forever" is a promise about the future. | **Flagged** in `ip-review.md`; keep it only if meant, or say "free and open source". |
| L5 | The app icon art is AI-generated (the source carries an OpenAI C2PA manifest), so its US copyright protection is weak. | **Noted.** Trademark rights in the icon are unaffected. |
| L6 | A settings migration had silently picked Claude Code as the AI provider for people who used Tabbi before AI providers existed. | **Fixed** by C1: such a choice sends nothing until the user picks it again and allows it. Those users see "None" once, which is the right privacy result. |

## Decisions that shape the documents

- **Who is responsible.** Ethan Chen, an individual in New York, is the controller and the party to the Terms. There is no company, so liability is personal (see the lawyer list).
- **Minimum age 13** for Party and accounts, with a parent's permission below the digital consent age (up to 16 in parts of the EU) and, in the Terms, under 18. The rest of the app works offline and sends nothing to the operator, so it has no minimum age.
- **No arbitration and no class waiver.** New York law and New York County courts, a small-claims option and a 30-day informal step. Consumers outside the US keep their home courts. The reasons (cost to the operator, mass-arbitration risk, weak enforceability against EU and UK consumers and minors, small exposure) are in `terms-memo.md`.
- **Liability** is capped at 50 US dollars, with carve-outs for death, injury, fraud, intent and gross negligence and savings for EU and UK consumers, so a court is less likely to strike the whole clause.
- **MIT License vs the service.** The code is MIT. The Terms govern the website, the friends service and the App Store copy (which also falls under Apple's Standard EULA). The Terms never restrict what the MIT License allows.
- **Copyright complaints** follow the 512(c)(3) elements, but the Terms do not claim DMCA safe harbor, because no agent is registered.
- **CCPA/CPRA and the other state laws** probably do not apply (no revenue, far below the volume thresholds), but the policy offers the same rights to everyone, so nothing depends on that conclusion.

## Residual risks

- **Naming.** Until a trademark search is done and the App Store name is settled, H5 and M5 are the largest open exposures. The worst realistic outcome is a forced rename, not damages.
- **Children already signed in** (M4). An account made before the age check existed, or by someone who answers under 13 in Party afterwards, is not deleted automatically; it goes with Delete Account or an email to support.
- **Self-declared age.** A child can lie at the age check. That is accepted practice for a general-audience service without actual knowledge, but the study audience makes "likely to be accessed by children" (UK Age Appropriate Design Code) an arguable test.
- **Personal liability.** With no company, any judgment falls on the maintainer personally.
- **Third-party terms.** Running the user's own Claude Code, Codex and Gemini CLIs, and scripting the user's SoundCloud tab, depend on those providers' terms, which can change.
- **Policy drift.** Every future feature that sends data must update the Privacy Policy, `backend/PRIVACY.md`, the FAQ, the privacy label and the privacy manifest together. `README.md` in this folder lists those surfaces.
- **Facts not verified by code.** Cloudflare's DPF participation and its data processing terms are stated from Cloudflare's public materials, not checked against a signed agreement.

## For a lawyer to confirm

1. **Trademark.** Run a full search for TABBI (Classes 9, 42 and 45; US, EU and UK), decide whether to file, and decide whether `Tabbi: Notch Focus Timer` must change given the existing "Notch Focus Timer" app.
2. **Personal liability.** Whether to form an LLC (or similar) before Party returns or the App Store launch, and whether the Terms' 50 US dollar cap and narrow indemnity hold up in New York, the EU and under the UK Consumer Rights Act.
3. **Disputes.** Whether no arbitration is the right call, and whether the New York County forum clause with its consumer carve-outs is enforceable as drafted.
4. **Minors.** Whether 13+ with self-declared age is enough for COPPA given the study audience, whether the UK Age Appropriate Design Code and US state minors' laws (for example New York's Child Data Protection Act and California's Age-Appropriate Design Code, where in force) reach Tabbi, and whether the parental-permission language for 13 to 17 year olds works under New York and California contract rules.
5. **GDPR.** Whether an EU and UK representative (Art. 27) is needed, or whether the occasional-processing exemption applies. Confirm the legal bases table (especially legitimate interests for abuse prevention and crash reports), and confirm Cloudflare's SCCs, UK addendum and DPF participation against the actual data processing addendum.
6. **DMCA.** Whether to register a designated agent with the US Copyright Office to gain safe harbor.
7. **AI providers.** Whether launching the user's own Claude Code, Codex and Gemini CLIs from Tabbi fits each provider's current terms, especially for subscription plans, and whether the consent alert's wording is enough under Guideline 5.1.2(i) and GDPR.
8. **Export.** Whether the export and sanctions paragraph is enough for free open source software (EAR 734.7) with a US-run service on Cloudflare.
9. **Account deletion.** Confirm that the Apple revocation secrets are set in production, so Delete Account fully revokes Sign in with Apple as the reviewer notes promise.
10. **Icon.** Whether the AI-generated icon art needs any further protection, such as registering the icon as a trademark once in use.
