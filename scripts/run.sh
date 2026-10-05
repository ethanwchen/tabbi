#!/usr/bin/env bash
# Rebuild (debug) and relaunch Tabbi.   usage: scripts/run.sh [edition]
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x Tabbi 2>/dev/null || true
app=$(scripts/bundle.sh "${1:-tabbi}" debug | tail -1)
open "$app"
