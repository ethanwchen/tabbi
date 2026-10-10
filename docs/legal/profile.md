# Practice profile

RESEARCH NOTES - NOT LEGAL ADVICE - REVIEW WITH A LICENSED ATTORNEY BEFORE ACTING

This stands in for the company profile and the privacy, product and IP practice profiles that the claude-for-legal cold-start interviews would write.
The facts come from the maintainer's brief for this review.

## Who we are

- **Operator:** Ethan Chen, an individual in New York, United States. There is no company or LLC.
- **Contact:** support@tabbinotch.com.
- **Product:** Tabbi, a free, open-source (MIT) macOS app that turns the MacBook notch into a panel of tabs, plus the website tabbinotch.com and a small friends service (Party, sync, invites) on Cloudflare Workers.
- **Distribution:** worldwide, as a direct download (signed, notarized, updated by Sparkle from GitHub) and on the Mac App Store (sandboxed).
- **Business model:** none. No price, no in-app purchases, no ads, no tracking or telemetry. The server counts a few aggregate totals.
- **Users:** the general public, with a strong study focus (student kits such as Med School), so users can be students, including minors.
- **Role:** controller for the friends service, account sync, crash reports, suggestions and support email. Not a processor for anyone.
- **Privacy team:** the maintainer alone. No DPO. No EU or UK representative.

## Who is using this

- **Role:** non-lawyer without in-house attorney access (a solo developer).
- **Work-product header:** `RESEARCH NOTES - NOT LEGAL ADVICE - REVIEW WITH A LICENSED ATTORNEY BEFORE ACTING`.
- **Risk posture:** conservative on privacy and children; practical on everything else. Prefer collecting less over disclosing more.

## Regulatory footprint

Applies or likely applies:

- **GDPR and UK GDPR** (Art. 3(2)(a): offering a service to people in the EU and UK, even for free).
- **US FTC Act Section 5** (deceptive or unfair practices: every privacy statement must be true).
- **COPPA** (only if the service is directed to children under 13 or the operator has actual knowledge of a child user).
- **App Store Review Guidelines** (contractual, enforced by Apple: 5.1.1 data collection and account deletion, 5.1.2 data use and AI disclosure, 1.2 user-generated content, 1.3 and 5.1.4 kids).
- **New York SHIELD Act** (breach notification and reasonable security for private information of New York residents; Tabbi holds very little that qualifies).
- **Children's codes:** UK Age Appropriate Design Code and similar design codes (likely-to-be-accessed test).

Likely does not apply, but the policy addresses anyway:

- **CCPA/CPRA** (thresholds: $25M revenue, 100,000 consumers or households, or 50% revenue from selling or sharing; a free, revenue-less project meets none).
- **Other US state comprehensive privacy laws** (Virginia, Colorado, Connecticut, Texas and others: volume thresholds generally 100,000 residents; Texas applies to anyone not a small business as SBA defines it, and an individual hobby developer is likely a small business).
- **FERPA** (Tabbi is not offered to or through schools).
- **HIPAA** (no health data; the Med School kit is a study aid).

## Published commitments

| Surface | Location | Last updated |
|---|---|---|
| Privacy Policy | `site/_legal.py` (PRIVACY), served at tabbinotch.com/privacy | 9 October 2026 |
| Terms of Use | `site/_legal.py` (TERMS), served at tabbinotch.com/terms | 9 October 2026 |
| Friends service privacy | `backend/PRIVACY.md` | see git history |
| App Store privacy label and review notes | `docs/appstore.md` | see git history |
| README privacy section | `README.md` | see git history |

## Escalation

Everything marked "for a lawyer" in `review.md` goes to outside counsel before the maintainer relies on it.
