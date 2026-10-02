# Security Policy

## Supported versions

NotchDeck is a young project.
Security fixes go into the latest release only.

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Please do not report security issues in public issues, discussions, or pull requests.

Report them privately through GitHub instead:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Describe the issue, the affected version, and the steps to reproduce it.

You can expect an acknowledgment within a few days.
We will keep you updated while we work on a fix, and credit you in the release notes unless you prefer to stay anonymous.

## Scope

NotchDeck runs locally and has a small attack surface, but these areas deserve particular care:

- **The `claude` CLI integration.** Ask Claude and Claude Usage start the user's local `claude` command.
  Issues such as running an unexpected binary, passing untrusted input to it in an unsafe way, or exposing its output to other processes are in scope.
- **Local data.** NotchDeck reads Claude Code transcripts under `~/.claude` (read-only) and stores the Today checklist in `~/Library/Application Support/NotchDeck`.
  Leaking that data outside the Mac is in scope.
- **Apple Events.** NotchDeck controls Spotify and Apple Music through Automation.
  Anything that lets another app abuse that permission through NotchDeck is in scope.
- **Network access.** The only network requests NotchDeck makes are for album artwork.
  Any other outgoing request is a bug and in scope.

These are out of scope:

- Gatekeeper warnings caused by release builds being ad-hoc signed rather than notarized.
  This is a known limitation, documented in the README.
- Vulnerabilities in macOS, Spotify, Apple Music, or the `claude` CLI themselves.
  Please report those to their vendors.
