# Tabbi for Windows: environment

The full brief is [HANDOFF.md](HANDOFF.md); this page is only the environment variables and the setup checklist.

## Do we need any environment variables?

No.
Building, testing and running the Windows app against the production backend needs no environment variables, no API keys and no `.env` file.
The production Worker URL and the Sign in with Apple Services ID (`dev.tabbi.Tabbi.signin`) are public values that live in code.

## Optional, for development only

| Variable | Effect |
| --- | --- |
| `TABBI_DEMO=1` | Demo mode: sample data, no network, calendar, Anki or AI calls, nothing saved, and no cape on the pet |
| `TABBI_PARTY_SERVER=http://localhost:8787` | Party and sync against a local `wrangler dev` Worker (`cd backend && npm run dev`); only plain-http localhost is accepted |
| `TABBI_PARTY_TOKEN`, `TABBI_PARTY_CODE` | Act as an existing user of that local Worker |
| `TABBI_CLAUDE_PATH`, `TABBI_CODEX_PATH`, `TABBI_GEMINI_PATH` | Phase 5 only: explicit paths to the AI command line tools |

`TABBI_RECORD_FIXTURES` is for the Mac only; never set it on Windows.
AI keys are never environment variables: paste your own key in Settings > Connections (stored in Windows Credential Manager) or run Ollama locally, and only when testing AI.

## Secrets that must never be committed

- The Sign in with Apple key (`APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, the `.p8` file): Worker secrets and the owner's password manager.
- `ADMIN_TOKEN` and `GITHUB_TOKEN`: Worker secrets.
- Cloudflare API tokens and `wrangler login` sessions: the owner's machine only.
- Mac signing: the Developer ID certificate, notarization password and Sparkle EdDSA key, in the owner's keychain and GitHub repository secrets.
- Windows signing, later: Azure Artifact Signing credentials or an OV certificate, and the Tauri updater private key, in Azure, the owner's password manager and GitHub repository secrets.
- Users' Party tokens and AI keys: Credential Manager on the user's machine, never a file or a log.

The Windows dev session needs none of these.

## Windows PC setup checklist

- [ ] Windows 11 (or Windows 10 22H2) with Developer Mode on.
- [ ] Git for Windows, with Git Bash (it includes perl for `scripts/check-style.sh`).
- [ ] `git config --global core.autocrlf input`, so files keep LF line endings.
- [ ] GitHub CLI, then `gh auth login` (HTTPS, repo scope).
- [ ] Node.js 20 or newer (LTS) with npm, for the Windows UI and `backend/` tests.
- [ ] Rust stable through rustup, with the `x86_64-pc-windows-msvc` toolchain.
- [ ] Visual Studio 2022 Build Tools with "Desktop development with C++" and the Windows 11 SDK.
- [ ] WebView2 Runtime (already on Windows 11; the Evergreen installer on Windows 10).
- [ ] Claude Code.
- [ ] Optional: Anki with AnkiConnect (phase 3), Ollama (phase 4), Python 3 for `scripts/l10n-add.py`.
- [ ] Later, owner only: Azure Artifact Signing for code signing, and a Microsoft Partner Center account for the Store.
