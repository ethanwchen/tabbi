# Legal review workspace

RESEARCH NOTES - NOT LEGAL ADVICE - REVIEW WITH A LICENSED ATTORNEY BEFORE ACTING

This folder holds the legal review of Tabbi's Privacy Policy, Terms of Use and the app itself.
It follows the workflows in Anthropic's claude-for-legal plugins (privacy-legal, product-legal and ip-legal, reviewed at commit 4a6c651).
Where those skills read or write a practice profile under `~/.claude/plugins/config`, this review uses `profile.md` in this folder instead.

None of this replaces a licensed attorney.
`review.md` ends with the items the maintainer should have a lawyer confirm.

## Files

- `profile.md` - the practice profile the skills expect: who the operator is, the regulatory footprint, the published commitments and where each lives.
- `data-inventory.md` (next) - every piece of personal data Tabbi touches, where it lives, who receives it and how long it is kept, checked against the code (the policy-monitor and pia-generation workflows).
- `terms-memo.md` - why the Terms of Use say what they say (scope, minors, no arbitration, liability, moderation, copyright, Apple terms).
- `review.md` (last) - findings by severity, what was changed, residual risks and the list for a lawyer.

## Surfaces that make privacy commitments

The policy-monitor skill asks for every surface that promises something about data, not just the policy page.
For Tabbi these are:

- `site/_legal.py` - the Privacy Policy and Terms of Use on tabbinotch.com (`/privacy`, `/terms`).
- `backend/PRIVACY.md` - the technical description of what the friends service stores.
- `docs/appstore.md` - the App Store privacy label ("nutrition label"), the App Review notes and the listing copy.
- The README's Privacy section and the site's support FAQ.
- In-app copy: the Party setup, Sign in with Apple, crash report prompt, AI provider setup and deletion buttons.
