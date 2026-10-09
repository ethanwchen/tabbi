#!/usr/bin/env bash
# Tests for scripts/release-notes.sh. Each case builds a throwaway git
# repository with a copy of the script, makes commits and tags, and compares
# the notes with what people should see.
#
#   usage: scripts/tests/release-notes.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

work=$(mktemp -d -t tabbi-release-notes)
trap 'rm -rf "$work"' EXIT
failures=0

# A fresh repository in $repo with the script under test.
new_repo() {
    repo="$work/$1"
    mkdir -p "$repo/scripts"
    cp "$root/scripts/release-notes.sh" "$repo/scripts/"
    git -C "$repo" init -q
    git -C "$repo" config user.name Test
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config commit.gpgsign false
    git -C "$repo" config tag.gpgsign false
}

commit() { git -C "$repo" commit -q --allow-empty -m "$1"; }
tag() { git -C "$repo" tag "$1"; }

# expect <case> <version> <expected notes>
expect() {
    local actual
    actual=$("$repo/scripts/release-notes.sh" "$2" 2>&1) || actual="exit $?: $actual"
    if [[ "$actual" == "$3" ]]; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        diff <(printf '%s\n' "$3") <(printf '%s\n' "$actual") | sed 's/^/  /'
        failures=$((failures + 1))
    fi
}

new_repo first
commit "feat: notch window"
commit "Rename the app (#24)"
expect "the first release gets a welcome, not the whole history" 0.1.0 "## Tabbi 0.1.0

The first release of Tabbi: a small panel of tabs in your MacBook notch."

new_repo sections
commit "feat: notch window"
tag v0.1.0
commit "fix: the timer skipped a second (#40)"
commit "docs: explain kits"
commit "feat(today): show tomorrow's first event (#41)"
commit "perf: draw the ticker once per second"
commit "feat(packaging): smaller DMG"
commit "fix(release): sign the zip"
commit "ci: cache npm"
commit "feat!: kits can hide the tab bar"
commit "not a conventional commit"
expect "changes since the last tag, grouped, user facing only" 0.2.0 "## Tabbi 0.2.0

### New

- Show tomorrow's first event
- Kits can hide the tab bar

### Fixed

- The timer skipped a second

### Faster

- Draw the ticker once per second"

new_repo retagged
commit "feat: notch window"
tag v0.1.0
commit "fix: a crash at launch"
tag v0.1.1
expect "a version that is already tagged compares with the tag before it" 0.1.1 "## Tabbi 0.1.1

### Fixed

- A crash at launch"

new_repo quiet
commit "feat: notch window"
tag v0.1.0
commit "docs: typo"
commit "test: cover the parser"
expect "a release with nothing user facing still says something" 0.1.1 "## Tabbi 0.1.1

Small improvements and fixes."

new_repo named
commit "feat: notch window"
tag v1.0.0
commit "fix: something"
expect "the edition name heads the notes" 1.1.0 "## Tabbi 1.1.0

### Fixed

- Something"
actual=$("$repo/scripts/release-notes.sh" 1.1.0 Pawdoro)
if [[ "${actual%%$'\n'*}" == "## Pawdoro 1.1.0" ]]; then echo "ok: a name argument replaces Tabbi"; else echo "FAIL: name argument: $actual"; failures=$((failures + 1)); fi

if ((failures > 0)); then
    echo "$failures release notes test(s) failed" >&2
    exit 1
fi
