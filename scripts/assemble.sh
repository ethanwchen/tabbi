#!/usr/bin/env bash
# Assemble an edition's .app around a built NotchDeck binary. Used by
# bundle.sh and release.sh; prints the .app path.
#
#   usage: scripts/assemble.sh <binary> <output-dir> [edition]
#
# Every edition ships the same binary. An edition only differs in its
# Info.plist (Resources/Editions/<edition>/Info.plist replaces keys of
# Resources/Info.plist: name, bundle id, usage descriptions, and the
# NotchDeckEdition id the app reads to preselect its kit) and, optionally,
# its icon (Resources/Editions/<edition>/AppIcon.icns).
set -euo pipefail
cd "$(dirname "$0")/.."

bin=$1
out=$2
edition=${3:-notchdeck}
overlay_dir=Resources/Editions/$edition

if [[ "$edition" != notchdeck && ! -f "$overlay_dir/Info.plist" ]]; then
    available=$(cd Resources/Editions && ls -d -- */ 2>/dev/null | tr -d / | tr '\n' ' ' | sed 's/ *$//')
    echo "error: unknown edition '$edition' (available: notchdeck $available)" >&2
    exit 1
fi

plist=$(mktemp -t notchdeck-plist)
trap 'rm -f "$plist"' EXIT
if [[ -f "$overlay_dir/Info.plist" ]]; then
    # Merge skips keys the overlay already has, so the overlay wins.
    cp "$overlay_dir/Info.plist" "$plist"
    /usr/libexec/PlistBuddy -c "Merge Resources/Info.plist" "$plist" >/dev/null
else
    cp Resources/Info.plist "$plist"
fi
plutil -lint -s "$plist"

name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist")
icon=Resources/AppIcon.icns
[[ -f "$overlay_dir/AppIcon.icns" ]] && icon=$overlay_dir/AppIcon.icns

app="$out/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/NotchDeck"
cp "$plist" "$app/Contents/Info.plist"
cp "$icon" "$app/Contents/Resources/AppIcon.icns"
# SwiftPM resource bundles (bundled kit manifests); see KitResources.swift.
cp -R "$(dirname "$bin")"/*.bundle "$app/Contents/Resources/"
echo "$app"
