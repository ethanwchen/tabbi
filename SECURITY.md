# Security Policy

## Supported versions

Tabbi is a young project.
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

Tabbi runs locally and has a small attack surface, but these areas deserve particular care:

- **The `claude` CLI integration.** Ask Claude, Claude Usage, Today's Plan my day and Wrap up, and the Validate button in Settings > Connections (under More options) start the user's local `claude` command.
  Issues such as running an unexpected binary, passing untrusted input to it in an unsafe way, or exposing its output to other processes are in scope.
- **Local data.** Tabbi reads Claude Code transcripts under `~/.claude` (read-only) and stores its own data in `~/Library/Application Support/Tabbi`: the Today checklist and daily reviews, the activity log, the study log, the pet save, imported kits and the Claude Usage scan index.
  Leaking that data outside the Mac is in scope.
- **Apple Events.** Tabbi controls Spotify and Apple Music through Automation.
  Anything that lets another app abuse that permission through Tabbi is in scope.
- **Network access.** Tabbi only connects to the hosts its modules list in their descriptors: album artwork for Now Playing, AnkiConnect on localhost for Anki, and the friends server for Party (only when that tab is on).
  Release builds also download the update feed from GitHub through Sparkle, unless automatic checks are turned off in Settings > About.
  Any other outgoing request is a bug and in scope.

These are out of scope:

- Gatekeeper warnings on builds made with `scripts/release.sh --adhoc`, which are not notarized.
  Official releases are signed and notarized; see [docs/install.md](docs/install.md).
- Vulnerabilities in macOS, Spotify, Apple Music, or the `claude` CLI themselves.
  Please report those to their vendors.
