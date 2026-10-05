#!/usr/bin/env bash
# Write the Homebrew cask for a release DMG, from packaging/homebrew/tabbi.rb.in.
#
#   usage: scripts/make-cask.sh <path/to/Name-version.dmg> [<out.rb>]
#
# The same cask serves the project tap (ethanwchen/homebrew-tap, Casks/) and
# the official homebrew/cask, which only accepts apps that pass Gatekeeper,
# so submit it there only for Developer ID signed, notarized releases.
# It downloads the DMG from the GitHub Release tagged v<version>, leaves
# updates to Sparkle (auto_updates true, so `brew upgrade` skips it) and
# never strips the quarantine attribute: a notarized app does not need that.
# The token, name, bundle id and feed come from the edition and
# packaging/updates.env. out defaults to the DMG's folder, named <token>.rb.
set -euo pipefail
cd "$(dirname "$0")/.."

dmg=${1:?usage: scripts/make-cask.sh <path/to/Name-version.dmg> [<out.rb>]}
[[ -f "$dmg" ]] || { echo "error: no DMG at $dmg" >&2; exit 1; }

file=$(basename "$dmg" .dmg)
name=${file%-*}
version=${file##*-}
edition_file=$(grep -l "\"name\": \"$name\"" Sources/TabbiKitCore/Editions/BundledEditions/*.json | head -n 1 || true)
[[ -n "$edition_file" ]] || { echo "error: no edition is named $name" >&2; exit 1; }
bundle_id=$(plutil -extract bundleIdentifier raw -o - "$edition_file")
token=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
# shellcheck source=packaging/updates.env disable=SC2031 # read in a subshell on purpose
feed_url=${SPARKLE_FEED_URL:-$(. packaging/updates.env; printf '%s' "${SPARKLE_FEED_URL:-}")}
# The repository is the one the feed's releases live in.
repo_url=${feed_url%%/releases/*}
[[ "$repo_url" == https://github.com/* ]] \
    || { echo "error: SPARKLE_FEED_URL ($feed_url) is not a GitHub Releases URL" >&2; exit 1; }
sha256=$(shasum -a 256 "$dmg" | cut -d ' ' -f 1)
out=${2:-$(dirname "$dmg")/$token.rb}
mkdir -p "$(dirname "$out")"

sed -e "s|@TOKEN@|$token|g" -e "s|@VERSION@|$version|g" -e "s|@SHA256@|$sha256|g" \
    -e "s|@NAME@|$name|g" -e "s|@BUNDLE_ID@|$bundle_id|g" \
    -e "s|@REPO_URL@|$repo_url|g" -e "s|@FEED_URL@|$feed_url|g" \
    packaging/homebrew/tabbi.rb.in > "$out"
echo "$out"
