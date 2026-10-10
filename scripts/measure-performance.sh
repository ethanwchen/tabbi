#!/usr/bin/env bash
# Measure a running Tabbi over time: CPU, idle wakeups, energy impact,
# memory footprint, leaks and network traffic. See docs/performance.md.
#
#   usage: scripts/measure-performance.sh [options]
#     --app PATH        the .app to launch (default build/Tabbi.app;
#                       build it with scripts/bundle.sh tabbi release)
#     --pid PID         measure an already running Tabbi instead of launching one
#     --live            launch with real data (default: TABBI_DEMO=1)
#     --duration SEC    how long to sample (default 120)
#     --interval SEC    seconds per sample (default 5)
#     --warmup SEC      seconds to wait after launch before sampling (default 20)
#     --out DIR         where to write samples.csv and summary.txt
#                       (default perf-results/<timestamp>)
#     --keep            leave a launched app running afterwards
#     --no-leaks        skip leaks, which pauses the process while it scans
#     --pointer-moves N post N mouse moves per second (the pointer stays put)
#                       while sampling, as a user moving the mouse would
#     --open TAB        hold the launched notch open on this tab's module id
#                       (study, planner, spotify, claudeAsk, closet, ...)
#
# The app is launched by running its binary directly, so this script knows
# its PID and stops only that process. Nothing here needs sudo: top reports
# CPU, context switches and its energy impact score per process, footprint
# and leaks inspect the process, and nettop counts its bytes.
set -euo pipefail
cd "$(dirname "$0")/.."

app=build/Tabbi.app
pid=""
demo=1
duration=120
interval=5
warmup=20
out=""
keep=0
check_leaks=1
pointer_moves=0
mover_pid=""
open_tab=""
while [ $# -gt 0 ]; do
    case "$1" in
        --app) app=$2; shift ;;
        --pid) pid=$2; shift ;;
        --live) demo=0 ;;
        --duration) duration=$2; shift ;;
        --interval) interval=$2; shift ;;
        --warmup) warmup=$2; shift ;;
        --out) out=$2; shift ;;
        --keep) keep=1 ;;
        --no-leaks) check_leaks=0 ;;
        --pointer-moves) pointer_moves=$2; shift ;;
        --open) open_tab=$2; shift ;;
        -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
out=${out:-perf-results/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$out"

launched=0
if [ -z "$pid" ]; then
    bin="$app/Contents/MacOS/Tabbi"
    [ -x "$bin" ] || { echo "no app at $app; run scripts/bundle.sh tabbi release" >&2; exit 1; }
    env_vars=()
    [ "$demo" = 1 ] && env_vars+=(TABBI_DEMO=1)
    [ -n "$open_tab" ] && env_vars+=(TABBI_PERF_OPEN="$open_tab")
    env ${env_vars[@]+"${env_vars[@]}"} "$bin" >"$out/app.log" 2>&1 &
    pid=$!
    launched=1
    echo "launched $bin as pid $pid (demo=$demo, open=${open_tab:-no}), warming up ${warmup}s"
    sleep "$warmup"
fi
kill -0 "$pid" 2>/dev/null || { echo "pid $pid is not running" >&2; exit 1; }

cleanup() {
    [ -n "$mover_pid" ] && kill "$mover_pid" 2>/dev/null
    if [ "$launched" = 1 ] && [ "$keep" = 0 ]; then
        kill "$pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if [ "$pointer_moves" != 0 ]; then
    mover=$(mktemp -d)/perf-pointer-moves
    swiftc -O scripts/perf-pointer-moves.swift -o "$mover"
fi

# Phys footprint in MB, as Activity Monitor's Memory column shows it.
footprint_mb() {
    footprint "$pid" 2>/dev/null | awk '/phys_footprint:/ { v=$2; u=$3
        if (u ~ /KB/) v/=1024; if (u ~ /GB/) v*=1024; printf "%.1f", v; exit }'
}

# CPU seconds the process has used so far.
cpu_seconds() {
    ps -o time= -p "$pid" | awk -F: '{ s=0; for (i=1; i<=NF; i++) s=s*60+$i; printf "%.2f", s }'
}

samples=$(( duration / interval ))
[ "$samples" -ge 1 ] || samples=1
echo "time_s,cpu_percent,context_switches_per_s,energy_impact,footprint_mb" >"$out/samples.csv"

# nettop runs for the whole window in delta mode: one subscription costs the
# target less CPU than a fresh nettop per sample, and each line after the
# first sample is bytes moved since the previous one. A connection line
# names both ends, so the distinct ones count the connections opened.
nettop -p "$pid" -d -L $(( samples + 1 )) -s "$interval" -J bytes_in,bytes_out -x \
    >"$out/network.csv" 2>/dev/null &
nettop_pid=$!

if [ "$pointer_moves" != 0 ]; then
    "$mover" "$pointer_moves" $(( duration + 2 * samples + 5 )) &
    mover_pid=$!
fi
cpu0=$(cpu_seconds)
echo "sampling pid $pid: $samples samples every ${interval}s"
start=$(date +%s)
for _ in $(seq "$samples"); do
    # The first of top's two samples has no delta; the second covers the
    # interval. top's IDLEW column reads 0 on current macOS, so context
    # switches stand in for wakeups: a process that sleeps has none.
    line=$(top -l 2 -s "$interval" -c d -pid "$pid" -stats pid,cpu,csw,power 2>/dev/null |
        awk -v pid="$pid" '$1 == pid { l=$2 " " $3 " " $4 } END { print l }')
    kill -0 "$pid" 2>/dev/null || { echo "pid $pid exited" >&2; break; }
    read -r cpu csw power <<<"$line"
    printf '%s,%s,%s,%s,%s\n' "$(( $(date +%s) - start ))" "$cpu" \
        "$(awk -v c="${csw%+}" -v s="$interval" 'BEGIN { printf "%.1f", c / s }')" \
        "$power" "$(footprint_mb)" >>"$out/samples.csv"
done
elapsed=$(( $(date +%s) - start ))
cpu1=$(cpu_seconds)
[ -n "$mover_pid" ] && { kill "$mover_pid" 2>/dev/null; wait "$mover_pid" 2>/dev/null || true; mover_pid=""; }
wait "$nettop_pid" 2>/dev/null || true

[ "$check_leaks" = 1 ] && { leaks "$pid" >"$out/leaks.txt" 2>&1 || true; }
footprint "$pid" >"$out/footprint.txt" 2>&1 || true

# Skips nettop's first sample, which holds totals from before the window.
read -r bytes_in bytes_out connections <<<"$(awk -F, '
    $1 == "" { block++; next }
    block < 2 { if ($1 !~ /^Tabbi\./) seen[$1]=1; next }
    $1 ~ /^Tabbi\./ { i+=$2; o+=$3; next }
    !($1 in seen) { seen[$1]=1; n++ }
    END { printf "%d %d %d", i, o, n }' "$out/network.csv")"

awk -F, -v c0="$cpu0" -v c1="$cpu1" -v t="$elapsed" \
    -v bi="$bytes_in" -v bo="$bytes_out" -v nc="$connections" '
    NR > 1 { n++; cpu+=$2; w+=$3; e+=$4; if (n == 1) m0=$5; m=$5; if ($5 > peak) peak=$5
        if ($2 > maxcpu) maxcpu=$2 }
    END { if (!n) exit 1
        printf "samples            %d over %ds\n", n, t
        printf "cpu time           %.2fs (%.2f%% of one core)\n", c1-c0, (c1-c0)*100/t
        printf "cpu mean / max     %.2f%% / %.1f%% per sample\n", cpu/n, maxcpu
        printf "context switches   %.1f per second\n", w/n
        printf "energy impact      %.2f mean\n", e/n
        printf "footprint          %.1f MB -> %.1f MB (peak %.1f MB)\n", m0, m, peak
        printf "network            %d bytes in, %d bytes out, %d new connections\n", bi, bo, nc }' \
    "$out/samples.csv" | tee "$out/summary.txt"
[ "$check_leaks" = 1 ] && { grep -m1 "leaks for" "$out/leaks.txt" | tee -a "$out/summary.txt" || true; }
echo "results in $out"
