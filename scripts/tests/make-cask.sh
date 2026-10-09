#!/usr/bin/env bash
# Tests for scripts/make-cask.sh. Each case writes a cask for a stand-in DMG
# and compares it with the cask the tap should get, or checks that a bad
# input stops with a clear error. CI also runs brew style and brew audit on
# the cask (the "cask" job in .github/workflows/ci.yml).
#
#   usage: scripts/tests/make-cask.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

work=$(mktemp -d -t tabbi-make-cask)
trap 'rm -rf "$work"' EXIT
failures=0

pass() { echo "ok: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# A stand-in DMG: make-cask.sh only reads its name and checksum.
dmg="$work/Tabbi-1.2.3.dmg"
printf 'not really a disk image' > "$dmg"
sha256=$(shasum -a 256 "$dmg" | cut -d ' ' -f 1)

out=$(env -u SPARKLE_FEED_URL "$root/scripts/make-cask.sh" "$dmg" 2>&1) || { fail "make-cask.sh failed: $out"; out=; }
if [[ "$out" == "$work/tabbi.rb" ]]; then pass "the cask is written beside the DMG as tabbi.rb"; else fail "cask path: $out"; fi

expected='cask "tabbi" do
  version "1.2.3"
  sha256 "'"$sha256"'"

  url "https://github.com/ethanwchen/tabbi/releases/download/v#{version}/Tabbi-#{version}.dmg"
  name "Tabbi"
  desc "Clickable panel of tabs in the MacBook notch"
  homepage "https://github.com/ethanwchen/tabbi"

  livecheck do
    url "https://github.com/ethanwchen/tabbi/releases/latest/download/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on macos: :sonoma

  app "Tabbi.app"

  uninstall quit: "dev.tabbi.Tabbi"

  zap login_item: "Tabbi",
      trash:      [
        "~/Library/Application Support/Tabbi",
        "~/Library/Caches/dev.tabbi.Tabbi",
        "~/Library/HTTPStorages/dev.tabbi.Tabbi",
        "~/Library/Preferences/dev.tabbi.Tabbi.plist",
      ]
end'
if [[ -f "$work/tabbi.rb" && "$(cat "$work/tabbi.rb")" == "$expected" ]]; then
    pass "the cask downloads this version's DMG from the feed's GitHub repository"
else
    fail "cask contents"
    [[ -f "$work/tabbi.rb" ]] && diff <(printf '%s\n' "$expected") "$work/tabbi.rb" | sed 's/^/  /'
fi

if grep -q '@[A-Z_]*@' "$work/tabbi.rb" 2>/dev/null; then fail "a placeholder was left in the cask"; else pass "every placeholder is filled in"; fi

# expect_error <case> <expected message part> <command...>
expect_error() {
    local name=$1 message=$2 actual
    shift 2
    if actual=$("$@" 2>&1); then
        fail "$name: succeeded with $actual"
    elif [[ "$actual" == *"$message"* ]]; then
        pass "$name"
    else
        fail "$name: $actual"
    fi
}

expect_error "a missing DMG stops with an error" "no DMG at" \
    "$root/scripts/make-cask.sh" "$work/Tabbi-9.9.9.dmg"

other="$work/Nobody-1.0.0.dmg"
printf 'x' > "$other"
expect_error "a DMG no edition is named after stops with an error" "no edition is named Nobody" \
    "$root/scripts/make-cask.sh" "$other"

expect_error "a feed outside GitHub Releases stops with an error" "is not a GitHub Releases URL" \
    env SPARKLE_FEED_URL=https://example.com/appcast.xml "$root/scripts/make-cask.sh" "$dmg" "$work/other.rb"

if ((failures > 0)); then
    echo "$failures make-cask test(s) failed" >&2
    exit 1
fi
