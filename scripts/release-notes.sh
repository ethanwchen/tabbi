#!/usr/bin/env bash
# Print the release notes for a version as Markdown, written from the git
# history since the previous release tag (v*). They go into the appcast,
# which Sparkle shows in its update window, and into the GitHub Release.
#
#   usage: scripts/release-notes.sh <version> [<name>]
#
# Only changes people notice are listed: feat commits under "New", fix under
# "Fixed" and perf under "Faster", with the conventional-commit prefix
# and a trailing pull request number ("(#12)") removed. Other commit types
# (docs, test, ci, chore, ...) and the scopes that only concern people
# building Tabbi (packaging, release) are left out.
# The first release (no earlier v* tag) gets a short welcome instead: its
# history is the whole development of the app, which means nothing to someone
# installing it. The notes come from commit messages, so CHANGELOG.md is never
# edited here.
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/release-notes.sh <version> [<name>]}
name=${2:-Tabbi}

# The release before this one: the newest v* tag that is not this version's.
previous=$(git describe --tags --abbrev=0 --match 'v*' --exclude "v$version" HEAD 2>/dev/null || true)

echo "## $name $version"
if [[ -z "$previous" ]]; then
    echo
    echo "The first release of $name: a small panel of tabs in your MacBook notch."
    exit 0
fi

# One line per commit: "<section>\t<text>", in history order (oldest first).
entries=$(git log --no-merges --reverse --format=%s "$previous..HEAD" | awk '
    {
        if (!match($0, /^[a-z]+(\([^)]*\))?!?: /)) next
        type = substr($0, 1, RLENGTH)
        scope = type
        sub(/[(!:].*/, "", type)
        if (scope ~ /^[a-z]+\((packaging|release)\)/) next
        text = substr($0, RLENGTH + 1)
        sub(/ \(#[0-9]+\)$/, "", text)
        if (type == "feat") section = 1
        else if (type == "fix") section = 2
        else if (type == "perf") section = 3
        else next
        text = toupper(substr(text, 1, 1)) substr(text, 2)
        print section "\t" text
    }')

if [[ -z "$entries" ]]; then
    echo
    echo "Small improvements and fixes."
    exit 0
fi
for section in 1 2 3; do
    lines=$(printf '%s\n' "$entries" | awk -F'\t' -v s="$section" '$1 == s { print "- " $2 }')
    [[ -n "$lines" ]] || continue
    case $section in
        1) title=New ;;
        2) title=Fixed ;;
        3) title=Faster ;;
    esac
    printf '\n### %s\n\n%s\n' "$title" "$lines"
done
