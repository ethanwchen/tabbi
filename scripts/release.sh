#!/usr/bin/env bash
# Build a universal (arm64 + x86_64) NotchDeck.app, ad-hoc sign it, and package
# it as build/release/NotchDeck-<version>.zip plus a .sha256 checksum.
#
#   usage: scripts/release.sh
#
# The version comes from CFBundleShortVersionString in Resources/Info.plist.
#
# The app is ad-hoc signed, NOT notarized (that needs a paid Apple Developer ID).
# Gatekeeper therefore blocks the first launch of a downloaded copy. Users open
# it once with right-click > Open (or System Settings > Privacy & Security >
# Open Anyway), or clear the quarantine flag:
#   xattr -dr com.apple.quarantine /Applications/NotchDeck.app
set -euo pipefail
cd "$(dirname "$0")/.."

plist=Resources/Info.plist
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
out=build/release
app="$out/NotchDeck.app"
zip="$out/NotchDeck-$version.zip"

echo "==> Building NotchDeck $version (arm64 + x86_64)"
arch_flags=(-c release --arch arm64 --arch x86_64)
swift build "${arch_flags[@]}"
bin="$(swift build "${arch_flags[@]}" --show-bin-path)/NotchDeck"

archs=$(lipo -archs "$bin")
for arch in arm64 x86_64; do
    [[ " $archs " == *" $arch "* ]] || { echo "error: $bin is missing $arch (has: $archs)" >&2; exit 1; }
done

echo "==> Assembling $app"
rm -rf "$out"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/NotchDeck"
cp "$plist" "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# SwiftPM resource bundles (bundled kit manifests); see KitResources.swift.
cp -R "$(dirname "$bin")"/*.bundle "$app/Contents/Resources/"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"

echo "==> Packaging $zip"
# ditto keeps the bundle structure and extended attributes the way Finder does.
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
(cd "$out" && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")

cat <<EOF

Built:
  $zip
  $zip.sha256  ($(cut -d' ' -f1 "$zip.sha256"))

Next steps for a GitHub release:
  1. Make sure CHANGELOG.md has a $version section and commit it.
  2. Tag and push:   git tag v$version && git push origin v$version
  3. Publish:        gh release create v$version "$zip" "$zip.sha256" \\
                       --title "NotchDeck $version" --notes-file <release-notes.md>
  4. Remind users in the notes that the app is ad-hoc signed, not notarized:
     right-click NotchDeck.app > Open on first launch, or run
       xattr -dr com.apple.quarantine /Applications/NotchDeck.app
EOF
