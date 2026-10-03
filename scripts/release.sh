#!/usr/bin/env bash
# Build a universal (arm64 + x86_64) edition .app, ad-hoc sign it, and package
# it as build/release/<Name>-<version>.zip plus a .sha256 checksum.
#
#   usage: scripts/release.sh [edition]      (default: tabbi)
#
# The version comes from CFBundleShortVersionString in Resources/Info.plist.
#
# The app is ad-hoc signed, NOT notarized (that needs a paid Apple Developer ID).
# Gatekeeper therefore blocks the first launch of a downloaded copy. Users open
# it once with right-click > Open (or System Settings > Privacy & Security >
# Open Anyway), or clear the quarantine flag:
#   xattr -dr com.apple.quarantine /Applications/Tabbi.app
set -euo pipefail
cd "$(dirname "$0")/.."

edition=${1:-tabbi}
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
out=build/release

echo "==> Building $edition $version (arm64 + x86_64)"
arch_flags=(-c release --arch arm64 --arch x86_64)
swift build "${arch_flags[@]}"
bin="$(swift build "${arch_flags[@]}" --show-bin-path)/Tabbi"

archs=$(lipo -archs "$bin")
for arch in arm64 x86_64; do
    [[ " $archs " == *" $arch "* ]] || { echo "error: $bin is missing $arch (has: $archs)" >&2; exit 1; }
done

echo "==> Assembling the $edition app"
rm -rf "$out"
app=$(scripts/assemble.sh "$bin" "$out" "$edition")
name=$(basename "$app" .app)
zip="$out/$name-$version.zip"

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
                       --title "$name $version" --notes-file <release-notes.md>
  4. Remind users in the notes that the app is ad-hoc signed, not notarized:
     right-click $name.app > Open on first launch, or run
       xattr -dr com.apple.quarantine /Applications/$name.app
EOF
