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
# Ad-hoc signature by default: required on Apple Silicon and gives TCC a
# stable identity. SIGN_IDENTITY (for example "Developer ID Application")
# signs with a certificate of team B9VRALHV8S instead, which the widget needs
# to read the app's state: macOS keeps an ad-hoc signed widget out of the
# team-prefixed App Group container (see docs/widget.md).
identity=${SIGN_IDENTITY:--}
# The widget extension goes first, with its own sandbox entitlements.
codesign --force --sign "$identity" --entitlements packaging/TabbiWidget.entitlements \
    "$app/Contents/PlugIns/TabbiWidget.appex" >/dev/null
# The app's entitlements give it the App Group it shares with the widget.
codesign --force --sign "$identity" --entitlements packaging/Tabbi.entitlements "$app" >/dev/null
echo "$app"
