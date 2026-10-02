#!/usr/bin/env bash
# Build NotchDeck.app into ./build.   usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
config=${1:-release}
swift build -c "$config"
bin="$(swift build -c "$config" --show-bin-path)/NotchDeck"
app=build/NotchDeck.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/NotchDeck"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# Ad-hoc signature: required on Apple Silicon and gives TCC a stable identity.
codesign --force --sign - "$app" >/dev/null
echo "$app"
