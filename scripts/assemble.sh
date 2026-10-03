#!/usr/bin/env bash
# Assemble an edition's .app around a built Tabbi binary. Used by
# bundle.sh and release.sh; prints the .app path.
#
#   usage: scripts/assemble.sh <binary> <output-dir> [edition]
#
# Every edition ships the same binary. An edition is one JSON file,
# Sources/TabbiKitCore/Editions/BundledEditions/<edition>.json, which the
# app reads too (Edition.swift). Its name, bundle id and id (TabbiEdition,
# which the app reads to preselect its kit) and its infoPlist strings
# (usage descriptions that name the app) replace keys of Resources/Info.plist,
# and its optional icon names an .icns file in Resources.
set -euo pipefail
cd "$(dirname "$0")/.."

bin=$1
out=$2
edition=${3:-tabbi}
editions=Sources/TabbiKitCore/Editions/BundledEditions
file=$editions/$edition.json

if [[ ! -f "$file" ]]; then
    available=$(cd "$editions" && ls -- *.json | sed 's/\.json$//' | tr '\n' ' ' | sed 's/ *$//')
    echo "error: unknown edition '$edition' (available: $available)" >&2
    exit 1
fi

field() { plutil -extract "$1" raw -o - "$file" 2>/dev/null; }
name=$(field name)
bundle_id=$(field bundleIdentifier)
icon=Resources/$(field icon || echo AppIcon.icns)
[[ -f "$icon" ]] || { echo "error: edition icon $icon not found" >&2; exit 1; }

plist=$(mktemp -t tabbi-plist)
trap 'rm -f "$plist"' EXIT
plutil -extract infoPlist xml1 -o "$plist" "$file" 2>/dev/null || plutil -create xml1 "$plist"
plutil -replace TabbiEdition -string "$edition" "$plist"
plutil -replace CFBundleName -string "$name" "$plist"
plutil -replace CFBundleDisplayName -string "$name" "$plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist"
# Merge skips keys the edition already set, so the edition wins.
/usr/libexec/PlistBuddy -c "Merge Resources/Info.plist" "$plist" >/dev/null
plutil -lint -s "$plist"

app="$out/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Tabbi"
cp "$plist" "$app/Contents/Info.plist"
cp "$icon" "$app/Contents/Resources/AppIcon.icns"
# SwiftPM resource bundles (bundled kits and editions); see KitResources.swift.
cp -R "$(dirname "$bin")"/*.bundle "$app/Contents/Resources/"
echo "$app"
