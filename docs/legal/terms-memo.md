# Terms of Use: decisions memo

RESEARCH NOTES - NOT LEGAL ADVICE - REVIEW WITH A LICENSED ATTORNEY BEFORE ACTING

This memo records why the Terms of Use in `site/_legal.py` (rewritten 9 October 2026) say what they say.
It follows the product-legal launch-review and is-this-a-problem workflows: each choice names the risk, the option taken and what is left for a lawyer.

## Scope of the terms

The MIT License governs the app's code, and the Terms say nothing in them takes away an MIT right.
The Terms govern only what the license cannot: the friends service (Party), the Sign in with Apple account and the website.
This avoids the conflict of an open source license and a restrictive EULA covering the same code.
App Store copies also fall under Apple's Standard EULA, because `docs/appstore.md` sets no custom license agreement.

## Age and minors

- Party and accounts are 13+, matching the Privacy Policy's children section (COPPA: no knowing collection under 13).
- Under 18, a parent or guardian must permit use and accepts the terms for the minor.
  Minors can generally disaffirm contracts, so the Terms do not rely on a minor's own assent for anything important, and section 13 says a minor keeps their rights.
- The app has no age gate yet (`app-audit.md` gap 2), so the 13+ rule is only stated, not enforced.
  The next code iteration should add one before Party registers.

## Disputes: no arbitration

Considered: a mandatory arbitration clause with a class-action waiver and a small-claims carve-out.
Chosen: New York law, courts in New York County, a small-claims option, a 30-day informal resolution step, and no arbitration.
Reasons:

- Cost falls on the operator.
  Under the major providers' consumer rules (AAA, JAMS) the business pays most fees, which can far exceed the value of any claim against a free app.
  Mass-arbitration filings are a known risk for consumer apps with arbitration clauses.
- Weak enforceability against the main user groups.
  EU and UK consumers cannot be bound by a pre-dispute arbitration clause or a forum clause that takes away their home courts (Unfair Contract Terms Directive, Brussels I bis Article 18, UK Consumer Rights Act 2015).
  Minors can disaffirm the agreement, including its arbitration clause.
- The exposure is small.
  There is no payment, and the liability cap is 50 US dollars, so class actions are unlikely and the waiver adds little.
  A class waiver without an arbitration clause is of uncertain enforceability and was not added.
- Readability and trust matter for a student audience; the clause would be the longest section of the Terms.

## Liability and indemnity

- The cap is 50 US dollars with carve-outs for death or personal injury, fraud, intent and gross negligence, which most legal systems will not let a provider exclude anyway.
  Without carve-outs, courts in the EU and UK may strike the whole clause rather than reading it down.
- Indemnity is narrow (claims caused by the user's own breach, reasonable costs) and does not apply where local consumer law forbids it.
  A broad indemnity from a teenager on a free service is unlikely to be enforced and would look hostile.

## User content and moderation

- Users keep their rights, and the license to us is limited to running the service and ends on deletion (with backup and legal-hold exceptions that match the Privacy Policy's retention section).
- The rules list matches what the service can actually enforce: names, harassment, false reports, leaderboard cheating, attacks and rate-limit evasion.
  `backend/src/hub.ts` implements rename, ban (hidden, no name changes, no parties) and 429 rate limits; the Terms describe those outcomes.
- An appeal path (email) exists, which App Store Guideline 1.2 and the EU Digital Services Act's spirit both favor.
  Tabbi is likely below DSA thresholds for most obligations, but the appeal and statement-of-reasons style is cheap to offer.
- App Store Guideline 1.2 (user-generated content) asks for filtering, reporting, blocking and contact info; those exist in Party, and Party is not in the App Store edition today.

## Copyright complaints

The Terms give a notice procedure that mirrors 17 U.S.C. 512(c)(3) elements and a counter-notice path.
They deliberately do not claim DMCA safe harbor: that requires a designated agent registered with the US Copyright Office (a small fee, renewed every three years).
User content is tiny (names, pet choices from a fixed catalog, report notes), so the risk is low.
A lawyer should confirm whether registering an agent is worth it.

## Trademarks

The Terms state that third-party names are used descriptively and that Tabbi is not affiliated with their owners.
The name Tabbi itself (an existing "Tabbi" iPhone app by Tabbi Inc) is analysed in the IP clearance step, not resolved by the Terms.

## Apple

Section 15 contains the minimum terms Apple requires of a custom license (acknowledgement, maintenance and support, warranty, product claims, IP claims, third-party beneficiary, contact).
Because Apple's Standard EULA applies, these are belt and braces, but they keep the Terms consistent if a custom EULA is ever set in App Store Connect.

## Changes

Material changes get 14 days' notice on the site and GitHub; there is no email channel, because Tabbi does not collect email addresses.
Changes do not apply to disputes that started earlier, which supports enforceability of unilateral-change clauses under US case law.

## For the lawyer list

- Confirm no-arbitration is the right call, and that the New York County forum clause plus consumer carve-outs is enforceable as drafted.
- Confirm the parental-acceptance language for 13 to 17 year olds, and whether New York or California minor contracting rules need more.
- Decide whether to register a DMCA designated agent.
- Confirm the 50 US dollar cap and the carve-outs, including under the UK Consumer Rights Act and EU law.
- Confirm the export and sanctions paragraph is enough for a free open source app with a service run from the US on Cloudflare (EAR 734.7 publicly available software).
