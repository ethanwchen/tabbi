#!/usr/bin/env bash
# Tests for scripts/make-appcast.sh. Each case writes the appcast for a
# stand-in release zip (a tiny Tabbi.app carrying the version and the update
# key in its Info.plist), signed with a throwaway key made for the run, and
# checks the feed installed copies would read, including that the archive's
# signature verifies the way Sparkle checks it before installing.
#
#   usage: scripts/tests/make-appcast.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

work=$(mktemp -d -t tabbi-make-appcast)
trap 'rm -rf "$work"' EXIT
failures=0

pass() { echo "ok: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

sparkle_bin="$root/.build/artifacts/sparkle/Sparkle/bin"
[[ -x "$sparkle_bin/sign_update" ]] || swift package --package-path "$root" resolve >/dev/null

# A throwaway Ed25519 key pair (base64 raw keys, as generate_keys -x exports).
new_key() {
    printf '%s\n' 'import CryptoKit' 'let key = Curve25519.Signing.PrivateKey()' \
        'print(key.rawRepresentation.base64EncodedString())' \
        'print(key.publicKey.rawRepresentation.base64EncodedString())' | swift -
}
keys=$(new_key)
private_key=${keys%$'\n'*}
public_key=${keys#*$'\n'}
other_keys=$(new_key)
other_private_key=${other_keys%$'\n'*}

# Name-version.zip holding a Tabbi.app whose Info.plist names the key.
make_zip() {
    local version=$1 build=$2 dir="$work/$1"
    local app="$dir/stage/Tabbi.app"
    mkdir -p "$app/Contents/MacOS"
    cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>Tabbi</string>
    <key>CFBundleIdentifier</key><string>dev.tabbi.Tabbi</string>
    <key>CFBundleExecutable</key><string>Tabbi</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$build</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>SUPublicEDKey</key><string>$public_key</string>
</dict></plist>
EOF
    printf '#!/bin/sh\n' > "$app/Contents/MacOS/Tabbi"
    chmod +x "$app/Contents/MacOS/Tabbi"
    ditto -c -k --keepParent "$app" "$dir/Tabbi-$version.zip"
    printf '## Tabbi %s\n\n### New\n\n- Plan my day fills the gaps between meetings\n' "$version" > "$dir/release-notes.md"
    echo "$dir/Tabbi-$version.zip"
}

zip=$(make_zip 1.2.3 70)
notes="$work/1.2.3/release-notes.md"

# The feed from packaging/updates.env and a key that matches the app.
out=$(env -u SPARKLE_FEED_URL SPARKLE_PRIVATE_KEY="$private_key" "$root/scripts/make-appcast.sh" "$zip" "$notes" 2>"$work/log") \
    || { fail "make-appcast.sh failed: $(cat "$work/log")"; out=; }
if [[ "$out" == "$work/1.2.3/appcast.xml" ]]; then pass "the appcast is written beside the zip"; else fail "appcast path: $out"; fi
feed=$(cat "$work/1.2.3/appcast.xml" 2>/dev/null || true)

check() {
    if grep -qF -- "$2" <<<"$feed"; then pass "$1"; else fail "$1: no '$2' in $feed"; fi
}
check "the archive downloads from the release's tag" \
    'url="https://github.com/ethanwchen/tabbi/releases/download/v1.2.3/Tabbi-1.2.3.zip"'
check "the build number is what installed copies compare" '<sparkle:version>70</sparkle:version>'
check "the version people see" '<sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>'
check "the minimum macOS comes from the app" '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>'
check "the release notes are embedded as Markdown" '<description sparkle:format="markdown"><![CDATA[## Tabbi 1.2.3'
check "the notes keep their sections" '- Plan my day fills the gaps between meetings'
items=$(grep -c '<item>' <<<"$feed" || true)
if [[ "$items" == 1 ]]; then pass "the feed lists only this version"; else fail "the feed has $items items"; fi

signature=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$feed")
length=$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$feed")
printf '%s' "$private_key" > "$work/private-key"
if [[ -n "$signature" ]] && "$sparkle_bin/sign_update" --verify "$zip" "$signature" --ed-key-file "$work/private-key" >/dev/null 2>&1; then
    pass "the archive's signature verifies with the update key"
else
    fail "the signature '$signature' does not verify"
fi
if [[ "$length" == "$(stat -f %z "$zip")" ]]; then pass "the length is the zip's size"; else fail "length $length"; fi
printf '%s' "$other_private_key" > "$work/other-private-key"
if "$sparkle_bin/sign_update" --verify "$zip" "$signature" --ed-key-file "$work/other-private-key" >/dev/null 2>&1; then
    fail "the signature also verifies with another key"
else
    pass "another key does not verify the signature"
fi

# A feed outside GitHub Releases serves the archive from beside it.
zip=$(make_zip 1.3.0 71)
out=$(SPARKLE_FEED_URL=https://updates.example.com/tabbi/appcast.xml SPARKLE_PRIVATE_KEY="$private_key" \
    "$root/scripts/make-appcast.sh" "$zip" "$work/1.3.0/release-notes.md" "$work/elsewhere/feed.xml" 2>"$work/log") \
    || { fail "make-appcast.sh failed: $(cat "$work/log")"; out=; }
if [[ "$out" == "$work/elsewhere/feed.xml" ]]; then pass "the appcast goes where it is asked to"; else fail "appcast path: $out"; fi
feed=$(cat "$work/elsewhere/feed.xml" 2>/dev/null || true)
check "a feed outside GitHub Releases serves the archive from beside it" \
    'url="https://updates.example.com/tabbi/Tabbi-1.3.0.zip"'

# Each bad input stops with a clear error and writes no appcast.
expect_error() {
    local label=$1 message=$2 target=$3
    shift 3
    if output=$("$@" 2>&1); then
        fail "$label: make-appcast.sh succeeded"
    elif [[ "$output" != *"$message"* ]]; then
        fail "$label: unexpected output: $output"
    elif [[ -e "$target" ]]; then
        fail "$label: it still wrote $target"
    else
        pass "$label"
    fi
}
zip=$(make_zip 2.0.0 80)
notes="$work/2.0.0/release-notes.md"
expect_error "a key that does not match the app stops" "does not match the app's SUPublicEDKey" "$work/2.0.0/appcast.xml" \
    env -u SPARKLE_FEED_URL SPARKLE_PRIVATE_KEY="$other_private_key" "$root/scripts/make-appcast.sh" "$zip" "$notes"
expect_error "a feed that is not HTTPS stops" "is not an HTTPS URL" "$work/2.0.0/appcast.xml" \
    env SPARKLE_FEED_URL=http://example.com/appcast.xml SPARKLE_PRIVATE_KEY="$private_key" "$root/scripts/make-appcast.sh" "$zip" "$notes"
expect_error "a missing zip stops" "no zip at" "$work/missing/appcast.xml" \
    env SPARKLE_PRIVATE_KEY="$private_key" "$root/scripts/make-appcast.sh" "$work/missing/Tabbi-2.0.0.zip" "$notes"
expect_error "missing release notes stop" "no release notes at" "$work/2.0.0/appcast.xml" \
    env SPARKLE_PRIVATE_KEY="$private_key" "$root/scripts/make-appcast.sh" "$zip" "$work/missing.md"

if ((failures > 0)); then
    echo "$failures make-appcast.sh test(s) failed"
    exit 1
fi
echo "all make-appcast.sh tests passed"
