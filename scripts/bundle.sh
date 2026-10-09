#!/usr/bin/env bash
# Build an edition's .app into ./build.
#
#   usage: scripts/bundle.sh [edition] [debug|release]
#
# edition defaults to tabbi, which builds build/Tabbi.app. Other editions
# are files in Sources/TabbiKitCore/Editions/BundledEditions; see assemble.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
edition=tabbi
config=release
for arg in "$@"; do
    case "$arg" in
        debug|release) config=$arg ;;
        *) edition=$arg ;;
    esac
done
swift build -c "$config"
bin="$(swift build -c "$config" --show-bin-path)/Tabbi"
app=$(scripts/assemble.sh "$bin" build "$edition")
# Ad-hoc signature: required on Apple Silicon and gives TCC a stable identity.
# The widget extension goes first, with its own sandbox entitlements.
codesign --force --sign - --entitlements packaging/TabbiWidget.entitlements \
    "$app/Contents/PlugIns/TabbiWidget.appex" >/dev/null
# The app's entitlements give it the App Group it shares with the widget.
codesign --force --sign - --entitlements packaging/Tabbi.entitlements "$app" >/dev/null
echo "$app"
