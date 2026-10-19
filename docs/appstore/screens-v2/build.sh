#!/bin/sh
# Renders the second App Store screenshot set (docs/appstore/screenshots-v2).
#
#   docs/appstore/screens-v2/build.sh            # render the app, then compose
#   docs/appstore/screens-v2/build.sh --compose  # compose from the last render
#
# 1. The app's own snapshot renderer draws every panel in demo mode for the
#    App Store edition, once per theme the set uses (3 pixels per point, and
#    1.4 for the theme grid), and PetGallery draws the pet lineup.
# 2. Headless Chrome screenshots shots.html once per shot at 1440x900 CSS
#    pixels and 2x, so a 3x panel lands 1:1 on the 2880x1800 canvas.
# 3. sips flattens each PNG to 8-bit sRGB with no alpha, as App Store Connect asks.
#
# Everything rendered lands in docs/appstore/screens-v2/build (ignored by git).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
build="$here/build"
out="$repo/docs/appstore/screenshots-v2"
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
tabs=study,planner,anki,spotify,claudeAsk,closet

# Themes the shots show at full size, and the nine the theme grid shows.
themes="cozy strawberryMilk matchaLatte taro blueberryMilk bananaMilk deepSea stargazer cherrySoda mintChoco"
grid="strawberryMilk blueberryMilk matchaLatte taro bananaMilk deepSea cherrySoda stargazer mintChoco"

if [ "${1:-}" != "--compose" ]; then
    cd "$repo"
    swift build --product Tabbi
    swift build --product PetGallery
    bin=$(swift build --show-bin-path)
    rm -rf "$build"
    mkdir -p "$build"
    render() { # folder theme scale
        TABBI_DEMO=1 "$bin/Tabbi" --snapshot "$build/$1" --edition appstore --tabs "$tabs" \
            --scale "$3" --transparent --theme "$2" > "$build/$1.log" 2>&1
    }
    pids=""
    for theme in $themes; do render "snap-$theme" "$theme" 3 & pids="$pids $!"; done
    for theme in $grid; do render "grid-$theme" "$theme" 1.4 & pids="$pids $!"; done
    "$bin/PetGallery" "$build/pets" store
    for pid in $pids; do wait "$pid"; done
fi

mkdir -p "$out"
profile=$(mktemp -d)
trap 'rm -rf "$profile"' EXIT
for shot in $(sed -n 's/^ *{ *id: "\([0-9][0-9]-[a-z-]*\)".*/\1/p' "$here/shots.html"); do
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$profile" \
        --allow-file-access-from-files --force-device-scale-factor=2 --window-size=1440,900 \
        --virtual-time-budget=4000 --screenshot="$out/$shot.png" "file://$here/shots.html?shot=$shot" 2>/dev/null
    sips -s format png -s formatOptions default -m "/System/Library/ColorSync/Profiles/sRGB Profile.icc" \
        "$out/$shot.png" --out "$out/$shot.png" > /dev/null
    echo "wrote $out/$shot.png"
done

# A contact sheet for review (not for upload), in a subfolder so it never
# goes up with the set.
mkdir -p "$out/review"
"$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$profile" \
    --allow-file-access-from-files --force-device-scale-factor=2 --window-size=1440,1010 \
    --virtual-time-budget=4000 --screenshot="$out/review/contact-sheet.png" "file://$here/contact.html" 2>/dev/null
echo "wrote $out/review/contact-sheet.png"
