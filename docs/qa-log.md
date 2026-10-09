# QA log

What the whole-app quality pass found and fixed, newest first, one sentence per line.

- Settings footers that wrapped set their later lines flush right (a grouped Form trails its footers), and sat 10 pt left of the section headers; every pane now shares one leading, inset `SectionFooter`.
- Baseline: `swift build` has no warnings, `swift test` (1628 XCTest and 49 Swift Testing tests), `scripts/check-style.sh`, and the backend `npm test` and `npm run typecheck` all pass.
