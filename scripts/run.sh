#!/usr/bin/env bash
# Rebuild (debug) and relaunch NotchDeck.
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x NotchDeck 2>/dev/null || true
app=$(scripts/bundle.sh debug | tail -1)
open "$app"
