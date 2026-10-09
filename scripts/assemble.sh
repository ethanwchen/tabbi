#!/usr/bin/env bash
# Assemble an edition's .app around a built Tabbi binary. Used by
# bundle.sh and release.sh; prints the .app path.
#
#   usage: scripts/assemble.sh <binary> <output-dir> [edition]
#
# Every edition ships the same binary. An edition is one JSON file,
# Sources/TabbiKitCore/Editions/BundledEditions/<edition>.json, which the
# app reads too (Edition.swift). Its name (also the executable's), bundle id and id (TabbiEdition,
# which the app reads to preselect its kit) and its infoPlist strings
# (usage descriptions that name the app) replace keys of Resources/Info.plist,
# and its optional icon names an .icns file in Resources.
#
# An App Store edition (distribution appStore) gets what App Store Connect
# checks for: the export compliance answer in Info.plist and a resource
# bundle with its own Info.plist. Its binary must come from the App Store
# build (TABBI_APPSTORE=1), which does not link Sparkle.
set -euo pipefail
cd "$(dirname "$0")/.."

bin=$1
out=$2
edition=${3:-tabbi}
editions=Sources/TabbiKitCore/Editions/BundledEditions
file=$editions/$edition.json

if [[ ! -f "$file" ]]; then
    available=$(for path in "$editions"/*.json; do basename "$path" .json; done | tr '\n' ' ' | sed 's/ *$//')
    echo "error: unknown edition '$edition' (available: $available)" >&2
    exit 1
fi

field() { plutil -extract "$1" raw -o - "$file" 2>/dev/null; }
name=$(field name)
app_store=false
[[ "$(field distribution || true)" == appStore ]] && app_store=true
bundle_id=$(field bundleIdentifier)
icon=Resources/$(field icon || echo AppIcon.icns)
[[ -f "$icon" ]] || { echo "error: edition icon $icon not found" >&2; exit 1; }

plist=$(mktemp -t tabbi-plist)
trap 'rm -f "$plist"' EXIT
plutil -extract infoPlist xml1 -o "$plist" "$file" 2>/dev/null || plutil -create xml1 "$plist"
plutil -replace TabbiEdition -string "$edition" "$plist"
plutil -replace CFBundleName -string "$name" "$plist"
plutil -replace CFBundleDisplayName -string "$name" "$plist"
# The executable carries the edition's name, so Activity Monitor, Force Quit
# and pkill show the app the user installed.
plutil -replace CFBundleExecutable -string "$name" "$plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist"
# Tabbi only uses the encryption built into macOS (HTTPS), which is exempt.
# Without this key App Store Connect asks about it on every upload.
$app_store && plutil -replace ITSAppUsesNonExemptEncryption -bool NO "$plist"
# Merge skips keys the edition already set, so the edition wins.
/usr/libexec/PlistBuddy -c "Merge Resources/Info.plist" "$plist" >/dev/null
plutil -lint -s "$plist"

app="$out/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
cp "$plist" "$app/Contents/Info.plist"
cp "$icon" "$app/Contents/Resources/AppIcon.icns"
# SwiftPM resource bundles (bundled kits and editions); see KitResources.swift.
if $app_store; then
    if otool -L "$bin" | grep -q Sparkle; then
        echo "error: $bin is the direct build (it links Sparkle). Build with TABBI_APPSTORE=1 for an App Store edition" >&2
        exit 1
    fi
    # SwiftPM names its resource bundles' ids after the checkout folder, and
    # a single-architecture build makes the bundles flat with no Info.plist,
    # which App Store Connect rejects as invalid. Lay each out as a macOS
    # bundle with an id under the app's; Bundle finds the same resources in
    # Contents/Resources.
    for bundle in "$(dirname "$bin")"/*.bundle; do
        resources=$bundle
        [[ -d "$bundle/Contents/Resources" ]] && resources=$bundle/Contents/Resources
        dest="$app/Contents/Resources/$(basename "$bundle")"
        mkdir -p "$dest/Contents/Resources"
        cp -R "$resources"/. "$dest/Contents/Resources/"
        bundle_plist="$dest/Contents/Info.plist"
        plutil -create xml1 "$bundle_plist"
        plutil -replace CFBundleIdentifier -string "$bundle_id.$(basename "$bundle" .bundle | tr _ -)" "$bundle_plist"
        plutil -replace CFBundleName -string "$(basename "$bundle" .bundle)" "$bundle_plist"
        plutil -replace CFBundlePackageType -string BNDL "$bundle_plist"
        plutil -replace CFBundleInfoDictionaryVersion -string 6.0 "$bundle_plist"
    done
else
    cp -R "$(dirname "$bin")"/*.bundle "$app/Contents/Resources/"
fi
# Frameworks from binary packages (Sparkle), found through the executable's
# @executable_path/../Frameworks rpath (Package.swift). ditto keeps their symlinks.
for framework in "$(dirname "$bin")"/*.framework; do
    [[ -e "$framework" ]] || continue
    mkdir -p "$app/Contents/Frameworks"
    ditto "$framework" "$app/Contents/Frameworks/$(basename "$framework")"
done

# The widget extension (docs/widget.md), built beside the app's binary. Its
# Info.plist carries the app's versions, which macOS and App Store Connect
# expect to match; release scripts that change the app's build number change
# the extension's too. The extension reads the pet art from its own copy of
# TabbiKitCore's resource bundle, since a sandboxed process loads resources
# from its own bundle.
widget_bin="$(dirname "$bin")/TabbiWidget"
[[ -x "$widget_bin" ]] || { echo "error: $widget_bin not found (swift build builds it with the app)" >&2; exit 1; }
appex="$app/Contents/PlugIns/TabbiWidget.appex"
mkdir -p "$appex/Contents/MacOS" "$appex/Contents/Resources"
cp "$widget_bin" "$appex/Contents/MacOS/TabbiWidget"
cp -R "$app/Contents/Resources/Tabbi_TabbiKitCore.bundle" "$appex/Contents/Resources/"
if $app_store; then
    # Every bundle in an upload needs its own id.
    plutil -replace CFBundleIdentifier -string "$bundle_id.Widget.Tabbi-TabbiKitCore" \
        "$appex/Contents/Resources/Tabbi_TabbiKitCore.bundle/Contents/Info.plist"
fi
widget_plist="$appex/Contents/Info.plist"
plutil -create xml1 "$widget_plist"
plutil -replace CFBundleIdentifier -string "$bundle_id.Widget" "$widget_plist"
plutil -replace CFBundleExecutable -string TabbiWidget "$widget_plist"
plutil -replace CFBundleName -string TabbiWidget "$widget_plist"
plutil -replace CFBundleDisplayName -string "$name" "$widget_plist"
plutil -replace CFBundlePackageType -string 'XPC!' "$widget_plist"
plutil -replace CFBundleInfoDictionaryVersion -string 6.0 "$widget_plist"
plutil -replace CFBundleSupportedPlatforms -json '["MacOSX"]' "$widget_plist"
for key in CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion; do
    plutil -replace "$key" -string "$(plutil -extract "$key" raw -o - "$plist")" "$widget_plist"
done
plutil -replace NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' "$widget_plist"
plutil -lint -s "$widget_plist"
echo "$app"
