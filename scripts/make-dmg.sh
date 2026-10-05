#!/usr/bin/env bash
# Package an edition's .app as a drag-to-install DMG with the edition's
# background art, and print the DMG path.
#
#   usage: scripts/make-dmg.sh [edition] [--app <path/to/Name.app>] [--out <dir>]
#
# edition defaults to tabbi. Without --app it builds the app first with
# scripts/bundle.sh (release, this Mac's architecture); release.sh passes the
# universal, signed app instead. The DMG is <out>/<Name>-<version>.dmg, with
# out defaulting to ./build.
#
# The DMG is built by dmgbuild (packaging/dmg/settings.py), which this script
# installs once, pinned by hash, into .build/dmgbuild. The background is drawn
# by packaging/dmg/render-background.swift at 1x and 2x and merged into one
# HiDPI TIFF, so Finder shows it sharp on every display.
set -euo pipefail
cd "$(dirname "$0")/.."

edition=tabbi
app=
out=build
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) app=${2:?--app needs a path}; shift 2 ;;
        --out) out=${2:?--out needs a directory}; shift 2 ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 64 ;;
        *) edition=$1; shift ;;
    esac
done

log() { echo "==> $*" >&2; }

if [[ -z "$app" ]]; then
    log "Building the $edition app"
    app=$(scripts/bundle.sh "$edition" release | tail -n 1)
fi
[[ -d "$app" && -f "$app/Contents/Info.plist" ]] || { echo "error: $app is not an app bundle" >&2; exit 1; }

plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist"; }
name=$(plist_value CFBundleName)
version=$(plist_value CFBundleShortVersionString)
dmg="$out/$name-$version.dmg"

# dmgbuild, pinned by hash in a private virtual environment. Reinstalled only
# when packaging/dmg/requirements.txt changes.
venv=.build/dmgbuild
requirements=packaging/dmg/requirements.txt
if ! cmp -s "$requirements" "$venv/requirements.txt" 2>/dev/null; then
    log "Installing dmgbuild into $venv"
    python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
        || { echo "error: dmgbuild needs Python 3.10 or newer (found $(python3 --version 2>&1))" >&2; exit 1; }
    rm -rf "$venv"
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes --only-binary :all: -r "$requirements" >&2
    cp "$requirements" "$venv/requirements.txt"
fi

work=$(mktemp -d -t tabbi-dmg)
trap 'rm -rf "$work"' EXIT

log "Rendering the background"
swift packaging/dmg/render-background.swift "$name" "$work" >/dev/null
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff" 2>/dev/null

log "Building $dmg"
mkdir -p "$out"
rm -f "$dmg"
"$venv/bin/dmgbuild" -s packaging/dmg/settings.py \
    -D app="$app" \
    -D background="$work/background.tiff" \
    -D icon="$app/Contents/Resources/AppIcon.icns" \
    "$name" "$dmg" >&2
hdiutil verify -quiet "$dmg"

log "$(basename "$dmg"): $(du -h "$dmg" | cut -f1 | tr -d ' ') (app: $(du -sh "$app" | cut -f1 | tr -d ' '))"
echo "$dmg"
