#!/bin/bash
# End-to-end check of the iPhone app (ios/README.md): runs the
# FoundationFlowTests UI test on a simulator and takes a screenshot with
# `xcrun simctl io <device> screenshot --mask=black` at each of its
# checkpoints (the black mask fills the Dynamic Island as a device shows it,
# where the default leaves its inside transparent): the app,
# the Dynamic Island, and the Lock Screen Live Activity before and after the
# one-minute timer ends.
#
#   usage: ios/e2e.sh <output folder> [simulator name] [OS version]
set -euo pipefail

out=${1:?usage: ios/e2e.sh <output folder> [simulator name] [OS version]}
name=${2:-iPhone 17 Pro}
os=${3:-26.5}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)
handshake=$(mktemp -d)
trap 'rm -rf "$handshake"' EXIT

device=$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name, os = sys.argv[1], sys.argv[2]
runtimes = json.load(sys.stdin)["devices"]
for runtime, devices in runtimes.items():
    if runtime.endswith("iOS-" + os.replace(".", "-")):
        for d in devices:
            if d["name"] == name:
                print(d["udid"]); sys.exit()
sys.exit("no " + name + " on iOS " + os)' "$name" "$os")
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b > /dev/null
# A clean status bar, so screenshots do not depend on the Mac's clock or network.
xcrun simctl status_bar "$device" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode active --cellularBars 4

(cd "$here" && xcodegen generate --spec project.yml > /dev/null)
TEST_RUNNER_TABBI_E2E_DIR="$handshake" xcodebuild test -project "$here/TabbiPhone.xcodeproj" \
    -scheme TabbiPhoneUITests -destination "id=$device" > "$out/e2e-xcodebuild.log" 2>&1 &
test_pid=$!

# Screenshot each checkpoint as the test reaches it.
while kill -0 "$test_pid" 2> /dev/null; do
    for ready in "$handshake"/*.ready; do
        [[ -e $ready ]] || continue
        step=$(basename "$ready" .ready)
        xcrun simctl io "$device" screenshot --mask=black "$out/$step.png" > /dev/null 2>&1
        echo "shot $step"
        mv "$ready" "$handshake/$step.taken"
        touch "$handshake/$step.done"
    done
    sleep 0.3
done
wait "$test_pid" && status=0 || status=$?
xcrun simctl status_bar "$device" clear
grep -E "Executed|TEST SUCCEEDED|TEST FAILED|error:" "$out/e2e-xcodebuild.log" | tail -5
exit "$status"
