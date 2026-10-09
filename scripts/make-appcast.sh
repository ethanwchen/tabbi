#!/usr/bin/env bash
# Write the Sparkle appcast for a release zip, signed with the update key.
#
#   usage: scripts/make-appcast.sh <path/to/Name-version.zip> <release-notes.md> [<out.xml>]
#
# The feed lists just this version, which is all Sparkle needs: installed
# copies compare its build number (CFBundleVersion) with their own. The notes
# are embedded in the feed, so the update window shows them as they were at
# build time. The archive is downloaded from the GitHub Release tagged
# v<version> when SPARKLE_FEED_URL is .../releases/latest/download/appcast.xml,
# and from beside the feed otherwise.
# The private key comes from SPARKLE_PRIVATE_KEY (what generate_keys -x
# exported, as in CI) or else from the login keychain. The script stops when
# that key does not match the app's SUPublicEDKey, because every installed
# copy would then reject the update. out defaults to the zip's folder.
set -euo pipefail

usage="usage: scripts/make-appcast.sh <path/to/Name-version.zip> <release-notes.md> [<out.xml>]"
zip=${1:?$usage}
notes=${2:?$usage}
[[ -f "$zip" ]] || { echo "error: no zip at $zip" >&2; exit 1; }
[[ -f "$notes" ]] || { echo "error: no release notes at $notes" >&2; exit 1; }
out=${3:-$(dirname "$zip")/appcast.xml}
# Absolute paths, so they still hold after the cd to the repository.
absolute() { (cd "$(dirname "$1")" && printf '%s/%s' "$(pwd)" "$(basename "$1")"); }
zip=$(absolute "$zip")
notes=$(absolute "$notes")
mkdir -p "$(dirname "$out")"
out=$(absolute "$out")
cd "$(dirname "$0")/.."

file=$(basename "$zip" .zip)
version=${file##*-}
# shellcheck source=packaging/updates.env disable=SC2031 # read in a subshell on purpose
feed_url=${SPARKLE_FEED_URL:-$(. packaging/updates.env; printf '%s' "${SPARKLE_FEED_URL:-}")}
[[ "$feed_url" == https://* ]] || { echo "error: SPARKLE_FEED_URL ($feed_url) is not an HTTPS URL" >&2; exit 1; }
case "$feed_url" in
    https://github.com/*/releases/latest/download/*)
        download_prefix="${feed_url%%/releases/latest/download/*}/releases/download/v$version/" ;;
    *) download_prefix="${feed_url%/*}/" ;;
esac

sparkle_bin=.build/artifacts/sparkle/Sparkle/bin
[[ -x "$sparkle_bin/generate_appcast" ]] || swift package resolve >/dev/null

# A fresh folder holds just this archive and, named like it, its notes.
feed_dir=$(mktemp -d -t tabbi-appcast)
trap 'rm -rf "$feed_dir"' EXIT
cp "$zip" "$feed_dir/"
cp "$notes" "$feed_dir/$file.md"

args=(--download-url-prefix "$download_prefix" --embed-release-notes --disable-signing-warning -o "$feed_dir/appcast.xml")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    report=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sparkle_bin/generate_appcast" --ed-key-file - "${args[@]}" "$feed_dir" 2>&1)
else
    report=$("$sparkle_bin/generate_appcast" "${args[@]}" "$feed_dir" 2>&1)
fi
echo "$report" >&2
# generate_appcast only warns about a key that does not match.
if grep -q "does not match" <<<"$report"; then
    echo "error: the private update key does not match the app's SUPublicEDKey, so no installed copy could install this update" >&2
    exit 1
fi
[[ -f "$feed_dir/appcast.xml" ]] || { echo "error: generate_appcast wrote no appcast" >&2; exit 1; }
mv "$feed_dir/appcast.xml" "$out"
echo "$out"
