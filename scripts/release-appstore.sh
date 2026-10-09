#!/usr/bin/env bash
# Build the Mac App Store release of Tabbi: the App Store build of the binary
# (TABBI_APPSTORE=1: no Sparkle, no install hygiene, no claude CLI modules),
# universal (arm64 + x86_64) and stripped, assembled as the appstore edition,
# sandboxed with packaging/Tabbi-AppStore.entitlements, signed with an Apple
# Distribution certificate around an App Store provisioning profile, and
# packaged as a signed installer package in build/appstore/, ready for
# Transporter or `xcrun altool --upload-app`. Nothing is uploaded.
#
#   usage: scripts/release-appstore.sh [--adhoc]
#
# The version comes from CFBundleShortVersionString in Resources/Info.plist,
# and the build number (CFBundleVersion, which must grow with every upload)
# is the commit count, so it needs a full clone. docs/appstore.md lists the
# certificates and the profile to create.
#
# Signing settings come from the environment:
#   APPSTORE_IDENTITY   the app's signing identity. Leave it unset to use the
#                       single "Apple Distribution" (or older "3rd Party Mac
#                       Developer Application") identity in the keychain.
#   INSTALLER_IDENTITY  the package's signing identity. Leave it unset to use
#                       the single "3rd Party Mac Developer Installer" (or
#                       "Mac Installer Distribution") identity.
#   APPSTORE_PROFILE    the App Store provisioning profile, by default
#                       packaging/Tabbi-AppStore.provisionprofile (gitignored).
# When an identity or the profile is missing, the script stops before building
# and says how to set it up.
#
# --adhoc builds without certificates or a profile (contributors, CI, and the
# sandbox check in docs/appstore.md): the app is ad-hoc signed with the sandbox
# entitlements, so it runs sandboxed on this Mac, and the package is unsigned.
# The App Store does not accept it.
set -euo pipefail
cd "$(dirname "$0")/.."

adhoc=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --adhoc) adhoc=true; shift ;;
        -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *) echo "error: unknown argument $1" >&2; exit 64 ;;
    esac
done

log() { echo "==> $*" >&2; }
fail() { echo "error: $*" >&2; exit 1; }

edition=appstore
entitlements=packaging/Tabbi-AppStore.entitlements
profile=${APPSTORE_PROFILE:-packaging/Tabbi-AppStore.provisionprofile}
app_identity=${APPSTORE_IDENTITY:-}
installer_identity=${INSTALLER_IDENTITY:-}
bundle_id=$(plutil -extract bundleIdentifier raw -o - "Sources/TabbiKitCore/Editions/BundledEditions/$edition.json")
out=build/appstore
work=$(mktemp -d -t tabbi-appstore)
trap 'rm -rf "$work"' EXIT

# Prints the one identity in the keychain whose name starts with one of the
# given prefixes; prints nothing when there is none, and fails when there are
# several (the caller's variable then has to pick one).
find_identity() {
    local variable=$1 policy=$2 found
    shift 2
    found=$(security find-identity -v -p "$policy" 2>/dev/null \
        | sed -n 's/^ *[0-9][0-9]*) [0-9A-F]* "\(.*\)"$/\1/p' \
        | grep -E "^($(IFS='|'; echo "$*")): " | sort -u || true)
    case $(printf '%s' "$found" | grep -c .) in
        0) ;;
        1) printf '%s' "$found" ;;
        *) fail "found more than one matching identity. Set $variable to one of:
$(printf '%s\n' "$found" | sed 's/^/  /')" ;;
    esac
}

# True when the keychain has a valid identity with exactly this name.
has_identity() {
    security find-identity -v -p "$2" 2>/dev/null | grep -qF "\"$1\""
}

# A value from the provisioning profile's plist, or nothing.
profile_value() {
    plutil -extract "$1" raw -o - "$work/profile.plist" 2>/dev/null || true
}

# Fails early, before the slow build, with the setup steps that are missing.
preflight() {
    local identity_ok=true installer_ok=true profile_ok=true profile_problem=
    if [[ -n "$app_identity" ]]; then
        has_identity "$app_identity" codesigning || identity_ok=false
    else
        app_identity=$(find_identity APPSTORE_IDENTITY codesigning "Apple Distribution" "3rd Party Mac Developer Application")
        [[ -n "$app_identity" ]] || identity_ok=false
    fi
    if [[ -n "$installer_identity" ]]; then
        has_identity "$installer_identity" basic || installer_ok=false
    else
        installer_identity=$(find_identity INSTALLER_IDENTITY basic "3rd Party Mac Developer Installer" "Mac Installer Distribution")
        [[ -n "$installer_identity" ]] || installer_ok=false
    fi
    if [[ ! -f "$profile" ]]; then
        profile_ok=false
        profile_problem="not found at $profile"
    elif ! security cms -D -i "$profile" -o "$work/profile.plist" 2>/dev/null; then
        profile_ok=false
        profile_problem="$profile is not a provisioning profile"
    else
        local app_id team expires
        app_id=$(profile_value Entitlements.com\\.apple\\.application-identifier)
        team=$(profile_value Entitlements.com\\.apple\\.developer\\.team-identifier)
        expires=$(profile_value ExpirationDate)
        if [[ "$app_id" != "$team.$bundle_id" ]]; then
            profile_ok=false
            profile_problem="$profile is for ${app_id:-an unknown app}, not $bundle_id"
        elif [[ "$(profile_value ProvisionsAllDevices)" == true || -n "$(profile_value ProvisionedDevices)" ]]; then
            profile_ok=false
            profile_problem="$profile is a development or Developer ID profile, not a Mac App Store one"
        elif [[ -n "$expires" && "$expires" < "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ]]; then
            profile_ok=false
            profile_problem="$profile expired on $expires"
        elif [[ -z "$(profile_value Entitlements.com\\.apple\\.developer\\.applesignin)" ]]; then
            profile_ok=false
            profile_problem="$profile does not grant Sign in with Apple"
        fi
    fi
    $identity_ok && $installer_ok && $profile_ok && return 0

    mark() { $1 && echo "done" || echo "missing"; }
    cat >&2 <<EOF

The App Store build of Tabbi is signed with an Apple Distribution certificate
around an App Store provisioning profile, and its installer package with an
installer certificate. This needs three one-time setup steps (docs/appstore.md):

  1. Apple Distribution certificate ($(mark $identity_ok))
     ${APPSTORE_IDENTITY:+Looked for: $APPSTORE_IDENTITY
     }In Xcode: Settings > Accounts > your team > Manage Certificates > + >
     Apple Distribution. Check that it shows up with:
       security find-identity -v -p codesigning

  2. Mac Installer Distribution certificate ($(mark $installer_ok))
     ${INSTALLER_IDENTITY:+Looked for: $INSTALLER_IDENTITY
     }In Xcode: Settings > Accounts > your team > Manage Certificates > + >
     Mac Installer Distribution. Check that it shows up with:
       security find-identity -v

  3. Mac App Store provisioning profile ($(mark $profile_ok))
     ${profile_problem:+Problem: $profile_problem
     }Turn on Sign in with Apple for the App ID $bundle_id (Identifiers),
     then at https://developer.apple.com/account/resources/profiles create a
     Mac App Store Connect profile for it with your Apple Distribution
     certificate, download it and save it as
       $profile
     (the file is gitignored) or point APPSTORE_PROFILE at it.

To build without certificates (to check the sandboxed app on this Mac), run:
  scripts/release-appstore.sh --adhoc
EOF
    exit 1
}

if $adhoc; then
    log "Ad-hoc build: the App Store will not accept it"
else
    preflight
    log "Signing the app as: $app_identity"
    log "Signing the package as: $installer_identity"
fi

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
# App Store Connect takes each build number only once per version, and later
# uploads need higher ones: the commit count only grows.
[[ $(git rev-parse --is-shallow-repository) == false ]] \
    || fail "this is a shallow clone, so the build number would be wrong. Fetch the full history (git fetch --unshallow)."
build_number=$(git rev-list --count HEAD)

log "Building the App Store build of Tabbi $version (arm64 + x86_64)"
# Its own scratch path keeps the direct build's cache. Without Sparkle the
# manifest has no dependencies, so SwiftPM must not rewrite Package.resolved.
build_flags=(-c release --arch arm64 --arch x86_64 --scratch-path .build/appstore --only-use-versions-from-resolved-file)
TABBI_APPSTORE=1 swift build "${build_flags[@]}"
bin="$(TABBI_APPSTORE=1 swift build "${build_flags[@]}" --show-bin-path)/Tabbi"

archs=$(lipo -archs "$bin")
for arch in arm64 x86_64; do
    [[ " $archs " == *" $arch "* ]] || fail "$bin is missing $arch (has: $archs)"
done
# App Review rejects apps that update themselves; the App Store build has no
# updater at all, and this makes sure no change brings one back.
if otool -L "$bin" | grep -q Sparkle; then
    fail "$bin links Sparkle, which the App Store build must not"
fi

log "Assembling the $edition edition"
rm -rf "$out"
mkdir -p "$out"
app=$(scripts/assemble.sh "$bin" "$out" "$edition")
name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$app/Contents/Info.plist")
executable="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Contents/Info.plist")"
plutil -replace CFBundleVersion -string "$build_number" "$app/Contents/Info.plist"

# Local symbols are only useful to a debugger; stripping them roughly halves the binary.
# The linker's ad-hoc signature goes first, or strip warns that it breaks it.
codesign --remove-signature "$executable"
strip -x "$executable"

# The signing entitlements: the sandbox file plus, for the App Store, the
# application and team identifiers, which must match the embedded profile.
# Without a profile macOS refuses to launch an app that claims Sign in with
# Apple, so the ad-hoc build leaves it out (its Account row says so).
signing_entitlements="$work/Tabbi.entitlements"
cp "$entitlements" "$signing_entitlements"
if $adhoc; then
    plutil -remove com\\.apple\\.developer\\.applesignin "$signing_entitlements"
else
    cp "$profile" "$app/Contents/embedded.provisionprofile"
    for key in com.apple.application-identifier com.apple.developer.team-identifier; do
        value=$(profile_value "Entitlements.${key//./\\.}")
        plutil -replace "${key//./\\.}" -string "$value" "$signing_entitlements"
    done
fi

log "Signing ($($adhoc && echo ad-hoc || echo Apple Distribution))"
if $adhoc; then
    codesign --force --sign - --timestamp=none --entitlements "$signing_entitlements" "$app"
else
    codesign --force --sign "$app_identity" --timestamp --entitlements "$signing_entitlements" "$app"
fi
codesign --verify --strict --deep --verbose=2 "$app"
codesign --display --entitlements - --xml "$app" 2>/dev/null | plutil -extract com\\.apple\\.security\\.app-sandbox raw -o - - | grep -qx true \
    || fail "$app is not sandboxed"

pkg="$out/$name-$version.pkg"
log "Packaging $pkg"
# The App Store installs into /Applications; productbuild records that.
if $adhoc; then
    productbuild --component "$app" /Applications "$pkg" >/dev/null
else
    productbuild --component "$app" /Applications --sign "$installer_identity" "$pkg" >/dev/null
    pkgutil --check-signature "$pkg" >/dev/null || fail "$pkg has no valid signature"
fi

size() { du -sh "$1" | cut -f1 | tr -d ' '; }
cat <<EOF

Built $name $version, build $build_number ($($adhoc && echo "ad-hoc signed, not for the App Store" || echo "signed for the Mac App Store")):
  $pkg  ($(size "$pkg"))
  app: $(size "$app"), executable: $(size "$executable")
EOF
$adhoc || cat <<EOF

Upload it with Transporter, or check and upload it from the command line
(docs/appstore.md has how to create the API key):
  xcrun altool --validate-app -f $pkg -t macos --apiKey <KEY ID> --apiIssuer <ISSUER ID>
  xcrun altool --upload-app -f $pkg -t macos --apiKey <KEY ID> --apiIssuer <ISSUER ID>
EOF
