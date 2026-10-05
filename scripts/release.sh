#!/usr/bin/env bash
# Build a release of an edition: a universal (arm64 + x86_64), stripped app,
# signed with a Developer ID under the Hardened Runtime, notarized and stapled,
# packaged as a DMG (signed, notarized and stapled too) and a zip, with
# checksums, in build/release/.
#
#   usage: scripts/release.sh [edition] [--adhoc]
#
# edition defaults to tabbi. The version comes from CFBundleShortVersionString
# in Resources/Info.plist.
#
# Signing settings live in packaging/signing.env (DEVELOPER_ID, NOTARY_PROFILE)
# and update settings in packaging/updates.env (SPARKLE_PUBLIC_KEY,
# SPARKLE_FEED_URL); environment variables with the same names override them.
# When the Developer ID, the notary profile or the update key is missing, the
# script stops before building and says how to set them up. The build number
# (CFBundleVersion, which Sparkle compares) is the commit count, so it needs a
# full clone.
#
# --adhoc builds without a Developer ID (contributors, CI): the app is ad-hoc
# signed and not notarized, so Gatekeeper blocks its first launch on other Macs
# until the user clicks Open Anyway in System Settings > Privacy & Security.
set -euo pipefail
cd "$(dirname "$0")/.."

edition=tabbi
adhoc=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --adhoc) adhoc=true; shift ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 64 ;;
        *) edition=$1; shift ;;
    esac
done

log() { echo "==> $*" >&2; }
fail() { echo "error: $*" >&2; exit 1; }

entitlements=packaging/Tabbi.entitlements
config=packaging/signing.env
# The file's values, then the environment's, which win when set.
developer_id=${DEVELOPER_ID:-$(. "$config"; printf '%s' "${DEVELOPER_ID:-}")}
notary_profile=${NOTARY_PROFILE:-$(. "$config"; printf '%s' "${NOTARY_PROFILE:-}")}
updates=packaging/updates.env
sparkle_key=${SPARKLE_PUBLIC_KEY:-$(. "$updates"; printf '%s' "${SPARKLE_PUBLIC_KEY:-}")}
feed_url=${SPARKLE_FEED_URL:-$(. "$updates"; printf '%s' "${SPARKLE_FEED_URL:-}")}
sparkle_bin=.build/artifacts/sparkle/Sparkle/bin

# True when the update key is an Ed25519 public key (32 bytes, base64).
update_key_ok() {
    [[ -n "$sparkle_key" && "$(printf '%s' "$sparkle_key" | base64 -D 2>/dev/null | wc -c | tr -d ' ')" == 32 ]]
}

# Fails early, before the slow build, with the setup steps that are missing.
preflight_developer_id() {
    local identities identity_ok=true profile_ok=true key_ok=true
    identities=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p')
    if [[ -z "$developer_id" ]]; then
        case $(printf '%s' "$identities" | grep -c .) in
            0) identity_ok=false ;;
            1) developer_id=$identities ;;
            *) fail "found more than one Developer ID Application identity. Set DEVELOPER_ID in $config to one of:
$(printf '%s\n' "$identities" | sed 's/^/  /')" ;;
        esac
    elif ! printf '%s\n' "$identities" | grep -qxF "$developer_id"; then
        identity_ok=false
    fi
    if [[ -z "$notary_profile" ]] \
        || ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
        profile_ok=false
    fi
    update_key_ok || key_ok=false
    $identity_ok && $profile_ok && $key_ok && return 0

    mark() { $1 && echo "done" || echo "missing"; }
    cat >&2 <<EOF

Tabbi releases are signed with your Developer ID and notarized by Apple, so
people can open them without a Gatekeeper warning, and they update themselves
through Sparkle. This needs three one-time setup steps on this Mac:

  1. Developer ID certificate ($(mark $identity_ok))
     ${developer_id:+Looked for: $developer_id
     }In Xcode: Settings > Accounts > your team > Manage Certificates > + >
     Developer ID Application. Check that it shows up with:
       security find-identity -v -p codesigning

  2. Notary credentials in the keychain ($(mark $profile_ok))
     Create an app-specific password at https://account.apple.com, then run:
       xcrun notarytool store-credentials ${notary_profile:-notchdeck} --apple-id <your Apple ID> --team-id <TEAMID>
     notarytool asks for the password and keeps it in the keychain.

  3. Update signing key ($(mark $key_ok))
     Run once (swift package resolve fetches the tool):
       $sparkle_bin/generate_keys
     It keeps the private key in your login keychain and prints the public
     key. Paste that into SPARKLE_PUBLIC_KEY in $updates. Back the private
     key up (generate_keys -x <file>) somewhere safe, never in the repository:
     without it, installed copies can never be updated again.

To build without a Developer ID (for testing on your own Mac), run:
  scripts/release.sh --adhoc
EOF
    exit 1
}

if $adhoc; then
    log "Ad-hoc build: the app will not be notarized"
else
    preflight_developer_id
    log "Signing as: $developer_id (notary profile: $notary_profile)"
fi

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
# Sparkle offers an update when the appcast's build number is higher than the
# running app's, so it must only ever grow: the commit count does.
[[ $(git rev-parse --is-shallow-repository) == false ]] \
    || fail "this is a shallow clone, so the build number would be wrong. Fetch the full history (git fetch --unshallow)."
build_number=$(git rev-list --count HEAD)
out=build/release

log "Building $edition $version (arm64 + x86_64)"
arch_flags=(-c release --arch arm64 --arch x86_64)
swift build "${arch_flags[@]}"
bin="$(swift build "${arch_flags[@]}" --show-bin-path)/Tabbi"

archs=$(lipo -archs "$bin")
for arch in arm64 x86_64; do
    [[ " $archs " == *" $arch "* ]] || fail "$bin is missing $arch (has: $archs)"
done

log "Assembling the $edition app"
rm -rf "$out"
app=$(scripts/assemble.sh "$bin" "$out" "$edition")
name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$app/Contents/Info.plist")
executable="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Contents/Info.plist")"

info="$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$info"
if update_key_ok; then
    # The feed and key turn the updater on (UpdatePolicy); automatic checks
    # default to on without Sparkle's "check automatically?" prompt, and
    # Settings has the switch.
    plutil -replace SUFeedURL -string "$feed_url" "$info"
    plutil -replace SUPublicEDKey -string "$sparkle_key" "$info"
    plutil -replace SUEnableAutomaticChecks -bool YES "$info"
    log "Updates: on ($feed_url)"
else
    log "Updates: off (no SPARKLE_PUBLIC_KEY in $updates)"
fi

# Headers and module maps in embedded frameworks only matter to a compiler.
for framework in "$app"/Contents/Frameworks/*.framework; do
    [[ -e "$framework" ]] || continue
    rm -rf "$framework"/{Headers,Modules,PrivateHeaders} "$framework"/Versions/Current/{Headers,Modules,PrivateHeaders}
done

# Local symbols are only useful to a debugger; stripping them roughly halves the binary.
# The linker's ad-hoc signature goes first, or strip warns that it breaks it.
codesign --remove-signature "$executable"
before=$(stat -f %z "$executable")
strip -x "$executable"
log "Stripped $(basename "$executable"): $((before / 1024)) KB -> $(($(stat -f %z "$executable") / 1024)) KB"

# codesign arguments for one piece of code. Developer ID builds get a secure
# timestamp and the Hardened Runtime, both required for notarization.
sign() {
    if $adhoc; then
        codesign --force --sign - --timestamp=none "$@"
    else
        codesign --force --sign "$developer_id" --timestamp --options runtime "$@"
    fi
}

# Nested code is signed inside-out, each piece on its own, never with --deep,
# which would sign everything with the app's entitlements.
sign_nested() {
    local frameworks="$app/Contents/Frameworks"
    [[ -d "$frameworks" ]] || return 0
    for framework in "$frameworks"/*.framework; do
        [[ -e "$framework" ]] || continue
        local current="$framework/Versions/Current"
        # Sparkle's helpers, in the order its documentation gives
        # (https://sparkle-project.org/documentation/sandboxing/#code-signing).
        [[ -d "$current/XPCServices/Installer.xpc" ]] && sign "$current/XPCServices/Installer.xpc"
        [[ -d "$current/XPCServices/Downloader.xpc" ]] \
            && sign --preserve-metadata=entitlements "$current/XPCServices/Downloader.xpc"
        [[ -f "$current/Autoupdate" ]] && sign "$current/Autoupdate"
        [[ -d "$current/Updater.app" ]] && sign "$current/Updater.app"
        sign "$framework"
    done
}

log "Signing ($($adhoc && echo ad-hoc || echo Developer ID))"
sign_nested
sign --entitlements "$entitlements" "$app"
codesign --verify --strict --deep --verbose=2 "$app"

# Submits a file to Apple's notary service and waits; on rejection prints
# Apple's log, which names each problem.
notarize() {
    log "Notarizing $(basename "$1") (this usually takes a few minutes)"
    local result status id
    result=$(xcrun notarytool submit "$1" --keychain-profile "$notary_profile" --wait --output-format json) \
        || fail "notarytool could not submit $1"
    status=$(plutil -extract status raw -o - - <<<"$result")
    id=$(plutil -extract id raw -o - - <<<"$result")
    if [[ "$status" != Accepted ]]; then
        xcrun notarytool log "$id" --keychain-profile "$notary_profile" >&2 || true
        fail "notarization of $1 ended with status '$status' (submission $id)"
    fi
}

if ! $adhoc; then
    # notarytool takes a zip of the app; the ticket is stapled to the app itself.
    submission="$out/$name-notarize.zip"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$submission"
    notarize "$submission"
    rm -f "$submission"
    xcrun stapler staple -q "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi

zip="$out/$name-$version.zip"
log "Packaging $zip"
# ditto keeps the bundle structure and extended attributes the way Finder does.
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

dmg=$(scripts/make-dmg.sh "$edition" --app "$app" --out "$out" | tail -n 1)
if ! $adhoc; then
    codesign --force --sign "$developer_id" --timestamp "$dmg"
    notarize "$dmg"
    xcrun stapler staple -q "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi

(cd "$out" && shasum -a 256 "$(basename "$dmg")" "$(basename "$zip")" > SHA256SUMS)

size() { du -sh "$1" | cut -f1 | tr -d ' '; }
cat <<EOF

Built $name $version, build $build_number ($($adhoc && echo "ad-hoc signed, not notarized" || echo "Developer ID signed, notarized and stapled")):
  $dmg  ($(size "$dmg"))
  $zip  ($(size "$zip"))
  $out/SHA256SUMS
  app: $(size "$app"), executable: $(size "$executable")
EOF
